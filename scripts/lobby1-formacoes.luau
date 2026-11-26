--!strict
-- Espalha as formações de rocha do Lobby 1 (Fase 4 do BRIEFING-LOBBY1.md). NÃO faz parte do jogo: rode no datamodel
-- Edit (MCP execute_luau) depois do Terrain (scripts/lobby1-terreno.luau). Refaz tudo dentro de
-- Workspace.Lobby1.Formacoes (apaga só o que está lá), com semente fixa.
--
-- Malhas: asset 106755483997689 ("FormacoesLobby1", gerado por scripts/lobby1-formacoes.py). Os modelos limpos ficam em
-- ServerStorage.Lobby1Modelos.Formacoes (montados a partir do asset na primeira vez).
--
-- Regras do briefing: rotação e escala aleatórias (0,6 a 1,6×), mais densas nas bordas, nunca bloqueando a avenida ou as
-- entradas. Presas do Teto no teto inteiro (fora do buraco do feixe); Gotas da Fenda no teto da avenida, perto do
-- altar; Agulhas de Pedra entre as colunas e nas áreas; Rochedos Caídos como entulho na beira da nave e nas bordas.

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ASSET_ID = 106755483997689
local SEED = 1717
local WALL = 292 -- meia-largura da caverna (igual ao gerador do Terrain)
local SHAFT = Vector2.new(0, -106) -- poço do feixe (fica livre)

local terrain = workspace.Terrain
local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local rng = Random.new(SEED)

-- ------------------------------------------------------------------ modelos

local function templates(): Folder
	local root = ServerStorage:FindFirstChild("Lobby1Modelos")
	if not root then
		local created = Instance.new("Folder")
		created.Name = "Lobby1Modelos"
		created.Parent = ServerStorage
		root = created
	end
	assert(root, "Lobby1Modelos")
	local existing = root:FindFirstChild("Formacoes")
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Formacoes"
	local inserted = ServerStorage:FindFirstChild("FormacoesLobby1")
	local source: Instance = if inserted then inserted else InsertService:LoadAsset(ASSET_ID)
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			local kind, n, piece = string.match(d.Name, "^(%a+)_(%d+)_?(%a*)$")
			assert(kind and n, `nome inesperado no asset: {d.Name}`)
			assert(math.abs(d.CFrame.UpVector.Y) > 0.99, `{d.Name} não está em pé no asset`)
			local clone = d:Clone()
			clone.Anchored = true
			clone.CFrame = CFrame.new(clone.Position)
			if piece == "" then
				clone.Name = `{kind}_{n}`
				clone.Parent = folder
			else
				local modelName = `{kind}_{n}`
				local model = folder:FindFirstChild(modelName) :: Model?
				if not model then
					local created = Instance.new("Model")
					created.Name = modelName
					created.Parent = folder
					model = created
				end
				assert(model, modelName)
				clone.Name = piece :: string
				clone.Parent = model
				if piece == "Rocha" then
					model.PrimaryPart = clone
				end
			end
		end
	end
	folder.Parent = root
	source:Destroy() -- o asset pode ser inserido de novo pelo id
	return folder
end

local T = templates()

local function meshes(prefix: string): { MeshPart }
	local list: { MeshPart } = {}
	for i = 1, 9 do
		local item = T:FindFirstChild(`{prefix}_{i}`)
		if item and item:IsA("MeshPart") then
			table.insert(list, item)
		end
	end
	assert(#list > 0, `sem modelos {prefix}`)
	return list
end

local function models(prefix: string): { Model }
	local list: { Model } = {}
	for i = 1, 9 do
		local item = T:FindFirstChild(`{prefix}_{i}`)
		if item and item:IsA("Model") then
			table.insert(list, item)
		end
	end
	assert(#list > 0, `sem modelos {prefix}`)
	return list
end

local PRESAS = meshes("PresaDoTeto")
local GOTAS = models("GotaDaFenda")
local AGULHAS = meshes("AgulhaDePedra")
local ROCHEDOS = meshes("RochedoCaido")

-- ------------------------------------------------------------------ pastas de saída

local formacoes = lobby:FindFirstChild("Formacoes") :: Folder
assert(formacoes, "falta Workspace.Lobby1.Formacoes")

local function outFolder(name: string): Folder
	local f = formacoes:FindFirstChild(name)
	if f then
		f:ClearAllChildren()
		return f :: Folder
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = formacoes
	return created
end

local OUT_PRESAS = outFolder("Presas do Teto")
local OUT_GOTAS = outFolder("Gotas da Fenda")
local OUT_AGULHAS = outFolder("Agulhas de Pedra")
local OUT_ROCHEDOS = outFolder("Rochedos Caídos")

-- ------------------------------------------------------------------ geometria do lobby

local function roundedRadius(x: number, z: number): number
	local ax, az = math.abs(x), math.abs(z)
	return (ax ^ 6 + az ^ 6) ^ (1 / 6)
end

-- 0 no centro, 1 perto das paredes: as formações ficam mais densas e maiores nas bordas
local function edgeFactor(x: number, z: number): number
	return math.clamp((roundedRadius(x, z) / WALL - 0.45) / 0.5, 0, 1)
end

local function isAir(p: Vector3): boolean
	local lo = Vector3.new(math.floor(p.X / 4) * 4, math.floor(p.Y / 4) * 4, math.floor(p.Z / 4) * 4)
	local _, occupancies = terrain:ReadVoxels(Region3.new(lo, lo + Vector3.new(4, 4, 4)), 4)
	return occupancies[1][1][1] < 0.05
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { terrain }
terrainOnly.IgnoreWater = false

-- Altura do teto acima de (x, z), ou nil (dentro de rocha, fora da caverna ou no poço)
local function ceilingAt(x: number, z: number): number?
	local start = Vector3.new(x, 90, z)
	if not isAir(start) then
		return nil
	end
	local hit = workspace:Raycast(start, Vector3.new(0, 100, 0), terrainOnly)
	if not hit or hit.Position.Y < 100 or hit.Position.Y > 160 then
		return nil
	end
	return hit.Position.Y
end

-- Altura do chão em (x, z), ou nil (água, rochedo, saliência, fora da caverna)
local function floorAt(x: number, z: number): number?
	local start = Vector3.new(x, 70, z)
	if not isAir(start) then
		return nil
	end
	local hit = workspace:Raycast(start, Vector3.new(0, -90, 0), terrainOnly)
	if not hit or hit.Material == Enum.Material.Water or hit.Position.Y > 3 then
		return nil
	end
	return hit.Position.Y
end

-- Pontos com função no jogo (montados por código, não existem no modo Edit) e marcos do cenário: (x, z, raio)
local KEEP_CLEAR: { { number } } = {
	{ 191, 144, 12 }, -- loja (balcão do Tanu, na frente do prédio da Loja do Tanu)
	{ 188.5, 157, 5 }, -- Tanu
	{ 155, 191, 10 }, -- Forja (bigorna, na frente do prédio da Forja de Cristal)
	{ 161.5, 189, 5 }, -- Brokk
	{ -85, 60, 8 }, -- bonecos de treino
	{ -100, 60, 8 },
	{ -130, 52, 6 }, -- onda de treino
	{ -145, 62, 6 },
	{ -130, 72, 6 },
	{ 98, -112, 9 }, -- Poço de Calor
	{ 160, -238, 12 }, -- Cascata do Abismo (e o futuro Túnel dos Ecos atrás dela)
}
local COLUMN_Z = { 85, 51, 17, -17, -51, -85 }

local function blocked(x: number, z: number, r: number): boolean
	local ax, az = math.abs(x), math.abs(z)
	if ax < 30 + r and z > -120 and z < 114 then
		return true -- Avenida das Colunas e Altar do Coração
	end
	for _, cz in COLUMN_Z do
		if Vector2.new(ax - 30, z - cz).Magnitude < 7 + r then
			return true -- colunas
		end
	end
	if ax < 85 and math.abs(az - 68) < 13 + r then
		return true -- passagens pelos arcos até as quatro áreas
	end
	if ax < 70 and az < 22 + r then
		return true -- cruzamento das torres (portais e entradas)
	end
	for _, c in KEEP_CLEAR do
		if Vector2.new(x - c[1], z - c[2]).Magnitude < c[3] + r then
			return true
		end
	end
	local ex, ez = (x - 150) / 56, (z + 185) / 58
	if ex * ex + ez * ez < 1 then
		return true -- Lago Espelhado
	end
	if z > 225 - r and ax > 130 - r and ax < 250 then
		return true -- rampas das Galerias Altas e a chegada até elas (um rochedo no pé da rampa SE atrapalhava)
	end
	return false
end

-- Peças do blockout (tendas, bancas, estantes, lanternas...): os pisos invisíveis das áreas têm CanQuery = false
local propParams = OverlapParams.new()
propParams.FilterType = Enum.RaycastFilterType.Include
local propFolders: { Instance } = {}
for _, name in { "Nave", "Altar", "Torres", "Roleplay", "Luzes" } do
	local f = lobby:FindFirstChild(name)
	assert(f, `falta Workspace.Lobby1.{name}`)
	table.insert(propFolders, f)
end
propParams.FilterDescendantsInstances = propFolders

local function hitsProp(pos: Vector3, radius: number): boolean
	return #workspace:GetPartBoundsInRadius(pos, radius, propParams) > 0
end

type Spot = { x: number, z: number, r: number }
local ceilingTaken: { Spot } = {}
local floorTaken: { Spot } = {}

local function free(list: { Spot }, x: number, z: number, r: number, gap: number): boolean
	for _, s in list do
		local d = r + s.r + gap
		if (x - s.x) ^ 2 + (z - s.z) ^ 2 < d * d then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------------ aparência

-- Material Rock: usa a textura estilizada do pacote do vídeo (override Ground_06 no MaterialService), e a cor só
-- tinge, por isso tons claros. O sorteio de antes (Basalt/Rock/Slate) continua consumindo o mesmo número do gerador,
-- então as posições não mudam.
local ROCK_COLORS = { Color3.fromRGB(215, 208, 232), Color3.fromRGB(190, 182, 210), Color3.fromRGB(228, 222, 240) }

local function styleRock(p: MeshPart, collide: boolean, shadow: boolean)
	p.Anchored = true
	local _ = rng:NextNumber()
	p.Material = Enum.Material.Rock
	p.Color = ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)]
	p.CastShadow = shadow
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
end

local function randomTurn(tilt: number): CFrame
	return CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* CFrame.Angles(math.rad(rng:NextNumber(-tilt, tilt)), 0, math.rad(rng:NextNumber(-tilt, tilt)))
end

-- Peça de uma malha só. anchorY = teto (pendurada: o topo fica 2 studs dentro da rocha) ou chão (apoiada).
local function placeMesh(
	template: MeshPart,
	parent: Instance,
	x: number,
	z: number,
	anchorY: number,
	hanging: boolean,
	s: number,
	tilt: number,
	sink: number
): MeshPart
	local p = template:Clone()
	p.Size = template.Size * s
	local half = p.Size.Y / 2
	local y = if hanging then anchorY + 2 - half else anchorY - sink + half
	p.CFrame = CFrame.new(x, y, z) * randomTurn(tilt)
	p.Parent = parent
	return p
end

local function footprint(template: MeshPart, s: number): number
	return math.max(template.Size.X, template.Size.Z) / 2 * s
end

-- ------------------------------------------------------------------ 1) Gotas da Fenda (antes das Presas: lugar garantido)

local counts = { gotas = 0, presas = 0, agulhas = 0, rochedos = 0 }
local tries = 0
while counts.gotas < 14 and tries < 600 do
	tries += 1
	local x, z = rng:NextNumber(-34, 34), rng:NextNumber(-114, -22)
	if (Vector2.new(x, z) - SHAFT).Magnitude < 26 then
		continue
	end
	local ceiling = ceilingAt(x, z)
	local template = GOTAS[rng:NextInteger(1, #GOTAS)]
	local s = rng:NextNumber(0.8, 1.4)
	local rock = template.PrimaryPart :: MeshPart
	local r = math.max(rock.Size.X, rock.Size.Z) / 2 * s
	if not ceiling or not free(ceilingTaken, x, z, r, 4) then
		continue
	end
	local m = template:Clone()
	m:ScaleTo(s)
	local cloneRock = m.PrimaryPart :: MeshPart
	m:PivotTo(CFrame.new(x, ceiling + 2 - cloneRock.Size.Y / 2, z) * randomTurn(3))
	for _, part in m:GetChildren() do
		if part:IsA("MeshPart") then
			if part.Name == "Cristal" then
				part.Anchored = true
				part.Material = Enum.Material.Neon
				part.Color = Color3.fromHex("8A3CFF")
				part.CastShadow = false
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			else
				styleRock(part, false, false)
			end
		end
	end
	m.Parent = OUT_GOTAS
	table.insert(ceilingTaken, { x = x, z = z, r = r })
	counts.gotas += 1
end
task.wait()

-- ------------------------------------------------------------------ 2) Presas do Teto (grade com sorteio)

for gx = -280, 280, 20 do
	for gz = -280, 280, 20 do
		local x, z = gx + rng:NextNumber(-8, 8), gz + rng:NextNumber(-8, 8)
		local edge = edgeFactor(x, z)
		local template = PRESAS[rng:NextInteger(1, #PRESAS)]
		local s = 0.6 + 0.6 * rng:NextNumber() + 0.4 * edge
		local keep = rng:NextNumber() < 0.3 + 0.7 * edge
		if keep and (Vector2.new(x, z) - SHAFT).Magnitude >= 26 then
			local ceiling = ceilingAt(x, z)
			local r = footprint(template, s) * 0.6
			if ceiling and free(ceilingTaken, x, z, r, 1) then
				local p = placeMesh(template, OUT_PRESAS, x, z, ceiling, true, s, 4, 0)
				styleRock(p, false, false)
				table.insert(ceilingTaken, { x = x, z = z, r = r })
				counts.presas += 1
			end
		end
	end
	task.wait()
end

-- ------------------------------------------------------------------ 3) Agulhas de Pedra

local function tryFloor(
	list: { MeshPart },
	parent: Instance,
	x: number,
	z: number,
	s: number,
	tilt: number,
	sink: number
): boolean
	local template = list[rng:NextInteger(1, #list)]
	local r = footprint(template, s)
	if blocked(x, z, r) or not free(floorTaken, x, z, r, 3) then
		return false
	end
	local ground = floorAt(x, z)
	if not ground or hitsProp(Vector3.new(x, ground + 3, z), r + 3) then
		return false
	end
	local p = placeMesh(template, parent, x, z, ground, false, s, tilt, sink)
	styleRock(p, true, true)
	table.insert(floorTaken, { x = x, z = z, r = r })
	return true
end

-- entre as colunas (fora das passagens e do cruzamento): nas duas fileiras, ao sul e ao norte da nave
for _, spot in { { 40, 34 }, { 40, -34 }, { 44, 104 }, { 42, -100 } } do
	for _, side in { -1, 1 } do
		local x, z = spot[1] * side, spot[2]
		if tryFloor(AGULHAS, OUT_AGULHAS, x, z, rng:NextNumber(0.9, 1.3), 5, 0.6) then
			counts.agulhas += 1
		end
		if
			tryFloor(AGULHAS, OUT_AGULHAS, x + side * 6, z + rng:NextNumber(-4, 4), rng:NextNumber(0.6, 0.8), 6, 0.6)
		then
			counts.agulhas += 1
		end
	end
end
tries = 0
while counts.agulhas < 70 and tries < 4000 do
	tries += 1
	local x, z = rng:NextNumber(-285, 285), rng:NextNumber(-285, 285)
	local edge = edgeFactor(x, z)
	if rng:NextNumber() < 0.12 + 0.88 * edge then
		local s = 0.6 + 0.6 * rng:NextNumber() + 0.4 * edge
		if tryFloor(AGULHAS, OUT_AGULHAS, x, z, s, 5, 0.6) then
			counts.agulhas += 1
		end
	end
end
task.wait()

-- ------------------------------------------------------------------ 4) Rochedos Caídos (entulho)

tries = 0
while counts.rochedos < 45 and tries < 4000 do
	tries += 1
	local x, z = rng:NextNumber(-285, 285), rng:NextNumber(-285, 285)
	local edge = edgeFactor(x, z)
	local ax = math.abs(x)
	local nearNave = if ax > 33 and ax < 62 and z > -120 and z < 114 then 0.5 else 0
	if rng:NextNumber() < 0.15 + 0.45 * edge + nearNave then
		local s = 0.6 + 0.7 * rng:NextNumber() + 0.3 * edge
		if tryFloor(ROCHEDOS, OUT_ROCHEDOS, x, z, s, 3, 0.2) then
			counts.rochedos += 1
		end
	end
end

print(
	`[Lobby1] formações: {counts.presas} Presas do Teto, {counts.gotas} Gotas da Fenda, {counts.agulhas} Agulhas de Pedra, {counts.rochedos} Rochedos Caídos`
)
