--!strict
-- Loja e Forja do Mercado das Raízes (Tripo + Blender): os prédios que o designer gerou no Tripo, completados no
-- Blender (scripts/blender/mercado_tripo.py: morro de grama atrás, cristais separados para brilhar). NÃO faz parte do
-- jogo: rode no datamodel Edit (MCP execute_luau). Refaz os Models "Loja do Tanu" e "Forja de Cristal" em
-- Roleplay/"Mercado das Raízes". As peças com função (balcão da loja, bigorna da forja, Tanu e Brokk) continuam
-- geradas por código nos lugares destes prédios: LobbyService (SHOP_POSITION, FORGE_POSITION) e NpcService (POSITIONS).
-- Mudou o lugar de um prédio? Mude essas constantes junto.
--
-- Desenho em "L" no canto sudeste (decisão do designer, 26/11/2026; as bancas saíram):
-- - Loja: no lado leste, de frente para o meio do Mercado (-x), afastada das rochas da parede; o morro desce em rampa
--   até a parede da caverna (x ~ 240).
-- - Forja: no lado sul, de costas para a rampa das Galerias Altas (z ~ 240) e de frente para quem vem do spawn (-z).
--   Olhando para a Forja, a Loja fica à esquerda.
-- - Cristais em três tons (como o Coração do Abismo): claros e médios em Neon, escuros sem brilho; uma luz roxa fraca
--   por prédio e a luz da fornalha na Forja.
-- - Plantas do pacote do vídeo em grupos, só na grama do morro (o capim 3D do Terrain não nasce em MeshPart).
--
-- Malha nova: rode o mercado_tripo.py no Blender, suba cada GLB como nova versão do asset (PATCH
-- /assets/v1/assets/{id}), copie os centros que o export devolve e apague o cache em ServerStorage.Lobby1Modelos
-- (LojaTripo, ForjaTripo). O importador gira a malha 180° em Y (ver lobby1-pedras).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local PLANT_ATLAS = "rbxassetid://17750471621" -- as plantas do pacote vêm sem textura (ver lobby1-revestimento)
local CRYSTAL_LIGHT = Color3.fromRGB(192, 140, 255) -- #C08CFF
local FIRE = Color3.fromRGB(255, 140, 60)

type Building = {
	name: string, -- Model no Studio
	cache: string, -- pasta em ServerStorage.Lobby1Modelos
	asset: number,
	prefix: string, -- prefixo das malhas no GLB
	origin: CFrame, -- centro do prédio no chão; o +z do arquivo (a frente) vira para onde a loja olha
	centers: { [string]: Vector3 }, -- centro da caixa de cada malha no glTF (o que o export devolve)
	lightAt: Vector3, -- luz roxa dos cristais (no espaço do prédio, frente = +z)
	fireAt: Vector3?, -- luz da fornalha
	seed: number,
}

local BUILDINGS: { Building } = {
	{
		name = "Loja do Tanu",
		cache = "LojaTripo",
		asset = 117044231943259,
		prefix = "Loja",
		-- fachada em x ~ 187 (a frente fica a 10,45 do centro); a 1ª versão (x ~ 197) encostava o morro nas rochas
		origin = CFrame.new(197.5, 0, 150) * CFrame.Angles(0, -math.pi / 2, 0),
		centers = {
			LojaTripo = Vector3.new(0.0, 8.94, 0.0),
			LojaCristalClaro = Vector3.new(0.739, 8.512, -0.07),
			LojaCristalMedio = Vector3.new(0.739, 8.512, -0.276),
			LojaCristalEscuro = Vector3.new(0.692, 8.459, -2.445),
			LojaMorroGrama = Vector3.new(-0.6, 6.527, -22.8),
			LojaMorroTerra = Vector3.new(0.0, 5.885, -6.0),
		},
		lightAt = Vector3.new(0, 15, -2),
		seed = 41,
	},
	{
		name = "Forja de Cristal",
		cache = "ForjaTripo",
		asset = 88131421963908,
		prefix = "Forja",
		-- de costas para a rampa (sul), de frente para o norte; a frente fica a 7,9 do centro (z ~ 188)
		origin = CFrame.new(152, 0, 196) * CFrame.Angles(0, math.pi, 0),
		centers = {
			ForjaTripo = Vector3.new(-0.006, 7.513, 0.0),
			ForjaCristalClaro = Vector3.new(0.235, 7.46, -2.0),
			ForjaCristalMedio = Vector3.new(0.205, 7.894, -3.83),
			ForjaCristalEscuro = Vector3.new(0.205, 7.378, -3.9),
			ForjaMorroGrama = Vector3.new(-0.6, 5.677, -22.8),
			ForjaMorroTerra = Vector3.new(0.0, 5.343, -6.0),
		},
		lightAt = Vector3.new(0, 14, -3),
		fireAt = Vector3.new(1.5, 4, 1.5),
		seed = 42,
	},
}

type Style = { material: Enum.Material, color: Color3 }
local STYLES: { [string]: Style } = {
	CristalClaro = { material = Enum.Material.Neon, color = Color3.fromRGB(100, 78, 232) },
	CristalMedio = { material = Enum.Material.Neon, color = Color3.fromRGB(78, 36, 200) },
	CristalEscuro = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(58, 26, 130) },
	-- o morro usa os materiais do pacote do vídeo (overrides de Grass e Ground): cor clara, a textura dá a cor
	MorroGrama = { material = Enum.Material.Grass, color = Color3.fromRGB(205, 215, 195) },
	MorroTerra = { material = Enum.Material.Ground, color = Color3.fromRGB(205, 195, 185) },
}
local NAMES: { [string]: string } = {
	Tripo = "Prédio",
	CristalClaro = "Cristais (faces claras)",
	CristalMedio = "Cristais (faces médias)",
	CristalEscuro = "Cristais (faces escuras)",
	MorroGrama = "Morro (grama)",
	MorroTerra = "Morro (terra)",
}

local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local market = lobby:FindFirstChild("Roleplay") and lobby.Roleplay:FindFirstChild("Mercado das Raízes")
assert(market, "falta Workspace.Lobby1.Roleplay.Mercado das Raízes")
local root = ServerStorage:FindFirstChild("Lobby1Modelos")
assert(root, "falta ServerStorage.Lobby1Modelos")
local pack = ServerStorage:FindFirstChild("BonesStylizedPackAssets")
assert(pack, "falta ServerStorage.BonesStylizedPackAssets (pacote do vídeo)")

local plants: { MeshPart } = {}
for _, child in pack:GetChildren() do
	if
		child:IsA("MeshPart")
		and child.Name == "Plant"
		and child.Size.Y > 0.5
		and math.min(child.Size.X, child.Size.Z) > 0.2
	then
		table.insert(plants, child) -- fora os planos finos (folhas soltas)
	end
end
assert(#plants >= 10, "pacote incompleto")

local function templates(b: Building): Folder
	local existing = root:FindFirstChild(b.cache)
	if existing then
		return existing :: Folder
	end
	assert(b.asset ~= 0, `falta o asset de {b.name}`)
	local folder = Instance.new("Folder")
	folder.Name = b.cache
	local source = InsertService:LoadAsset(b.asset)
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

local function pointLight(parent: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
end

local function anchorPart(name: string, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- plantas em grupos na grama do morro: o raio de cima precisa bater PRIMEIRO na grama (não no prédio)
local function plantHill(model: Model, grass: BasePart, rng: Random): number
	local everything = RaycastParams.new()
	everything.FilterType = Enum.RaycastFilterType.Include
	everything.FilterDescendantsInstances = { model }
	local folder = Instance.new("Folder")
	folder.Name = "Plantas do Morro"
	folder.Parent = model
	local half = grass.Size / 2
	local count = 0
	for _ = 1, 26 do
		local c = grass.CFrame
			* CFrame.new(rng:NextNumber(-half.X, half.X) * 0.85, 0, rng:NextNumber(-half.Z, half.Z) * 0.85)
		for _ = 1, rng:NextInteger(3, 6) do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = 3.5 * math.sqrt(rng:NextNumber())
			local x, z = c.X + math.cos(a) * d, c.Z + math.sin(a) * d
			local hit = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -100, 0), everything)
			if hit and hit.Instance == grass and hit.Normal.Y > 0.6 and hit.Position.Y > 0.6 then
				local source = plants[rng:NextInteger(1, #plants)]
				local size = source.Size * rng:NextNumber(1.1, 2.1)
				local p = source:Clone()
				p.TextureID = PLANT_ATLAS
				p.Size = size
				local axis = Vector3.new(0, 1, 0):Cross(hit.Normal)
				local tilt = if axis.Magnitude > 0.01
					then CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(hit.Normal.Y, -1, 1)) * 0.5)
					else CFrame.identity
				p.CFrame = CFrame.new(hit.Position + Vector3.new(0, size.Y / 2 - 0.15, 0))
					* tilt
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Parent = folder
				count += 1
			end
		end
	end
	return count
end

-- tira formações e plantas do chão que ficaram inteiras debaixo do morro ou dentro do prédio (as que só encostam
-- ficam: pedra saindo do morro é natural)
local function clearBuried(model: Model): number
	local solid: { Instance } = {}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(solid, c)
		end
	end
	local onlyModel = RaycastParams.new()
	onlyModel.FilterType = Enum.RaycastFilterType.Include
	onlyModel.FilterDescendantsInstances = solid
	local containers: { [Instance]: boolean } = {}
	local search: { Instance } = {}
	local formacoes = lobby:FindFirstChild("Formacoes")
	if formacoes then
		for _, category in formacoes:GetChildren() do
			containers[category] = true
		end
		table.insert(search, formacoes)
	end
	local terreno = lobby:FindFirstChild("Terreno")
	local plantas = terreno and terreno:FindFirstChild("Plantas")
	if plantas then
		containers[plantas] = true
		table.insert(search, plantas)
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = search
	local removed = 0
	local cf, size = model:GetBoundingBox()
	local seen: { [Instance]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(cf, size, overlap) do
		local node: Instance? = part
		while node and node.Parent and not containers[node.Parent] do
			node = node.Parent
		end
		if node and node.Parent and not seen[node] then
			seen[node] = true
			local top: Vector3? = nil
			if node:IsA("Model") then
				local c, s = node:GetBoundingBox()
				top = c.Position + Vector3.new(0, s.Y / 2, 0)
			elseif node:IsA("BasePart") then
				top = node.Position + Vector3.new(0, node.Size.Y / 2, 0)
			end
			if top then
				local hit = workspace:Raycast(Vector3.new(top.X, 80, top.Z), Vector3.new(0, -80, 0), onlyModel)
				if hit and hit.Position.Y > top.Y then
					node:Destroy()
					removed += 1
				end
			end
		end
	end
	return removed
end

local report: { string } = {}
for _, b in BUILDINGS do
	local T = templates(b)
	local old = market:FindFirstChild(b.name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = b.name
	local grass: BasePart? = nil
	for name, center in b.centers do
		local template = T:FindFirstChild(name) :: MeshPart?
		assert(template, `falta a malha {name}`)
		local part = template:Clone()
		part.CFrame = b.origin * CFrame.new(center) * CFrame.Angles(0, math.pi, 0)
		part.Anchored = true
		local kind = string.sub(name, #b.prefix + 1)
		part.Name = NAMES[kind] or kind
		local style = STYLES[kind]
		if style then
			part.Material = style.material
			part.Color = style.color
			part.TextureID = ""
		end
		if string.sub(kind, 1, 7) == "Cristal" then
			-- sem colisão: os cristais estão espalhados pelo prédio todo, e a caixa deles cobriria a loja inteira
			part.CastShadow = false
			part.CanCollide = false
			part.CanTouch = false
		else
			-- prédio (dá para entrar pela porta) e morro (dá para subir) seguem a forma
			part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end
		if kind == "MorroGrama" then
			grass = part
		end
		part.Parent = model
	end
	pointLight(anchorPart("Luz dos Cristais", b.origin * CFrame.new(b.lightAt), model), CRYSTAL_LIGHT, 0.8, 22) -- com 1,4 a Forja inteira ficava roxa
	if b.fireAt then
		pointLight(anchorPart("Luz da Fornalha", b.origin * CFrame.new(b.fireAt), model), FIRE, 1.6, 18)
	end
	model.Parent = market

	local planted = if grass then plantHill(model, grass, Random.new(b.seed)) else 0
	local removed = clearBuried(model)
	table.insert(report, `{b.name}: {planted} plantas, {removed} formações/plantas enterradas tiradas`)
end

return table.concat(report, "\n")
