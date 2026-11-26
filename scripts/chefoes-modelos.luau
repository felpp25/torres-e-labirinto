--!strict
-- Monta os MODELOS dos chefões em ServerStorage.ChefoesModelos.<bossId> (Balance/Bosses). NÃO faz parte do jogo: rode
-- no datamodel Edit (MCP execute_luau). O chefão em si continua sendo criado pelo jogo (server/Services/BossService):
-- ele veste o corpo de colisão (caixa invisível) com este modelo; sem modelo, fica o greybox.
--
-- Origem: o designer gerou os dois no Tripo (lobby1-claude-code/Tripo/Bosses/); no Blender
-- (scripts/blender/chefoes_tripo.py) o Golem perdeu as partes geradas erradas (golem pequeno, pedestal, placas e cacos
-- voando), ficou de frente (vinha girado 45°) e foi cortado em PEDAÇOS DE PEDRA com bolas de lava nas juntas (decisão
-- do designer: animação por código, sem esqueleto); o Kokuryū é uma peça só. Arquivos em
-- lobby1-claude-code/modelos/chefoes/.
--
-- Cada peça do modelo leva dois Attributes, que o BossService usa para prender as peças com Motor6D e o cliente
-- (client/Controllers/BossVisualController) para animar:
-- - Pai: nome da peça onde ela se prende ("" = o corpo do chefão);
-- - Junta: o ponto em volta do qual ela gira, no espaço do modelo.
--
-- Coordenadas do modelo: origem no chão, no centro; frente = -z. O importador do Roblox gira a malha 180° em Y (ver
-- lobby1-pedras): com a rotação zero a frente do glTF (+z) fica em -z, e o centro da malha (x, y, z) do glTF vai para
-- (-x, y, -z). Uma junta do Blender (x, y, z) fica em (-x, z, y).

local InsertService: InsertService = game:GetService("InsertService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

-- juntas do Golem no Blender (chefoes_tripo.JUNTAS), convertidas para o Roblox
local function blender(x: number, y: number, z: number): Vector3
	return Vector3.new(-x, z, y)
end
local J = {
	Pelvis = blender(-0.15, 0.0, 4.2),
	Pescoco = blender(-0.2, 0.0, 9.2),
	OmbroD = blender(-2.7, 0.1, 8.1),
	CotoveloD = blender(-3.9, 0.1, 6.3),
	OmbroE = blender(2.2, 0.1, 8.0),
	CotoveloE = blender(3.0, 0.2, 6.6),
	QuadrilD = blender(-1.9, 0.0, 3.8),
	JoelhoD = blender(-2.0, 0.0, 2.0),
	QuadrilE = blender(1.6, 0.0, 3.8),
	JoelhoE = blender(1.8, 0.0, 2.0),
}

-- peça: malha no asset, centro dela no glTF (o export devolve), pai, junta
type Piece = { mesh: string, center: Vector3, parent: string, joint: Vector3, lava: boolean? }
type Spec = { bossId: string, asset: number, yaw: number, pieces: { [string]: Piece } }

-- Neon (mais claro estoura em branco com o Bloom). Na luz de dia da torre, as bolas no tamanho do Blender e com
-- 230, 90, 30 pareciam adesivos laranja saindo do corpo: ficam menores e mais escuras aqui (o Blender guarda o raio cheio)
local LAVA_COLOR = Color3.fromRGB(190, 65, 20)
local LAVA_SCALE = 0.7

local SPECS: { Spec } = {
	-- Golem de Obsidiana e Magma (Torre 1) COM ESQUELETO: o designer gerou de novo no Tripo com rig Mixamo; no Blender
	-- (chefoes_tripo.preparar_golem_rig) foi para 11 studs e 9.800 triângulos. Uma peça só, com os ossos (Bones)
	-- dentro; o cliente anima os ossos (BossVisualController).
	{
		bossId = "TowerGuardian",
		asset = 93271892979410,
		yaw = 0,
		pieces = {
			Corpo = { mesh = "GolemRig", center = Vector3.new(0, 5.503, 0), parent = "", joint = Vector3.zero },
		},
	},
	-- Reserva (o jogo não usa): o Golem em pedaços de pedra com juntas de lava, de antes do esqueleto. Para voltar a
	-- ele, troque o bossId para "TowerGuardian" (e o de cima para outro nome).
	{
		bossId = "TowerGuardian_Pedacos",
		asset = 106231545121719,
		yaw = 0,
		pieces = {
			Tronco = {
				mesh = "GolemTronco",
				center = Vector3.new(-0.234, 6.023, -0.161),
				parent = "",
				joint = J.Pelvis,
			},
			Cabeca = {
				mesh = "GolemCabeca",
				center = Vector3.new(-0.343, 9.971, -0.112),
				parent = "Tronco",
				joint = J.Pescoco,
			},
			BracoD = {
				mesh = "GolemBracoD",
				center = Vector3.new(-3.081, 7.757, -0.331),
				parent = "Tronco",
				joint = J.OmbroD,
			},
			AntebracoD = {
				mesh = "GolemAntebracoD",
				center = Vector3.new(-4.017, 5.447, -0.031),
				parent = "BracoD",
				joint = J.CotoveloD,
			},
			BracoE = {
				mesh = "GolemBracoE",
				center = Vector3.new(2.349, 7.751, -0.32),
				parent = "Tronco",
				joint = J.OmbroE,
			},
			AntebracoE = {
				mesh = "GolemAntebracoE",
				center = Vector3.new(2.802, 6.026, 0.382),
				parent = "BracoE",
				joint = J.CotoveloE,
			},
			CoxaD = { mesh = "GolemCoxaD", center = Vector3.new(-2.125, 3.576, 0.18), parent = "", joint = J.QuadrilD },
			CanelaD = {
				mesh = "GolemCanelaD",
				center = Vector3.new(-2.634, 1.497, -0.045),
				parent = "CoxaD",
				joint = J.JoelhoD,
			},
			CoxaE = { mesh = "GolemCoxaE", center = Vector3.new(1.828, 3.585, 0.17), parent = "", joint = J.QuadrilE },
			CanelaE = {
				mesh = "GolemCanelaE",
				center = Vector3.new(2.204, 1.45, -0.287),
				parent = "CoxaE",
				joint = J.JoelhoE,
			},
			-- lava nas juntas, presa ao pedaço de cima (chefoes_tripo.LAVA)
			LavaPescoco = {
				mesh = "GolemLavaPescoco",
				center = Vector3.new(-0.201, 9.198, 0.003),
				parent = "Tronco",
				joint = J.Pescoco,
				lava = true,
			},
			LavaOmbroD = {
				mesh = "GolemLavaOmbroD",
				center = Vector3.new(-2.704, 8.119, -0.103),
				parent = "Tronco",
				joint = J.OmbroD,
				lava = true,
			},
			LavaOmbroE = {
				mesh = "GolemLavaOmbroE",
				center = Vector3.new(2.194, 7.997, -0.096),
				parent = "Tronco",
				joint = J.OmbroE,
				lava = true,
			},
			LavaCotoveloD = {
				mesh = "GolemLavaCotoveloD",
				center = Vector3.new(-3.903, 6.287, -0.082),
				parent = "BracoD",
				joint = J.CotoveloD,
				lava = true,
			},
			LavaCotoveloE = {
				mesh = "GolemLavaCotoveloE",
				center = Vector3.new(2.992, 6.601, -0.2),
				parent = "BracoE",
				joint = J.CotoveloE,
				lava = true,
			},
			LavaQuadrilD = {
				mesh = "GolemLavaQuadrilD",
				center = Vector3.new(-1.902, 3.841, 0.002),
				parent = "CoxaD",
				joint = J.QuadrilD,
				lava = true,
			},
			LavaQuadrilE = {
				mesh = "GolemLavaQuadrilE",
				center = Vector3.new(1.592, 3.79, -0.027),
				parent = "CoxaE",
				joint = J.QuadrilE,
				lava = true,
			},
			LavaJoelhoD = {
				mesh = "GolemLavaJoelhoD",
				center = Vector3.new(-1.994, 1.962, -0.015),
				parent = "CoxaD",
				joint = J.JoelhoD,
				lava = true,
			},
			LavaJoelhoE = {
				mesh = "GolemLavaJoelhoE",
				center = Vector3.new(1.813, 1.999, 0.019),
				parent = "CoxaE",
				joint = J.JoelhoE,
				lava = true,
			},
		},
	},
	-- Kokuryū (Torre 2): uma peça só, girando em volta dos pés. Gira 22,5°: com 0 a cabeça olha para o lado; com 45
	-- ela olha para a frente, mas o corpo enrolado fica de perfil e parece fino.
	{
		bossId = "Geomancer",
		asset = 119906539899630,
		yaw = 22.5,
		pieces = {
			Corpo = {
				mesh = "KokuryuTripo",
				center = Vector3.new(-0.475, 7.0, -0.145),
				parent = "",
				joint = Vector3.zero,
			},
		},
	},
}

local root = ServerStorage:FindFirstChild("ChefoesModelos")
if not root then
	root = Instance.new("Folder")
	root.Name = "ChefoesModelos"
	root.Parent = ServerStorage
end
assert(root, "sem ServerStorage.ChefoesModelos")

local done: { string } = {}
for _, spec in SPECS do
	local source = InsertService:LoadAsset(spec.asset)
	local turn = CFrame.Angles(0, math.rad(spec.yaw), 0)
	local model = Instance.new("Model")
	model.Name = spec.bossId
	local first: BasePart? = nil
	for name, piece in spec.pieces do
		local found = source:FindFirstChild(piece.mesh, true)
		assert(found and found:IsA("MeshPart"), `falta a malha {piece.mesh} no asset {spec.asset}`)
		local part = found:Clone()
		part.Name = name
		part.CFrame = turn * CFrame.new(-piece.center.X, piece.center.Y, -piece.center.Z)
		part.Anchored = true
		-- só aparência: a colisão, os golpes e os acertos são do corpo do código
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		if piece.lava then
			part.Size *= LAVA_SCALE
			part.Material = Enum.Material.Neon
			part.Color = LAVA_COLOR
			part.TextureID = ""
			part.CastShadow = false
		end
		part:SetAttribute("Pai", piece.parent)
		part:SetAttribute("Junta", (turn * CFrame.new(piece.joint)).Position)
		part.Parent = model
		if piece.parent == "" and not first then
			first = part
		end
	end
	source:Destroy()
	assert(first, `sem peça presa ao corpo em {spec.bossId}`)
	model.PrimaryPart = first
	-- pivô no chão, no centro (com PrimaryPart o pivô vem dela: ver lobby1-observador)
	first.PivotOffset = first.CFrame:Inverse()

	local old = root:FindFirstChild(spec.bossId)
	if old then
		old:Destroy()
	end
	model.Parent = root
	table.insert(done, `{spec.bossId}: {#model:GetChildren()} peças`)
end

return "Chefões prontos em ServerStorage.ChefoesModelos: " .. table.concat(done, "; ")
