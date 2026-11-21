--!strict
-- Uso de consumíveis (poções) por atalho. O cliente só PEDE (UsePotion); aqui é validado: o item existe, o
-- jogador está vivo, tem o item e a recarga daquele item já passou. Poção não é gasta se não teria efeito
-- (vida ou stamina já cheias).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Combat = require(Shared.Balance.Combat)
local Shop = require(Shared.Balance.Shop)

local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

local ConsumableService = {}

local readyAt: { [Player]: { [string]: number } } = {}

local function onUsePotion(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" then
		return
	end
	local def = Shop.items[itemId]
	if not def then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local times = readyAt[player]
	if not times then
		times = {}
		readyAt[player] = times
	end
	local now = workspace:GetServerTimeNow()
	if now + Combat.serverTimingTolerance < (times[itemId] or 0) then
		return -- em recarga
	end
	-- Não gasta a poção à toa.
	if def.effect == "Heal" and humanoid.Health >= humanoid.MaxHealth then
		return
	end
	if def.effect == "Stamina" and CombatService.isStaminaFull(player) then
		return
	end
	if not ProgressionService.tryConsumeItem(player, itemId) then
		return
	end

	times[itemId] = now + def.cooldown
	player:SetAttribute(Keys.itemReadyAttr(itemId), times[itemId])
	if def.effect == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * def.amount)
	else
		CombatService.addStamina(player, def.amount)
	end
end

function ConsumableService.init()
	Remotes.get("UsePotion").OnServerEvent:Connect(onUsePotion)
	Players.PlayerRemoving:Connect(function(player: Player)
		readyAt[player] = nil
	end)
end

function ConsumableService.start() end

return ConsumableService
