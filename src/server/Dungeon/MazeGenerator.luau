--!strict
-- Gera o LAYOUT de um andar (só dados: grade, salas e portas). Não cria peças: isso é o RoomBuilder.
-- Função pura e determinística: a mesma seed gera sempre o mesmo andar (a seed vai para o log).
--
-- Algoritmo:
-- 1. sorteia o nº de salas (8 a 12) e o nº de becos (1 ou 2), cada beco com um corredor de 1 a 2 salas;
-- 2. caminho principal (Entrada -> ... -> Puzzle) por busca em profundidade com retrocesso na grade;
-- 3. pendura os corredores laterais em salas do meio do caminho; a última sala de cada um é um beco.
-- Só existem portas entre salas ligadas (o andar é uma árvore): o caminho até o puzzle é garantido.
-- Andar do boss: a sala final é "Boss" (no lugar de "Puzzle") e fica sempre na BORDA da grade, para a arena
-- poder crescer para fora da grade sem invadir outras salas.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

export type Config = {
	gridWidth: number,
	gridHeight: number,
	minRooms: number,
	maxRooms: number,
	minDeadEnds: number,
	maxDeadEnds: number,
	maxBranchLength: number,
}

type Direction = "North" | "South" | "East" | "West"
type Cell = { x: number, y: number }

local DIRECTIONS: { Direction } = { "North", "South", "East", "West" }
-- Chave `string` (não `Direction`): o verificador de tipos alarga o laço sobre DIRECTIONS para string.
local OFFSETS: { [string]: Cell } = {
	North = { x = 0, y = -1 },
	South = { x = 0, y = 1 },
	East = { x = 1, y = 0 },
	West = { x = -1, y = 0 },
}
local OPPOSITE: { [string]: Direction } = { North = "South", South = "North", East = "West", West = "East" }

local MAX_ATTEMPTS = 50
local MAX_DFS_STEPS = 20000

local MazeGenerator = {}

local function cellKey(x: number, y: number): number
	return y * 1000 + x
end

local function shuffled(list: { Direction }, rng: Random): { Direction }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function newRoom(x: number, y: number, kind: Types.RoomKind): Types.Room
	return { x = x, y = y, kind = kind, doors = { North = false, South = false, East = false, West = false } }
end

local function connect(a: Types.Room, b: Types.Room)
	for _, direction in DIRECTIONS do
		local offset = OFFSETS[direction]
		if a.x + offset.x == b.x and a.y + offset.y == b.y then
			a.doors[direction] = true
			b.doors[OPPOSITE[direction]] = true
			return
		end
	end
	error("connect: salas não são vizinhas")
end

local function tryGenerate(
	rng: Random,
	seed: number,
	floorNumber: number,
	config: Config,
	isBossFloor: boolean
): Types.FloorLayout?
	local width, height = config.gridWidth, config.gridHeight
	local function inBounds(x: number, y: number): boolean
		return x >= 0 and x < width and y >= 0 and y < height
	end

	local roomCount = rng:NextInteger(config.minRooms, config.maxRooms)
	local deadEndCount = rng:NextInteger(config.minDeadEnds, config.maxDeadEnds)
	local branchLengths: { number } = {}
	local branchTotal = 0
	for i = 1, deadEndCount do
		branchLengths[i] = rng:NextInteger(1, config.maxBranchLength)
		branchTotal += branchLengths[i]
	end
	local mainLength = roomCount - branchTotal
	if mainLength < 3 then
		return nil -- precisa de Entrada, ao menos 1 sala no meio e o Puzzle
	end

	-- 2. Caminho principal (busca em profundidade com retrocesso, com limite de passos).
	local occupied: { [number]: boolean } = {}
	local path: { Cell } = {}
	local steps = 0
	local function dfs(x: number, y: number): boolean
		steps += 1
		if steps > MAX_DFS_STEPS then
			return false
		end
		occupied[cellKey(x, y)] = true
		table.insert(path, { x = x, y = y })
		if #path == mainLength then
			return true
		end
		for _, direction in shuffled(DIRECTIONS, rng) do
			local offset = OFFSETS[direction]
			local nx, ny = x + offset.x, y + offset.y
			if inBounds(nx, ny) and not occupied[cellKey(nx, ny)] and dfs(nx, ny) then
				return true
			end
		end
		occupied[cellKey(x, y)] = nil
		table.remove(path)
		return false
	end
	if not dfs(rng:NextInteger(0, width - 1), rng:NextInteger(0, height - 1)) then
		return nil
	end
	local goal = path[#path]
	local goalOnBorder = goal.x == 0 or goal.x == width - 1 or goal.y == 0 or goal.y == height - 1
	if isBossFloor and not goalOnBorder then
		return nil -- tenta de novo: a arena do boss precisa de um lado livre para fora da grade
	end
	local goalKind: Types.RoomKind = if isBossFloor then "Boss" else "Puzzle"

	local rooms: { Types.Room } = {}
	local byKey: { [number]: Types.Room } = {}
	local mainRooms: { Types.Room } = {}
	for i, cell in path do
		local kind: Types.RoomKind = if i == 1 then "Entrance" elseif i == #path then goalKind else "Combat"
		local room = newRoom(cell.x, cell.y, kind)
		table.insert(rooms, room)
		table.insert(mainRooms, room)
		byKey[cellKey(cell.x, cell.y)] = room
		if i > 1 then
			connect(mainRooms[i - 1], room)
		end
	end

	-- 3. Corredores laterais terminando em becos, pendurados em salas do MEIO do caminho principal.
	for _, length in branchLengths do
		local placed = false
		local anchors: { Types.Room } = {}
		for i = 2, #mainRooms - 1 do
			table.insert(anchors, mainRooms[i])
		end
		-- Embaralha as salas candidatas.
		for i = #anchors, 2, -1 do
			local j = rng:NextInteger(1, i)
			anchors[i], anchors[j] = anchors[j], anchors[i]
		end

		for _, anchor in anchors do
			local current = anchor
			local branch: { Types.Room } = {}
			for _ = 1, length do
				local nextRoom: Types.Room? = nil
				for _, direction in shuffled(DIRECTIONS, rng) do
					local offset = OFFSETS[direction]
					local nx, ny = current.x + offset.x, current.y + offset.y
					if inBounds(nx, ny) and not byKey[cellKey(nx, ny)] then
						nextRoom = newRoom(nx, ny, "Combat")
						break
					end
				end
				if not nextRoom then
					break
				end
				local room = nextRoom :: Types.Room
				byKey[cellKey(room.x, room.y)] = room
				table.insert(branch, room)
				current = room
			end

			if #branch == length then
				local previous = anchor
				for _, room in branch do
					table.insert(rooms, room)
					connect(previous, room)
					previous = room
				end
				branch[#branch].kind = "DeadEnd"
				placed = true
				break
			else
				for _, room in branch do -- desfaz a tentativa
					byKey[cellKey(room.x, room.y)] = nil
				end
			end
		end
		if not placed then
			return nil
		end
	end

	return { seed = seed, floorNumber = floorNumber, width = width, height = height, rooms = rooms }
end

-- Gera o layout. Tenta de novo (com o mesmo gerador, então continua determinístico) se uma tentativa falhar.
function MazeGenerator.generate(
	seed: number,
	floorNumber: number,
	config: Config,
	isBossFloor: boolean
): Types.FloorLayout
	local rng = Random.new(seed)
	for _ = 1, MAX_ATTEMPTS do
		local layout = tryGenerate(rng, seed, floorNumber, config, isBossFloor)
		if layout then
			return layout
		end
	end
	error(`MazeGenerator: não consegui gerar o andar (seed {seed})`)
end

local function doorCount(room: Types.Room): number
	local count = 0
	for _, direction in DIRECTIONS do
		if room.doors[direction] then
			count += 1
		end
	end
	return count
end

-- Confere as regras do GDD num layout. Devolve (ok, lista de problemas).
function MazeGenerator.validate(layout: Types.FloorLayout, config: Config): (boolean, { string })
	local problems: { string } = {}
	local byKey: { [number]: Types.Room } = {}
	local entrance: Types.Room? = nil
	local puzzle: Types.Room? = nil
	local entrances, puzzles, deadEnds = 0, 0, 0

	for _, room in layout.rooms do
		local key = cellKey(room.x, room.y)
		if byKey[key] then
			table.insert(problems, `sala duplicada em ({room.x},{room.y})`)
		end
		byKey[key] = room
		if room.kind == "Entrance" then
			entrances += 1
			entrance = room
		elseif room.kind == "Puzzle" or room.kind == "Boss" then
			puzzles += 1 -- sala final do andar (puzzle ou arena do boss)
			puzzle = room
			if room.kind == "Boss" then
				local onBorder = room.x == 0 or room.x == layout.width - 1 or room.y == 0 or room.y == layout.height - 1
				if not onBorder then
					table.insert(problems, "a sala do boss não está na borda da grade")
				end
			end
		elseif room.kind == "DeadEnd" then
			deadEnds += 1
			if doorCount(room) ~= 1 then
				table.insert(problems, `beco em ({room.x},{room.y}) com {doorCount(room)} portas`)
			end
		elseif doorCount(room) < 2 then
			table.insert(problems, `sala de combate em ({room.x},{room.y}) é um beco não marcado`)
		end
	end

	local count = #layout.rooms
	if count < config.minRooms or count > config.maxRooms then
		table.insert(problems, `{count} salas (esperado {config.minRooms} a {config.maxRooms})`)
	end
	if entrances ~= 1 or puzzles ~= 1 then
		table.insert(problems, `{entrances} entradas e {puzzles} salas finais (esperado 1 e 1)`)
	end
	if deadEnds < config.minDeadEnds or deadEnds > config.maxDeadEnds then
		table.insert(problems, `{deadEnds} becos (esperado {config.minDeadEnds} a {config.maxDeadEnds})`)
	end

	-- Portas simétricas e levando a salas que existem.
	for _, room in layout.rooms do
		for _, direction in DIRECTIONS do
			if room.doors[direction] then
				local offset = OFFSETS[direction]
				local neighbor = byKey[cellKey(room.x + offset.x, room.y + offset.y)]
				if not neighbor or not neighbor.doors[OPPOSITE[direction]] then
					table.insert(problems, `porta {direction} de ({room.x},{room.y}) não tem par`)
				end
			end
		end
	end

	-- Busca em largura a partir da entrada: o puzzle e todas as salas precisam ser alcançáveis.
	if entrance and puzzle then
		local visited: { [Types.Room]: boolean } = { [entrance] = true }
		local queue: { Types.Room } = { entrance }
		local head = 1
		while head <= #queue do
			local room = queue[head]
			head += 1
			for _, direction in DIRECTIONS do
				if room.doors[direction] then
					local offset = OFFSETS[direction]
					local neighbor = byKey[cellKey(room.x + offset.x, room.y + offset.y)]
					if neighbor and not visited[neighbor] then
						visited[neighbor] = true
						table.insert(queue, neighbor)
					end
				end
			end
		end
		if not visited[puzzle] then
			table.insert(problems, "o puzzle não é alcançável a partir da entrada")
		end
		for _, room in layout.rooms do
			if not visited[room] then
				table.insert(problems, `sala ({room.x},{room.y}) inalcançável`)
			end
		end
	end

	return #problems == 0, problems
end

return table.freeze(MazeGenerator)
