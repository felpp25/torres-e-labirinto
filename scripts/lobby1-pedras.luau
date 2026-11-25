--!strict
-- Troca as peças de pedra "geométricas" do Lobby 1 por pedra lavrada e gasta (pedido do designer depois do pacote do
-- vídeo "Environmental Art"): colunas em tambores lascados com faixas de ouro amassadas, capitéis e ábacos lascados,
-- base de cada coluna feita com as rochas do pacote (Stone_1–5, "rocha de verdade"), arcos em blocos e a escadaria e
-- a plataforma do altar em pedras soltas. NÃO faz parte do jogo: rode no datamodel Edit (MCP execute_luau).
--
-- Malhas: asset 76512463950762 ("PedrasLobby1", gerado por scripts/lobby1-pedras.py). O importador do Roblox gira a
-- malha 180° em Y (medido: o centro z da escadaria veio com o sinal trocado), por isso cada peça leva
-- CFrame.Angles(0, π, 0) depois do centro da caixa (CENTERS, copiado do PedrasLobby1.json).
-- Malha nova: rode o .py, suba o GLB como nova versão do mesmo asset (PATCH /assets/v1/assets/{id}), copie os centros
-- do json e apague ServerStorage.Lobby1Modelos.Pedras (o cache dos modelos) antes de rodar este script.
--
-- Refaz tudo o que é dele (Nave/Colunas do Salão, os arcos, Altar/Pedras do Altar) e pode rodar de novo. Na primeira vez
-- apaga as colunas e adornos antigos (Parts lisas) e deixa os degraus e a plataforma antigos invisíveis: eles continuam
-- como colisão (o topo de cada pedra fica a ±0,1 do topo da Part).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ASSET_ID = 76512463950762
local SEED = 4242
local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local nave = lobby:FindFirstChild("Nave") :: Folder
local altar = lobby:FindFirstChild("Altar") :: Folder
assert(nave and altar, "falta Nave ou Altar")
local rng = Random.new(SEED)

-- centro da caixa de cada malha no glTF (PedrasLobby1.json)
local CENTERS: { [string]: Vector3 } = {
	Fuste_1 = Vector3.new(0.02, 45, -0.001),
	Fuste_2 = Vector3.new(0.032, 45, -0.119),
	Fuste_3 = Vector3.new(-0.015, 45, 0.02),
	Escadaria_1 = Vector3.new(-0.002, 3.892, -88.271),
	PlataformaDoAltar_1 = Vector3.new(0.001, 4.034, -106.064),
}

local STONE = Color3.fromRGB(215, 208, 232) -- pedra clara: a textura do pacote dá a cor (igual às formações)
local STONE_DARK = Color3.fromRGB(190, 182, 210)
local GOLD = Color3.fromRGB(201, 162, 74)

-- Colunas do Salão: x = ±30, z de 85 a −85 (O = oeste, L = leste; 1 = sul, perto do spawn)
local COLUMN_Z = { 85, 51, 17, -17, -51, -85 }
local BANDS_Y = { 9, 33, 58, 81 }
local DIAMONDS_Y = { 22, 46 }
local CAPITAL_Y, ABACUS_Y = 87.5, 91

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
	local existing = root:FindFirstChild("Pedras")
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pedras"
	local source = InsertService:LoadAsset(ASSET_ID)
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			assert(math.abs(d.CFrame.UpVector.Y) > 0.99, `{d.Name} não está em pé no asset`)
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
local pack = ServerStorage:FindFirstChild("BonesStylizedPackAssets")
assert(pack, "falta ServerStorage.BonesStylizedPackAssets (pacote do vídeo)")

local function piece(name: string, cf: CFrame, parent: Instance, newName: string?): MeshPart
	local template = T:FindFirstChild(name) :: MeshPart?
	assert(template, `falta a malha {name}`)
	local part = template:Clone()
	local center = CENTERS[name] or Vector3.zero
	part.CFrame = cf * CFrame.new(center) * CFrame.Angles(0, math.pi, 0)
	part.Anchored = true
	part.Material = Enum.Material.Rock
	part.Color = STONE
	part.CastShadow = true
	part.Name = newName or name
	part.Parent = parent
	return part
end

-- rochas do pacote, pela ordem em que aparecem no ServerStorage (cada Stone_N tem várias escalas)
local stones: { MeshPart } = {}
for _, child in pack:GetChildren() do
	if child:IsA("MeshPart") and string.match(child.Name, "^Stone_%d") then
		table.insert(stones, child)
	end
end
assert(#stones >= 5, "faltam as rochas do pacote")

local function packStone(source: MeshPart, size: Vector3, cf: CFrame, parent: Instance): MeshPart
	local s = source:Clone()
	s.Size = size
	s.CFrame = cf
	s.Anchored = true
	s.CanCollide = true
	local sa = s:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		sa.Color = Color3.fromRGB(205, 196, 228) -- puxa o cinza do pacote para o violeta da caverna
	end
	s.Parent = parent
	return s
end

local function stoneByName(name: string, minVolume: number): MeshPart
	local best: MeshPart? = nil
	for _, s in stones do
		if s.Name == name and s.Size.X * s.Size.Y * s.Size.Z >= minVolume then
			if not best or s.Size.Magnitude < best.Size.Magnitude then
				best = s
			end
		end
	end
	assert(best, name)
	return best
end

-- ------------------------------------------------------------------ limpeza (primeira vez: peças lisas antigas)

for _, child in nave:GetChildren() do
	if string.match(child.Name, "^Coluna do Salão") and child:IsA("BasePart") then
		child:Destroy()
	end
end
local oldAdornos = nave:FindFirstChild("Adornos das Colunas")
if oldAdornos then
	oldAdornos:Destroy()
end
local oldColumns = nave:FindFirstChild("Colunas do Salão")
if oldColumns then
	oldColumns:Destroy()
end

-- ------------------------------------------------------------------ colunas

local columnsFolder = Instance.new("Folder")
columnsFolder.Name = "Colunas do Salão"
columnsFolder.Parent = nave

local function buildColumn(name: string, x: number, z: number)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = columnsFolder -- já no workspace: o raio dos losangos precisa da colisão do fuste
	local yaw = rng:NextNumber(0, math.pi * 2)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local shaft = piece(`Fuste_{rng:NextInteger(1, 3)}`, base, model, "Fuste")
	shaft.CanCollide = true
	shaft.CollisionFidelity = Enum.CollisionFidelity.Hull
	model.PrimaryPart = shaft

	for _, y in BANDS_Y do
		local band = piece(
			`FaixaDourada_{rng:NextInteger(1, 2)}`,
			CFrame.new(x, y, z)
				* CFrame.Angles(
					rng:NextNumber(-0.012, 0.012),
					rng:NextNumber(0, math.pi * 2),
					rng:NextNumber(-0.012, 0.012)
				),
			model,
			"Faixa Dourada"
		)
		band.Material = Enum.Material.Metal
		band.Color = GOLD
		band.CanCollide = false
	end

	local capital = piece(
		`Capitel_{rng:NextInteger(1, 3)}`,
		CFrame.new(x, CAPITAL_Y, z) * CFrame.Angles(0, rng:NextNumber(-0.08, 0.08), 0),
		model,
		"Capitel"
	)
	capital.Color = STONE_DARK
	local abacus = piece(
		`Abaco_{rng:NextInteger(1, 3)}`,
		CFrame.new(x, ABACUS_Y, z)
			* CFrame.Angles(rng:NextNumber(-0.015, 0.015), rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.015, 0.015)),
		model,
		"Ábaco"
	)
	abacus.Color = STONE_DARK

	-- Losangos de cristal virados para a avenida, encostados na superfície real do fuste (raio de cima para o eixo)
	local inward = if x < 0 then 1 else -1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shaft }
	for _, y in DIAMONDS_Y do
		local from = Vector3.new(x + inward * 10, y, z)
		local hit = workspace:Raycast(from, Vector3.new(-inward * 10, 0, 0), params)
		local surface = if hit then hit.Position.X else x + inward * 6
		local diamond = Instance.new("Part")
		diamond.Name = "Losango de Cristal"
		diamond.Size = Vector3.new(0.8, 2.8, 2.8)
		diamond.CFrame = CFrame.new(surface - inward * 0.05, y, z) * CFrame.Angles(math.rad(45), 0, 0)
		diamond.Material = Enum.Material.Neon
		diamond.Color = Color3.fromRGB(105, 45, 190)
		diamond.Transparency = 0.25
		diamond.Anchored = true
		diamond.CanCollide = false
		diamond.CastShadow = false
		diamond.Parent = model
	end

	-- Base: rocha de verdade (Stone_1 do pacote, achatada e larga) com o fuste "engolido" + 2 pedras menores no pé,
	-- do lado de fora e nas laterais (nunca no lado da avenida)
	local baseFolder = Instance.new("Model")
	baseFolder.Name = "Base de Rocha"
	local main = stoneByName("Stone_1_Low", 0)
	local w = rng:NextNumber(18, 20.5)
	local h = rng:NextNumber(7, 8.5)
	packStone(
		main,
		Vector3.new(w, h, w * rng:NextNumber(0.92, 1.05)),
		CFrame.new(x, h / 2 - 1.1, z)
			* CFrame.Angles(rng:NextNumber(-0.05, 0.05), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.05, 0.05)),
		baseFolder
	)
	local small = { stoneByName("Stone_2_Low", 0), stoneByName("Stone_3_Low", 0), stoneByName("Stone_5_Low", 0) }
	local outward = -inward
	for n = 1, 2 do
		local source = small[rng:NextInteger(1, #small)]
		local k = rng:NextNumber(4.5, 6.5) / math.max(source.Size.X, source.Size.Z)
		local size = source.Size * k
		local angle = (if n == 1 then 0 else math.pi) + rng:NextNumber(-0.9, 0.9) -- ±z, puxado para fora
		local dx = math.abs(math.sin(angle)) * outward * rng:NextNumber(0.4, 1)
		local dz = math.cos(angle)
		local dir = Vector3.new(dx, 0, dz).Unit
		local pos = Vector3.new(x, size.Y * 0.3 - 0.4, z) + dir * rng:NextNumber(8.5, 10)
		packStone(
			source,
			size,
			CFrame.new(pos)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.3, 0.3)),
			baseFolder
		)
	end
	baseFolder.Parent = model
end

for _, side in { { "O", -30 }, { "L", 30 } } do
	for i, z in COLUMN_Z do
		buildColumn(`Coluna do Salão {side[1]}{i}`, side[2] :: number, z)
		task.wait()
	end
end

-- ------------------------------------------------------------------ arcos (vigas entre as colunas)

for _, child in nave:GetChildren() do
	-- só as Parts lisas antigas: na segunda rodada os arcos já são MeshParts e ficam como estão
	if string.match(child.Name, "^Arco d") and child:IsA("Part") then
		local cf = child.CFrame
		local name = child.Name
		child:Destroy()
		local arch = piece(
			`Arco_{rng:NextInteger(1, 3)}`,
			cf * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0),
			nave,
			name
		)
		arch.Color = STONE_DARK
		arch.CanCollide = true
		arch.CollisionFidelity = Enum.CollisionFidelity.Box
	end
end

-- ------------------------------------------------------------------ altar

for _, child in altar:GetChildren() do
	if
		child:IsA("BasePart") and (string.match(child.Name, "^Degrau do Altar") or child.Name == "Plataforma do Altar")
	then
		child.Transparency = 1 -- fica só como colisão (pisável e reto; a pedra por cima é só visual)
		child.CastShadow = false
	end
end
local oldStones = altar:FindFirstChild("Pedras do Altar")
if oldStones then
	oldStones:Destroy()
end
local altarStones = Instance.new("Folder")
altarStones.Name = "Pedras do Altar"
local stair = piece("Escadaria_1", CFrame.new(), altarStones, "Degraus de Pedra")
local platform = piece("PlataformaDoAltar_1", CFrame.new(), altarStones, "Lajes da Plataforma")
for _, p in { stair, platform } do
	p.Color = STONE_DARK
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end
altarStones.Parent = altar

return `colunas: {#columnsFolder:GetChildren()}, arcos ok, altar ok`
