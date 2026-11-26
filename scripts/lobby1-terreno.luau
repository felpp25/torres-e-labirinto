--!strict
-- Gerador do Terrain do Lobby 1 (Abismo de Áuren), Fase 2 do BRIEFING-LOBBY1.md. NÃO faz parte do jogo: o Terrain
-- vive só no place (versões do place = backup). Rode no datamodel Edit (MCP execute_luau ou barra de comando do
-- Studio) para refazer ou ajustar a caverna. ATENÇÃO: reescreve TODO o Terrain das regiões abaixo (qualquer edição
-- manual de Terrain ali se perde) e refaz os rochedos (FillBall).
-- Depois de rodar, rode de novo o lobby1-entradas.luau: ele escava o túnel da Fenda e o corredor do Vigia do Sol.
--
-- Eixos (iguais ao blockout e ao LobbyService): cruzamento das torres na origem, spawn ao sul (+Z), Altar do Coração ao
-- norte (-Z), Torre 1 a oeste (-X), Torre 2 a leste (+X). Chão da caverna em y = 0.
--
-- Regras medidas no Studio (não óbvias):
-- - Sólido: a superfície fica em (centro da célula + ocupação × 4) na direção do ar. Para a superfície na distância d
--   do centro, ocupação = d / 4. (Com d / 4 + 0,5 tudo sai 2 studs para dentro do ar.)
-- - Água: a ocupação é o NÍVEL dentro da célula: ocupação = (nível - centro) / 4 + 0,5.
-- - WriteVoxels com região fora da grade de 4 studs NÃO lança erro: registra no console e não grava nada.

local Terrain = workspace.Terrain
local RES = 4
local SEED = 1717
local abs, max, min, sqrt, noise, clamp = math.abs, math.max, math.min, math.sqrt, math.noise, math.clamp
local AIR, ROCK, BASALT, SLATE, WATER =
	Enum.Material.Air, Enum.Material.Rock, Enum.Material.Basalt, Enum.Material.Slate, Enum.Material.Water
local GROUND, MUD, GRASS, LEAFY = Enum.Material.Ground, Enum.Material.Mud, Enum.Material.Grass, Enum.Material.LeafyGrass

local WALL = 292 -- meia-largura da caverna (paredes com ruído de ±10; com a espessura, ~600 × 600)
local SHAFT_X, SHAFT_Z = 0, -106 -- poço acima do Coração do Abismo (o feixe entra por ele)
local LAKE_X, LAKE_Z, LAKE_RX, LAKE_RZ = 150, -185, 50, 52 -- Lago Espelhado
local WATER_LEVEL = -0.5

-- Cores tiradas da paleta das referências 06 e 07 (método do vídeo "Environmental Art", do BONES): na imagem a rocha é
-- um cinza-violeta pouco saturado (~71/70/81 a 104/105/132) e o chão uma terra amarronzada (~68/46/41 a 111/71/54).
-- A textura do Terrain multiplica a cor e a caverna é escura, então a cor do material é mais clara que a percebida.
-- (Com #4A4462/#2E2A3D, as "cores fixas" ao pé da letra, a rocha virava um borrão escuro e fosco.)
-- As texturas vêm dos materiais PBR estilizados do pacote do vídeo (MaterialService > BonesStylizedPBR2, asset
-- 73133614571227), aplicados como override: Rock = Ground_06, Basalt = Lobby1_Basalto, Ground = Lobby1_Terra,
-- Mud = Ground, Grass = Grass, LeafyGrass = Grass2. Com textura própria, a cor do material só tinge: tons claros.
Terrain:SetMaterialColor(ROCK, Color3.fromRGB(225, 218, 240))
Terrain:SetMaterialColor(BASALT, Color3.fromRGB(195, 188, 215))
Terrain:SetMaterialColor(SLATE, Color3.fromRGB(110, 102, 122))
Terrain:SetMaterialColor(GROUND, Color3.fromRGB(225, 205, 190))
Terrain:SetMaterialColor(MUD, Color3.fromRGB(205, 192, 182))
-- Musgo (Musgo-Lume): Grass tem as folhinhas animadas (Decoration)
Terrain:SetMaterialColor(GRASS, Color3.fromRGB(150, 205, 150))
Terrain:SetMaterialColor(LEAFY, Color3.fromRGB(130, 180, 130))
Terrain.Decoration = true
-- Lago Espelhado: água parada e refletindo
Terrain.WaterColor = Color3.fromRGB(28, 30, 48)
Terrain.WaterReflectance = 1
Terrain.WaterTransparency = 0.25
Terrain.WaterWaveSize = 0
Terrain.WaterWaveSpeed = 0

local function n2(a: number, b: number, f: number): number
	return noise(a * f + 11.3, b * f - 7.1, SEED * 0.013)
end

local function n3(a: number, b: number, c: number, f: number): number
	return noise(a * f + 3.7, b * f + 5.9, c * f - 2.3)
end

-- "Raio" de quadrado arredondado: a planta da caverna
local function roundedRadius(x: number, z: number): number
	local ax, az = abs(x), abs(z)
	return (ax ^ 6 + az ^ 6) ^ (1 / 6)
end

-- Poço: ar dentro do cilindro irregular de y 100 a 298 (tampa de rocha acima, com a "Luz do Poço" embaixo dela)
local function carveShaft(x: number, y: number, z: number, d: number): number
	if y > 96 then
		local dist = sqrt((x - SHAFT_X) ^ 2 + (z - SHAFT_Z) ^ 2)
		local radius = 20 - (y - 140) * 0.04 + n3(x, y, z, 1 / 10) * 3
		local inside = min(radius - dist, 298 - y, y - 100)
		if -inside < d then
			d = -inside
		end
	end
	return d
end

-- Rótulos de onde cada voxel veio (escolhe o material)
local FLOOR, CEILING, WALLS, LEDGE, RIDGE, RAMP, MOUND = 1, 2, 3, 4, 5, 6, 7

-- Distância "para dentro da rocha" (positiva = rocha), de onde ela veio e se o ponto está na bacia do lago
local function sample(x: number, y: number, z: number): (number, number, boolean)
	local r = roundedRadius(x, z)
	local s = min(r / WALL, 1)
	local ax, az = abs(x), abs(z)

	-- chão: plano em y = 0, subindo irregular perto das paredes; um pouco abaixo das lajes do Piso de Áuren
	local floorHeight = 0
	if s > 0.8 then
		local t = (s - 0.8) / 0.2
		floorHeight = t * t * (10 + n2(x, z, 1 / 18) * 10)
	end
	if ax < 28 and z > -80 and z < 112 then
		floorHeight = -0.6
	end
	local d, label = floorHeight - y, FLOOR

	-- teto: ~150 no centro, ~120 nas paredes
	local ceiling = 150 - 30 * s * s + n2(x, z, 1 / 30) * 12 + n2(x, z, 1 / 9) * 4
	local v = y - ceiling
	if v > d then
		d, label = v, CEILING
	end

	-- paredes: inclinam para dentro acima de y = 60
	local wall = WALL - max(0, y - 60) * 0.45 + n3(x, y, z, 1 / 40) * 16 + n3(x, y, z, 1 / 12) * 5
	v = r - wall
	if v > d then
		d, label = v, WALLS
	end

	-- saliências das Galerias Altas (oeste, leste e cantos do norte): topo plano em y = 36
	if ax > 200 then
		v = min(ax - (240 + n2(z, y, 1 / 14) * 6), 36 - y, 272 - az)
		if v > d then
			d, label = v, LEDGE
		end
	end
	if z < -200 then
		v = min(-z - (240 + n2(x, y, 1 / 14) * 6), 36 - y, ax - (80 + n2(z, y, 1 / 10) * 3))
		if v > d then
			d, label = v, LEDGE
		end
	end

	-- rampas de rocha até as saliências (a partir do Acampamento e do Mercado)
	if ax > 140 and z > 230 then
		local top = min(36, 36 * (ax - 150) / 90)
		v = min(top - y, z - 246)
		if v > d then
			d, label = v, RAMP
		end
	end

	-- rochedos das torres: separam Acampamento/Arquivo (oeste) e Mercado/Lago (leste); face plana em |x| = 62 onde
	-- ficam a Entrada (Torre 1) e o Vigia do Sol (Torre 2)
	if ax > 50 and ax < 240 and az < 70 then
		local gate = az < 16 and y < 38
		local face = if gate then 0 else (n2(z, y, 1 / 10) + 0.5) * 6
		local top = 50 + n2(x, z, 1 / 25) * 18 - (az / 40) ^ 2 * 14
		v = min(ax - (62 + face), 205 + n2(z, y, 1 / 20) * 10 - ax, 40 + n2(x, y, 1 / 15) * 10 - az, top - y)
		if v > d then
			d, label = v, RIDGE
		end
	end

	-- monte atrás do altar (fundo escuro para o cristal)
	if z < -110 and z > -260 and ax < 100 then
		local e = sqrt((x / 70) ^ 2 + ((y + 10) / 45) ^ 2 + ((z + 180) / 50) ^ 2)
		v = (1 - e) * 40 + n3(x, y, z, 1 / 14) * 6
		if v > d then
			d, label = v, MOUND
		end
	end

	d = carveShaft(x, y, z, d)

	-- bacia do Lago Espelhado (até 11 de fundo)
	local inLake = false
	local ex, ez = (x - LAKE_X) / LAKE_RX, (z - LAKE_Z) / LAKE_RZ
	local e2 = ex * ex + ez * ez
	if e2 < 1.3 then
		local depth = 11 * (1 - e2)
		local basin = min((1 - sqrt(e2)) * 50, y + depth, 6 - y)
		if -basin < d then
			d = -basin
		end
		inLake = e2 < 1
	end
	return d, label, inLake
end

-- Chance de musgo num chão (0 a 1): onde faz sentido haver umidade e raízes
local function mossChance(label: number, x: number, z: number): number
	local c = 0.06
	local s = min(roundedRadius(x, z) / WALL, 1)
	if s > 0.7 then
		c += (s - 0.7) / 0.3 * 0.3 -- junto às paredes
	end
	if x > 65 and x < 220 and z > 80 and z < 225 then
		c += 0.55 -- Mercado das Raízes
	end
	local ex, ez = (x - LAKE_X) / LAKE_RX, (z - LAKE_Z) / LAKE_RZ
	local e2 = ex * ex + ez * ez
	if e2 < 2.4 then
		c += 0.6 * (1 - max(0, e2 - 1) / 1.4) -- beira do Lago Espelhado
	end
	if label == LEDGE then
		c += 0.35 -- topo das saliências das Galerias Altas
	elseif label == RIDGE or label == MOUND then
		c += 0.5 -- topo dos rochedos das torres e do monte do altar
	end
	return clamp(c, 0, 0.9)
end

-- Pintura por inclinação (como no vídeo): superfície virada para cima é chão (terra, com manchas de musgo e lama
-- perto da água); o resto (paredes, teto, laterais) é rocha
local function materialFor(label: number, x: number, y: number, z: number, isTop: boolean): Enum.Material
	local m = n3(x, y, z, 1 / 22)
	if isTop and label ~= CEILING then
		if abs(x) < 28 and z > -80 and z < 112 then
			return SLATE -- sob as lajes do Piso de Áuren
		end
		local patch = n2(x, z, 1 / 26) + 0.5 -- ~0 a 1, manchas de uns 20 studs
		if patch < mossChance(label, x, z) then
			return if n2(z, x, 1 / 11) > 0.1 then LEAFY else GRASS
		end
		local ex, ez = (x - LAKE_X) / LAKE_RX, (z - LAKE_Z) / LAKE_RZ
		if ex * ex + ez * ez < 1.6 then
			return MUD
		end
		return if m > 0.3 then MUD else GROUND
	end
	if label == CEILING then
		return if m > 0 then BASALT else ROCK
	end
	return if m > 0.22 then BASALT else ROCK
end

type VoxelFn = (x: number, y: number, z: number) -> (Enum.Material, number)

-- Escreve a região em fatias de 16 células em X (cada fatia cede o thread: o Studio não congela)
local function writeRegion(lo: Vector3, hi: Vector3, fn: VoxelFn)
	for _, value in { lo.X, lo.Y, lo.Z, hi.X, hi.Y, hi.Z } do
		assert(value % RES == 0, "região fora da grade de 4 studs (o WriteVoxels ignoraria sem erro)")
	end
	local nx, ny, nz = (hi.X - lo.X) // RES, (hi.Y - lo.Y) // RES, (hi.Z - lo.Z) // RES
	local slice = 16
	for x0 = 0, nx - 1, slice do
		local count = min(slice, nx - x0)
		local materials: { { { Enum.Material } } } = table.create(count)
		local occupancies: { { { number } } } = table.create(count)
		for i = 1, count do
			local x = lo.X + (x0 + i - 1) * RES + RES / 2
			local mx: { { Enum.Material } } = table.create(ny)
			local ox: { { number } } = table.create(ny)
			for j = 1, ny do
				local y = lo.Y + (j - 1) * RES + RES / 2
				local my: { Enum.Material } = table.create(nz)
				local oy: { number } = table.create(nz)
				for k = 1, nz do
					local z = lo.Z + (k - 1) * RES + RES / 2
					my[k], oy[k] = fn(x, y, z)
				end
				mx[j], ox[j] = my, oy
			end
			materials[i], occupancies[i] = mx, ox
		end
		local region =
			Region3.new(Vector3.new(lo.X + x0 * RES, lo.Y, lo.Z), Vector3.new(lo.X + (x0 + count) * RES, hi.Y, hi.Z))
		Terrain:WriteVoxels(region, RES, materials, occupancies)
		task.wait()
	end
end

-- 1) casca da caverna
writeRegion(Vector3.new(-344, -24, -344), Vector3.new(344, 184, 344), function(x: number, y: number, z: number)
	local d, label, inLake = sample(x, y, z)
	local occupancy = clamp(d / RES, 0, 1)
	if inLake and occupancy < 0.5 then
		local level = clamp((WATER_LEVEL - y) / RES + 0.5, 0, 1)
		if level > 0 then
			return WATER, level
		end
	end
	if occupancy > 0 then
		local above = sample(x, y + RES, z) -- célula de cima vazia = superfície virada para cima
		return materialFor(label, x, y, z, above < 1), occupancy
	end
	return AIR, 0
end)

-- 2) tubo de rocha do poço, acima da casca (o poço é falso: termina numa tampa a y = 298)
writeRegion(Vector3.new(-48, 184, -156), Vector3.new(48, 320, -56), function(x: number, y: number, z: number)
	local dist = sqrt((x - SHAFT_X) ^ 2 + (z - SHAFT_Z) ^ 2)
	local d = carveShaft(x, y, z, min(40 + n3(x, y, z, 1 / 12) * 6 - dist, 318 - y))
	local occupancy = clamp(d / RES, 0, 1)
	if occupancy > 0 then
		return if n3(x, y, z, 1 / 22) > 0 then BASALT else ROCK, occupancy
	end
	return AIR, 0
end)

-- 3) rochedos grandes separando as áreas (centro x, centro z, raio)
local rng = Random.new(SEED)
local BOULDER_MATERIALS = { ROCK, BASALT, BASALT, SLATE }
local BOULDERS = {
	-- faixa sul, atrás do Marco dos Recordes (entre Acampamento e Mercado)
	{ -38, 165, 14 },
	{ 42, 180, 16 },
	{ -8, 232, 18 },
	{ -62, 238, 12 },
	{ 66, 246, 13 },
	-- lado de fora dos vãos entre os rochedos das torres e as áreas (longe da nave e da área de treino)
	{ -182, 62, 12 },
	{ -168, -62, 13 },
	{ 176, 64, 12 },
	{ 182, -62, 13 },
	-- pé do monte atrás do altar
	{ -58, -150, 11 },
	{ 60, -156, 12 },
}
for _, boulder in BOULDERS do
	local cx, cz, radius = boulder[1], boulder[2], boulder[3]
	local function pick(): Enum.Material
		return BOULDER_MATERIALS[rng:NextInteger(1, #BOULDER_MATERIALS)]
	end
	Terrain:FillBall(Vector3.new(cx, -radius * 0.25, cz), radius, pick())
	for _ = 1, 2 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local small = radius * rng:NextNumber(0.45, 0.65)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * rng:NextNumber(0.6, 0.9)
		Terrain:FillBall(Vector3.new(cx, -small * 0.2, cz) + offset, small, pick())
	end
end

print("[Lobby1] Terrain gerado")
