--!strict
-- Andares da run: gera o layout (MazeGenerator), constrói (RoomBuilder), coloca os mobs e leva os jogadores
-- para a entrada. Todos morreram: a run volta ao andar 1 com um labirinto novo (GDD > Morte e checkpoint).
-- Ligado por Balance/Run.startInDungeon.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Dungeon = require(Shared.Balance.Dungeon)
local Mobs = require(Shared.Balance.Mobs)
local Run = require(Shared.Balance.Run)

local MazeGenerator = require(script.Parent.Parent.Dungeon.MazeGenerator)
local RoomBuilder = require(script.Parent.Parent.Dungeon.RoomBuilder)
local CombatService = require(script.Parent.CombatService)
local EnemyService = require(script.Parent.EnemyService)
local LifeService = require(script.Parent.LifeService)
local ProgressionService = require(script.Parent.ProgressionService)
local PuzzleService = require(script.Parent.PuzzleService)

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
	workspace:SetAttribute(Keys.WorldAttr.FloorNumber, floorNumber)
	local mobCount = spawnMobs(built, layout, floorNumber)
	PuzzleService.setup(built.roomCenters[built.puzzle], built.folder)

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

-- Checkpoint (GDD > Morte e checkpoint): um jogador vivo passou pela saída aberta.
-- Próximo andar (mais difícil); os mortos do grupo renascem na entrada; vida, mana e stamina cheias para todos.
local function onCheckpoint(player: Player)
	print(`[Andar] {currentFloor} concluído por {player.Name}`)
	DungeonService.startFloor(currentFloor + 1)
	LifeService.reviveDead(nil) -- nasce pelo spawn provider: entrada do andar novo
	for _, member in Players:GetPlayers() do
		if LifeService.isAlive(member) then
			ProgressionService.restoreHealth(member)
			CombatService.restoreResources(member)
		end
	end
end

-- Está dentro da sala de Entrada do andar atual? (zona segura para acordar mobs)
local function isInEntrance(position: Vector3): boolean
	local built = current
	if not built then
		return false
	end
	local center = built.roomCenters[built.entrance]
	local half = Dungeon.roomSize / 2
	return math.abs(position.X - center.X) <= half and math.abs(position.Z - center.Z) <= half
end

function DungeonService.init()
	PuzzleService.setExitHandler(onCheckpoint)
	EnemyService.setWakeSafeZone(isInEntrance)
end

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
