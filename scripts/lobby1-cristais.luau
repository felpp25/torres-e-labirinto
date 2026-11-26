--!strict
-- Monta o Coração do Abismo no Altar do Coração (malhas do scripts/lobby1-cristais.py). NÃO faz parte do jogo: rode
-- no datamodel Edit (MCP execute_luau). Refaz o Model Altar/"Coração do Abismo".
--
-- Cristal em três tons (faces claras, médias e escuras: ver o .py). As claras e as médias são Neon (o brilho); as
-- escuras não brilham, e é o contraste entre elas que mostra as faces. O pedestal é pedra lavrada.
--
-- Na primeira vez troca o bloco Neon do blockout ("Coração do Abismo", Part) e a "Base do Coração": a luz e o rótulo do
-- blockout passam para as faces claras.
--
-- Malha nova: rode o .py, suba o GLB como nova versão do asset (PATCH /assets/v1/assets/{id}), copie os centros do
-- json e apague ServerStorage.Lobby1Modelos.Cristais (cache). O importador gira a malha 180° em Y (ver lobby1-pedras).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ASSET_ID = 120692311991767
local ORIGIN = CFrame.new(0, 8, -106) -- topo da Plataforma do Altar, no eixo do poço do feixe
local PEDESTAL_TOP = 3 -- igual ao .py: o cristal nasce aqui
-- O designer pediu o cristal 30% maior (do spawn ele parecia pequeno perto das artes): cristais e anéis crescem a
-- partir do topo do pedestal; o pedestal fica do tamanho da plataforma.
local SCALE = 1.3
local CRYSTAL_AT = ORIGIN * CFrame.new(0, PEDESTAL_TOP * (1 - SCALE), 0)

-- centro da caixa de cada malha no glTF (CristaisLobby1.json)
local CENTERS: { [string]: Vector3 } = {
	CoracaoClaro_1 = Vector3.new(0.416, 24.319, -0.737),
	CoracaoMedio_1 = Vector3.new(0.06, 24.319, -0.737),
	CoracaoEscuro_1 = Vector3.new(0.416, 24.366, -0.737),
	PedestalDoCoracao_1 = Vector3.new(0.039, 1.5, -0.191),
	AnelFita_1 = Vector3.new(0.0, 0.0, 0.0),
	AnelRunas_1 = Vector3.new(0.003, 0.0, -0.0),
	AnelFita_2 = Vector3.new(0.0, 0.0, 0.0),
	AnelRunas_2 = Vector3.new(-0.005, 0.0, 0.0),
}

local CRYSTAL_LIGHT = Color3.fromRGB(192, 140, 255) -- #C08CFF
-- tons das faces: (malha, nome no Studio, material, cor)
local TONES: { { any } } = {
	{ "CoracaoClaro_1", "Faces Claras", Enum.Material.Neon, Color3.fromRGB(100, 78, 232) },
	{ "CoracaoMedio_1", "Faces Médias", Enum.Material.Neon, Color3.fromRGB(78, 36, 200) },
	{ "CoracaoEscuro_1", "Faces Escuras", Enum.Material.SmoothPlastic, Color3.fromRGB(58, 26, 130) },
}
-- (com cores claras, 175/135/255, o Neon estourava em branco com o Bloom)
local STONE_DARK = Color3.fromRGB(190, 182, 210)

local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local altar = lobby:FindFirstChild("Altar") :: Folder
assert(altar, "falta Workspace.Lobby1.Altar")

local function templates(): Folder
	local root = ServerStorage:FindFirstChild("Lobby1Modelos")
	assert(root, "falta ServerStorage.Lobby1Modelos")
	local existing = root:FindFirstChild("Cristais")
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Cristais"
	local source = InsertService:LoadAsset(ASSET_ID)
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			local clone = d:Clone()
			clone.Anchored = true
			clone.CFrame = CFrame.new()
			clone.Parent = folder
		end
	end
	folder.Parent = root
	source:Destroy()
	return folder
end
local T = templates()

local function piece(name: string, parent: Instance, newName: string, at: CFrame?, scale: number?): MeshPart
	local template = T:FindFirstChild(name) :: MeshPart?
	assert(template, `falta a malha {name}`)
	local part = template:Clone()
	local k = scale or 1
	part.Size *= k
	part.CFrame = (at or ORIGIN) * CFrame.new(CENTERS[name] * k) * CFrame.Angles(0, math.pi, 0)
	part.Anchored = true
	part.Name = newName
	part.Parent = parent
	return part
end

-- blockout antigo: guarda a luz e o rótulo, apaga o resto
local light: Instance? = nil
local label: Instance? = nil
local old = altar:FindFirstChild("Coração do Abismo")
if old then
	light = old:FindFirstChildWhichIsA("PointLight", true)
	label = old:FindFirstChild("Rotulo", true)
	if light then
		light.Parent = nil
	end
	if label then
		label.Parent = nil
	end
	old:Destroy()
end
local oldBase = altar:FindFirstChild("Base do Coração")
if oldBase then
	oldBase:Destroy()
end

local model = Instance.new("Model")
model.Name = "Coração do Abismo"

local pedestal = piece("PedestalDoCoracao_1", model, "Pedestal")
pedestal.Material = Enum.Material.Rock
pedestal.Color = STONE_DARK
pedestal.CanCollide = true

local bright: MeshPart? = nil
for _, tone in TONES do
	local part = piece(tone[1] :: string, model, tone[2] :: string, CRYSTAL_AT, SCALE)
	part.Material = tone[3] :: Enum.Material
	part.Color = tone[4] :: Color3
	part.Reflectance = if part.Material == Enum.Material.SmoothPlastic then 0.25 else 0
	part.CanCollide = true
	part.CastShadow = false
	bright = bright or part
end
assert(bright, "faltam as malhas dos tons")

if not light then
	local created = Instance.new("PointLight")
	created.Brightness = 3
	created.Range = 60
	created.Color = CRYSTAL_LIGHT
	light = created
end
assert(light, "luz do Coração")
light.Parent = bright
if label then
	label.Parent = bright
end
model.PrimaryPart = pedestal
model:SetAttribute("Blockout", nil)
model.Parent = altar

-- ------------------------------------------------------------------ Anéis Rúnicos
-- Duas fitas de ouro de Áuren com runas, inclinadas em volta do Coração (artes 04 e 05). Ficam paradas aqui; girar é
-- efeito (Fase 7, script do cliente em src/): o Attribute GiraGrausPorSegundo diz a velocidade de cada uma.
local oldRings = altar:FindFirstChild("Anéis Rúnicos")
if oldRings then
	oldRings:Destroy()
end
local rings = Instance.new("Model")
rings.Name = "Anéis Rúnicos"
local RINGS = {
	{ n = 1, y = 21, tilt = CFrame.Angles(math.rad(16), 0, math.rad(9)), speed = 6 },
	{ n = 2, y = 31, tilt = CFrame.Angles(math.rad(-13), math.rad(40), math.rad(-11)), speed = -9 },
}
for _, r in RINGS do
	local at = ORIGIN * CFrame.new(0, PEDESTAL_TOP + (r.y - PEDESTAL_TOP) * SCALE, 0) * r.tilt
	local ring = Instance.new("Model")
	ring.Name = `Anel Rúnico {r.n}`
	local band = piece(`AnelFita_{r.n}`, ring, "Fita", at, SCALE)
	band.Material = Enum.Material.Neon
	band.Color = Color3.fromRGB(235, 150, 60) -- ouro de Áuren (com #FFB85C o Neon saía amarelo-limão)
	band.Transparency = 0.82
	local glyphs = piece(`AnelRunas_{r.n}`, ring, "Runas", at, SCALE)
	glyphs.Material = Enum.Material.Neon
	glyphs.Color = Color3.fromRGB(235, 150, 60)
	for _, p in { band, glyphs } do
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	ring.PrimaryPart = band
	ring:SetAttribute("GiraGrausPorSegundo", r.speed)
	ring.Parent = rings
end
rings.Parent = altar

-- ------------------------------------------------------------------ Feixe Ascendente
-- Luz ciano do buraco do teto até a ponta do Coração: dois Beams virados para a câmera (largo e fraco + núcleo
-- estreito). O estado "fraco até vencer Kokuryū" é por jogador (Fase 7, cliente).
local efeitos = lobby:FindFirstChild("Efeitos") :: Folder
assert(efeitos, "falta Workspace.Lobby1.Efeitos")
local oldBeam = efeitos:FindFirstChild("Feixe Ascendente")
if oldBeam then
	oldBeam:Destroy()
end
local beamFolder = Instance.new("Model")
beamFolder.Name = "Feixe Ascendente"
local function anchorPart(name: string, pos: Vector3): Attachment
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = beamFolder
	local a = Instance.new("Attachment")
	a.Parent = p
	return a
end
local top = anchorPart("Topo", Vector3.new(0, 190, -106))
local bottom = anchorPart("Ponta do Coração", ORIGIN.Position + Vector3.new(0, PEDESTAL_TOP + 44 * SCALE, 0))
local CYAN = Color3.fromRGB(63, 224, 255)
for _, spec in { { "Feixe", 34, 16, 0.72 }, { "Núcleo do Feixe", 12, 6, 0.55 } } do
	local beam = Instance.new("Beam")
	beam.Name = spec[1] :: string
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Width0 = spec[2] :: number
	beam.Width1 = spec[3] :: number
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(170, 245, 255), CYAN)
	local t = spec[4] :: number
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, t),
		NumberSequenceKeypoint.new(0.85, t),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = beamFolder
end
beamFolder.Parent = efeitos

return "Coração do Abismo, Anéis Rúnicos e Feixe Ascendente montados"
