--!strict
-- Andares da run: gera o layout (MazeGenerator), constrói (RoomBuilder), coloca os mobs e leva os jogadores
-- para a entrada. Todos morreram: a run volta ao andar 1 com um labirinto novo (GDD > Morte e checkpoint).
-- Ligado por Balance/Run.startInDungeon.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Dungeon = require(Shared.Balance.Dungeon)
local Mobs = require(Shared.Balance.Mobs)
local Run = require(Shared.Balance.Run)

local MazeGenerator = require(script.Parent.Parent.Dungeon.MazeGenerator)
local RoomBuilder = require(script.Parent.Parent.Dungeon.RoomBuilder)
local EnemyService = require(script.Parent.EnemyService)
local LifeService = require(script.Parent.LifeService)

local SPAWN_HEIGHT = 4 -- studs acima do piso
local PLAYER_SPAWN_SPACING = 4

local DungeonService = {}

local rng = Random.new()
local currentFloor = 0
local current: RoomBuilder.BuiltFloor? = nil
local container: Folder? = nil

local function getContainer(): Folder
	if not container then
		local folder = Instance.new("Folder")
		folder.Name = "Dungeon"
		folder.Parent = workspace
		container = folder
	end
	return container :: Folder
end

-- Ponto de nascimento na entrada, com um pequeno espaçamento por jogador para não nascerem uns dentro dos outros.
local function entranceCFrame(index: number): CFrame
	local built = current
	assert(built, "nenhum andar construído")
	local center = built.roomCenters[built.entrance]
	local offset = Vector3.new(((index - 1) % 4 - 1.5) * PLAYER_SPAWN_SPACING, SPAWN_HEIGHT, 0)
	return CFrame.new(center + offset)
end

local function playerIndex(player: Player): number
	return table.find(Players:GetPlayers(), player) or 1
end

local function spawnMobs(built: RoomBuilder.BuiltFloor, layout: Types.FloorLayout, floorNumber: number): number
	local mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = built.folder

	local perRoom = Dungeon.mobsPerCombatRoom + Dungeon.extraMobsPerFloor * (floorNumber - 1)
	local multiplier = Formulas.floorStatMultiplier(floorNumber, Dungeon.mobStatGrowthPerFloor)
	local spread = Dungeon.roomSize * Dungeon.mobSpawnSpread
	local total = 0
	for _, room in layout.rooms do
		if room.kind == "Combat" or room.kind == "DeadEnd" then
			local center = built.roomCenters[room]
			for _ = 1, perRoom do
				local mobId = Dungeon.mobPool[rng:NextInteger(1, #Dungeon.mobPool)]
				local def = Mobs[mobId]
				assert(def, `mob desconhecido em Dungeon.mobPool: {mobId}`)
				local offset =
					Vector3.new(rng:NextNumber(-spread, spread), SPAWN_HEIGHT, rng:NextNumber(-spread, spread))
				EnemyService.spawn(def, CFrame.new(center + offset), multiplier, mobsFolder)
				total += 1
			end
		end
	end
	return total
end

-- Gera e constrói o andar `floorNumber` (o anterior é destruído, com os mobs dele) e leva os vivos para a entrada.
function DungeonService.startFloor(floorNumber: number)
	if current then
		current.folder:Destroy()
		current = nil
	end

	local seed = rng:NextInteger(1, 2 ^ 31 - 2)
	local layout = MazeGenerator.generate(seed, floorNumber, Dungeon)
	local ok, problems = MazeGenerator.validate(layout, Dungeon)
	if not ok then
		warn(`[Andar] seed {seed} violou regras: {table.concat(problems, "; ")}`)
	end

	local built = RoomBuilder.build(layout, Dungeon.floorOrigin, getContainer())
	current = built
	currentFloor = floorNumber
	workspace:SetAttribute("FloorNumber", floorNumber)
	local mobCount = spawnMobs(built, layout, floorNumber)

	local deadEnds = 0
	for _, room in layout.rooms do
		if room.kind == "DeadEnd" then
			deadEnds += 1
		end
	end
	print(`[Andar] {floorNumber}: seed {seed}, {#layout.rooms} salas, {deadEnds} becos, {mobCount} mobs`)

	for _, player in Players:GetPlayers() do
		if LifeService.isAlive(player) and player.Character then
			player.Character:PivotTo(entranceCFrame(playerIndex(player)))
		end
	end
end

function DungeonService.getCurrentFloor(): number
	return currentFloor
end

function DungeonService.init() end

function DungeonService.start()
	if not Run.startInDungeon then
		return
	end
	DungeonService.startFloor(1)
	LifeService.setSpawnProvider(function(player: Player): CFrame?
		return if current then entranceCFrame(playerIndex(player)) else nil
	end)
	LifeService.setAllDeadHandler(function()
		print("[Run] todos morreram: recomeçando do andar 1")
		DungeonService.startFloor(1)
		LifeService.respawnAll()
	end)
end

return DungeonService
