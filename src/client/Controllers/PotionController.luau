--!strict
-- Atalhos das poções (GDD > Lobby e loja): tecla 1 = Vida, 2 = Stamina, 3 = Mana; no controle, direcional
-- esquerda/direita/baixo;
-- no celular, botões na tela. Ícones embaixo, à direita dos de esquiva e habilidades, com quantidade e recarga.
-- O cliente só PEDE (UsePotion); o servidor valida (tem o item, recarga, vivo) e aplica.

local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Shop = require(Shared:WaitForChild("Balance"):WaitForChild("Shop"))
local ActionBar = require(script.Parent.Parent:WaitForChild("ActionBar"))

local localPlayer = Players.LocalPlayer

local KEYS: { [number]: Enum.KeyCode } = { [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two, [3] = Enum.KeyCode.Three }
local GAMEPAD: { [number]: Enum.KeyCode } =
	{ [1] = Enum.KeyCode.DPadLeft, [2] = Enum.KeyCode.DPadRight, [3] = Enum.KeyCode.DPadDown }
local SHORT_NAMES: { [string]: string } = { HealthPotion = "Vida", StaminaPotion = "Stamina", ManaPotion = "Mana" }
local ICON_COLORS: { [string]: Color3 } = {
	HealthPotion = Color3.fromRGB(150, 40, 50),
	StaminaPotion = Color3.fromRGB(150, 120, 30),
	ManaPotion = Color3.fromRGB(40, 80, 160),
}
-- Botões de toque à esquerda dos de combate.
local TOUCH_POSITIONS: { [number]: UDim2 } = {
	[1] = UDim2.new(1, -300, 1, -200),
	[2] = UDim2.new(1, -370, 1, -150),
	[3] = UDim2.new(1, -370, 1, -80),
}

type Icon = { frame: Frame, name: TextLabel, count: TextLabel, overlay: Frame, timer: TextLabel }

local PotionController = {}

local icons: { [string]: Icon } = {}

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function makeText(parent: Instance, text: string, y: number, height: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Position = UDim2.fromOffset(0, y)
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBold
	label.ZIndex = 3
	label.Parent = parent
	return label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PotionGui"
	gui.ResetOnSpawn = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	for index, itemId in Shop.order do
		local def = Shop.items[itemId]
		local frame = Instance.new("Frame")
		frame.Name = `Potion_{itemId}`
		frame.Size = UDim2.fromOffset(ActionBar.iconSize, ActionBar.iconSize)
		frame.Position = ActionBar.position(ActionBar.potionSlot(index)) -- depois da esquiva e das habilidades
		frame.BackgroundColor3 = ICON_COLORS[itemId] or Color3.fromRGB(60, 60, 70)
		frame.BackgroundTransparency = 0.2
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame

		makeText(frame, tostring(def.hotkey), 4, 16, 14)
		local name = makeText(frame, SHORT_NAMES[itemId] or def.displayName, 22, 14, 12)
		local count = makeText(frame, "x0", 40, 18, 15)

		local overlay = Instance.new("Frame")
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.35
		overlay.BorderSizePixel = 0
		overlay.AnchorPoint = Vector2.new(0, 1)
		overlay.Position = UDim2.fromScale(0, 1)
		overlay.Size = UDim2.fromScale(1, 0)
		overlay.ZIndex = 2
		overlay.Parent = frame
		local overlayCorner = Instance.new("UICorner")
		overlayCorner.CornerRadius = UDim.new(0, 10)
		overlayCorner.Parent = overlay

		local timer = makeText(frame, "", 22, 18, 18)
		icons[itemId] = { frame = frame, name = name, count = count, overlay = overlay, timer = timer }
	end
end

local function update()
	local now = workspace:GetServerTimeNow()
	for itemId, icon in icons do
		local def = Shop.items[itemId]
		local owned = numberAttr(Keys.itemAttr(itemId))
		icon.count.Text = `x{owned}`
		icon.frame.BackgroundTransparency = if owned > 0 then 0.2 else 0.7
		local remaining = math.max(numberAttr(Keys.itemReadyAttr(itemId)) - now, 0)
		icon.overlay.Size = UDim2.fromScale(1, math.clamp(remaining / def.cooldown, 0, 1))
		local cooling = remaining > 0.05
		icon.timer.Text = if cooling then string.format("%.0f", math.ceil(remaining)) else ""
		icon.name.Visible = not cooling -- os segundos da recarga ocupam o lugar do nome
	end
end

local function makeHandler(itemId: string)
	return function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local ready = workspace:GetServerTimeNow() >= numberAttr(Keys.itemReadyAttr(itemId))
		if numberAttr(Keys.itemAttr(itemId)) > 0 and ready then
			Remotes.get("UsePotion"):FireServer(itemId)
		end
		return Enum.ContextActionResult.Sink
	end
end

function PotionController.init()
	build()
end

function PotionController.start()
	for _, itemId in Shop.order do
		local def = Shop.items[itemId]
		local action = `Potion_{itemId}`
		local key = KEYS[def.hotkey]
		local pad = GAMEPAD[def.hotkey]
		if key and pad then
			ContextActionService:BindAction(action, makeHandler(itemId), true, key, pad)
			ContextActionService:SetTitle(action, SHORT_NAMES[itemId] or def.displayName)
			local position = TOUCH_POSITIONS[def.hotkey]
			if position then
				ContextActionService:SetPosition(action, position)
			end
		end
	end
	RunService.Heartbeat:Connect(update)
end

return PotionController
