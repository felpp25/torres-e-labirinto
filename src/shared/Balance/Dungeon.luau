--!strict
-- Geração de andares e escala de dificuldade.

local Dungeon = table.freeze({
	-- Grade do labirinto
	gridWidth = 5,
	gridHeight = 5,
	roomSize = 48, -- lado de cada sala (studs)
	wallHeight = 14,
	wallThickness = 2,
	doorWidth = 10,

	-- Regras do GDD: 8 a 12 salas, caminho garantido até o puzzle, 1 ou 2 becos sem saída
	minRooms = 8,
	maxRooms = 12,
	minDeadEnds = 1,
	maxDeadEnds = 2,

	-- Mobs
	mobsPerCombatRoom = 2,
	extraMobsPerFloor = 1, -- +1 mob por sala de combate a cada andar
	mobStatGrowthPerFloor = 0.15, -- +15% de vida e dano por andar

	-- Puzzle de placas de pressão (ficam ativadas depois de pisadas; funciona solo e em grupo)
	minPlates = 2,
	maxPlates = 3,

	-- Altura onde os andares são construídos
	floorOrigin = Vector3.new(0, 100, 0),
})

return Dungeon
