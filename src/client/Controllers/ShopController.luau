--!strict
-- Painel da loja (GDD > Lobby e loja). Abre ao acionar o prompt "Loja" do balcão do lobby
-- (tecla F / direcional para cima no controle / toque no celular) e fecha sozinho ao se afastar.
-- O cliente só PEDE (BuyItem / ResetAttributes); o servidor valida e responde por ShopResult.

local Players: Players = game:GetService("Players")
local ProximityPromptService: ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Shop = require(Shared:WaitForChild("Balance"):WaitForChild("Shop"))

local localPlayer = Players.LocalPlayer

local PROMPT_NAME = "ShopPrompt"
local CLOSE_DISTANCE = Shop.shopRange + 6
local CONFIRM_WINDOW = 3 -- s: o reset pede um segundo clique para confirmar
local FONT = Enum.Font.GothamBold
local ROW_HEIGHT = 64
local PANEL_WIDTH = 420

local COLORS = {
	panel = Color3.fromRGB(20, 20, 28),
	row = Color3.fromRGB(36, 36, 46),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(170, 170, 185),
	gold = Color3.fromRGB(255, 205, 70),
	buy = Color3.fromRGB(70, 170, 90),
	disabled = Color3.fromRGB(70, 70, 80),
	danger = Color3.fromRGB(190, 70, 60),
	ok = Color3.fromRGB(120, 255, 140),
	fail = Color3.fromRGB(255, 110, 110),
}

type ItemRow = { owned: TextLabel, buy: TextButton }

local ShopController = {}

local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local messageLabel: TextLabel? = nil
local resetButton: TextButton? = nil
local rows: { [string]: ItemRow } = {}
local resetConfirmUntil = 0

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function makeText(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.TextColor3 = COLORS.text
	label.TextSize = textSize
	label.Font = FONT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextSize = 15
	button.Font = FONT
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local function resetPrice(): number
	return Shop.resetPricePerLevel * math.max(numberAttr(Keys.PlayerAttr.Level), 1)
end

local function refresh()
	local frame = panel
	if not frame or not frame.Visible then
		return
	end
	local gold = numberAttr(Keys.PlayerAttr.Gold)
	if titleLabel then
		titleLabel.Text = `Loja  ·  Gold: {gold}`
	end
	for itemId, row in rows do
		local def = Shop.items[itemId]
		local owned = numberAttr(Keys.itemAttr(itemId))
		row.owned.Text = `Você tem {owned}/{def.maxOwned}`
		local canBuy = gold >= def.price and owned < def.maxOwned
		row.buy.BackgroundColor3 = if canBuy then COLORS.buy else COLORS.disabled
	end
	if resetButton then
		local confirming = os.clock() < resetConfirmUntil
		resetButton.Text = if confirming then "Confirmar?" else `Resetar ({resetPrice()})`
		resetButton.BackgroundColor3 = if gold >= resetPrice() then COLORS.danger else COLORS.disabled
	end
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
	end
	if open and messageLabel then
		messageLabel.Text = ""
	end
	refresh()
end

local function counterPosition(): Vector3?
	local lobby = workspace:FindFirstChild("Lobby")
	local counter = lobby and lobby:FindFirstChild("ShopCounter")
	return if counter and counter:IsA("BasePart") then counter.Position else nil
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local height = 52 + #Shop.order * ROW_HEIGHT + ROW_HEIGHT + 40
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(PANEL_WIDTH, height)
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	panel = frame

	local title = makeText(frame, "Loja", UDim2.new(1, -60, 0, 24), UDim2.fromOffset(14, 12), 18)
	title.TextColor3 = COLORS.gold
	titleLabel = title
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local function makeRow(index: number, name: string, description: string): Frame
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(10, 52 + (index - 1) * ROW_HEIGHT)
		row.Size = UDim2.new(1, -20, 0, ROW_HEIGHT - 8)
		row.BackgroundColor3 = COLORS.row
		row.Parent = frame
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row
		makeText(row, name, UDim2.fromOffset(230, 18), UDim2.fromOffset(10, 5), 15)
		local desc = makeText(row, description, UDim2.fromOffset(240, 14), UDim2.fromOffset(10, 24), 12)
		desc.TextColor3 = COLORS.dim
		return row
	end

	for index, itemId in Shop.order do
		local def = Shop.items[itemId]
		local row = makeRow(index, `{def.displayName}  ·  {def.price} Gold`, def.description)
		row.Name = `Row_{itemId}`
		local owned = makeText(row, "", UDim2.fromOffset(160, 14), UDim2.fromOffset(10, 39), 11)
		owned.TextColor3 = COLORS.dim
		local buy = makeButton(row, "Comprar", UDim2.fromOffset(100, 34), UDim2.new(1, -110, 0, 11), COLORS.buy)
		buy.Name = "Buy"
		buy.Activated:Connect(function()
			Remotes.get("BuyItem"):FireServer(itemId)
		end)
		rows[itemId] = { owned = owned, buy = buy }
	end

	local resetRow = makeRow(#Shop.order + 1, "Resetar atributos", "Devolve todos os pontos para redistribuir")
	resetRow.Name = "Row_Reset"
	local reset = makeButton(resetRow, "", UDim2.fromOffset(120, 34), UDim2.new(1, -130, 0, 11), COLORS.danger)
	reset.Name = "Reset"
	reset.Activated:Connect(function()
		-- Ação cara e definitiva: pede um segundo clique para confirmar.
		if os.clock() < resetConfirmUntil then
			resetConfirmUntil = 0
			Remotes.get("ResetAttributes"):FireServer()
		else
			resetConfirmUntil = os.clock() + CONFIRM_WINDOW
		end
		refresh()
	end)
	resetButton = reset

	local message =
		makeText(frame, "", UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 52 + (#Shop.order + 1) * ROW_HEIGHT + 6), 14)
	message.Name = "Message"
	messageLabel = message
end

local function onShopResult(payload: unknown)
	if typeof(payload) ~= "table" or not messageLabel then
		return
	end
	local data = payload :: Remotes.ShopResultPayload
	if typeof(data.message) ~= "string" then
		return
	end
	local label = messageLabel :: TextLabel
	label.Text = data.message
	label.TextColor3 = if data.ok == true then COLORS.ok else COLORS.fail
	refresh()
end

function ShopController.init()
	build()
end

function ShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			setOpen(true)
		end
	end)
	Remotes.get("ShopResult").OnClientEvent:Connect(onShopResult)
	localPlayer.AttributeChanged:Connect(function(name: string)
		if name == Keys.PlayerAttr.Gold or name == Keys.PlayerAttr.Level or string.sub(name, 1, 5) == "Item_" then
			refresh()
		end
	end)
	-- Fecha sozinho ao se afastar do balcão (e atualiza o botão de confirmação do reset).
	RunService.Heartbeat:Connect(function()
		local frame = panel
		if not frame or not frame.Visible then
			return
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local counter = counterPosition()
		if root and root:IsA("BasePart") and counter and (root.Position - counter).Magnitude > CLOSE_DISTANCE then
			setOpen(false)
		elseif resetConfirmUntil > 0 and os.clock() >= resetConfirmUntil then
			resetConfirmUntil = 0
			refresh()
		end
	end)
end

return ShopController
