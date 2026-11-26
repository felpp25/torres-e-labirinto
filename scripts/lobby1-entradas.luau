--!strict
-- Monta as entradas das torres do Lobby 1 (malhas feitas no Blender: scripts/blender/entradas.py e vigia.py). NÃO faz
-- parte do jogo: rode no datamodel Edit (MCP execute_luau), DEPOIS do Terrain (lobby1-terreno.luau): este script
-- escava o túnel e o corredor no Terrain. Refaz tudo o que é dele.
--
-- Torre 1, Caverna das Profundezas (oeste): a Fenda. Boca de rocha que sobe em zigue-zague até virar rachadura, com
-- os Veios da Fenda (Neon roxo), cristais e um túnel curto que faz curva (o fundo escuro não aparece de frente). O
-- portal (TowerPortal_1, gerado pelo LobbyService) continua no chão, na frente da boca.
-- Torre 2, Ruínas Subterrâneas (leste): o Portal do Vigia do Sol. Fachada de pedra lavrada com pilares de runas
-- solares, lintel com runas, um nicho oval vazio no meio (o designer descartou o rosto e a caveira), porta em arco com
-- grade meio erguida e corredor escuro com brilho laranja; as quatro Estelas Solares na frente.
--
-- Malha nova: rode o build no Blender, exporte (LB.export_glb), suba o GLB como nova versão do asset
-- (PATCH /assets/v1/assets/{id}), copie os centros do EntradasLobby1.json e apague
-- ServerStorage.Lobby1Modelos.Entradas (cache). O importador gira a malha 180° em Y (ver lobby1-pedras.luau).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ASSET_ID = 125244967030800

-- centro da caixa de cada malha no glTF (EntradasLobby1.json)
local CENTERS: { [string]: Vector3 } = {
	EstelaRuna_1 = Vector3.new(-0.725, 7.058, 0.0),
	EstelaRuna_2 = Vector3.new(-0.725, 7.046, 0.0),
	EstelaSolar_1 = Vector3.new(-0.011, 4.975, -0.02),
	EstelaSolar_2 = Vector3.new(-0.008, 5.206, 0.056),
	FendaChao_1 = Vector3.new(-69.472, 0.06, -0.703),
	FendaCristalClaro_1 = Vector3.new(-66.414, 15.8, -0.314),
	FendaCristalEscuro_1 = Vector3.new(-66.414, 15.8, -0.366),
	FendaCristalMedio_1 = Vector3.new(-66.321, 15.833, -0.366),
	FendaFundo_1 = Vector3.new(-77.668, 13.651, -3.918),
	FendaPedras_1 = Vector3.new(-59.641, 17.732, -0.127),
	FendaRocha_1 = Vector3.new(-62.081, 24.35, -0.065),
	FendaTunel_1 = Vector3.new(-69.516, 13.932, -0.82),
	FendaVeios_1 = Vector3.new(-62.078, 21.486, 1.549),
	VigiaCorredor_1 = Vector3.new(66.3, 11.3, 0.0),
	VigiaFundo_1 = Vector3.new(72.0, 11.3, 0.0),
	VigiaMoldura_1 = Vector3.new(61.027, 23.349, -0.056),
	VigiaPortao_1 = Vector3.new(61.1, 14.333, -0.002),
	VigiaRunas_1 = Vector3.new(59.15, 25.535, 0.0),
}

local STONE = Color3.fromRGB(215, 208, 232) -- pedra clara: a textura do pacote dá a cor (igual às formações)
local STONE_DARK = Color3.fromRGB(190, 182, 210)
local TUNNEL = Color3.fromRGB(150, 140, 178)

type Spec = {
	mesh: string,
	name: string,
	material: Enum.Material,
	color: Color3,
	collide: boolean,
	precise: boolean?,
	reflect: number?,
}

-- (malha, nome no Studio, material, cor, colisão). Rocha e túnel com colisão precisa: com o casco convexo, a boca
-- ficaria fechada por uma parede invisível.
local FENDA: { Spec } = {
	{
		mesh = "FendaRocha_1",
		name = "Rocha da Fenda",
		material = Enum.Material.Rock,
		color = STONE,
		collide = true,
		precise = true,
	},
	{
		mesh = "FendaTunel_1",
		name = "Túnel",
		material = Enum.Material.Rock,
		color = TUNNEL,
		collide = true,
		precise = true,
	},
	{
		mesh = "FendaPedras_1",
		name = "Pedras da Boca",
		material = Enum.Material.Rock,
		color = STONE_DARK,
		collide = true,
	},
	{ mesh = "FendaChao_1", name = "Chão do Túnel", material = Enum.Material.Rock, color = TUNNEL, collide = true },
	{
		mesh = "FendaFundo_1",
		name = "Fundo",
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(6, 4, 12),
		collide = true,
	},
	{
		mesh = "FendaVeios_1",
		name = "Veios da Fenda",
		material = Enum.Material.Neon,
		color = Color3.fromRGB(120, 55, 235),
		collide = false,
	},
	{
		mesh = "FendaCristalClaro_1",
		name = "Cristais Claros",
		material = Enum.Material.Neon,
		color = Color3.fromRGB(100, 78, 232),
		collide = false,
	},
	{
		mesh = "FendaCristalMedio_1",
		name = "Cristais Médios",
		material = Enum.Material.Neon,
		color = Color3.fromRGB(78, 36, 200),
		collide = false,
	},
	{
		mesh = "FendaCristalEscuro_1",
		name = "Cristais Escuros",
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(58, 26, 130),
		collide = false,
		reflect = 0.25,
	},
}

local GOLD = Color3.fromRGB(235, 150, 60) -- ouro de Áuren (igual aos Anéis Rúnicos)
local VIGIA: { Spec } = {
	{
		mesh = "VigiaMoldura_1",
		name = "Moldura",
		material = Enum.Material.Rock,
		color = STONE,
		collide = true,
		precise = true,
	},
	{ mesh = "VigiaRunas_1", name = "Runas Solares", material = Enum.Material.Neon, color = GOLD, collide = false },
	{
		mesh = "VigiaPortao_1",
		name = "Grade",
		material = Enum.Material.Metal,
		color = Color3.fromRGB(70, 64, 78),
		collide = true,
	},
	{ mesh = "VigiaCorredor_1", name = "Corredor", material = Enum.Material.Rock, color = TUNNEL, collide = true },
	{
		mesh = "VigiaFundo_1",
		name = "Fundo",
		material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(6, 4, 12),
		collide = true,
	},
}
-- Estelas Solares: duas variações, nas quatro posições do blockout (a frente, com a runa, virada para a avenida)
local ESTELAS = {
	{ z = -34, variant = 1 },
	{ z = -22, variant = 2 },
	{ z = 22, variant = 1 },
	{ z = 34, variant = 2 },
}
local ESTELA_X = 54

-- Terrain escavado para o túnel (a parede do rochedo é sólida atrás da boca)
local TUNNEL_CARVE = { cframe = CFrame.new(-70, 15.5, -1), size = Vector3.new(18, 31, 20) }
-- corredor atrás da porta do Vigia
local CORRIDOR_CARVE = { cframe = CFrame.new(67.25, 11.25, 0), size = Vector3.new(13.5, 21.5, 14) }

local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local torres = lobby:FindFirstChild("Torres") :: Folder
local luzes = lobby:FindFirstChild("Luzes") :: Folder
assert(torres and luzes, "falta Lobby1.Torres ou Lobby1.Luzes")

local function templates(): Folder
	local root = ServerStorage:FindFirstChild("Lobby1Modelos")
	assert(root, "falta ServerStorage.Lobby1Modelos")
	local existing = root:FindFirstChild("Entradas")
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Entradas"
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

local function build(specs: { Spec }, parent: Instance, place: CFrame?)
	for _, spec in specs do
		local template = T:FindFirstChild(spec.mesh) :: MeshPart?
		assert(template, `falta a malha {spec.mesh}`)
		local center = CENTERS[spec.mesh]
		assert(center, `falta o centro de {spec.mesh}`)
		local part = template:Clone()
		part.CFrame = (place or CFrame.identity) * CFrame.new(center) * CFrame.Angles(0, math.pi, 0)
		part.Anchored = true
		part.Name = spec.name
		part.Material = spec.material
		part.Color = spec.color
		part.Reflectance = spec.reflect or 0
		part.CanCollide = spec.collide
		part.CanTouch = false
		part.CanQuery = spec.collide
		part.CastShadow = spec.material ~= Enum.Material.Neon
		if spec.precise then
			part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end
		part.Parent = parent
	end
end

-- apaga as peças do blockout e o que este script montou antes (guardando o rótulo de dev, se houver)
local function clear(folder: Instance, blockout: { string }, built: { string }): Instance?
	local label: Instance? = nil
	for _, child in folder:GetChildren() do
		local old = (table.find(blockout, child.Name) and child:IsA("BasePart")) or table.find(built, child.Name)
		if old then
			local found = child:FindFirstChild("Rotulo", true)
			if found and not label then
				found.Parent = nil
				label = found
			end
			child:Destroy()
		end
	end
	return label
end

local function pointLight(name: string, position: Vector3, color: Color3, brightness: number, range: number)
	local old = luzes:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Part")
	holder.Name = name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = holder
	holder.Parent = luzes
end

-- ------------------------------------------------------------------ Torre 1: a Fenda

local caverna = torres:FindFirstChild("Caverna das Profundezas") :: Model
assert(caverna, "falta Torres/Caverna das Profundezas")
local labelFenda = clear(caverna, { "Entrada" }, { "Fenda" })
workspace.Terrain:FillBlock(TUNNEL_CARVE.cframe, TUNNEL_CARVE.size, Enum.Material.Air)
local fenda = Instance.new("Model")
fenda.Name = "Fenda"
build(FENDA, fenda)
local rock = fenda:FindFirstChild("Rocha da Fenda") :: MeshPart
fenda.PrimaryPart = rock
if labelFenda then
	labelFenda.Parent = rock
end
fenda.Parent = caverna
-- brilho roxo lá dentro do túnel (a "Luz da Caverna das Profundezas" fica na frente)
pointLight("Luz do Túnel das Profundezas", Vector3.new(-72, 6, -2), Color3.fromRGB(150, 90, 255), 2, 22)

-- ------------------------------------------------------------------ Torre 2: o Portal do Vigia do Sol

local ruinas = torres:FindFirstChild("Ruínas Subterrâneas") :: Model
assert(ruinas, "falta Torres/Ruínas Subterrâneas")
local labelVigia = clear(
	ruinas,
	{ "Entrada", "Vigia do Sol", "Estela Solar 1", "Estela Solar 2", "Estela Solar 3", "Estela Solar 4" },
	{ "Vigia do Sol", "Estelas Solares" }
)
workspace.Terrain:FillBlock(CORRIDOR_CARVE.cframe, CORRIDOR_CARVE.size, Enum.Material.Air)
local vigia = Instance.new("Model")
vigia.Name = "Vigia do Sol"
build(VIGIA, vigia)
local frame = vigia:FindFirstChild("Moldura") :: MeshPart
vigia.PrimaryPart = frame
if labelVigia then
	labelVigia.Parent = frame
end
vigia.Parent = ruinas

local estelas = Instance.new("Model")
estelas.Name = "Estelas Solares"
local rng = Random.new(4401)
for i, e in ESTELAS do
	local place = CFrame.new(ESTELA_X + rng:NextNumber(-0.4, 0.4), 0, e.z)
		* CFrame.Angles(rng:NextNumber(-0.04, 0.04), rng:NextNumber(-0.18, 0.18), rng:NextNumber(-0.05, 0.05))
	local one = Instance.new("Model")
	one.Name = `Estela Solar {i}`
	build({
		{
			mesh = `EstelaSolar_{e.variant}`,
			name = "Pedra",
			material = Enum.Material.Rock,
			color = STONE,
			collide = true,
		},
		{
			mesh = `EstelaRuna_{e.variant}`,
			name = "Runa Solar",
			material = Enum.Material.Neon,
			color = GOLD,
			collide = false,
		},
	}, one, place)
	one.PrimaryPart = one:FindFirstChild("Pedra") :: MeshPart
	one.Parent = estelas
end
estelas.Parent = ruinas
-- brilho laranja (a cor do portal da Torre 2) no fim do corredor
pointLight("Luz do Corredor das Ruínas", Vector3.new(69, 7, 0), Color3.fromRGB(255, 140, 60), 2, 18)
-- (versões antigas tinham uma luz no rosto / na caveira do nicho: apaga se ainda existir)
for _, name in { "Luz do Rosto do Vigia", "Luz da Caveira do Vigia" } do
	local oldSpot = luzes:FindFirstChild(name)
	if oldSpot then
		oldSpot:Destroy()
	end
end

return "entradas montadas"
