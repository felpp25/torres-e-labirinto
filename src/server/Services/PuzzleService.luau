--!strict
-- Puzzle do andar (GDD > Andares): placas de pressão na sala do Puzzle abrem a saída (escada).
-- - Cada placa, depois de pisada por um participante vivo, FICA ativada (funciona solo e em grupo).
-- - Com todas ativas, a saída abre. Um participante vivo pisando na saída aberta = checkpoint (callback do
--   DungeonService).
-- Um puzzle por run (várias runs por servidor). Quem está pisando é verificado pelo servidor (consulta espacial
-- periódica), não pelo cliente.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Dungeon = require(Shared.Balance.Dungeon)

local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)

local PLATE_IDLE_COLOR = Color3.fromRGB(150, 60, 60)
local PLATE_ACTIVE_COLOR = Color3.fromRGB(80, 220, 110)
local EXIT_LOCKED_COLOR = Color3.fromRGB(45, 45, 55)
local EXIT_OPEN_COLOR = Color3.fromRGB(255, 200, 60)
local DETECT_HEIGHT = 6 -- altura da região acima da placa/saída onde um personagem conta como "pisando"

type Plate = { part: Part, active: boolean }
type Puzzle = {
	plates: { Plate },
	exit: Part,
	exitLabel: TextLabel,
	exitOpen: boolean,
	exitUsed: boolean,
}

local PuzzleService = {}

local puzzles: { [RunRegistry.Run]: Puzzle } = {}
local onExitReached: (run: RunRegistry.Run, player: Player) -> () = function(_: RunRegistry.Run, _: Player) end

local function makePad(name: string, size: number, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = Vector3.new(size, 0.4, size)
	part.Position = position + Vector3.new(0, 0.2, 0)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(part: Part, text: string): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Adornee = part
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = gui
	return label
end

-- Personagens vivos dos participantes da run.
local function aliveCharacters(run: RunRegistry.Run): { [Model]: Player }
	local result: { [Model]: Player } = {}
	for _, player in run.members do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 then
			result[character] = player
		end
	end
	return result
end

-- Primeiro jogador vivo com o corpo dentro da região acima da peça (ou nil).
local function playerOn(part: Part, characters: { [Model]: Player }): Player?
	local list: { Instance } = {}
	for character in characters do
		table.insert(list, character)
	end
	if #list == 0 then
		return nil
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	local regionCFrame = part.CFrame * CFrame.new(0, DETECT_HEIGHT / 2, 0)
	local regionSize = Vector3.new(part.Size.X, DETECT_HEIGHT, part.Size.Z)
	for _, hit in workspace:GetPartBoundsInBox(regionCFrame, regionSize, params) do
		local model = hit:FindFirstAncestorOfClass("Model")
		local player = model and characters[model]
		if player then
			return player
		end
	end
	return nil
end

local function publish(run: RunRegistry.Run, puzzle: Puzzle)
	local active = 0
	for _, plate in puzzle.plates do
		if plate.active then
			active += 1
		end
	end
	RunRegistry.setState(run, Keys.RunAttr.PlatesActive, active)
	RunRegistry.setState(run, Keys.RunAttr.PlatesTotal, #puzzle.plates)
	RunRegistry.setState(run, Keys.RunAttr.ExitOpen, puzzle.exitOpen)
end

local function openExit(run: RunRegistry.Run, puzzle: Puzzle)
	puzzle.exitOpen = true
	puzzle.exit.Color = EXIT_OPEN_COLOR
	puzzle.exit.Material = Enum.Material.Neon
	puzzle.exitLabel.Text = "Saída aberta: pise para subir"
	print(`[Puzzle] run {run.id}: todas as placas ativas, saída aberta`)
end

local function check(run: RunRegistry.Run, puzzle: Puzzle)
	local characters = aliveCharacters(run)
	local changed = false
	for _, plate in puzzle.plates do
		if not plate.active and playerOn(plate.part, characters) then
			plate.active = true
			plate.part.Color = PLATE_ACTIVE_COLOR
			plate.part.Material = Enum.Material.Neon
			changed = true
		end
	end
	if changed then
		local allActive = true
		for _, plate in puzzle.plates do
			allActive = allActive and plate.active
		end
		if allActive and not puzzle.exitOpen then
			openExit(run, puzzle)
		end
		publish(run, puzzle)
	end

	if puzzle.exitOpen and not puzzle.exitUsed then
		local player = playerOn(puzzle.exit, characters)
		if player then
			puzzle.exitUsed = true -- uma vez por andar
			onExitReached(run, player)
		end
	end
end

-- Cria placas e saída na sala do puzzle da run. `center` = centro do piso da sala (altura do topo do piso).
-- `rng` vem da seed do andar: refazer o andar recria as mesmas placas nos mesmos cantos.
function PuzzleService.setup(run: RunRegistry.Run, center: Vector3, parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Puzzle"
	folder.Parent = parent

	local corners: { Vector3 } = {}
	local d = Dungeon.plateCornerOffset
	for _, sign in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		table.insert(corners, center + sign * d)
	end
	-- Embaralha os cantos e usa os primeiros N.
	for i = #corners, 2, -1 do
		local j = rng:NextInteger(1, i)
		corners[i], corners[j] = corners[j], corners[i]
	end

	local plates: { Plate } = {}
	local count = rng:NextInteger(Dungeon.minPlates, Dungeon.maxPlates)
	for i = 1, count do
		local part = makePad(`Plate_{i}`, Dungeon.plateSize, corners[i], PLATE_IDLE_COLOR, folder)
		table.insert(plates, { part = part, active = false })
	end

	local exit = makePad("Exit", Dungeon.exitSize, center, EXIT_LOCKED_COLOR, folder)
	local label = makeLabel(exit, `Saída trancada: ative as {count} placas`)

	local puzzle: Puzzle = { plates = plates, exit = exit, exitLabel = label, exitOpen = false, exitUsed = false }
	puzzles[run] = puzzle
	publish(run, puzzle)
end

-- Andar sem puzzle (andar do boss) ou run encerrada: nada para verificar e o HUD mostra 0/0.
function PuzzleService.clear(run: RunRegistry.Run)
	puzzles[run] = nil
	RunRegistry.setState(run, Keys.RunAttr.PlatesActive, 0)
	RunRegistry.setState(run, Keys.RunAttr.PlatesTotal, 0)
	RunRegistry.setState(run, Keys.RunAttr.ExitOpen, false)
end

-- O DungeonService decide o que acontece no checkpoint (sem dependência circular entre os serviços).
function PuzzleService.setExitHandler(handler: (run: RunRegistry.Run, player: Player) -> ())
	onExitReached = handler
end

function PuzzleService.init() end

function PuzzleService.start()
	while true do
		task.wait(Dungeon.puzzleCheckInterval)
		for run, puzzle in puzzles do
			-- A sala pode ter sido destruída (andar trocado ou run encerrada) entre as verificações.
			if run.active and puzzle.exit.Parent then
				check(run, puzzle)
			end
		end
	end
end

return PuzzleService
