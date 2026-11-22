--!strict
-- Lobby (GDD > Lobby e loja): onde o jogador nasce, compra e entra na torre.
-- Construído por código (greybox), em volta do spawn do Baseplate:
-- - Loja e Forja: balcões com ProximityPrompt (o prompt nativo do Roblox funciona com tecla, controle e toque);
--   o cliente abre o painel ao acionar; os pedidos são validados no servidor (inclusive a distância).
-- - Portal da torre: placa no chão; pisar nela (vivo, fora da run) chama o handler do RunSessionService.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Shop = require(Shared.Balance.Shop)
local Forge = require(Shared.Balance.Forge)

local SPAWN_POSITION = Vector3.new(0, 4, 4)
local SHOP_POSITION = Vector3.new(-24, 0, 6) -- base do balcão (chão do Baseplate em y = 0)
-- Atrás da loja, do mesmo lado. Longe o bastante para as duas janelas não ficarem abertas juntas: cada uma fecha a
-- 20 studs do seu balcão (alcance + 6), e quem está no prompt de um fica a mais de 20 do outro (medido: a 22 de
-- distância, loja e forja abriam juntas).
local FORGE_POSITION = Vector3.new(-24, 0, -30)
local PORTAL_POSITION = Vector3.new(24, 0, 6)
local PORTAL_SIZE = 10
local PLAYER_SPACING = 4
local CHECK_INTERVAL = 0.2
-- Os controllers do cliente procuram por estes nomes.
local SHOP_PROMPT_NAME = "ShopPrompt"
local FORGE_PROMPT_NAME = "ForgePrompt"

local LobbyService = {}

local onPortal: (player: Player) -> () = function(_: Player) end
local portalPart: Part? = nil

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

	-- Portal da torre
	local portal = makePart(
		"TowerPortal",
		Vector3.new(PORTAL_SIZE, 0.4, PORTAL_SIZE),
		CFrame.new(PORTAL_POSITION + Vector3.new(0, 0.2, 0)),
		Color3.fromRGB(140, 80, 230),
		folder
	)
	portal.Material = Enum.Material.Neon
	makeSign(portal, "ENTRAR NA TORRE", Color3.fromRGB(220, 190, 255), 6)
	portalPart = portal
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

function LobbyService.setPortalHandler(handler: (player: Player) -> ())
	onPortal = handler
end

local function checkPortal()
	local portal = portalPart
	if not portal then
		return
	end
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
				onPortal(player)
			end
		end
	end
end

function LobbyService.init()
	build()
end

function LobbyService.start()
	while true do
		task.wait(CHECK_INTERVAL)
		checkPortal()
	end
end

return LobbyService
