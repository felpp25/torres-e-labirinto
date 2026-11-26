--!strict
-- Monta as bancas do Mercado das Raízes (malhas do scripts/lobby1-mercado.py). NÃO faz parte do jogo: rode no
-- datamodel Edit (MCP execute_luau). Refaz o Model Roleplay/"Mercado das Raízes"/Bancas.
--
-- Troca as caixas do blockout ("Banca 1" a "Banca 4") por bancas de madeira com toldo listrado, mercadoria e uma
-- lanterna debaixo do toldo. A Banca do Tanu fica em volta do balcão da loja (LobbyService.SHOP_POSITION): o balcão
-- do código continua lá (prompt e colisão) e fica invisível quando esta banca existe.
--
-- Formações e plantas que ficariam por dentro das bancas são apagadas (ao rodar de novo, o lobby1-formacoes e o
-- lobby1-revestimento já desviam das peças montadas).
--
-- Malha nova: rode o .py, suba o GLB como nova versão do asset (PATCH /assets/v1/assets/{id}), copie os centros do
-- json e apague ServerStorage.Lobby1Modelos.Mercado (cache). O importador gira a malha 180° em Y (ver lobby1-pedras).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ASSET_ID = 99435055061209

-- centro da caixa de cada malha no glTF (MercadoLobby1.json)
local CENTERS: { [string]: Vector3 } = {
	BancaMadeira_1 = Vector3.new(0.115, 4.758, 1.197),
	ToldoA_1 = Vector3.new(0.0, 8.018, 0.71),
	ToldoB_1 = Vector3.new(-0.0, 8.056, 0.71),
	BancaMadeira_2 = Vector3.new(-0.026, 4.778, 1.172),
	ToldoA_2 = Vector3.new(0.0, 7.986, 0.61),
	ToldoB_2 = Vector3.new(-0.0, 8.029, 0.61),
	BancaMadeira_3 = Vector3.new(-0.081, 4.771, 1.173),
	ToldoA_3 = Vector3.new(0.0, 8.029, 0.71),
	ToldoB_3 = Vector3.new(-0.0, 8.017, 0.71),
	Caixote_1 = Vector3.new(-0.01, 0.976, 0.005),
	Caixote_2 = Vector3.new(-0.02, 0.976, -0.012),
	Barril_1 = Vector3.new(-0.005, 1.501, 0.005),
	AroBarril_1 = Vector3.new(0.0, 1.5, -0.0),
	Saco_1 = Vector3.new(0.056, 1.226, 0.009),
	Saco_2 = Vector3.new(0.042, 1.225, 0.021),
	Cesto_1 = Vector3.new(-0.001, 0.451, 0.012),
	CristalClaro_1 = Vector3.new(-0.378, 0.458, -0.304),
	CristalEscuro_1 = Vector3.new(-0.378, 0.458, -0.294),
	CogumeloHaste_1 = Vector3.new(-0.068, 0.551, 0.04),
	CogumeloChapeu_1 = Vector3.new(-0.142, 0.911, -0.017),
}

-- material e cor por tipo de malha (o prefixo do nome)
type Style = { material: Enum.Material, color: Color3 }
local WOOD = Color3.fromRGB(122, 88, 60)
local STYLES: { [string]: Style } = {
	BancaMadeira = { material = Enum.Material.Wood, color = WOOD },
	ToldoA = { material = Enum.Material.Fabric, color = Color3.fromRGB(214, 196, 160) },
	ToldoB = { material = Enum.Material.Fabric, color = Color3.fromRGB(104, 70, 150) }, -- a cor vem de cada banca
	Caixote = { material = Enum.Material.Wood, color = Color3.fromRGB(150, 112, 74) },
	Barril = { material = Enum.Material.Wood, color = Color3.fromRGB(128, 86, 56) },
	AroBarril = { material = Enum.Material.Metal, color = Color3.fromRGB(72, 66, 76) },
	Saco = { material = Enum.Material.Fabric, color = Color3.fromRGB(178, 152, 112) },
	Cesto = { material = Enum.Material.Wood, color = Color3.fromRGB(176, 136, 84) },
	-- cristal em dois tons, como o Coração (as claras brilham; claras demais estouram em branco com o Bloom)
	CristalClaro = { material = Enum.Material.Neon, color = Color3.fromRGB(100, 78, 232) },
	CristalEscuro = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(58, 26, 130) },
	-- cogumelos-lume (verde musgo do lobby, mais escuro que #5BE37D pelo mesmo motivo do cristal)
	CogumeloHaste = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(206, 200, 178) },
	CogumeloChapeu = { material = Enum.Material.Neon, color = Color3.fromRGB(60, 170, 95) },
}
-- listras do toldo (ToldoB) por banca: as cores do lobby, apagadas (pano velho)
local STRIPE_PURPLE = Color3.fromRGB(104, 70, 150)
local STRIPE_GOLD = Color3.fromRGB(190, 146, 72)
local STRIPE_GREEN = Color3.fromRGB(64, 112, 72)
local LANTERN = Color3.fromRGB(255, 184, 92) -- #FFB85C, luz de Áuren

-- kits: mercadorias de mais de uma malha (as peças dividem a mesma origem)
local KITS: { [string]: { { string } } } = {
	Barril = { { "Barril_1", "Barril" }, { "AroBarril_1", "Aros" } },
	Cristais = { { "CristalClaro_1", "Faces Claras" }, { "CristalEscuro_1", "Faces Escuras" } },
	Cogumelos = { { "CogumeloHaste_1", "Hastes" }, { "CogumeloChapeu_1", "Chapéus" } },
	Caixote = { { "Caixote_1", "Caixote" } },
	Caixote2 = { { "Caixote_2", "Caixote" } },
	Saco = { { "Saco_1", "Saco" } },
	Saco2 = { { "Saco_2", "Saco" } },
	Cesto = { { "Cesto_1", "Cesto" } },
}
-- nome do Model de cada kit no Studio
local KIT_NAMES: { [string]: string } = {
	Barril = "Barril",
	Cristais = "Cristais",
	Cogumelos = "Cogumelos-Lume",
	Caixote = "Caixote",
	Caixote2 = "Caixote",
	Saco = "Saco",
	Saco2 = "Saco",
	Cesto = "Cesto",
}

-- cada mercadoria: kit, posição local (x, y, z: frente da banca = -z), giro em graus, escala
type Good = { string | number }
-- variante da banca: altura do balcão, postes de trás (z) e altura da frente do toldo
type Variant = { counter: number, backZ: number, frontZ: number, width: number }
local VARIANTS: { [number]: Variant } = {
	[1] = { counter = 3.4, backZ = 3.5, frontZ = -1.05, width = 9 },
	[2] = { counter = 3.4, backZ = 3.3, frontZ = -1.05, width = 8 },
	[3] = { counter = 4.05, backZ = 4.7, frontZ = -2.25, width = 11.6 },
}

type Stall = {
	name: string,
	variant: number,
	at: Vector3,
	yaw: number, -- graus; 0 = frente para -z
	stripe: Color3,
	goods: { Good },
	replaces: string?, -- caixa do blockout que esta banca substitui
	groundY: number?, -- altura fixa do chão (a do Tanu acompanha o balcão do código, y = 0)
}

local STALLS: { Stall } = {
	{
		name = "Banca do Tanu",
		variant = 3,
		at = Vector3.new(82, 0, 100),
		yaw = 0,
		stripe = STRIPE_GOLD,
		groundY = 0,
		goods = {
			{ "Cristais", -3.6, 4.05, -0.3, 20, 0.9 },
			{ "Cesto", -0.6, 4.05, 0.2, 0, 0.6 },
			{ "Cogumelos", -0.6, 4.3, 0.2, 40, 0.55 },
			{ "Saco2", 2.4, 4.05, 0.1, 30, 0.45 },
			{ "Cristais", 4.0, 4.05, -0.2, 150, 0.7 },
			{ "Caixote", -2.5, 3.4, 4.05, 10, 0.45 },
			{ "Cristais", 2.0, 5.6, 4.05, 70, 0.55 },
			{ "Saco", 0.0, 3.4, 4.0, 0, 0.4 },
			{ "Barril", 7.3, 0, 1.5, 0, 0.9 },
			{ "Caixote2", -7.2, 0, 0.6, 12, 0.9 },
			{ "Caixote", -7.0, 1.8, 0.8, -8, 0.7 },
			{ "Saco", -7.4, 0, 3.0, 40, 0.8 },
		},
	},
	{
		name = "Banca dos Cogumelos-Lume",
		variant = 1,
		at = Vector3.new(112, 0, 192),
		yaw = 0,
		stripe = STRIPE_GREEN,
		replaces = "Banca 1",
		goods = {
			{ "Cesto", -2.4, 3.4, 0.0, 0, 0.6 },
			{ "Cogumelos", -2.4, 3.65, 0.0, 10, 0.55 },
			{ "Cesto", 1.6, 3.4, 0.1, 0, 0.55 },
			{ "Cogumelos", 1.6, 3.62, 0.1, 200, 0.5 },
			{ "Cogumelos", -1.0, 3.4, 2.85, 90, 0.6 },
			{ "Cogumelos", 2.2, 5.6, 2.85, 300, 0.5 },
			{ "Saco", 5.8, 0, 0.4, 20, 0.75 },
			{ "Caixote", -5.9, 0, 1.0, -10, 0.85 },
			{ "Cogumelos", -5.9, 1.7, 1.0, 120, 0.7 },
		},
	},
	{
		name = "Banca dos Cristais",
		variant = 2,
		at = Vector3.new(150, 0, 198),
		yaw = 0,
		stripe = STRIPE_PURPLE,
		replaces = "Banca 2",
		goods = {
			{ "Cristais", -2.2, 3.4, 0.0, 0, 0.85 },
			{ "Cristais", 0.6, 3.4, -0.1, 130, 0.65 },
			{ "Cristais", 2.6, 3.4, 0.1, 250, 0.75 },
			{ "Cristais", -1.5, 5.6, 2.65, 60, 0.55 },
			{ "Cristais", 1.5, 3.4, 2.65, 300, 0.6 },
			{ "Caixote2", 5.4, 0, 0.6, 15, 0.9 },
			{ "Cristais", 5.4, 1.8, 0.6, 80, 0.8 },
			{ "Barril", -5.4, 0, 1.2, 0, 0.85 },
		},
	},
	{
		name = "Banca das Especiarias",
		variant = 1,
		at = Vector3.new(188, 0, 172),
		yaw = 90,
		stripe = STRIPE_GOLD,
		replaces = "Banca 3",
		goods = {
			{ "Saco", -2.6, 3.4, 0.0, 0, 0.45 },
			{ "Saco2", -0.6, 3.4, 0.1, 60, 0.42 },
			{ "Saco", 1.4, 3.4, -0.1, 140, 0.45 },
			{ "Saco2", 3.2, 3.4, 0.1, 220, 0.4 },
			{ "Saco", -2.0, 3.4, 2.85, 0, 0.42 },
			{ "Barril", 6.0, 0, 0.8, 0, 0.9 },
			{ "Barril", 6.3, 0, 3.4, 0, 0.8 },
			{ "Saco2", -5.9, 0, 0.4, 70, 0.8 },
			{ "Saco", -6.1, 0, 2.4, 10, 0.75 },
		},
	},
	{
		name = "Banca dos Caixotes",
		variant = 2,
		at = Vector3.new(186, 0, 128),
		yaw = 90,
		stripe = STRIPE_PURPLE,
		replaces = "Banca 4",
		goods = {
			{ "Caixote", -2.0, 3.4, 0.0, 8, 0.5 },
			{ "Caixote2", 0.4, 3.4, 0.1, -6, 0.45 },
			{ "Cristais", 2.4, 3.4, 0.0, 30, 0.6 },
			{ "Caixote", -1.6, 5.6, 2.65, 0, 0.4 },
			{ "Caixote2", 5.2, 0, 0.4, 5, 0.95 },
			{ "Caixote", 5.3, 1.9, 0.5, -12, 0.8 },
			{ "Caixote", 5.4, 0, 2.6, 20, 0.85 },
			{ "Barril", -5.3, 0, 1.0, 0, 0.85 },
		},
	},
}

-- ------------------------------------------------------------------ malhas

local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local market = lobby:FindFirstChild("Roleplay") and lobby.Roleplay:FindFirstChild("Mercado das Raízes")
assert(market, "falta Workspace.Lobby1.Roleplay.Mercado das Raízes")

local function templates(): Folder
	local root = ServerStorage:FindFirstChild("Lobby1Modelos")
	assert(root, "falta ServerStorage.Lobby1Modelos")
	local existing = root:FindFirstChild("Mercado")
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Mercado"
	local source = InsertService:LoadAsset(ASSET_ID)
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			local clone = d:Clone()
			clone.Name = d.Name
			clone.Parent = folder
		end
	end
	source:Destroy()
	folder.Parent = root
	return folder
end
local T = templates()

local function piece(name: string, parent: Instance, newName: string, at: CFrame, k: number, color: Color3?): MeshPart
	local template = T:FindFirstChild(name) :: MeshPart?
	assert(template, `falta a malha {name}`)
	local center = CENTERS[name]
	assert(center, `falta o centro de {name}`)
	local part = template:Clone()
	part.Size *= k
	part.CFrame = at * CFrame.new(center * k) * CFrame.Angles(0, math.pi, 0)
	part.Anchored = true
	part.Name = newName
	local style = STYLES[string.split(name, "_")[1]]
	if style then
		part.Material = style.material
		part.Color = style.color
	end
	if color then
		part.Color = color
	end
	-- colisão: a madeira da banca segue a forma (dá para entrar atrás do balcão); o toldo não segura ninguém; a
	-- mercadoria, pequena, vira caixa
	local kind = string.split(name, "_")[1]
	if kind == "BancaMadeira" then
		part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
	elseif string.sub(kind, 1, 5) == "Toldo" then
		part.CanCollide = false
		part.CanTouch = false
	else
		part.CollisionFidelity = Enum.CollisionFidelity.Box
	end
	part.Parent = parent
	return part
end

-- ------------------------------------------------------------------ chão

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

local function groundAt(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -80, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

-- ------------------------------------------------------------------ bancas

local old = market:FindFirstChild("Bancas")
if old then
	old:Destroy()
end
local folder = Instance.new("Model")
folder.Name = "Bancas"

local built: { Model } = {}
for _, stall in STALLS do
	local v = VARIANTS[stall.variant]
	local model = Instance.new("Model")
	model.Name = stall.name
	-- chão: o mais baixo entre o meio e os quatro cantos (a banca afunda um pouco no terreno irregular)
	local y = stall.groundY
	if not y then
		local lowest = math.huge
		for _, off in
			{ Vector3.zero, Vector3.new(4, 0, 2), Vector3.new(-4, 0, 2), Vector3.new(4, 0, -2), Vector3.new(-4, 0, -2) }
		do
			local p = stall.at + off
			lowest = math.min(lowest, groundAt(p.X, p.Z))
		end
		y = lowest - 0.1
	end
	local origin = CFrame.new(stall.at.X, y, stall.at.Z) * CFrame.Angles(0, math.rad(stall.yaw), 0)

	local n = stall.variant
	piece(`BancaMadeira_{n}`, model, "Madeira", origin, 1)
	piece(`ToldoA_{n}`, model, "Toldo", origin, 1)
	piece(`ToldoB_{n}`, model, "Toldo (listras)", origin, 1, stall.stripe)

	local goods = Instance.new("Folder")
	goods.Name = "Mercadoria"
	goods.Parent = model
	for _, g in stall.goods do
		local kit = KITS[g[1] :: string]
		assert(kit, `kit desconhecido {g[1]}`)
		local at = origin
			* CFrame.new(g[2] :: number, g[3] :: number, g[4] :: number)
			* CFrame.Angles(0, math.rad(g[5] :: number), 0)
		local item = Instance.new("Model")
		item.Name = KIT_NAMES[g[1] :: string]
		for _, spec in kit do
			piece(spec[1], item, spec[2], at, g[6] :: number)
		end
		item.Parent = goods
	end

	-- lanterna debaixo do toldo, perto da frente (luz quente de Áuren)
	local lantern = Instance.new("Part")
	lantern.Name = "Lanterna da Banca"
	lantern.Size = Vector3.new(0.6, 0.8, 0.6)
	-- abaixo do babado (a 6,7 ficava escondida atrás dele)
	lantern.CFrame = origin * CFrame.new(v.width / 2 - 1.6, 5.5, v.frontZ + 1.5)
	lantern.Material = Enum.Material.Neon
	lantern.Color = LANTERN
	lantern.Anchored = true
	lantern.CanCollide = false
	lantern.CastShadow = false
	lantern.Parent = model
	local cord = Instance.new("Part")
	cord.Name = "Cordão"
	cord.Size = Vector3.new(0.08, 1.2, 0.08)
	cord.CFrame = lantern.CFrame * CFrame.new(0, 1.0, 0)
	cord.Material = Enum.Material.Fabric
	cord.Color = Color3.fromRGB(60, 46, 36)
	cord.Anchored = true
	cord.CanCollide = false
	cord.Parent = model
	local light = Instance.new("PointLight")
	light.Color = LANTERN
	light.Brightness = 1.2
	light.Range = 16
	light.Shadows = false
	light.Parent = lantern

	model.Parent = folder
	table.insert(built, model)

	local replaced = stall.replaces and market:FindFirstChild(stall.replaces)
	if replaced then
		replaced:Destroy()
	end
end
folder.Parent = market

-- a lanterna do blockout ao lado do Tanu (Fase 3) vira a lanterna da banca
local lights = lobby:FindFirstChild("Luzes")
local auren = lights and lights:FindFirstChild("Áuren")
local oldLantern = auren and auren:FindFirstChild("Lanterna de Áuren (Banca do Tanu)")
if oldLantern then
	oldLantern:Destroy()
end

-- ------------------------------------------------------------------ limpa o que ficou por dentro

local clearFolders: { Instance } = {}
for _, path in { { "Formacoes" }, { "Terreno", "Plantas" } } do
	local f: Instance? = lobby
	for _, name in path do
		f = f and f:FindFirstChild(name)
	end
	if f then
		table.insert(clearFolders, f)
	end
end
-- pastas que guardam os itens soltos: cada categoria de Formacoes (Agulhas de Pedra, Rochedos Caídos...) e Plantas
local containers: { [Instance]: boolean } = {}
for _, f in clearFolders do
	if f.Name == "Formacoes" then
		for _, category in f:GetChildren() do
			containers[category] = true
		end
	else
		containers[f] = true
	end
end
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = clearFolders
local removed = 0
for _, model in built do
	local cf, size = model:GetBoundingBox()
	for _, part in workspace:GetPartBoundsInBox(cf, size + Vector3.new(3, 0, 3), overlap) do
		-- sobe até o item inteiro (o filho direto da pasta da categoria)
		local node: Instance? = part
		while node and node.Parent and not containers[node.Parent] do
			node = node.Parent
		end
		if node and node.Parent then
			node:Destroy()
			removed += 1
		end
	end
end

return `Mercado: {#built} bancas montadas, {removed} formações/plantas tiradas de dentro delas`
