--!strict
-- Lobby (GDD > Lobby e loja): onde o jogador nasce, compra e entra na torre.
-- O cenário do Lobby 1 (Abismo de Áuren) é montado no Studio (Workspace/Lobby1, vive só no place); aqui ficam as peças
-- com função, construídas por código (greybox) nos lugares do blockout. Eixos: o cruzamento das torres no meio da
-- nave fica na origem; o spawn ao sul (+Z), o Altar do Coração ao norte (-Z), Torre 1 a oeste (-X), Torre 2 a leste.
-- - Loja e Forja: balcões com ProximityPrompt (o prompt nativo do Roblox funciona com tecla, controle e toque);
--   o cliente abre o painel ao acionar; os pedidos são validados no servidor (inclusive a distância).
-- - Portais: um por torre (GDD > Torre 2 e escolha de torre), placa no chão. A cada verificação, o handler do
--   RunSessionService recebe quem está em cima de cada portal (vivo, fora de run): ele cuida da espera do grupo.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Shop = require(Shared.Balance.Shop)
local Forge = require(Shared.Balance.Forge)
local Towers = require(Shared.Balance.Towers)

-- Círculo Rúnico. CFrame.new olha para -Z: o jogador nasce olhando para o Altar do Coração.
local SPAWN_POSITION = Vector3.new(0, 4, 80)
-- Banca do Tanu, no Mercado das Raízes (base do balcão; chão em y = 0).
local SHOP_POSITION = Vector3.new(82, 0, 100)
-- Forja de Cristal (Brokk), também no Mercado, a 54 studs da loja. Longe o bastante para as duas janelas não ficarem
-- abertas juntas: cada uma fecha a 20 studs do seu balcão (alcance + 6), e quem está no prompt de um fica a mais de 20
-- do outro (medido: a 22 de distância, loja e forja abriam juntas).
local FORGE_POSITION = Vector3.new(118, 0, 140)
-- Portais nas entradas das torres, no meio da nave (~6 s do spawn). Nome da peça: "TowerPortal_<torre>".
type PortalDef = { towerId: number, position: Vector3, color: Color3 }
local PORTALS: { PortalDef } = {
	-- Caverna das Profundezas (oeste)
	{ towerId = 1, position = Vector3.new(-55, 0, 0), color = Color3.fromRGB(140, 80, 230) },
	-- Ruínas Subterrâneas (leste)
	{ towerId = 2, position = Vector3.new(55, 0, 0), color = Color3.fromRGB(230, 120, 50) },
}
local PORTAL_SIZE = 10
local PLAYER_SPACING = 4
local CHECK_INTERVAL = 0.2
-- Os controllers do cliente procuram por estes nomes.
local SHOP_PROMPT_NAME = "ShopPrompt"
local FORGE_PROMPT_NAME = "ForgePrompt"

local LobbyService = {}

local onPortalTick: (towerId: number, players: { Player }) -> () = function(_: number, _: { Player }) end
local portalParts: { [number]: Part } = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeSign(part: BasePart, text: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
end

local function makePrompt(parent: BasePart, name: string, actionText: string, objectText: string, range: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = range - 2
	prompt.RequiresLineOfSight = false
	-- Teclas que não conflitam com o combate (E = Poção de Vida; X no controle = painel Personagem).
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp -- L1 é a ultimate
	prompt.Parent = parent
end

-- Peça do cenário do Lobby 1 (Workspace/Lobby1, montado no Studio), pelo caminho dos nomes; nil se não existir.
local function lobbyArt(path: { string }): Instance?
	local node: Instance? = workspace:FindFirstChild("Lobby1")
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- Loja
	local counter = makePart(
		"ShopCounter",
		Vector3.new(10, 4, 4),
		CFrame.new(SHOP_POSITION + Vector3.new(0, 2, 0)),
		Color3.fromRGB(150, 110, 60),
		folder
	)
	makeSign(counter, "LOJA", Color3.fromRGB(255, 205, 70), 5)
	makePrompt(counter, SHOP_PROMPT_NAME, "Abrir loja", "Loja", Shop.shopRange)
	-- No Lobby 1 a Banca do Tanu (madeira e toldo, scripts/lobby1-mercado.luau) é montada em volta deste balcão: ele
	-- fica invisível e continua com o prompt, a placa e a colisão.
	if lobbyArt({ "Roleplay", "Mercado das Raízes", "Bancas", "Banca do Tanu" }) then
		counter.Transparency = 1
	end

	-- Forja (greybox: bigorna escura com brasa)
	local forge = makePart(
		"ForgeCounter",
		Vector3.new(8, 4, 4),
		CFrame.new(FORGE_POSITION + Vector3.new(0, 2, 0)),
		Color3.fromRGB(70, 70, 78),
		folder
	)
	forge.Material = Enum.Material.Slate
	local ember = makePart(
		"Ember",
		Vector3.new(3, 0.4, 2),
		CFrame.new(FORGE_POSITION + Vector3.new(0, 4.2, 0)),
		Color3.fromRGB(255, 120, 40),
		folder
	)
	ember.Material = Enum.Material.Neon
	ember.CanCollide = false
	makeSign(forge, "FORJA", Color3.fromRGB(255, 150, 70), 5)
	makePrompt(forge, FORGE_PROMPT_NAME, "Abrir forja", "Forja", Forge.forgeRange)

	-- Portais das torres
	for _, def in PORTALS do
		local tower = Towers.byId[def.towerId]
		assert(tower, `Lobby: portal de uma torre que não existe ({def.towerId})`)
		local portal = makePart(
			`TowerPortal_{def.towerId}`,
			Vector3.new(PORTAL_SIZE, 0.4, PORTAL_SIZE),
			CFrame.new(def.position + Vector3.new(0, 0.2, 0)),
			def.color,
			folder
		)
		portal.Material = Enum.Material.Neon
		local title = string.upper(tower.displayName)
		makeSign(
			portal,
			if tower.minLevel > 1 then `{title} · NÍVEL {tower.minLevel}` else title,
			Color3.fromRGB(220, 190, 255),
			6
		)
		portalParts[def.towerId] = portal
	end
end

-- Ponto de nascimento no lobby (pequeno espaçamento por jogador).
function LobbyService.spawnCFrame(player: Player): CFrame
	local index = table.find(Players:GetPlayers(), player) or 1
	local offset = Vector3.new(((index - 1) % 4 - 1.5) * PLAYER_SPACING, 0, 0)
	return CFrame.new(SPAWN_POSITION + offset)
end

local function isNear(player: Player, position: Vector3, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
	return flat.Magnitude <= range and math.abs(root.Position.Y - position.Y) < 12
end

-- Usado pela loja para validar compras: o jogador precisa estar perto do balcão.
function LobbyService.isNearShop(player: Player): boolean
	return isNear(player, SHOP_POSITION, Shop.shopRange)
end

-- Usado pela Forja: o jogador precisa estar perto da bigorna.
function LobbyService.isNearForge(player: Player): boolean
	return isNear(player, FORGE_POSITION, Forge.forgeRange)
end

-- O handler recebe, a cada verificação e para CADA portal, quem está em cima dele (lista vazia também: quem saiu do
-- portal sai da espera).
function LobbyService.setPortalHandler(handler: (towerId: number, players: { Player }) -> ())
	onPortalTick = handler
end

local function playersOn(portal: Part): { Player }
	local result: { Player } = {}
	local half = PORTAL_SIZE / 2
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			humanoid
			and humanoid.Health > 0
			and root
			and root:IsA("BasePart")
			and player:GetAttribute(Keys.InRunAttr) ~= true
		then
			local offset = root.Position - portal.Position
			if math.abs(offset.X) <= half and math.abs(offset.Z) <= half and offset.Y >= -1 and offset.Y <= 8 then
				table.insert(result, player)
			end
		end
	end
	return result
end

function LobbyService.init()
	build()
end

function LobbyService.start()
	while true do
		task.wait(CHECK_INTERVAL)
		for towerId, portal in portalParts do
			onPortalTick(towerId, playersOn(portal))
		end
	end
end

return LobbyService
