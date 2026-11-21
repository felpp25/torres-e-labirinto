--!strict
-- Andares da run: gera o layout (MazeGenerator), constrói (RoomBuilder), coloca os mobs e o puzzle e leva os
-- jogadores para a entrada. TUDO do andar (layout, mobs, placas) sai da seed: a mesma seed refaz o mesmo andar.
-- O que fazer quando todos morrem (vidas, game over) é decidido pelo RunSessionService.
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

local seedRng = Random.new() -- só sorteia a seed de cada andar novo
local currentFloor = 0
local currentSeed = 0
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

local function spawnMobs(
	built: RoomBuilder.BuiltFloor,
	layout: Types.FloorLayout,
	floorNumber: number,
	rng: Random
): number
	local mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = built.folder

	local perRoom =
		Formulas.mobsPerRoom(floorNumber, Dungeon.mobsPerCombatRoom, Dungeon.extraMobsPerStep, Dungeon.floorsPerMobStep)
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

-- Constrói o andar `floorNumber` (o anterior é destruído, com os mobs dele) e leva os vivos para a entrada.
-- Sem `seed`: andar novo (seed sorteada). Com `seed`: refaz exatamente aquele andar.
function DungeonService.startFloor(floorNumber: number, seed: number?)
	if current then
		current.folder:Destroy()
		current = nil
	end

	local floorSeed = seed or seedRng:NextInteger(1, 2 ^ 31 - 2)
	currentSeed = floorSeed
	local layout = MazeGenerator.generate(floorSeed, floorNumber, Dungeon)
	local ok, problems = MazeGenerator.validate(layout, Dungeon)
	if not ok then
		warn(`[Andar] seed {floorSeed} violou regras: {table.concat(problems, "; ")}`)
	end

	local built = RoomBuilder.build(layout, Dungeon.floorOrigin, getContainer())
	current = built
	currentFloor = floorNumber
	workspace:SetAttribute(Keys.WorldAttr.FloorNumber, floorNumber)
	-- Gerador próprio do conteúdo, derivado da seed (separado do do layout): mesmos mobs e placas ao refazer.
	local contentRng = Random.new(floorSeed + 1)
	local mobCount = spawnMobs(built, layout, floorNumber, contentRng)
	PuzzleService.setup(built.roomCenters[built.puzzle], built.folder, contentRng)

	local deadEnds = 0
	for _, room in layout.rooms do
		if room.kind == "DeadEnd" then
			deadEnds += 1
		end
	end
	local action = if seed then "recomeçado" else "gerado"
	print(`[Andar] {floorNumber} {action}: seed {floorSeed}, {#layout.rooms} salas, {deadEnds} becos, {mobCount} mobs`)

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
end

-- Recomeça o andar atual com a mesma seed (mesmo labirinto, mobs e placas no estado inicial).
function DungeonService.restartCurrentFloor()
	DungeonService.startFloor(currentFloor, currentSeed)
end

return DungeonService
