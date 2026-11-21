--!strict
-- Transforma o layout (MazeGenerator) em peças greybox: piso por sala e paredes com vão nas portas.
-- Paredes entre duas salas vizinhas são criadas uma vez só (pela sala do Leste/Sul), sem peças sobrepostas.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Dungeon = require(Shared.Balance.Dungeon)

-- Arena do boss: a sala "Boss" (na borda da grade) se abre para fora e ganha uma sala extra colada nela.
-- `center`/`halfX`/`halfZ` descrevem o retângulo inteiro (sala + extensão); `bossSpawn` = centro da extensão.
export type Arena = {
	center: Vector3,
	halfX: number,
	halfZ: number,
	bossSpawn: Vector3,
}

export type BuiltFloor = {
	folder: Folder,
	roomCenters: { [Types.Room]: Vector3 }, -- centro do piso de cada sala, na altura do topo do piso
	entrance: Types.Room,
	goal: Types.Room, -- sala final: "Puzzle" ou "Boss"
	arena: Arena?, -- só no andar do boss
}

-- "North" | "South" | "East" | "West". Declarado como string: o verificador de tipos alarga o laço sobre a
-- lista de direções para string, e o tipo literal geraria erros falsos.
type Direction = string

local BOSS_FLOOR_COLOR = Color3.fromRGB(120, 60, 70)
local FLOOR_COLORS: { [Types.RoomKind]: Color3 } = {
	Entrance = Color3.fromRGB(95, 140, 95),
	Combat = Color3.fromRGB(110, 110, 120),
	DeadEnd = Color3.fromRGB(125, 105, 85),
	Puzzle = Color3.fromRGB(85, 110, 150),
	Boss = BOSS_FLOOR_COLOR,
}
local OFFSETS: { [string]: Vector3 } = {
	North = Vector3.new(0, 0, -1),
	South = Vector3.new(0, 0, 1),
	East = Vector3.new(1, 0, 0),
	West = Vector3.new(-1, 0, 0),
}
local OPPOSITE: { [string]: string } = { North = "South", South = "North", East = "West", West = "East" }
local WALL_COLOR = Color3.fromRGB(70, 70, 80)

local RoomBuilder = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Uma parede no lado `direction` da sala; com porta, vira dois pedaços com um vão no meio.
local function buildWall(center: Vector3, direction: Direction, hasDoor: boolean, parent: Instance)
	local size, height, thickness = Dungeon.roomSize, Dungeon.wallHeight, Dungeon.wallThickness
	local half = size / 2
	local alongX = direction == "North" or direction == "South"
	local offset = if direction == "North"
		then Vector3.new(0, 0, -half)
		elseif direction == "South" then Vector3.new(0, 0, half)
		elseif direction == "East" then Vector3.new(half, 0, 0)
		else Vector3.new(-half, 0, 0)
	local wallCenter = center + offset + Vector3.new(0, height / 2, 0)
	local length = size + thickness -- fecha os cantos

	local function segment(segmentLength: number, shift: number)
		local partSize = if alongX
			then Vector3.new(segmentLength, height, thickness)
			else Vector3.new(thickness, height, segmentLength)
		local shiftVector = if alongX then Vector3.new(shift, 0, 0) else Vector3.new(0, 0, shift)
		makePart("Wall", partSize, CFrame.new(wallCenter + shiftVector), WALL_COLOR, parent)
	end

	if hasDoor then
		local segmentLength = (length - Dungeon.doorWidth) / 2
		local shift = Dungeon.doorWidth / 2 + segmentLength / 2
		segment(segmentLength, -shift)
		segment(segmentLength, shift)
	else
		segment(length, 0)
	end
end

local function neighborKey(room: Types.Room, direction: Direction): string
	local dx = if direction == "East" then 1 elseif direction == "West" then -1 else 0
	local dy = if direction == "South" then 1 elseif direction == "North" then -1 else 0
	return `{room.x + dx},{room.y + dy}`
end

function RoomBuilder.build(layout: Types.FloorLayout, origin: Vector3, parent: Instance): BuiltFloor
	local folder = Instance.new("Folder")
	folder.Name = `Floor_{layout.floorNumber}`

	local byKey: { [string]: Types.Room } = {}
	for _, room in layout.rooms do
		byKey[`{room.x},{room.y}`] = room
	end

	local roomCenters: { [Types.Room]: Vector3 } = {}
	local entrance: Types.Room? = nil
	local goal: Types.Room? = nil
	local arena: Arena? = nil
	local floorTop = origin.Y + Dungeon.floorThickness / 2
	local floorSize = Vector3.new(Dungeon.roomSize, Dungeon.floorThickness, Dungeon.roomSize)

	local function buildFloorTile(center: Vector3, color: Color3, roomFolder: Instance)
		makePart(
			"Floor",
			floorSize,
			CFrame.new(center - Vector3.new(0, Dungeon.floorThickness / 2, 0)),
			color,
			roomFolder
		)
	end

	-- Lado da sala do boss que dá para FORA da grade (o gerador garante que existe ao menos um).
	local function outwardDirection(room: Types.Room): string?
		for _, direction in { "North", "South", "East", "West" } do
			local offset = OFFSETS[direction]
			local nx, ny = room.x + offset.X, room.y + offset.Z
			if nx < 0 or nx >= layout.width or ny < 0 or ny >= layout.height then
				return direction
			end
		end
		return nil
	end

	for _, room in layout.rooms do
		local roomFolder = Instance.new("Folder")
		roomFolder.Name = `Room_{room.x}_{room.y}_{room.kind}`
		roomFolder.Parent = folder

		local center = Vector3.new(origin.X + room.x * Dungeon.roomSize, floorTop, origin.Z + room.y * Dungeon.roomSize)
		roomCenters[room] = center
		buildFloorTile(center, FLOOR_COLORS[room.kind], roomFolder)

		local arenaDirection = if room.kind == "Boss" then outwardDirection(room) else nil
		for _, direction in { "North", "South", "East", "West" } do
			local hasNeighbor = byKey[neighborKey(room, direction)] ~= nil
			-- Parede compartilhada: quem cria é a sala do Leste/Sul (a vizinha cuida do Norte/Oeste dela).
			-- Na sala do boss, o lado que dá para fora fica aberto: é a passagem para a extensão da arena.
			if direction ~= arenaDirection and not (hasNeighbor and (direction == "North" or direction == "West")) then
				buildWall(center, direction, room.doors[direction], roomFolder)
			end
		end

		if room.kind == "Entrance" then
			entrance = room
		elseif room.kind == "Puzzle" or room.kind == "Boss" then
			goal = room
		end

		if arenaDirection then
			-- Extensão da arena: uma sala inteira colada do lado de fora, com paredes nos 3 lados externos.
			local outward = OFFSETS[arenaDirection]
			local extensionCenter = center + outward * Dungeon.roomSize
			buildFloorTile(extensionCenter, BOSS_FLOOR_COLOR, roomFolder)
			for _, direction in { "North", "South", "East", "West" } do
				if direction ~= OPPOSITE[arenaDirection] then
					buildWall(extensionCenter, direction, false, roomFolder)
				end
			end
			local alongX = arenaDirection == "East" or arenaDirection == "West"
			arena = {
				center = (center + extensionCenter) / 2,
				halfX = if alongX then Dungeon.roomSize else Dungeon.roomSize / 2,
				halfZ = if alongX then Dungeon.roomSize / 2 else Dungeon.roomSize,
				bossSpawn = extensionCenter,
			}
		end
	end

	assert(entrance and goal, "layout sem entrada ou sem sala final")
	folder.Parent = parent
	return { folder = folder, roomCenters = roomCenters, entrance = entrance, goal = goal, arena = arena }
end

return table.freeze(RoomBuilder)
