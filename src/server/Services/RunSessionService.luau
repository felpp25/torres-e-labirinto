--!strict
-- A run atual (GDD > Vidas e > Progressão global e torres):
-- - 3 vidas do GRUPO. Wipe (todos mortos) gasta 1 vida e recomeça o andar atual (mesmo labirinto).
-- - Sem vidas: GAME OVER. Cada jogador volta ao "retrato" tirado quando entrou na run (perde XP, níveis,
--   pontos e Gold ganhos nela) e a torre recomeça do andar 1 com labirinto novo.
-- - Coração: drop raro dos mobs que devolve 1 vida (até o máximo). Pego por qualquer jogador vivo encostando.
-- Vidas e nº da run vão para Attributes do workspace (o HUD mostra e avisa).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Run = require(Shared.Balance.Run)

local CombatService = require(script.Parent.CombatService)
local DungeonService = require(script.Parent.DungeonService)
local EnemyService = require(script.Parent.EnemyService)
local LifeService = require(script.Parent.LifeService)
local ProgressionService = require(script.Parent.ProgressionService)

local HEART_COLOR = Color3.fromRGB(255, 60, 90)
local HEART_SIZE = 2

local RunSessionService = {}

local rng = Random.new()
local lives = Run.startingLives
local runNumber = 1
local snapshots: { [Player]: ProgressionService.Snapshot } = {}
local hearts: { Part } = {}

local function publish()
	workspace:SetAttribute(Keys.WorldAttr.Lives, lives)
	workspace:SetAttribute(Keys.WorldAttr.RunNumber, runNumber)
end

local function takeSnapshot(player: Player)
	snapshots[player] = ProgressionService.snapshot(player)
end

local function gameOver()
	print(`[Run] GAME OVER na run {runNumber}: todos voltam ao estado de antes da run`)
	for player, snapshot in snapshots do
		if player.Parent then
			ProgressionService.restore(player, snapshot)
		end
	end
	runNumber += 1
	lives = Run.startingLives
	publish()
	DungeonService.startFloor(1) -- andar 1 com labirinto novo
	LifeService.respawnAll()
	for _, player in Players:GetPlayers() do
		CombatService.restoreResources(player)
		takeSnapshot(player) -- a nova run começa deste ponto
	end
end

local function onWipe()
	lives -= 1
	if lives <= 0 then
		gameOver()
		return
	end
	print(`[Run] wipe: {lives} vida(s) restante(s), recomeçando o andar {DungeonService.getCurrentFloor()}`)
	publish()
	DungeonService.restartCurrentFloor()
	LifeService.respawnAll()
end

local function spawnHeart(position: Vector3, parent: Instance)
	local heart = Instance.new("Part")
	heart.Name = "Heart"
	heart.Shape = Enum.PartType.Ball
	heart.Size = Vector3.one * HEART_SIZE
	heart.Anchored = true
	heart.CanCollide = false
	heart.Material = Enum.Material.Neon
	heart.Color = HEART_COLOR
	heart.Position = position
	heart.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100
	gui.Parent = heart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "+1 VIDA"
	label.TextColor3 = HEART_COLOR
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui

	table.insert(hearts, heart)
	print("[Run] um Coração caiu!")
end

local function onMobDied(_: Types.MobDef, position: Vector3, parent: Instance)
	-- TODO (futuro): a Sorte de quem matou aumenta a chance (GDD > Vidas).
	if rng:NextNumber() < Run.heartDropChance then
		spawnHeart(position, parent)
	end
end

local function checkHearts()
	for i = #hearts, 1, -1 do
		local heart = hearts[i]
		if not heart.Parent then
			table.remove(hearts, i) -- o andar foi trocado/recomeçado: o coração sumiu junto
		else
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					root
					and root:IsA("BasePart")
					and LifeService.isAlive(player)
					and (root.Position - heart.Position).Magnitude <= Run.heartPickupRadius
				then
					heart:Destroy()
					table.remove(hearts, i)
					lives = math.min(lives + 1, Run.maxLives)
					publish()
					print(`[Run] {player.Name} pegou um Coração: {lives} vida(s)`)
					break
				end
			end
		end
	end
end

function RunSessionService.getLives(): number
	return lives
end

function RunSessionService.init()
	EnemyService.setDeathHandler(onMobDied)
	-- Quem entra no meio da run tem o retrato tirado na entrada (ProgressionService já criou os dados dele).
	Players.PlayerAdded:Connect(takeSnapshot)
	Players.PlayerRemoving:Connect(function(player: Player)
		snapshots[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		takeSnapshot(player)
	end
end

function RunSessionService.start()
	if not Run.startInDungeon then
		return
	end
	publish()
	LifeService.setAllDeadHandler(onWipe)
	while true do
		task.wait(Run.heartCheckInterval)
		checkHearts()
	end
end

return RunSessionService
