--!strict
-- Equipamento (GDD > Equipamentos): baú da conta, equipar e trocar peças (SÓ no lobby), dar peças novas, os
-- sorteios de drop (quem recebe e com que Sorte é decisão do RunSessionService), a venda (ShopService) e o
-- fortalecimento (ForgeService). Loja e Forja conferem a distância do balcão; o resto é conferido aqui.
-- As gemas ficam no GemService (usa o publish daqui: o GearData leva peças, gemas e Removedores).
-- As regras (slot certo, classe da arma, baú de 50, arma nunca vazia...) são funções puras do PlayerSchema; aqui
-- ficam o que depende do jogo: lobby, anti-spam, mensagens, recalcular atributos e avisar o cliente.
-- O cliente só PEDE (EquipGear / UnequipGear); tudo é validado. Ele recebe o estado pelo Attribute GearData
-- (Shared/GearSnapshot), a resposta pelo GearResult e os drops pelo GearNotice.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local GearInfo = require(Shared.GearInfo)
local GearSnapshot = require(Shared.GearSnapshot)
local Gear = require(Shared.Balance.Gear)
local Forge = require(Shared.Balance.Forge)
local Gems = require(Shared.Balance.Gems)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local ProgressionService = require(script.Parent.ProgressionService)

local REQUEST_COOLDOWN = 0.15 -- s entre pedidos de equipar/tirar do mesmo jogador (anti-spam; técnico)

export type GrantSource = "Boss" | "Mob" | "Dev"
export type EnhanceOutcome = "Success" | "Fail" | "Refused"
export type GrantResult = {
	stored: boolean, -- true = foi para o baú; false = baú cheio, virou Gold
	id: number?,
	goldInstead: number,
}

local GearService = {}

local rng = Random.new()
local lastRequestAt: { [Player]: number } = {}
local lastPublished: { [Player]: string } = {}
local forceMobDrop: { [Player]: boolean } = {} -- só testes no Studio (DevService)

local function reply(player: Player, ok: boolean, message: string)
	local payload: Remotes.GearResultPayload = { ok = ok, message = message }
	Remotes.get("GearResult"):FireClient(player, payload)
end

local function nameOf(piece: Types.OwnedGear?): string
	local def = if piece then PlayerSchema.defOf(piece) else nil
	if piece and def then
		return GearInfo.fullName(def, piece.rarity, piece.enhance)
	end
	return "peça"
end

-- Envia ao cliente o estado do equipamento, das gemas e dos Removedores (só quando muda).
function GearService.publish(player: Player)
	local profile, data = ProgressionService.getLoadedProfile(player)
	if not profile or not data then
		return
	end
	local used = PlayerSchema.equippedIds(profile)
	local entries: { Types.GearEntry } = {}
	for _, piece in profile.gear do
		if PlayerSchema.defOf(piece) ~= nil then -- peça inerte não aparece
			local gem = piece.gem
			table.insert(entries, {
				id = piece.id,
				defId = piece.defId,
				rarity = piece.rarity,
				enhance = piece.enhance,
				gem = if gem then { attribute = gem.attribute, level = gem.level } else nil,
				inUse = used[piece.id] == true,
			})
		end
	end
	-- Pilhas na ordem fixa (atributo, depois nível): o cliente mostra nesta ordem.
	local gemStacks: { Types.GemStack } = {}
	for _, attribute: Types.GemAttribute in Gems.attributes do
		for level = 1, Gems.maxLevel do
			local count = PlayerSchema.gemCount(profile, attribute, level)
			if count > 0 then
				table.insert(gemStacks, { attribute = attribute, level = level, count = count })
			end
		end
	end
	local removerStacks: { Types.RemoverStack } = {}
	for level = 1, Gems.maxLevel do
		local count = PlayerSchema.removerCount(profile, level)
		if count > 0 then
			table.insert(removerStacks, { level = level, count = count })
		end
	end
	local snapshot: Types.GearSnapshot = {
		gear = entries,
		equipped = table.clone(data.equipped),
		gems = gemStacks,
		removers = removerStacks,
	}
	local encoded = GearSnapshot.encode(snapshot)
	if lastPublished[player] ~= encoded then
		lastPublished[player] = encoded
		player:SetAttribute(Keys.PlayerAttr.GearData, encoded)
	end
end

-- Dá uma peça nova ao jogador (drop do chefe/mob ou teste). Baú cheio: a peça vira Gold pelo preço de venda.
-- `silent` = sem aviso na tela e sem publicar (quem chama publica uma vez no fim; ex.: encher o baú em teste).
-- Devolve nil se o perfil ainda não carregou.
function GearService.grant(
	player: Player,
	defId: string,
	rarity: Types.Rarity,
	source: GrantSource,
	silent: boolean?
): GrantResult?
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return nil
	end
	local def = Gear.byId[defId]
	assert(def, `GearService.grant: peça desconhecida {defId}`)
	local result: GrantResult
	if PlayerSchema.chestCount(profile) >= Gear.chestCapacity then
		local gold = Formulas.gearSellPrice(def, rarity, 0)
		ProgressionService.addGold(player, gold)
		result = { stored = false, id = nil, goldInstead = gold }
		print(`[Loot] {player.Name}: {GearInfo.fullName(def, rarity)} ({source}) -> baú cheio, +{gold} Gold`)
	else
		local piece = PlayerSchema.addGear(profile, defId, rarity)
		result = { stored = true, id = piece.id, goldInstead = 0 }
		print(`[Loot] {player.Name}: {GearInfo.fullName(def, rarity)} ({source}), id {piece.id}`)
	end
	if not silent then
		GearService.publish(player)
		local payload: Remotes.GearNoticePayload =
			{ defId = defId, rarity = rarity, source = source, goldInstead = result.goldInstead }
		Remotes.get("GearNotice"):FireClient(player, payload)
	end
	return result
end

-- ===== Drops (GDD > Equipamentos > Obtenção) =====

-- Sorteia a peça: slot ao acaso, depois uma peça do drop desse slot (armas só da classe do personagem).
-- Com 2 linhas por slot e 2 armas do Lutador, cada uma das 14 peças sai com a mesma chance.
function GearService.rollDefId(classId: string): string
	local slot = Gear.slots[rng:NextInteger(1, #Gear.slots)]
	local options: { string } = {}
	for _, defId in Gear.dropPool do
		local def = Gear.byId[defId]
		if def.slot == slot and (def.classId == nil or def.classId == classId) then
			table.insert(options, defId)
		end
	end
	if #options == 0 then
		-- Classe sem arma neste drop: sorteia entre as peças que não são arma.
		for _, defId in Gear.dropPool do
			if Gear.byId[defId].classId == nil then
				table.insert(options, defId)
			end
		end
	end
	return options[rng:NextInteger(1, #options)]
end

-- Item garantido do chefe: Raro com a chance de Balance/Gear, aumentada pela Sorte (regra dos achados raros).
function GearService.rollBossRarity(luck: number): Types.Rarity
	return if rng:NextNumber() < Formulas.luckChance(Gear.bossRareChance, luck) then "Rare" else "Common"
end

function GearService.rollsMobDrop(luck: number): boolean
	return rng:NextNumber() < Formulas.luckChance(Gear.mobDropChance, luck)
end

-- 1 peça garantida do chefe para este jogador (loot individual). `luck` = Sorte do grupo (quem chama calcula).
function GearService.rollBossLoot(player: Player, luck: number): GrantResult?
	local classId = ProgressionService.getClass(player).id
	return GearService.grant(player, GearService.rollDefId(classId), GearService.rollBossRarity(luck), "Boss")
end

-- Chance de uma peça Comum por mob, para cada jogador perto (loot individual).
function GearService.rollMobLoot(player: Player, luck: number): GrantResult?
	local forced = forceMobDrop[player] == true
	if not forced and not GearService.rollsMobDrop(luck) then
		return nil
	end
	forceMobDrop[player] = nil
	local classId = ProgressionService.getClass(player).id
	return GearService.grant(player, GearService.rollDefId(classId), "Common", "Mob")
end

-- SÓ TESTES no Studio (DevService): o próximo mob que morrer perto do jogador dá uma peça.
function GearService.debugForceNextMobDrop(player: Player)
	forceMobDrop[player] = true
end

local function inRun(player: Player): boolean
	return player:GetAttribute(Keys.InRunAttr) == true
end

-- Depois de mudar o equipamento: recalcula atributos (vida máxima etc.) e avisa o cliente.
local function afterChange(player: Player)
	ProgressionService.refreshEquipment(player)
	GearService.publish(player)
end

-- Equipa a peça `id` no personagem ativo. Devolve (ok, mensagem); mensagem nil = nada a dizer.
-- Mesmo caminho do Remote e das ferramentas de teste.
function GearService.tryEquip(player: Player, id: number): (boolean, string?)
	local profile, _ = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, nil
	end
	if inRun(player) then
		return false, "Troca de equipamento só no lobby"
	end
	local piece = PlayerSchema.findGear(profile, id)
	local outcome = PlayerSchema.equip(profile, profile.activeSlot, id)
	if outcome == "Equipped" then
		afterChange(player)
		print(`[Equip] {player.Name} equipou {nameOf(piece)} (id {id})`)
		return true, `Equipou {nameOf(piece)}`
	elseif outcome == "AlreadyEquipped" then
		return true, nil
	elseif outcome == "WrongClass" then
		return false, "Esta arma é de outra classe"
	elseif outcome == "LowLevel" then
		local def = if piece then PlayerSchema.defOf(piece) else nil
		return false, `Precisa do nível {if def then def.minLevel else "?"}`
	elseif outcome == "ChestFull" then
		return false, `Baú cheio ({PlayerSchema.chestCount(profile)}/{Gear.chestCapacity}): venda algo antes`
	elseif outcome == "OtherCharacterWeapon" then
		return false, "Esta arma está equipada em outro personagem"
	end
	return false, "Item não encontrado"
end

-- Tira a peça do slot (vai para o baú). A arma só é trocada, nunca tirada.
function GearService.tryUnequip(player: Player, slot: Types.EquipSlot): (boolean, string?)
	local profile, data = ProgressionService.getLoadedProfile(player)
	if not profile or not data then
		return false, nil
	end
	if inRun(player) then
		return false, "Troca de equipamento só no lobby"
	end
	local id = data.equipped[slot]
	local piece = if id ~= nil then PlayerSchema.findGear(profile, id) else nil
	local outcome = PlayerSchema.unequip(profile, profile.activeSlot, slot)
	if outcome == "Unequipped" then
		afterChange(player)
		print(`[Equip] {player.Name} tirou {nameOf(piece)} ({slot})`)
		return true, `Tirou {nameOf(piece)}`
	elseif outcome == "WeaponLocked" then
		return false, "A arma não pode ser tirada, só trocada por outra"
	elseif outcome == "ChestFull" then
		return false, `Baú cheio ({Gear.chestCapacity}/{Gear.chestCapacity}): venda algo antes de tirar`
	end
	return false, nil -- slot já vazio (tela desatualizada)
end

-- Vende uma peça do BAÚ (a loja já conferiu a distância do balcão). Preço do catálogo, nunca do cliente: base da
-- raridade + parte das tentativas de fortalecimento (Formulas.gearSellPrice).
-- Peça equipada não é vendida (a arma equipada nem pode ser tirada: troque por outra antes).
function GearService.trySell(player: Player, id: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local found = PlayerSchema.findGear(profile, id)
	local outcome, piece = PlayerSchema.sell(profile, id)
	local soldDef = if piece then PlayerSchema.defOf(piece) else nil
	if outcome == "Sold" and piece and soldDef then
		local price = Formulas.gearSellPrice(soldDef, piece.rarity, piece.enhance)
		ProgressionService.addGold(player, price)
		GearService.publish(player)
		print(`[Loja] {player.Name} vendeu {nameOf(piece)} (id {id}) por {price} Gold`)
		return true, `Vendeu {nameOf(piece)} por {price} Gold`
	elseif outcome == "InUse" then
		local def = if found then PlayerSchema.defOf(found) else nil
		if def and def.slot == "Weapon" then
			return false, "Arma em uso: troque por outra antes de vender"
		end
		return false, "Item em uso: tire antes de vender"
	elseif outcome == "HasGem" then
		return false, "Peça com gema: extraia a gema na Forja antes de vender"
	end
	return false, "Item não encontrado"
end

-- Destrói uma peça do baú (arrastada para fora da mochila; o cliente já pediu confirmação). Vale em qualquer lugar,
-- inclusive na torre: serve para abrir espaço antes do chefe. A fortalecida pode; equipada e com gema, não.
function GearService.tryDestroy(player: Player, id: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local outcome, piece = PlayerSchema.destroyGear(profile, id)
	if outcome == "Destroyed" and piece then
		GearService.publish(player)
		print(`[Baú] {player.Name} destruiu {nameOf(piece)} (id {id})`)
		return true, `Destruiu {nameOf(piece)}`
	elseif outcome == "InUse" then
		return false, "Item em uso: tire antes de destruir"
	elseif outcome == "HasGem" then
		return false, "Peça com gema: extraia a gema na Forja antes de destruir"
	end
	return false, "Item não encontrado"
end

-- ===== Fortalecimento (GDD > Fortalecimento; a Forja já conferiu a distância do balcão) =====

-- Uma tentativa de fortalecer a peça `id` (de qualquer personagem da conta, ou do baú). Cobra o Gold da tentativa,
-- sorteia no servidor e aplica o resultado (Formulas.enhanceResult). Devolve (resultado, mensagem):
-- "Success"/"Fail" = houve sorteio (Gold gasto); "Refused" = nada mudou.
-- `forced` = SÓ testes no Studio (DevService): força o resultado do sorteio.
function GearService.tryEnhance(player: Player, id: number, forced: boolean?): (EnhanceOutcome, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return "Refused", "Aguarde, carregando seus dados"
	end
	if inRun(player) then
		return "Refused", "Fortalecimento só no lobby"
	end
	local piece = PlayerSchema.findGear(profile, id)
	local def = if piece then PlayerSchema.defOf(piece) else nil
	if not piece or not def then
		return "Refused", "Item não encontrado"
	end
	if piece.enhance >= Forge.maxEnhance then
		return "Refused", `Já está no máximo (+{Forge.maxEnhance})`
	end
	local target = piece.enhance + 1
	local cost = Formulas.enhanceCost(def, target)
	if not ProgressionService.trySpendGold(player, cost) then
		return "Refused", `Gold insuficiente (custa {cost})`
	end
	local success = if forced ~= nil then forced else rng:NextNumber() < Formulas.enhanceChance(target)
	local before = piece.enhance
	piece.enhance = Formulas.enhanceResult(before, success)
	afterChange(player)
	print(
		`[Forja] {player.Name}: {def.displayName} (id {id}) +{before} -> +{piece.enhance}`
			.. ` ({if success then "sucesso" else "falha"}, {cost} Gold)`
	)
	if success then
		return "Success", `Sucesso! {GearInfo.displayName(def, piece.enhance)}`
	elseif piece.enhance < before then
		return "Fail", `Falhou: caiu para +{piece.enhance}`
	end
	return "Fail", `Falhou: continua +{piece.enhance} (o Gold foi gasto)`
end

-- Transferir o fortalecimento: as peças `fromId` e `toId` trocam os níveis (decisões do designer: mesmo tipo de peça,
-- só para a mesma torre ou uma mais baixa; custa 1 tentativa do maior nível trocado). A Forja confere a distância.
function GearService.tryTransfer(player: Player, fromId: number, toId: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	if inRun(player) then
		return false, "Transferência só no lobby"
	end
	local from = PlayerSchema.findGear(profile, fromId)
	local to = PlayerSchema.findGear(profile, toId)
	local defFrom = if from then PlayerSchema.defOf(from) else nil
	local defTo = if to then PlayerSchema.defOf(to) else nil
	if not from or not to or not defFrom or not defTo or fromId == toId then
		return false, "Item não encontrado"
	end
	local check: Formulas.TransferCheck = Formulas.transferCheck(defFrom, from.enhance, defTo, to.enhance)
	local blocked = GearInfo.transferBlockedReason(check)
	if blocked then
		return false, blocked
	end
	local cost = Formulas.transferCost(defFrom, from.enhance, defTo, to.enhance)
	if ProgressionService.getGold(player) < cost then
		return false, `Gold insuficiente (custa {cost})`
	end
	local before = `{nameOf(from)} e {nameOf(to)}`
	if PlayerSchema.transferEnhance(profile, fromId, toId) ~= "Transferred" then
		return false, "Não foi possível transferir"
	end
	ProgressionService.trySpendGold(player, cost)
	afterChange(player)
	print(`[Forja] {player.Name}: troca de fortalecimento {before} -> {nameOf(from)} e {nameOf(to)}, {cost} Gold`)
	return true, `Trocado: {nameOf(to)} e {nameOf(from)}`
end

-- SÓ TESTES no Studio (DevService): define o fortalecimento direto, sem custo nem sorteio.
function GearService.debugSetEnhance(player: Player, id: number, enhance: number): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	local piece = if profile then PlayerSchema.findGear(profile, id) else nil
	if not piece then
		return false
	end
	piece.enhance = math.clamp(math.floor(enhance), 0, Forge.maxEnhance)
	afterChange(player)
	return true
end

-- Anti-spam por jogador (os pedidos acima do ritmo são ignorados em silêncio).
local function allowRequest(player: Player): boolean
	local t = os.clock()
	if t - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = t
	return true
end

local function onEquipGear(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil or not allowRequest(player) then
		return
	end
	local ok, message = GearService.tryEquip(player, id)
	if message then
		reply(player, ok, message)
	end
end

local function onUnequipGear(player: Player, rawSlot: unknown)
	local slot: Types.EquipSlot? = Formulas.parseEquipSlot(rawSlot)
	if slot == nil or not allowRequest(player) then
		return
	end
	local ok, message = GearService.tryUnequip(player, slot)
	if message then
		reply(player, ok, message)
	end
end

local function onDestroyGear(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil or not allowRequest(player) then
		return
	end
	local ok, message = GearService.tryDestroy(player, id)
	reply(player, ok, message)
end

function GearService.init()
	Remotes.get("EquipGear").OnServerEvent:Connect(onEquipGear)
	Remotes.get("UnequipGear").OnServerEvent:Connect(onUnequipGear)
	Remotes.get("DestroyGear").OnServerEvent:Connect(onDestroyGear)
	-- Publica assim que o perfil carregar (sem prazo: o carregamento pode esperar a trava de outro servidor).
	ProgressionService.setLoadedHandler(GearService.publish)
	-- Jogadores que já estavam no servidor e terminaram de carregar antes deste registro (publish ignora quem ainda
	-- não carregou; esses recebem pelo handler acima).
	for _, player in Players:GetPlayers() do
		task.spawn(GearService.publish, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		lastPublished[player] = nil
		forceMobDrop[player] = nil
	end)
end

function GearService.start() end

return GearService
