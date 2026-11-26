--!strict
-- Monta o MODELO do Observador em ServerStorage.Lobby1Modelos.Observador. NÃO faz parte do jogo: rode no datamodel
-- Edit (MCP execute_luau). O NPC em si continua sendo criado pelo jogo (server/Services/NpcService), que clona este
-- modelo; sem ele, o NpcService usa o greybox antigo.
--
-- Origem do modelo: o designer gerou o Observador no Tripo (plano pago, "mystic sorcerer", ~9.600 triângulos, só
-- textura de cor 1024: fica fosco) e importou pelo Importador 3D do Studio, que subiu a malha e a textura como assets
-- da conta. Os olhos ciano e a gema do peito já vêm pintados na textura (o NpcService põe a luz ciano na cabeça).
-- O modelo anterior (Tripo grátis + réplica no Blender, asset 93431960046630) foi substituído.
--
-- Coordenadas do modelo: origem no chão, no centro; frente = -z (o NpcService vira o -z para o spawn). A malha
-- importada já olha para -z com rotação zero (conferido em captura), então não leva giro.

local AssetService: AssetService = game:GetService("AssetService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local MESH_ID = "rbxassetid://116489598679600"
local COLOR_MAP = "rbxassetid://87756855113208"
local HEIGHT = 7.6 -- studs (1,5x o jogador)
-- centro do capuz em fração da malha (medido no EditableMesh: x e z em fração da altura, y em fração da altura a
-- partir dos pés)
local HOOD = Vector3.new(-0.045, 0.89, -0.1)

local root = ServerStorage:FindFirstChild("Lobby1Modelos")
assert(root, "falta ServerStorage.Lobby1Modelos")

local body = AssetService:CreateMeshPartAsync(Content.fromUri(MESH_ID))
local scale = HEIGHT / body.MeshSize.Y
body.Name = "Corpo"
body.Size = body.MeshSize * scale
body.CFrame = CFrame.new(0, HEIGHT / 2, 0)
body.Anchored = true
-- sem colisão: o NpcService põe uma colisão simples (a capa aberta deixaria a colisão da malha larga demais)
body.CanCollide = false
body.CanQuery = true
body.CanTouch = false
body.Material = Enum.Material.Plastic

local surface = Instance.new("SurfaceAppearance")
surface.ColorMap = COLOR_MAP
surface.Parent = body

local model = Instance.new("Model")
model.Name = "Observador"
body.Parent = model

-- "Head" invisível dentro do capuz: a câmera da conversa e o "!" da missão procuram uma peça com esse nome
local head = Instance.new("Part")
head.Name = "Head"
head.Size = Vector3.new(1.4, 1.6, 1.4)
head.CFrame = CFrame.new(HOOD.X * HEIGHT, HOOD.Y * HEIGHT, HOOD.Z * HEIGHT)
head.Transparency = 1
head.Anchored = true
head.CanCollide = false
head.CanQuery = false
head.CanTouch = false
head.Parent = model

model.PrimaryPart = body
-- pivô no chão, no centro: com PrimaryPart o pivô vem dela (o WorldPivot não vale; medido: o PivotTo punha o MEIO do
-- corpo no chão e o Observador ficava enterrado até a cintura)
body.PivotOffset = body.CFrame:Inverse()

local old = root:FindFirstChild("Observador")
if old then
	old:Destroy()
end
model.Parent = root

return string.format(
	"Observador pronto em ServerStorage.Lobby1Modelos (%.2f x %.2f x %.2f studs)",
	body.Size.X,
	body.Size.Y,
	body.Size.Z
)
