--!strict
-- Progressão do jogador: classe, atributos, XP e Gold (nível e pontos de atributo entram no M4).
-- Também aplica no personagem o que vem da classe e dos atributos (vida máxima, velocidade).
-- XP e Gold só mudam aqui, chamados por serviços do servidor; são replicados por Attributes para o HUD.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Classes = require(Shared.Balance.Classes)
local Combat = require(Shared.Balance.Combat)

type PlayerData = {
	classId: string,
	attributes: Types.Attributes,
	xp: number,
	gold: number,
}

local ProgressionService = {}

local playerData: { [Player]: PlayerData } = {}

local function getData(player: Player): PlayerData
	local data = playerData[player]
	if not data then
		data = {
			classId = Classes.defaultClassId,
			attributes = Formulas.emptyAttributes(),
			xp = 0,
			gold = 0,
		}
		playerData[player] = data
	end
	return data
end

local function replicate(player: Player, data: PlayerData)
	player:SetAttribute(Keys.PlayerAttr.XP, data.xp)
	player:SetAttribute(Keys.PlayerAttr.Gold, data.gold)
end

function ProgressionService.addXp(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = getData(player)
	data.xp += amount
	replicate(player, data)
end

function ProgressionService.addGold(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = getData(player)
	data.gold += math.floor(amount)
	replicate(player, data)
end

function ProgressionService.getClass(player: Player): Types.ClassDef
	local classDef = Classes.byId[getData(player).classId]
	assert(classDef, "classe desconhecida")
	return classDef
end

-- Devolve uma cópia: quem chama não pode alterar os atributos por fora.
function ProgressionService.getAttributes(player: Player): Types.Attributes
	return table.clone(getData(player).attributes)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local classDef = ProgressionService.getClass(player)
	local attributes = getData(player).attributes
	humanoid.MaxHealth = Formulas.maxHealth(classDef, attributes)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = classDef.walkSpeed

	if Combat.disableNaturalHealthRegen then
		-- O Roblox coloca um Script "Health" em todo personagem que regenera vida aos poucos.
		local healthScript = character:WaitForChild("Health", 5)
		if healthScript then
			healthScript:Destroy()
		end
	end
end

local function onPlayerAdded(player: Player)
	replicate(player, getData(player))
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function ProgressionService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		playerData[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function ProgressionService.start() end

return ProgressionService
