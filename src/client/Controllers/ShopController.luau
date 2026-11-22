--!strict
-- Painel da loja (GDD > Lobby e loja). Abre ao acionar o prompt "Loja" do balcão do lobby
-- (tecla F / direcional para cima no controle / toque no celular) e fecha sozinho ao se afastar.
-- Abas: Comprar (poções e reset de atributos), Vender (peças de equipamento do baú; as equipadas, as fortalecidas e
-- as com gema não aparecem: decisões do designer) e Gemas (gema Nv1 de cada atributo e Removedor; ficam no baú).
-- O cliente só PEDE (BuyItem / ResetAttributes / SellGear / BuyGem / BuyRemover); o servidor valida e responde por
-- ShopResult.

local Players: Players = game:GetService("Players")
local ProximityPromptService: ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = Shared:WaitForChild("Balance")
local Types = require(Shared:WaitForChild("Types"))
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local GearSnapshot = require(Shared:WaitForChild("GearSnapshot"))
local Shop = require(Balance:WaitForChild("Shop"))
local Gear = require(Balance:WaitForChild("Gear"))
local Gems = require(Balance:WaitForChild("Gems"))

local ChatBlocker = require(script.Parent.Parent:WaitForChild("ChatBlocker"))

local localPlayer = Players.LocalPlayer

local PROMPT_NAME = "ShopPrompt"
local CLOSE_DISTANCE = Shop.shopRange + 6
local CONFIRM_WINDOW = 3 -- s: o reset e a venda de peça Rara pedem um segundo clique para confirmar
local FONT = Enum.Font.GothamBold
local ROW_HEIGHT = 64
local SELL_ROW_HEIGHT = 46
local GEM_ROW_HEIGHT = 46
local PANEL_WIDTH = 460
local HEADER_HEIGHT = 52
local PANEL_HEIGHT = HEADER_HEIGHT + #Shop.order * ROW_HEIGHT + ROW_HEIGHT + 40

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
	tabActive = Color3.fromRGB(70, 110, 200),
	tabIdle = Color3.fromRGB(50, 50, 62),
}

type Tab = "Buy" | "Sell" | "Gems"
type ItemRow = { owned: TextLabel, buy: TextButton }
-- Linha da aba Gemas: quanto tem no baú e se cabe mais um (pilha nova ocupa 1 espaço do baú).
type GemRow = { owned: TextLabel, buy: TextButton, count: () -> number, price: number }

local ShopController = {}

local panel: Frame? = nil
local goldLabel: TextLabel? = nil
local messageLabel: TextLabel? = nil
local resetButton: TextButton? = nil
local rows: { [string]: ItemRow } = {}
local resetConfirmUntil = 0
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local currentTab: Tab = "Buy"
local sellList: ScrollingFrame? = nil
local sellButtons: { [number]: TextButton } = {}
local sellConfirmUntil: { [number]: number } = {}
local gemRows: { GemRow } = {}
local gemHint: TextLabel? = nil
local snapshot: Types.GearSnapshot = GearSnapshot.empty()

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

local function hexColor(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
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
	if goldLabel then
		goldLabel.Text = `Gold: {gold}`
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then COLORS.tabActive else COLORS.tabIdle
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
	local t = os.clock()
	for id, button in sellButtons do
		button.Text = if t < (sellConfirmUntil[id] or 0) then "Confirmar?" else "Vender"
	end
	for _, row in gemRows do
		local count = row.count()
		row.owned.Text = `No baú: {count}`
		local canBuy = gold >= row.price and GearSnapshot.canStoreOne(snapshot, count)
		row.buy.BackgroundColor3 = if canBuy then COLORS.buy else COLORS.disabled
	end
	if gemHint then
		gemHint.Text = `Ficam no baú: cada tipo ocupa 1 espaço ({GearSnapshot.chestCount(snapshot)}/`
			.. `{Gear.chestCapacity})  ·  incruste na Forja ({Gems.socketCost} Gold)`
	end
end

-- Lista de venda: só peças do baú sem fortalecimento e sem gema, por slot, Rara primeiro, nome e id.
local function rebuildSellRows()
	local list = sellList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	table.clear(sellButtons)

	local chest: { Types.GearEntry } = {}
	for _, entry in snapshot.gear do
		if not entry.inUse and entry.enhance == 0 and entry.gem == nil then
			table.insert(chest, entry)
		end
	end
	GearSnapshot.sortEntries(chest)

	if #chest == 0 then
		local empty = makeText(list, "Nada para vender no baú.", UDim2.new(1, -8, 0, 30), UDim2.new(), 13)
		empty.TextColor3 = COLORS.dim
		empty.LayoutOrder = 1
	end
	for index, entry in chest do
		local def = Gear.byId[entry.defId]
		local rarity: Types.Rarity = entry.rarity
		local price = Gear.sellPrice[rarity] or 0
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, SELL_ROW_HEIGHT - 4)
		row.BackgroundColor3 = COLORS.row
		row.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		local title = makeText(
			row,
			`<font color="{hexColor(GearInfo.rarityColor(rarity))}">{def.displayName}</font>  ·  {GearInfo.rarityLabel(
				rarity
			)}`,
			UDim2.new(1, -120, 0, 18),
			UDim2.fromOffset(10, 3),
			14
		)
		title.RichText = true
		title.TextTruncate = Enum.TextTruncate.AtEnd
		local detail = makeText(
			row,
			`{GearInfo.slotLabel(def.slot)}  ·  {GearInfo.describe(def, rarity)}  ·  {price} Gold`,
			UDim2.new(1, -120, 0, 14),
			UDim2.fromOffset(10, 22),
			11
		)
		detail.TextColor3 = COLORS.dim
		detail.TextTruncate = Enum.TextTruncate.AtEnd
		local id = entry.id
		local sell = makeButton(row, "Vender", UDim2.fromOffset(100, 30), UDim2.new(1, -106, 0, 6), COLORS.buy)
		sell.TextSize = 14
		sell.Activated:Connect(function()
			-- Peça Rara vale mais: pede um segundo clique para confirmar.
			if rarity == "Rare" and os.clock() >= (sellConfirmUntil[id] or 0) then
				sellConfirmUntil[id] = os.clock() + CONFIRM_WINDOW
			else
				sellConfirmUntil[id] = nil
				Remotes.get("SellGear"):FireServer(id)
			end
			refresh()
		end)
		sellButtons[id] = sell
	end
	refresh()
end

local function selectTab(tab: Tab)
	currentTab = tab
	for name, page in pages do
		page.Visible = name == tab
	end
	if tab == "Sell" then
		rebuildSellRows()
	end
	refresh()
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
	end
	ChatBlocker.setHidden("Shop", open)
	if open then
		if messageLabel then
			messageLabel.Text = ""
		end
		selectTab(currentTab)
	end
	refresh()
end

local function counterPosition(): Vector3?
	local lobby = workspace:FindFirstChild("Lobby")
	local counter = lobby and lobby:FindFirstChild("ShopCounter")
	return if counter and counter:IsA("BasePart") then counter.Position else nil
end

local function buildBuyPage(page: Frame)
	local function makeRow(index: number, name: string, description: string): Frame
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(10, HEADER_HEIGHT + (index - 1) * ROW_HEIGHT)
		row.Size = UDim2.new(1, -20, 0, ROW_HEIGHT - 8)
		row.BackgroundColor3 = COLORS.row
		row.Parent = page
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
end

local function buildSellPage(page: Frame)
	local hint = makeText(
		page,
		"Equipadas, fortalecidas e com gema não aparecem aqui (equipamento: tecla C)",
		UDim2.new(1, -28, 0, 14),
		UDim2.fromOffset(14, HEADER_HEIGHT),
		11
	)
	hint.TextColor3 = COLORS.dim
	local list = Instance.new("ScrollingFrame")
	list.Name = "SellList"
	list.Position = UDim2.fromOffset(10, HEADER_HEIGHT + 20)
	list.Size = UDim2.new(1, -20, 0, PANEL_HEIGHT - HEADER_HEIGHT - 20 - 40)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	sellList = list
end

-- Aba Gemas: uma linha por atributo (gema do nível da loja) e uma por Removedor à venda.
local function buildGemsPage(page: Frame)
	local hint = makeText(page, "", UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, HEADER_HEIGHT), 11)
	hint.Name = "Hint"
	hint.TextColor3 = COLORS.dim
	gemHint = hint
	local list = Instance.new("ScrollingFrame")
	list.Name = "GemList"
	list.Position = UDim2.fromOffset(10, HEADER_HEIGHT + 20)
	list.Size = UDim2.new(1, -20, 0, PANEL_HEIGHT - HEADER_HEIGHT - 20 - 40)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function makeRow(
		order: number,
		name: string,
		title: string,
		titleColor: Color3,
		detail: string,
		price: number,
		count: () -> number,
		onBuy: () -> ()
	)
		local row = Instance.new("Frame")
		row.Name = name
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, GEM_ROW_HEIGHT - 4)
		row.BackgroundColor3 = COLORS.row
		row.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		local titleLabel = makeText(row, title, UDim2.new(1, -230, 0, 18), UDim2.fromOffset(10, 3), 14)
		titleLabel.TextColor3 = titleColor
		local detailLabel = makeText(row, detail, UDim2.new(1, -230, 0, 14), UDim2.fromOffset(10, 22), 11)
		detailLabel.TextColor3 = COLORS.dim
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
		local owned = makeText(row, "", UDim2.fromOffset(96, 14), UDim2.new(1, -212, 0, 14), 11)
		owned.TextColor3 = COLORS.dim
		owned.TextXAlignment = Enum.TextXAlignment.Right
		local buy = makeButton(row, `{price} Gold`, UDim2.fromOffset(100, 30), UDim2.new(1, -106, 0, 6), COLORS.buy)
		buy.Name = "Buy"
		buy.TextSize = 14
		buy.Activated:Connect(onBuy)
		table.insert(gemRows, { owned = owned, buy = buy, count = count, price = price })
	end

	local level = Gems.shopLevel
	for index, attribute: Types.GemAttribute in Gems.attributes do
		makeRow(
			index,
			`Gem_{attribute}`,
			GearInfo.gemName(attribute, level),
			GearInfo.gemColor(attribute),
			`{GearInfo.gemEffect(attribute, level)} numa peça`,
			Gems.shopPrice,
			function(): number
				return GearSnapshot.gemCount(snapshot, attribute, level)
			end,
			function()
				Remotes.get("BuyGem"):FireServer(attribute)
			end
		)
	end
	for removerLevel = 1, Gems.removerShopMaxLevel do
		makeRow(
			#Gems.attributes + removerLevel,
			`Remover_{removerLevel}`,
			GearInfo.removerName(removerLevel),
			COLORS.text,
			`Tira uma gema Nv{removerLevel} da peça (na Forja)`,
			Gems.removerPrice[removerLevel],
			function(): number
				return GearSnapshot.removerCount(snapshot, removerLevel)
			end,
			function()
				Remotes.get("BuyRemover"):FireServer(removerLevel)
			end
		)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	panel = frame

	-- Telas baixas (celular deitado): o painel encolhe para caber.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function updateScale()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		scale.Scale = math.clamp(math.min((size.Y - 16) / PANEL_HEIGHT, (size.X - 16) / PANEL_WIDTH), 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()

	local buyTab = makeButton(frame, "Comprar", UDim2.fromOffset(100, 32), UDim2.fromOffset(10, 8), COLORS.tabActive)
	buyTab.Name = "BuyTab"
	buyTab.Activated:Connect(function()
		selectTab("Buy")
	end)
	local sellTab = makeButton(frame, "Vender", UDim2.fromOffset(100, 32), UDim2.fromOffset(116, 8), COLORS.tabIdle)
	sellTab.Name = "SellTab"
	sellTab.Activated:Connect(function()
		selectTab("Sell")
	end)
	local gemsTab = makeButton(frame, "Gemas", UDim2.fromOffset(100, 32), UDim2.fromOffset(222, 8), COLORS.tabIdle)
	gemsTab.Name = "GemsTab"
	gemsTab.Activated:Connect(function()
		selectTab("Gems")
	end)
	tabButtons.Buy = buyTab
	tabButtons.Sell = sellTab
	tabButtons.Gems = gemsTab

	local gold = makeText(frame, "Gold: 0", UDim2.fromOffset(120, 32), UDim2.new(1, -170, 0, 8), 16)
	gold.TextColor3 = COLORS.gold
	gold.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel = gold
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local function makePage(name: string): Frame
		local page = Instance.new("Frame")
		page.Name = name
		page.BackgroundTransparency = 1
		page.Size = UDim2.fromScale(1, 1)
		page.Parent = frame
		return page
	end
	local buyPage = makePage("BuyPage")
	local sellPage = makePage("SellPage")
	sellPage.Visible = false
	local gemsPage = makePage("GemsPage")
	gemsPage.Visible = false
	pages.Buy = buyPage
	pages.Sell = sellPage
	pages.Gems = gemsPage
	buildBuyPage(buyPage)
	buildSellPage(sellPage)
	buildGemsPage(gemsPage)

	local message = makeText(
		frame,
		"",
		UDim2.new(1, -28, 0, 22),
		UDim2.fromOffset(14, HEADER_HEIGHT + (#Shop.order + 1) * ROW_HEIGHT + 6),
		14
	)
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

local function onGearDataChanged()
	snapshot = GearSnapshot.decode(localPlayer:GetAttribute(Keys.PlayerAttr.GearData))
	if panel and panel.Visible and currentTab == "Sell" then
		rebuildSellRows()
	end
	refresh() -- aba Gemas: quantidades no baú
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
	localPlayer:GetAttributeChangedSignal(Keys.PlayerAttr.GearData):Connect(onGearDataChanged)
	onGearDataChanged()
	-- Fecha sozinho ao se afastar do balcão (e atualiza os botões de confirmação).
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
			return
		end
		local t = os.clock()
		local expired = false
		if resetConfirmUntil > 0 and t >= resetConfirmUntil then
			resetConfirmUntil = 0
			expired = true
		end
		for id, untilTime in sellConfirmUntil do
			if t >= untilTime then
				sellConfirmUntil[id] = nil
				expired = true
			end
		end
		if expired then
			refresh()
		end
	end)
end

return ShopController
