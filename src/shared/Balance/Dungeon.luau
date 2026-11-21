--!strict
-- Geração de andares e escala de dificuldade.

local Dungeon = table.freeze({
	-- Grade do labirinto
	gridWidth = 5,
	gridHeight = 5,
	roomSize = 48, -- lado de cada sala (studs)
	wallHeight = 14,
	wallThickness = 2,
	floorThickness = 1,
	doorWidth = 10,

	-- Regras do GDD: 8 a 12 salas, caminho garantido até o puzzle, 1 ou 2 becos sem saída
	minRooms = 8,
	maxRooms = 12,
	minDeadEnds = 1,
	maxDeadEnds = 2,
	maxBranchLength = 2, -- salas em cada corredor lateral que termina num beco

	-- Mobs (salas de combate e becos)
	mobPool = table.freeze({ "Brute" }),
	mobsPerCombatRoom = 2,
	extraMobsPerStep = 1, -- +1 mob por sala de combate...
	floorsPerMobStep = 2, -- ...a cada 2 andares (andares 1-2: 2 mobs; 3-4: 3 mobs; ...)
	mobStatGrowthPerFloor = 0.15, -- +15% de vida e dano por andar
	mobSpawnSpread = 0.3, -- mobs nascem até esta fração do lado da sala a partir do centro

	-- Puzzle de placas de pressão (ficam ativadas depois de pisadas; funciona solo e em grupo)
	minPlates = 2,
	maxPlates = 3,
	plateSize = 6, -- lado da placa (studs)
	plateCornerOffset = 14, -- distância do centro da sala até cada placa, nos eixos X e Z
	exitSize = 8, -- lado da saída (escada) no centro da sala do puzzle
	puzzleCheckInterval = 0.15, -- s entre verificações de quem está pisando nas placas/saída

	-- Onde os andares são construídos: longe do lobby (os mobs do andar não enxergam o lobby e vice-versa)
	floorOrigin = Vector3.new(1000, 50, 0),
})

return Dungeon
