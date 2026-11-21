--!strict
-- Loja do lobby (GDD > Lobby e loja): compra de itens, reset de atributos e venda de equipamento.
-- O cliente só PEDE (BuyItem / ResetAttributes / SellGear). Tudo é validado aqui: o item existe, o jogador está
-- perto do balcão, tem Gold suficiente e não passou do limite do item. Na venda, a distância é conferida aqui e o
-- resto (peça da conta, não equipada, preço do catálogo) no GearService. A resposta volta pelo Remote ShopResult.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Balance.Shop)

local GearService = require(script.Parent.GearService)
local LobbyService = require(script.Parent.LobbyService)
local ProgressionService = require(script.Parent.ProgressionService)

local SELL_COOLDOWN = 0.15 -- s entre vendas do mesmo jogador (anti-spam; técnico)

local ShopService = {}

local lastSellAt: { [Player]: number } = {}

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
	if id == nil then
		return
	end
	local t = os.clock()
	if t - (lastSellAt[player] or -math.huge) < SELL_COOLDOWN then
		return
	end
	lastSellAt[player] = t
	if not LobbyService.isNearShop(player) then
		reply(player, false, "Chegue mais perto da loja")
		return
	end
	local ok, message = GearService.trySell(player, id)
	reply(player, ok, message)
end

function ShopService.init()
	Remotes.get("BuyItem").OnServerEvent:Connect(onBuyItem)
	Remotes.get("ResetAttributes").OnServerEvent:Connect(onResetAttributes)
	Remotes.get("SellGear").OnServerEvent:Connect(onSellGear)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSellAt[player] = nil
	end)
end

function ShopService.start() end

return ShopService
