--!strict
-- Andares das runs: gera o layout (MazeGenerator), constrói (RoomBuilder) no ponto da run no mapa, coloca os mobs e
-- o puzzle e leva os participantes para a entrada. TUDO do andar (layout, mobs, placas) sai da seed: a mesma seed
-- refaz o mesmo andar. Um andar por run (várias runs por servidor).
-- O que fazer quando todos morrem (vidas, game over) é decidido pelo RunSessionService.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Dungeon = require(Shared.Balance.Dungeon)
local Mobs = require(Shared.Balance.Mobs)
local Bosses = require(Shared.Balance.Bosses)
local Towers = require(Shared.Balance.Towers)

local MazeGenerator = require(script.Parent.Parent.Dungeon.MazeGenerator)
local RoomBuilder = require(script.Parent.Parent.Dungeon.RoomBuilder)
local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)
local CombatService = require(script.Parent.CombatService)
local EnemyService = require(script.Parent.EnemyService)
local LifeService = require(script.Parent.LifeService)
local ProgressionService = require(script.Parent.ProgressionService)
local PuzzleService = require(script.Parent.PuzzleService)
local BossService = require(script.Parent.BossService)

local SPAWN_HEIGHT = 4 -- studs acima do piso
local PLAYER_SPAWN_SPACING = 4

type FloorState = {
	number: number,
	seed: number,
	built: RoomBuilder.BuiltFloor,
}

local DungeonService = {}

local seedRng = Random.new() -- só sorteia a seed de cada andar novo
local floors: { [RunRegistry.Run]: FloorState } = {}

-- Ponto de nascimento na entrada, com um pequeno espaçamento por jogador para não nascerem uns dentro dos outros.
local function entranceCFrame(floor: FloorState, index: number): CFrame
	local built = floor.built
	local center = built.roomCenters[built.entrance]
	local offset = Vector3.new(((index - 1) % 4 - 1.5) * PLAYER_SPAWN_SPACING, SPAWN_HEIGHT, 0)
	return CFrame.new(center + offset)
end

local function memberIndex(run: RunRegistry.Run, player: Player): number
	return table.find(run.members, player) or 1
end

-- Salas que recebem o mob de apoio da torre (ex.: o Arremessador): `share` dos mobs do andar, no máximo 1 por sala e
-- só em sala com 2+ mobs (sempre sobra alguém da linha de frente). Sorteadas pela seed do andar: refazer o andar dá
-- as mesmas salas. Andares com 3 mobs por sala e share 1/3: exatamente 1 por sala.
local function pickSupportRooms(counts: { number }, share: number, rng: Random): { [number]: boolean }
	local chosen: { [number]: boolean } = {}
	local total = 0
	local eligible: { number } = {}
	for index, count in counts do
		total += count
		if count >= 2 then
			table.insert(eligible, index)
		end
	end
	local wanted = math.min(math.round(total * share), #eligible)
	for i = 1, wanted do -- embaralha só o começo da lista (Fisher-Yates parcial)
		local j = rng:NextInteger(i, #eligible)
		eligible[i], eligible[j] = eligible[j], eligible[i]
		chosen[eligible[i]] = true
	end
	return chosen
end

local function spawnMobs(
	tower: Towers.TowerDef,
	built: RoomBuilder.BuiltFloor,
	layout: Types.FloorLayout,
	floorNumber: number,
	rng: Random,
	isBossFloor: boolean
): number
	local mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = built.folder

	local mobRooms: { Types.Room } = {}
	for _, room in layout.rooms do
		if room.kind == "Combat" or room.kind == "DeadEnd" then
			table.insert(mobRooms, room)
		end
	end
	local perRoom =
		Formulas.mobsPerRoom(floorNumber, Dungeon.mobsPerCombatRoom, Dungeon.extraMobsPerStep, Dungeon.floorsPerMobStep)
	-- No andar do boss há um teto de mobs no andar inteiro (o desafio principal é o boss).
	local counts = Formulas.mobDistribution(#mobRooms, perRoom, if isBossFloor then Dungeon.bossFloorMaxMobs else nil)
	-- Rampa do andar (+15% por andar) vezes a força da torre.
	local multiplier = Formulas.floorStatMultiplier(floorNumber, Dungeon.mobStatGrowthPerFloor) * tower.statMultiplier
	local spread = Dungeon.roomSize * Dungeon.mobSpawnSpread
	local supportMob = tower.supportMob
	local supportRooms = if supportMob then pickSupportRooms(counts, tower.supportShare, rng) else {}
	local total = 0
	for index, room in mobRooms do
		local center = built.roomCenters[room]
		for slot = 1, counts[index] do
			-- O último mob de uma sala escolhida é o de apoio; os outros, da linha de frente.
			local mobId: string = if supportMob
					and supportRooms[index]
					and slot == counts[index]
				then supportMob
				else tower.mobPool[rng:NextInteger(1, #tower.mobPool)]
			local def = Mobs[mobId]
			assert(def, `mob desconhecido na {tower.displayName}: {mobId}`)
			local offset = Vector3.new(rng:NextNumber(-spread, spread), SPAWN_HEIGHT, rng:NextNumber(-spread, spread))
			local model =
				EnemyService.spawn(def, CFrame.new(center + offset), multiplier, mobsFolder, tower.rewardMultiplier)
			model:SetAttribute("Room", index) -- diagnóstico (DevService): de que sala é o mob
			total += 1
		end
	end
	return total
end

-- Constrói o andar `floorNumber` da run (o anterior é destruído, com os mobs dele) e leva os participantes vivos
-- para a entrada. Sem `seed`: andar novo (seed sorteada). Com `seed`: refaz exatamente aquele andar.
function DungeonService.startFloor(run: RunRegistry.Run, floorNumber: number, seed: number?)
	local previous = floors[run]
	if previous then
		previous.built.folder:Destroy()
		floors[run] = nil
	end

	local floorSeed = seed or seedRng:NextInteger(1, 2 ^ 31 - 2)
	local isBossFloor = floorNumber >= Dungeon.floorsPerTower
	local layout = MazeGenerator.generate(floorSeed, floorNumber, Dungeon, isBossFloor)
	local ok, problems = MazeGenerator.validate(layout, Dungeon)
	if not ok then
		warn(`[Andar] seed {floorSeed} violou regras: {table.concat(problems, "; ")}`)
	end

	local built = RoomBuilder.build(layout, run.origin, run.folder)
	local floor: FloorState = { number = floorNumber, seed = floorSeed, built = built }
	floors[run] = floor
	-- IsBossFloor antes de FloorNumber: o HUD lê os dois quando o andar muda.
	RunRegistry.setState(run, Keys.RunAttr.IsBossFloor, isBossFloor)
	RunRegistry.setState(run, Keys.RunAttr.FloorNumber, floorNumber)
	-- Gerador próprio do conteúdo, derivado da seed (separado do do layout): mesmos mobs e placas ao refazer.
	local contentRng = Random.new(floorSeed + 1)
	local tower = Towers.byId[run.towerId]
	assert(tower, `torre desconhecida: {run.towerId}`)
	local mobCount = spawnMobs(tower, built, layout, floorNumber, contentRng, isBossFloor)
	local arena = built.arena
	if isBossFloor and arena then
		PuzzleService.clear(run)
		local bossDef = Bosses.byId[tower.bossId]
		assert(bossDef, `boss desconhecido na {tower.displayName}: {tower.bossId}`)
		BossService.spawn(
			run,
			bossDef,
			arena,
			arena.center.Y,
			built.folder,
			tower.statMultiplier,
			tower.rewardMultiplier
		)
	else
		BossService.clear(run)
		PuzzleService.setup(run, built.roomCenters[built.goal], built.folder, contentRng)
	end

	local deadEnds = 0
	for _, room in layout.rooms do
		if room.kind == "DeadEnd" then
			deadEnds += 1
		end
	end
	local action = if seed then "recomeçado" else "gerado"
	print(
		`[Andar] run {run.id}: andar {floorNumber} {action} (seed {floorSeed}, {#layout.rooms} salas, {deadEnds} becos, {mobCount} mobs)`
	)

	-- Só os participantes vivos vão para a entrada (os mortos renascem lá pelo spawn provider).
	for _, player in run.members do
		if LifeService.isAlive(player) and player.Character then
			player.Character:PivotTo(entranceCFrame(floor, memberIndex(run, player)))
		end
	end
end

-- Ponto de nascimento na entrada do andar atual da run para este jogador. nil = a run ainda não tem andar.
function DungeonService.entranceCFrameFor(run: RunRegistry.Run, player: Player): CFrame?
	local floor = floors[run]
	if not floor then
		return nil
	end
	return entranceCFrame(floor, memberIndex(run, player))
end

-- Fim da run: destrói o andar (mobs, boss e puzzle junto) e limpa o estado que o HUD lê.
function DungeonService.clear(run: RunRegistry.Run)
	local floor = floors[run]
	if floor then
		floor.built.folder:Destroy()
		floors[run] = nil
	end
	BossService.clear(run)
	PuzzleService.clear(run)
	RunRegistry.setState(run, Keys.RunAttr.IsBossFloor, false)
	RunRegistry.setState(run, Keys.RunAttr.FloorNumber, nil)
end

-- Andar atual da run (0 = nenhum).
function DungeonService.getCurrentFloor(run: RunRegistry.Run): number
	local floor = floors[run]
	return if floor then floor.number else 0
end

-- Vai para o andar `floorNumber` (novo): os mortos do grupo renascem na entrada e todos ficam com vida, mana e
-- stamina cheias. Usado no checkpoint.
function DungeonService.advanceTo(run: RunRegistry.Run, floorNumber: number)
	DungeonService.startFloor(run, floorNumber)
	LifeService.reviveDead(run.members) -- nascem pelo spawn provider: entrada do andar novo
	for _, member in run.members do
		if LifeService.isAlive(member) then
			ProgressionService.restoreHealth(member)
			CombatService.restoreResources(member)
		end
	end
end

-- Checkpoint (GDD > Morte e checkpoint): um participante vivo passou pela saída aberta -> próximo andar.
local function onCheckpoint(run: RunRegistry.Run, player: Player)
	local floorNumber = DungeonService.getCurrentFloor(run)
	print(`[Andar] run {run.id}: andar {floorNumber} concluído por {player.Name}`)
	DungeonService.advanceTo(run, floorNumber + 1)
end

-- Está dentro da sala de Entrada do andar de alguma run? (zona segura para ACORDAR mobs)
local function isInEntrance(position: Vector3): boolean
	local half = Dungeon.roomSize / 2
	for _, floor in floors do
		local center = floor.built.roomCenters[floor.built.entrance]
		if math.abs(position.X - center.X) <= half and math.abs(position.Z - center.Z) <= half then
			return true
		end
	end
	return false
end

function DungeonService.init()
	PuzzleService.setExitHandler(onCheckpoint)
	EnemyService.setWakeSafeZone(isInEntrance)
end

-- O andar 1 é criado quando um grupo entra pelo portal (RunSessionService).
function DungeonService.start() end

-- Recomeça o andar atual da run com a mesma seed (mesmo labirinto, mobs e placas no estado inicial).
function DungeonService.restartCurrentFloor(run: RunRegistry.Run)
	local floor = floors[run]
	if floor then
		DungeonService.startFloor(run, floor.number, floor.seed)
	end
end

return DungeonService
