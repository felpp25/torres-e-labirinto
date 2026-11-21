--!strict
-- Progressão do jogador: classe, atributos, nível, XP e Gold.
-- - XP sobe de nível (curva em Formulas.xpToNextLevel, teto em Balance/Progression.maxLevel);
-- - cada nível dá 3 pontos, distribuídos automaticamente nos atributos de scaling da classe ("recomendado");
-- - aplica no personagem o que vem da classe e dos atributos (vida máxima, velocidade).
-- Tudo só muda aqui, chamado por serviços do servidor; o cliente recebe por Attributes (HUD) e pelo Remote LevelUp.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Classes = require(Shared.Balance.Classes)
local Combat = require(Shared.Balance.Combat)
local Progression = require(Shared.Balance.Progression)

type PlayerData = {
	classId: string,
	attributes: Types.Attributes,
	level: number,
	xp: number, -- XP dentro do nível atual
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
			level = 1,
			xp = 0,
			gold = 0,
		}
		playerData[player] = data
	end
	return data
end

local function replicate(player: Player, data: PlayerData)
	player:SetAttribute(Keys.PlayerAttr.Level, data.level)
	player:SetAttribute(Keys.PlayerAttr.XP, data.xp)
	local toNext = Formulas.xpToNextLevel(data.level)
	player:SetAttribute(Keys.PlayerAttr.XPToNext, if toNext == math.huge then 0 else toNext)
	player:SetAttribute(Keys.PlayerAttr.Gold, data.gold)
	for _, name in Formulas.attributeNames() do
		player:SetAttribute(Keys.statAttr(name), data.attributes[name])
	end
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

function ProgressionService.getLevel(player: Player): number
	return getData(player).level
end

-- Vida máxima pela classe + Vitalidade. Quando ela aumenta (subiu de nível), a diferença entra na vida atual:
-- não é cura total (vida cheia só no checkpoint), mas o ponto novo não fica "vazio".
local function applyHealth(player: Player, fillToMax: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local data = getData(player)
	local newMax = Formulas.maxHealth(ProgressionService.getClass(player), data.attributes)
	local gained = math.max(newMax - humanoid.MaxHealth, 0)
	humanoid.MaxHealth = newMax
	humanoid.Health = if fillToMax then newMax else math.min(humanoid.Health + gained, newMax)
end

function ProgressionService.addXp(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = getData(player)
	local newLevel, newXp, levelsGained = Formulas.addXp(data.level, data.xp, amount)
	data.level = newLevel
	data.xp = newXp

	if levelsGained > 0 then
		local classDef = ProgressionService.getClass(player)
		local before = data.attributes
		data.attributes = Formulas.distributeRecommended(before, levelsGained * Progression.pointsPerLevel, classDef)
		local gains: { [string]: number } = {}
		for _, name in Formulas.attributeNames() do
			local delta = data.attributes[name] - before[name]
			if delta > 0 then
				gains[name] = delta
			end
		end
		applyHealth(player, false)
		local payload: Remotes.LevelUpPayload = { level = newLevel, gains = gains }
		Remotes.get("LevelUp"):FireClient(player, payload)
	end
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

-- Vida cheia (checkpoint, M6).
function ProgressionService.restoreHealth(player: Player)
	applyHealth(player, true)
end

-- "Retrato" da progressão global, tirado ao entrar na run. No game over, restore() volta exatamente a ele:
-- o jogador perde só o que ganhou na run (XP, níveis, pontos, Gold).
export type Snapshot = {
	level: number,
	xp: number,
	gold: number,
	attributes: Types.Attributes,
}

function ProgressionService.snapshot(player: Player): Snapshot
	local data = getData(player)
	return { level = data.level, xp = data.xp, gold = data.gold, attributes = table.clone(data.attributes) }
end

function ProgressionService.restore(player: Player, snapshot: Snapshot)
	local data = getData(player)
	data.level = snapshot.level
	data.xp = snapshot.xp
	data.gold = snapshot.gold
	data.attributes = table.clone(snapshot.attributes)
	replicate(player, data)
	applyHealth(player, true)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.WalkSpeed = ProgressionService.getClass(player).walkSpeed
	applyHealth(player, true)

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
