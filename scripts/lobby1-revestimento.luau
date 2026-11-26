--!strict
-- Revestimento do Lobby 1 com o pacote do vídeo "Environmental Art" (BONES): rochas grandes no pé das paredes e dos
-- barrancos e plantas em grupos no musgo e ao pé das rochas. NÃO faz parte do jogo: rode no datamodel Edit (MCP
-- execute_luau) DEPOIS do Terrain (lobby1-terreno.luau), das formações (lobby1-formacoes.luau) e das peças de pedra
-- (lobby1-pedras.luau). Refaz tudo dentro de Lobby1/Formacoes/Pedras das Paredes e Lobby1/Terreno/Plantas.
--
-- Técnica do vídeo: pedras GRANDES, em camadas (uma menor na frente, às vezes outra por cima), giradas e inclinadas,
-- sem repetir a mesma malha lado a lado e enterradas no chão e na parede; plantas sempre em grupos.
--
-- Onde: raios a partir do chão (só Terrain) acham paredes (normal quase horizontal); pontos perto de funções do jogo
-- (spawn, portais, loja, forja, NPCs, treino, avenida, altar) e de qualquer peça montada (casas, luzes, torres...)
-- ficam livres (consulta de espaço antes de cada pedra/planta).
--
-- Plantas: as MeshParts "Plant" do pacote vêm sem textura; o atlas delas é a imagem 17750471621 (a mesma que o
-- modelo de exemplo do pacote usa).

local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local SEED = 2626
local PLANT_ATLAS = "rbxassetid://17750471621"
local STONE_TINT = Color3.fromRGB(205, 196, 228) -- igual à base das colunas
local GRID = 7 -- passo da busca de chão (studs)
local LIMIT = 288
local MAX_STONES = 420
local MAX_PLANTS = 900

local lobby = workspace:FindFirstChild("Lobby1") :: Folder
assert(lobby, "falta Workspace.Lobby1")
local pack = ServerStorage:FindFirstChild("BonesStylizedPackAssets")
assert(pack, "falta ServerStorage.BonesStylizedPackAssets (pacote do vídeo)")
local terrain = workspace.Terrain
local rng = Random.new(SEED)

-- ------------------------------------------------------------------ pastas

local function remake(parentName: string, name: string): Folder
	local parent = lobby:FindFirstChild(parentName)
	assert(parent, parentName)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local stoneFolder = remake("Formacoes", "Pedras das Paredes")
local plantFolder = remake("Terreno", "Plantas")

-- ------------------------------------------------------------------ modelos do pacote

local stones: { MeshPart } = {}
local plants: { MeshPart } = {}
for _, child in pack:GetChildren() do
	if child:IsA("MeshPart") then
		if string.match(child.Name, "^Stone_%d") then
			table.insert(stones, child)
		elseif child.Name == "Plant" and child.Size.Y > 0.5 and math.min(child.Size.X, child.Size.Z) > 0.2 then
			table.insert(plants, child) -- fora os planos finos (folhas soltas de 0,001 de espessura)
		end
	end
end
assert(#stones >= 5 and #plants >= 10, "pacote incompleto")

-- ------------------------------------------------------------------ zonas livres

-- retângulos (x0, x1, z0, z1): avenida + colunas, altar, portões das torres, treino
local KEEP_RECTS = {
	{ -38, 38, -125, 115 },
	{ -75, -50, -22, 22 },
	{ 50, 75, -22, 22 },
	{ -158, -72, 40, 84 },
}
-- círculos (x, z, raio): portais, loja, forja, NPCs fora da avenida
local KEEP_CIRCLES = {
	{ -55, 0, 18 },
	{ 55, 0, 18 },
	{ 191, 144, 16 },
	{ 155, 191, 18 },
	{ 188.5, 157, 8 },
	{ 161.5, 189, 8 },
}

local function blocked(x: number, z: number): boolean
	for _, r in KEEP_RECTS do
		if x > r[1] and x < r[2] and z > r[3] and z < r[4] then
			return true
		end
	end
	for _, c in KEEP_CIRCLES do
		if (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < c[3] ^ 2 then
			return true
		end
	end
	return false
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { terrain }
terrainOnly.IgnoreWater = true

-- peças montadas (casas, luzes, torres, lobby funcional, formações...), menos o teto e o que este script cria
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local ignore: { Instance } = { terrain, stoneFolder, plantFolder }
local efeitos = lobby:FindFirstChild("Efeitos")
if efeitos then
	table.insert(ignore, efeitos)
end
overlap.FilterDescendantsInstances = ignore

local function crowded(pos: Vector3, radius: number): boolean
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		-- Presas do Teto e luzes altas não contam (bem acima do chão)
		if part.Position.Y - pos.Y < 25 then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ 1) chão

type Floor = { pos: Vector3, normal: Vector3, material: Enum.Material }
local floors: { Floor } = {}
for gx = -LIMIT, LIMIT, GRID do
	for gz = -LIMIT, LIMIT, GRID do
		local x = gx + rng:NextNumber(-GRID * 0.4, GRID * 0.4)
		local z = gz + rng:NextNumber(-GRID * 0.4, GRID * 0.4)
		if not blocked(x, z) then
			local hit = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -100, 0), terrainOnly)
			if hit and hit.Normal.Y > 0.6 and hit.Position.Y > -1 then
				-- teto livre acima (um raio que nasce dentro da rocha "acha" chão falso: aqui ele bate logo acima)
				local up = workspace:Raycast(hit.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, 7, 0), terrainOnly)
				if not up then
					table.insert(floors, { pos = hit.Position, normal = hit.Normal, material = hit.Material })
				end
			end
		end
	end
	task.wait()
end
-- embaralha (com a semente): com o limite de pedras, a ordem da grade encheria só o lado oeste
for i = #floors, 2, -1 do
	local j = rng:NextInteger(1, i)
	floors[i], floors[j] = floors[j], floors[i]
end

-- ------------------------------------------------------------------ 2) pedras no pé das paredes

type Placed = { pos: Vector3, mesh: string, radius: number }
local placed: { Placed } = {}

local function nearPlaced(pos: Vector3, dist: number): boolean
	for _, p in placed do
		if (p.pos - pos).Magnitude < dist then
			return true
		end
	end
	return false
end

-- malha diferente das vizinhas (o vídeo: não repetir a mesma pedra lado a lado)
local function pickStone(pos: Vector3): MeshPart
	local avoid: { [string]: boolean } = {}
	for _, p in placed do
		if (p.pos - pos).Magnitude < 22 then
			avoid[p.mesh] = true
		end
	end
	local options: { MeshPart } = {}
	for _, s in stones do
		if not avoid[s.MeshId] then
			table.insert(options, s)
		end
	end
	if #options == 0 then
		options = stones
	end
	return options[rng:NextInteger(1, #options)]
end

local function addStone(source: MeshPart, size: Vector3, cf: CFrame): MeshPart
	local s = source:Clone()
	s.Size = size
	s.CFrame = cf
	s.Anchored = true
	s.CanCollide = true
	s.CanTouch = false
	local sa = s:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		sa.Color = STONE_TINT:Lerp(Color3.fromRGB(175, 166, 202), rng:NextNumber(0, 0.6))
	end
	s.Parent = stoneFolder
	table.insert(placed, { pos = cf.Position, mesh = source.MeshId, radius = math.max(size.X, size.Z) / 2 })
	return s
end

local function randomTilt(amount: number): CFrame
	return CFrame.Angles(
		rng:NextNumber(-amount, amount),
		rng:NextNumber(0, math.pi * 2),
		rng:NextNumber(-amount, amount)
	)
end

local DIRS = 8
local stoneCount = 0
for i, f in floors do
	if stoneCount >= MAX_STONES then
		break
	end
	local origin = f.pos + Vector3.new(0, 2.5, 0)
	local a0 = rng:NextNumber(0, math.pi * 2)
	for d = 0, DIRS - 1 do
		local a = a0 + d * math.pi * 2 / DIRS
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local hit = workspace:Raycast(origin, dir * 16, terrainOnly)
		if hit and math.abs(hit.Normal.Y) < 0.55 then
			local wallPos = hit.Position
			if not blocked(wallPos.X, wallPos.Z) and not nearPlaced(wallPos, 12) then
				local source = pickStone(wallPos)
				local r = math.sqrt(wallPos.X ^ 2 + wallPos.Z ^ 2)
				local big = r > 230 or f.pos.Y > 8 -- paredes da caverna e saliências: pedras maiores
				-- medido na 1ª rodada: 11–20 / 7–13 ficavam pequenas perto do barranco (pareciam seixos)
				local target = if big then rng:NextNumber(18, 32) else rng:NextNumber(10, 18)
				local k = target / math.max(source.Size.X, source.Size.Y, source.Size.Z)
				local size = source.Size
					* k
					* Vector3.new(rng:NextNumber(0.9, 1.2), rng:NextNumber(0.85, 1.1), rng:NextNumber(0.9, 1.2))
				local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
				local half = (size.X + size.Z) / 4
				-- enterrada: ~35% na parede e ~25% no chão
				local pos = Vector3.new(wallPos.X, f.pos.Y + size.Y * 0.25, wallPos.Z) - n * half * 0.35
				if not crowded(pos + n * half * 0.5, half * 0.7) then
					addStone(source, size, CFrame.new(pos) * randomTilt(0.35))
					stoneCount += 1
					-- camada: uma pedra menor na frente (às vezes) e outra por cima, encostada na parede
					if rng:NextNumber() < 0.4 then
						local s2 = pickStone(pos)
						local k2 = target * rng:NextNumber(0.35, 0.55) / math.max(s2.Size.X, s2.Size.Y, s2.Size.Z)
						local size2 = s2.Size * k2
						local side = n:Cross(Vector3.yAxis) * rng:NextNumber(-half * 0.6, half * 0.6)
						local pos2 = Vector3.new(pos.X, f.pos.Y + size2.Y * 0.2, pos.Z) + n * half * 0.85 + side
						if not crowded(pos2, math.max(size2.X, size2.Z) * 0.4) then
							addStone(s2, size2, CFrame.new(pos2) * randomTilt(0.45))
							stoneCount += 1
						end
					end
					if big and rng:NextNumber() < 0.3 then
						local s3 = pickStone(pos)
						local k3 = target * rng:NextNumber(0.5, 0.75) / math.max(s3.Size.X, s3.Size.Y, s3.Size.Z)
						local size3 = s3.Size * k3
						local pos3 = pos + Vector3.new(0, size.Y * 0.55, 0) - n * half * 0.25
						addStone(s3, size3, CFrame.new(pos3) * randomTilt(0.5))
						stoneCount += 1
					end
				end
			end
		end
	end
	if i % 60 == 0 then
		task.wait()
	end
end

-- ------------------------------------------------------------------ 3) plantas em grupos

local plantCount = 0
local function addCluster(center: Vector3, count: number, radius: number)
	for _ = 1, count do
		if plantCount >= MAX_PLANTS then
			return
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = radius * math.sqrt(rng:NextNumber())
		local x, z = center.X + math.cos(a) * d, center.Z + math.sin(a) * d
		local hit = workspace:Raycast(Vector3.new(x, center.Y + 6, z), Vector3.new(0, -12, 0), terrainOnly)
		if hit and hit.Normal.Y > 0.55 and not blocked(x, z) then
			local source = plants[rng:NextInteger(1, #plants)]
			local size = source.Size * rng:NextNumber(1.1, 2.1) -- com 0,8–1,6 sumiam (o avatar tem 5 studs)
			local pos = hit.Position + Vector3.new(0, size.Y / 2 - 0.15, 0)
			if not crowded(pos, 0.6) then
				local p = source:Clone()
				p.TextureID = PLANT_ATLAS
				p.Size = size
				-- em pé, levemente inclinada para o lado da encosta
				local axis = Vector3.new(0, 1, 0):Cross(hit.Normal)
				local tilt = if axis.Magnitude > 0.01
					then CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(hit.Normal.Y, -1, 1)) * 0.5)
					else CFrame.identity
				p.CFrame = CFrame.new(pos) * tilt * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Parent = plantFolder
				plantCount += 1
			end
		end
	end
end

for i, f in floors do
	local moss = f.material == Enum.Material.Grass or f.material == Enum.Material.LeafyGrass
	local byStone = nearPlaced(f.pos, 9)
	local chance = (if moss then 0.45 else 0) + (if byStone then 0.3 else 0)
	if chance > 0 and rng:NextNumber() < chance then
		addCluster(f.pos, rng:NextInteger(3, 7), rng:NextNumber(2, 4))
	end
	if i % 120 == 0 then
		task.wait()
	end
end

return `chão: {#floors} pontos; pedras: {stoneCount}; plantas: {plantCount}`
