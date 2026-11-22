--!strict
-- Loja do lobby (GDD > Lobby e loja): compra de itens, reset de atributos, venda de equipamento, gemas Nv1 e
-- Removedores (GDD > Gemas) e venda das gemas e Removedores que sobram.
-- O cliente só PEDE (BuyItem / ResetAttributes / SellGear / BuyGem / BuyRemover / SellGem / SellRemover). Tudo é
-- validado aqui: o item
-- existe, o jogador está perto do balcão, tem Gold suficiente e não passou do limite do item. Na venda e nas gemas,
-- a distância e o anti-spam são conferidos aqui e o resto (peça da conta, baú, Gold) no GearService/GemService.
-- A resposta volta pelo Remote ShopResult.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Balance.Shop)
local Gems = require(Shared.Balance.Gems)

local GearService = require(script.Parent.GearService)
local GemService = require(script.Parent.GemService)
local LobbyService = require(script.Parent.LobbyService)
local ProgressionService = require(script.Parent.ProgressionService)

local REQUEST_COOLDOWN = 0.15 -- s entre vendas/compras de gema do mesmo jogador (anti-spam; técnico)

local ShopService = {}

local lastRequestAt: { [Player]: number } = {}

-- Anti-spam da venda e das gemas (pedidos acima do ritmo são ignorados em silêncio).
local function allowRequest(player: Player): boolean
	local t = os.clock()
	if t - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = t
	return true
end

local function reply(player: Player, ok: boolean, message: string)
	local payload: Remotes.ShopResultPayload = { ok = ok, message = message }
	Remotes.get("ShopResult"):FireClient(player, payload)
end

local function onBuyItem(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return
	end
	local def = Shop.items[itemId]
	if not def then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	if ProgressionService.getItemCount(player, itemId) >= def.maxOwned then
		reply(player, false, `Limite de {def.maxOwned} {def.displayName} atingido`)
		return
	end
	if not ProgressionService.trySpendGold(player, def.price) then
		reply(player, false, "Gold insuficiente")
		return
	end
	ProgressionService.addItem(player, itemId, 1)
	reply(player, true, `Comprou {def.displayName}`)
	print(`[Loja] {player.Name} comprou {itemId} por {def.price} Gold`)
end

-- Preço do reset de atributos para o nível atual do personagem.
function ShopService.resetPrice(player: Player): number
	return Shop.resetPricePerLevel * ProgressionService.getLevel(player)
end

local function onResetAttributes(player: Player)
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	local spent = 0
	for _, value in ProgressionService.getDistributedAttributes(player) :: { [string]: number } do
		spent += value
	end
	if spent == 0 then
		reply(player, false, "Você ainda não distribuiu nenhum ponto")
		return
	end
	local price = ShopService.resetPrice(player)
	if not ProgressionService.trySpendGold(player, price) then
		reply(player, false, `Gold insuficiente (custa {price})`)
		return
	end
	ProgressionService.resetAttributes(player)
	reply(player, true, `Atributos resetados: {spent} pontos livres para redistribuir`)
	print(`[Loja] {player.Name} resetou atributos por {price} Gold`)
end

local function onSellGear(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil or not allowRequest(player) then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	local ok, message = GearService.trySell(player, id)
	reply(player, ok, message)
end

-- Gema: a loja vende só o nível Gems.shopLevel (Nv1), de qualquer um dos 6 atributos.
local function onBuyGem(player: Player, rawAttribute: unknown)
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(rawAttribute)
	if attribute == nil or not allowRequest(player) then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	local ok, message = GemService.tryBuyGem(player, attribute)
	reply(player, ok, message)
end

-- Removedor: só os níveis que a loja vende hoje (até Gems.removerShopMaxLevel; decisão do designer).
local function onBuyRemover(player: Player, rawLevel: unknown)
	local level = Formulas.parseGemLevel(rawLevel)
	if level == nil or level > Gems.removerShopMaxLevel or not allowRequest(player) then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	local ok, message = GemService.tryBuyRemover(player, level)
	reply(player, ok, message)
end

-- Venda de sobras (decisão do designer: 10% do preço). Qualquer nível: as gemas Nv2+ caem do chefão (torres 5+).
local function onSellGem(player: Player, rawAttribute: unknown, rawLevel: unknown)
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(rawAttribute)
	local level = Formulas.parseGemLevel(rawLevel)
	if attribute == nil or level == nil or not allowRequest(player) then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	reply(player, GemService.trySellGem(player, attribute, level))
end

local function onSellRemover(player: Player, rawLevel: unknown)
	local level = Formulas.parseGemLevel(rawLevel)
	if level == nil or not allowRequest(player) then
		return
	end
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	reply(player, GemService.trySellRemover(player, level))
end

function ShopService.init()
	Remotes.get("BuyItem").OnServerEvent:Connect(onBuyItem)
	Remotes.get("ResetAttributes").OnServerEvent:Connect(onResetAttributes)
	Remotes.get("SellGear").OnServerEvent:Connect(onSellGear)
	Remotes.get("BuyGem").OnServerEvent:Connect(onBuyGem)
	Remotes.get("BuyRemover").OnServerEvent:Connect(onBuyRemover)
	Remotes.get("SellGem").OnServerEvent:Connect(onSellGem)
	Remotes.get("SellRemover").OnServerEvent:Connect(onSellRemover)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
	end)
end

function ShopService.start() end

return ShopService
