--!strict
-- Gemas (GDD > Equipamentos > Gemas): comprar gema Nv1 e Removedor e vender as sobras (loja), incrustar, extrair e
-- fundir (Forja) e destruir a pilha inteira (arrastar para fora da mochila; Remotes DestroyGems/DestroyRemovers aqui).
-- Loja e Forja conferem a distância do balcão e o anti-spam; aqui fica o resto: lobby, Gold, as regras puras do
-- PlayerSchema (baú de 50 com as pilhas, pilha cheia, Removedor do nível certo), recalcular os atributos (a gema
-- de uma peça equipada soma no personagem) e avisar o cliente (GearData, pelo GearService.publish).
-- Cada função devolve (ok, mensagem) e é o MESMO caminho dos Remotes e das ferramentas de teste (DevService).
-- O Gold é conferido antes de mexer em qualquer coisa e cobrado só se a operação acontecer (sem yield no meio).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local GearInfo = require(Shared.GearInfo)
local Gear = require(Shared.Balance.Gear)
local Gems = require(Shared.Balance.Gems)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local ProgressionService = require(script.Parent.ProgressionService)
local GearService = require(script.Parent.GearService)

local REQUEST_COOLDOWN = 0.15 -- s entre pedidos de destruir do mesmo jogador (anti-spam; técnico)

local GemService = {}

local lastRequestAt: { [Player]: number } = {}

local function inRun(player: Player): boolean
	return player:GetAttribute(Keys.InRunAttr) == true
end

-- Depois de mexer em gemas: a gema de uma peça equipada muda os atributos; o baú muda o GearData.
local function afterChange(player: Player)
	ProgressionService.refreshEquipment(player)
	GearService.publish(player)
end

local function chestFullMessage(profile: PlayerSchema.Profile): string
	return `Baú cheio ({PlayerSchema.chestCount(profile)}/{Gear.chestCapacity}): cada tipo de gema ou Removedor`
		.. " ocupa 1 espaço"
end

local function pieceName(piece: Types.OwnedGear): string
	local def = PlayerSchema.defOf(piece)
	return if def then GearInfo.displayName(def, piece.enhance) else "peça"
end

-- ===== Loja =====

-- Compra 1 gema do nível da loja (Nv1) do atributo pedido.
function GemService.tryBuyGem(player: Player, attribute: Types.GemAttribute): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local level = Gems.shopLevel
	local name = GearInfo.gemName(attribute, level)
	if ProgressionService.getGold(player) < Gems.shopPrice then
		return false, `Gold insuficiente (custa {Gems.shopPrice})`
	end
	local outcome = PlayerSchema.storeGems(profile, attribute, level, 1)
	if outcome == "ChestFull" then
		return false, chestFullMessage(profile)
	elseif outcome == "StackFull" then
		return false, `Limite de {Gems.stackMax} {name} atingido`
	end
	ProgressionService.trySpendGold(player, Gems.shopPrice)
	GearService.publish(player)
	print(`[Loja] {player.Name} comprou {name} por {Gems.shopPrice} Gold`)
	return true, `Comprou {name}`
end

-- Compra 1 Removedor do nível pedido (a loja só vende até Gems.removerShopMaxLevel; quem chama valida o nível).
function GemService.tryBuyRemover(player: Player, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local price = Gems.removerPrice[level]
	if price == nil then
		return false, "Item não encontrado"
	end
	local name = GearInfo.removerName(level)
	if ProgressionService.getGold(player) < price then
		return false, `Gold insuficiente (custa {price})`
	end
	local outcome = PlayerSchema.storeRemovers(profile, level, 1)
	if outcome == "ChestFull" then
		return false, chestFullMessage(profile)
	elseif outcome == "StackFull" then
		return false, `Limite de {Gems.stackMax} {name} atingido`
	end
	ProgressionService.trySpendGold(player, price)
	GearService.publish(player)
	print(`[Loja] {player.Name} comprou {name} por {price} Gold`)
	return true, `Comprou {name}`
end

-- Vende 1 gema do baú (sobra) pelo preço de venda (Formulas.gemSellPrice: 10% do preço da loja).
function GemService.trySellGem(player: Player, attribute: Types.GemAttribute, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local name = GearInfo.gemName(attribute, level)
	if PlayerSchema.takeGems(profile, attribute, level, 1) ~= "Taken" then
		return false, `Você não tem {name}`
	end
	local price = Formulas.gemSellPrice(level)
	ProgressionService.addGold(player, price)
	GearService.publish(player)
	print(`[Loja] {player.Name} vendeu {name} por {price} Gold`)
	return true, `Vendeu {name} por {price} Gold`
end

function GemService.trySellRemover(player: Player, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local name = GearInfo.removerName(level)
	if PlayerSchema.takeRemovers(profile, level, 1) ~= "Taken" then
		return false, `Você não tem {name}`
	end
	local price = Formulas.removerSellPrice(level)
	ProgressionService.addGold(player, price)
	GearService.publish(player)
	print(`[Loja] {player.Name} vendeu {name} por {price} Gold`)
	return true, `Vendeu {name} por {price} Gold`
end

-- ===== Destruir (arrastar para fora da mochila; o cliente já pediu confirmação) =====
-- Some a pilha INTEIRA (decisão do designer: destruir serve para liberar o espaço do baú). Vale em qualquer lugar,
-- inclusive na torre (abrir espaço antes do chefe).

function GemService.tryDestroyGems(player: Player, attribute: Types.GemAttribute, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local count = PlayerSchema.gemCount(profile, attribute, level)
	local name = GearInfo.gemName(attribute, level)
	if PlayerSchema.takeGems(profile, attribute, level, count) ~= "Taken" then
		return false, `Você não tem {name}`
	end
	GearService.publish(player)
	print(`[Baú] {player.Name} destruiu {count} {name}`)
	return true, `Destruiu {name} (×{count})`
end

function GemService.tryDestroyRemovers(player: Player, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	local count = PlayerSchema.removerCount(profile, level)
	local name = GearInfo.removerName(level)
	if PlayerSchema.takeRemovers(profile, level, count) ~= "Taken" then
		return false, `Você não tem {name}`
	end
	GearService.publish(player)
	print(`[Baú] {player.Name} destruiu {count} {name}`)
	return true, `Destruiu {name} (×{count})`
end

-- ===== Forja =====

-- Encaixa uma gema do baú na peça `id` (de qualquer personagem da conta, ou do baú). Cobra o custo de incrustar.
function GemService.trySocket(
	player: Player,
	id: number,
	attribute: Types.GemAttribute,
	level: number
): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	if inRun(player) then
		return false, "Gemas só no lobby"
	end
	if ProgressionService.getGold(player) < Gems.socketCost then
		return false, `Gold insuficiente (custa {Gems.socketCost})`
	end
	local outcome = PlayerSchema.socketGem(profile, id, attribute, level)
	local gemName = GearInfo.gemName(attribute, level)
	if outcome == "HasGem" then
		return false, "Esta peça já tem gema: extraia antes (com Removedor)"
	elseif outcome == "NoGem" then
		return false, `Você não tem {gemName}`
	elseif outcome ~= "Socketed" then
		return false, "Item não encontrado"
	end
	ProgressionService.trySpendGold(player, Gems.socketCost)
	afterChange(player)
	local piece = PlayerSchema.findGear(profile, id) :: Types.OwnedGear
	print(`[Forja] {player.Name}: {gemName} em {pieceName(piece)} (id {id}), {Gems.socketCost} Gold`)
	return true, `Incrustou {gemName} em {pieceName(piece)}`
end

-- Tira a gema da peça `id`: gasta 1 Removedor do nível da gema; a gema volta inteira para o baú.
function GemService.tryExtract(player: Player, id: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	if inRun(player) then
		return false, "Gemas só no lobby"
	end
	local piece = PlayerSchema.findGear(profile, id)
	local current = if piece then piece.gem else nil
	local outcome, gem = PlayerSchema.extractGem(profile, id)
	if outcome == "Extracted" and gem and piece then
		afterChange(player)
		local gemName = GearInfo.gemName(gem.attribute, gem.level)
		print(`[Forja] {player.Name}: extraiu {gemName} de {pieceName(piece)} (id {id})`)
		return true, `Extraiu {gemName} (gastou 1 {GearInfo.removerName(gem.level)})`
	elseif outcome == "Empty" then
		return false, "Esta peça não tem gema"
	elseif outcome == "NoRemover" and current then
		return false, `Precisa de 1 {GearInfo.removerName(current.level)} (compre na loja)`
	elseif outcome == "ChestFull" then
		return false, `{chestFullMessage(profile)}: a gema não teria onde ficar`
	elseif outcome == "StackFull" and current then
		return false, `Limite de {Gems.stackMax} {GearInfo.gemName(current.attribute, current.level)} no baú`
	end
	return false, "Item não encontrado"
end

-- Funde 3 gemas iguais do baú (atributo + nível) em 1 do nível seguinte. Cobra o custo da fusão desse nível.
function GemService.tryFuse(player: Player, attribute: Types.GemAttribute, level: number): (boolean, string)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false, "Aguarde, carregando seus dados"
	end
	if inRun(player) then
		return false, "Gemas só no lobby"
	end
	local cost = Formulas.fuseCost(level)
	if cost == nil then
		return false, GearInfo.fuseBlockedReason(level)
	end
	local have = PlayerSchema.gemCount(profile, attribute, level)
	if have < Gems.fuseCount then
		return false, `Precisa de {Gems.fuseCount} iguais (você tem {have})`
	end
	if ProgressionService.getGold(player) < cost then
		return false, `Gold insuficiente (custa {cost})`
	end
	local outcome = PlayerSchema.fuseGems(profile, attribute, level)
	local result = GearInfo.gemName(attribute, level + 1)
	if outcome == "ChestFull" then
		return false, `{chestFullMessage(profile)}: a gema nova não teria onde ficar`
	elseif outcome == "StackFull" then
		return false, `Limite de {Gems.stackMax} {result} no baú`
	elseif outcome ~= "Fused" then
		return false, "Não foi possível fundir"
	end
	ProgressionService.trySpendGold(player, cost)
	afterChange(player)
	local source = GearInfo.gemName(attribute, level)
	print(`[Forja] {player.Name}: fundiu {Gems.fuseCount} {source} em {result}, {cost} Gold`)
	return true, `Fundiu {Gems.fuseCount} × Nv{level}: ganhou 1 {result}`
end

-- ===== SÓ TESTES no Studio (DevService) =====

-- Põe gemas de qualquer nível no baú, sem custo (as Nv2+ ainda não caem: torres 5+). Devolve o resultado.
function GemService.debugGiveGems(
	player: Player,
	attribute: Types.GemAttribute,
	level: number,
	amount: number
): PlayerSchema.StoreOutcome?
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return nil
	end
	local outcome: PlayerSchema.StoreOutcome = PlayerSchema.storeGems(profile, attribute, level, amount)
	GearService.publish(player)
	return outcome
end

function GemService.debugGiveRemovers(player: Player, level: number, amount: number): PlayerSchema.StoreOutcome?
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return nil
	end
	local outcome: PlayerSchema.StoreOutcome = PlayerSchema.storeRemovers(profile, level, amount)
	GearService.publish(player)
	return outcome
end

-- ===== Remotes de destruir (a resposta vai pelo GearResult, que aparece no painel Personagem) =====

local function allowRequest(player: Player): boolean
	local t = os.clock()
	if t - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = t
	return true
end

local function reply(player: Player, ok: boolean, message: string)
	local payload: Remotes.GearResultPayload = { ok = ok, message = message }
	Remotes.get("GearResult"):FireClient(player, payload)
end

local function onDestroyGems(player: Player, rawAttribute: unknown, rawLevel: unknown)
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(rawAttribute)
	local level = Formulas.parseGemLevel(rawLevel)
	if attribute == nil or level == nil or not allowRequest(player) then
		return
	end
	reply(player, GemService.tryDestroyGems(player, attribute, level))
end

local function onDestroyRemovers(player: Player, rawLevel: unknown)
	local level = Formulas.parseGemLevel(rawLevel)
	if level == nil or not allowRequest(player) then
		return
	end
	reply(player, GemService.tryDestroyRemovers(player, level))
end

function GemService.init()
	Remotes.get("DestroyGems").OnServerEvent:Connect(onDestroyGems)
	Remotes.get("DestroyRemovers").OnServerEvent:Connect(onDestroyRemovers)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
	end)
end

function GemService.start() end

return GemService
