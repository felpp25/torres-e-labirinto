--!strict
-- Equipamento (GDD > Equipamentos): baú da conta, equipar e trocar peças (SÓ no lobby) e dar peças novas.
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

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local ProgressionService = require(script.Parent.ProgressionService)

local REQUEST_COOLDOWN = 0.15 -- s entre pedidos de equipar/tirar do mesmo jogador (anti-spam; técnico)

export type GrantSource = "Boss" | "Mob" | "Dev"
export type GrantResult = {
	stored: boolean, -- true = foi para o baú; false = baú cheio, virou Gold
	id: number?,
	goldInstead: number,
}

local GearService = {}

local lastRequestAt: { [Player]: number } = {}
local lastPublished: { [Player]: string } = {}

local function reply(player: Player, ok: boolean, message: string)
	local payload: Remotes.GearResultPayload = { ok = ok, message = message }
	Remotes.get("GearResult"):FireClient(player, payload)
end

local function nameOf(piece: Types.OwnedGear?): string
	local def = if piece then PlayerSchema.defOf(piece) else nil
	if piece and def then
		return GearInfo.fullName(def, piece.rarity)
	end
	return "peça"
end

-- Envia ao cliente o estado do equipamento (só quando muda).
function GearService.publish(player: Player)
	local profile, data = ProgressionService.getLoadedProfile(player)
	if not profile or not data then
		return
	end
	local used = PlayerSchema.equippedIds(profile)
	local entries: { Types.GearEntry } = {}
	for _, piece in profile.gear do
		if PlayerSchema.defOf(piece) ~= nil then -- peça inerte não aparece
			table.insert(
				entries,
				{ id = piece.id, defId = piece.defId, rarity = piece.rarity, inUse = used[piece.id] == true }
			)
		end
	end
	local snapshot: Types.GearSnapshot = { gear = entries, equipped = table.clone(data.equipped) }
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
		local gold = Gear.sellPrice[rarity] or 0
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

function GearService.init()
	Remotes.get("EquipGear").OnServerEvent:Connect(onEquipGear)
	Remotes.get("UnequipGear").OnServerEvent:Connect(onUnequipGear)
	-- Publica assim que o perfil carregar (sem prazo: o carregamento pode esperar a trava de outro servidor).
	ProgressionService.setLoadedHandler(GearService.publish)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		lastPublished[player] = nil
	end)
end

function GearService.start() end

return GearService
