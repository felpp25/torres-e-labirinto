--!strict
-- Loja do lobby (GDD > Lobby e loja): compra de itens e reset de atributos.
-- O cliente só PEDE (BuyItem / ResetAttributes). Tudo é validado aqui: o item existe, o jogador está perto do
-- balcão, tem Gold suficiente e não passou do limite do item. A resposta volta pelo Remote ShopResult.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Balance.Shop)

local LobbyService = require(script.Parent.LobbyService)
local ProgressionService = require(script.Parent.ProgressionService)

local ShopService = {}

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
	for _, value in ProgressionService.getAttributes(player) :: { [string]: number } do
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

function ShopService.init()
	Remotes.get("BuyItem").OnServerEvent:Connect(onBuyItem)
	Remotes.get("ResetAttributes").OnServerEvent:Connect(onResetAttributes)
end

function ShopService.start() end

return ShopService
