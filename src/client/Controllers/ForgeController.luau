--!strict
-- Janela da Forja (GDD > Forja; layout provisório, arte depois). Abre ao acionar o prompt da bigorna no lobby
-- (tecla F / direcional para cima no controle / toque) e fecha sozinha ao se afastar.
-- Aba "Fortalecer" (as abas de gemas entram na etapa 3):
-- - à esquerda: todas as peças da conta (as equipadas primeiro, marcadas com "E"), com o "+N" no canto;
-- - à direita: a peça escolhida, o que ela dá agora e no próximo nível, a chance, o custo e o risco da falha.
-- O cliente só PEDE (EnhanceGear); o servidor sorteia, cobra e responde por ForgeResult. Os números mostrados
-- aqui (chance, custo, prévia) vêm das mesmas fórmulas que o servidor usa (Shared/Formulas).

local Players: Players = game:GetService("Players")
local ProximityPromptService: ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local TweenService: TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = Shared:WaitForChild("Balance")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local GearSnapshot = require(Shared:WaitForChild("GearSnapshot"))
local Gear = require(Balance:WaitForChild("Gear"))
local Forge = require(Balance:WaitForChild("Forge"))

local ChatBlocker = require(script.Parent.Parent:WaitForChild("ChatBlocker"))

local localPlayer = Players.LocalPlayer

local PROMPT_NAME = "ForgePrompt"
local CLOSE_DISTANCE = Forge.forgeRange + 6
local CONFIRM_WINDOW = 3 -- s: tentativa que pode tirar um nível pede um segundo clique
local FONT = Enum.Font.GothamBold

local WINDOW_WIDTH = 720
local WINDOW_HEIGHT = 440
local TITLE_HEIGHT = 48
local LEFT_WIDTH = 330
local CELL_SIZE = 46
local CELL_GAP = 5
local BIG_CELL = 84

-- Sigla no quadrado da peça (sem arte ainda; mesma do painel Personagem).
local SLOT_SHORT: { [string]: string } = {
	Weapon = "ARMA",
	Helmet = "CAP",
	Armor = "ARM",
	Pants = "CAL",
	Boots = "BOT",
	Bracelet = "PUL",
	Necklace = "COL",
}

local COLORS = {
	window = Color3.fromRGB(20, 20, 28),
	section = Color3.fromRGB(30, 30, 40),
	cell = Color3.fromRGB(44, 44, 56),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(170, 170, 185),
	gold = Color3.fromRGB(255, 205, 70),
	forge = Color3.fromRGB(255, 150, 70),
	enhance = Color3.fromRGB(255, 170, 80),
	inUse = Color3.fromRGB(110, 220, 120),
	selected = Color3.fromRGB(255, 255, 255),
	button = Color3.fromRGB(205, 110, 40),
	confirm = Color3.fromRGB(190, 70, 60),
	disabled = Color3.fromRGB(70, 70, 80),
	ok = Color3.fromRGB(110, 220, 120),
	fail = Color3.fromRGB(240, 110, 110),
	tabActive = Color3.fromRGB(70, 110, 200),
}

local ForgeController = {}

local window: Frame? = nil
local goldLabel: TextLabel? = nil
local grid: ScrollingFrame? = nil
local cellStrokes: { [number]: UIStroke } = {}
local bigCell: Frame? = nil
local bigLabel: TextLabel? = nil
local bigBadge: TextLabel? = nil
local bigStroke: UIStroke? = nil
local nameLabel: TextLabel? = nil
local slotLabel: TextLabel? = nil
local nowLabel: TextLabel? = nil
local nextLabel: TextLabel? = nil
local chanceLabel: TextLabel? = nil
local costLabel: TextLabel? = nil
local riskLabel: TextLabel? = nil
local enhanceButton: TextButton? = nil
local messageLabel: TextLabel? = nil

local snapshot: Types.GearSnapshot = GearSnapshot.empty()
local selectedId: number? = nil
local confirmUntil = 0

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
	button.TextSize = 16
	button.Font = FONT
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local function makeSection(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = COLORS.section
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	return frame
end

local function makeStroke(parent: GuiObject, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = color
	stroke.Parent = parent
	return stroke
end

-- "+5" pequeno no canto superior direito da peça (some sem fortalecimento).
local function makeBadge(parent: GuiObject, textSize: number): TextLabel
	local badge = makeText(parent, "", UDim2.new(1, -4, 0, textSize + 2), UDim2.fromOffset(0, 2), textSize)
	badge.Name = "Enhance"
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.TextColor3 = COLORS.enhance
	badge.TextStrokeTransparency = 0.4
	return badge
end

local function showMessage(text: string, ok: boolean)
	local label = messageLabel
	if label then
		label.Text = text
		label.TextColor3 = if ok then COLORS.ok else COLORS.fail
	end
end

local function selectedEntry(): (Types.GearEntry?, Types.GearDef?)
	local entry = if selectedId ~= nil then GearSnapshot.find(snapshot, selectedId) else nil
	local def = if entry then Gear.byId[entry.defId] else nil
	return entry, def
end

-- Peças na ordem da grade: as equipadas pelo personagem ativo (na ordem dos slots), depois as outras.
local function orderedEntries(): { Types.GearEntry }
	local list: { Types.GearEntry } = {}
	local placed: { [number]: boolean } = {}
	for _, slot: Types.EquipSlot in Gear.slots do
		local id = snapshot.equipped[slot]
		local entry = if id ~= nil then GearSnapshot.find(snapshot, id) else nil
		if entry then
			table.insert(list, entry)
			placed[entry.id] = true
		end
	end
	local rest: { Types.GearEntry } = {}
	for _, entry in snapshot.gear do
		if not placed[entry.id] then
			table.insert(rest, entry)
		end
	end
	GearSnapshot.sortEntries(rest)
	for _, entry in rest do
		table.insert(list, entry)
	end
	return list
end

-- O que o botão faz agora: texto, cor e motivo do bloqueio (nil = liberado).
local function currentAction(): (string, Color3, string?)
	local entry, def = selectedEntry()
	if not entry or not def then
		return "Fortalecer", COLORS.disabled, "Escolha uma peça à esquerda"
	end
	if entry.enhance >= Forge.maxEnhance then
		return "Máximo", COLORS.disabled, `Já está no máximo (+{Forge.maxEnhance})`
	end
	local target = entry.enhance + 1
	local cost = Formulas.enhanceCost(def, target)
	if localPlayer:GetAttribute(Keys.InRunAttr) == true then
		return "Fortalecer", COLORS.disabled, "Fortalecimento só no lobby"
	end
	if numberAttr(Keys.PlayerAttr.Gold) < cost then
		return "Fortalecer", COLORS.disabled, `Gold insuficiente (custa {cost})`
	end
	if os.clock() < confirmUntil then
		return "Confirmar?", COLORS.confirm, nil
	end
	return "Fortalecer", COLORS.button, nil
end

local function refreshDetail()
	local entry, def = selectedEntry()
	local cellLabel, badge, stroke = bigLabel, bigBadge, bigStroke
	if cellLabel and badge and stroke then
		cellLabel.Text = if def then SLOT_SHORT[def.slot] else "?"
		badge.Text = if entry then GearInfo.enhanceLabel(entry.enhance) else ""
		stroke.Color = if entry then GearInfo.rarityColor(entry.rarity) else COLORS.disabled
	end
	local name, slot, now, nextText, chance, cost, risk =
		nameLabel, slotLabel, nowLabel, nextLabel, chanceLabel, costLabel, riskLabel
	if not name or not slot or not now or not nextText or not chance or not cost or not risk then
		return
	end
	if entry and def then
		local rarity: Types.Rarity = entry.rarity
		-- Nome na cor da raridade; a raridade por extenso vai na linha de baixo (não cabia ao lado do nome).
		name.Text = GearInfo.displayName(def, entry.enhance)
		name.TextColor3 = GearInfo.rarityColor(rarity)
		local equipped = if entry.inUse then "  ·  equipada" else ""
		slot.Text = `{GearInfo.rarityLabel(rarity)}  ·  {GearInfo.slotLabel(def.slot)}{equipped}`
		now.Text = `Agora: {GearInfo.describe(def, rarity, entry.enhance)}`
		if entry.enhance >= Forge.maxEnhance then
			nextText.Text = "Nível máximo"
			chance.Text = ""
			cost.Text = ""
			risk.Text = ""
		else
			local target = entry.enhance + 1
			nextText.Text = `No +{target}: {GearInfo.describe(def, rarity, target)}`
			chance.Text = `Chance de sucesso: {math.round(Formulas.enhanceChance(target) * 100)}%`
			cost.Text = `Custo: {Formulas.enhanceCost(def, target)} Gold`
			if target >= Forge.dropOnFailFrom then
				risk.Text = `Se falhar: cai para +{math.max(entry.enhance - 1, 0)}`
				risk.TextColor3 = COLORS.fail
			else
				risk.Text = "Se falhar: perde só o Gold"
				risk.TextColor3 = COLORS.dim
			end
		end
	else
		name.Text = "Escolha uma peça"
		name.TextColor3 = COLORS.text
		slot.Text = "Equipadas (E) ou da mochila"
		now.Text = ""
		nextText.Text = ""
		chance.Text = ""
		cost.Text = ""
		risk.Text = ""
	end
	local button = enhanceButton
	if button then
		local text, color, _ = currentAction()
		button.Text = text
		button.BackgroundColor3 = color
	end
end

local function refresh()
	local frame = window
	if not frame or not frame.Visible then
		return
	end
	if goldLabel then
		goldLabel.Text = `Gold: {numberAttr(Keys.PlayerAttr.Gold)}`
	end
	for id, stroke in cellStrokes do
		local entry = GearSnapshot.find(snapshot, id)
		if selectedId == id then
			stroke.Color = COLORS.selected
			stroke.Thickness = 3
		elseif entry then
			stroke.Color = GearInfo.rarityColor(entry.rarity)
			stroke.Thickness = 2
		end
	end
	refreshDetail()
end

local function rebuildGrid()
	local list = grid
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	table.clear(cellStrokes)
	for index, entry in orderedEntries() do
		local def = Gear.byId[entry.defId]
		local cell = Instance.new("TextButton")
		cell.Name = `Item_{entry.id}`
		cell.LayoutOrder = index
		cell.Text = ""
		cell.BackgroundColor3 = COLORS.cell
		cell.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cell
		cellStrokes[entry.id] = makeStroke(cell, GearInfo.rarityColor(entry.rarity))
		local label = makeText(cell, SLOT_SHORT[def.slot], UDim2.fromScale(1, 1), UDim2.new(), 13)
		label.TextXAlignment = Enum.TextXAlignment.Center
		makeBadge(cell, 11).Text = GearInfo.enhanceLabel(entry.enhance)
		if entry.inUse then
			local mark = makeText(cell, "E", UDim2.fromOffset(14, 14), UDim2.new(0, 3, 1, -15), 11)
			mark.Name = "InUse"
			mark.TextColor3 = COLORS.inUse
		end
		local id = entry.id
		cell.Activated:Connect(function()
			if selectedId ~= id then
				confirmUntil = 0
			end
			selectedId = id
			showMessage("", true)
			refresh()
		end)
	end
end

local function flash(color: Color3)
	local cell = bigCell
	if not cell then
		return
	end
	cell.BackgroundColor3 = color
	TweenService:Create(cell, TweenInfo.new(0.6), { BackgroundColor3 = COLORS.cell }):Play()
end

local function onEnhanceClicked()
	local _, _, blocked = currentAction()
	if blocked then
		showMessage(blocked, false)
		return
	end
	local entry, _ = selectedEntry()
	if not entry then
		return
	end
	-- Tentativa que pode tirar um nível (+8 a +10): pede um segundo clique.
	if entry.enhance + 1 >= Forge.dropOnFailFrom and os.clock() >= confirmUntil then
		confirmUntil = os.clock() + CONFIRM_WINDOW
		showMessage("", true) -- a mensagem da tentativa anterior confundiria com a confirmação
		refresh()
		return
	end
	confirmUntil = 0
	Remotes.get("EnhanceGear"):FireServer(entry.id)
	refresh()
end

local function setOpen(open: boolean)
	local frame = window
	if frame then
		frame.Visible = open
	end
	ChatBlocker.setHidden("Forge", open)
	confirmUntil = 0
	if open then
		showMessage("", true)
		rebuildGrid()
	end
	refresh()
end

local function forgePosition(): Vector3?
	local lobby = workspace:FindFirstChild("Lobby")
	local counter = lobby and lobby:FindFirstChild("ForgeCounter")
	return if counter and counter:IsA("BasePart") then counter.Position else nil
end

local function buildPiecesSide(frame: Frame)
	local side = makeSection(
		frame,
		"PiecesSide",
		UDim2.fromOffset(LEFT_WIDTH, WINDOW_HEIGHT - TITLE_HEIGHT - 10),
		UDim2.fromOffset(10, TITLE_HEIGHT)
	)
	local header = makeText(side, "Suas peças", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 14)
	header.TextColor3 = COLORS.gold
	local hint = makeText(side, "E = equipada", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 11)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = COLORS.dim

	local list = Instance.new("ScrollingFrame")
	list.Name = "Grid"
	list.Position = UDim2.fromOffset(10, 32)
	list.Size = UDim2.new(1, -20, 1, -42)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = side
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	grid = list
end

local function buildEnhanceSide(frame: Frame)
	local x = 10 + LEFT_WIDTH + 10
	local side = makeSection(
		frame,
		"EnhanceSide",
		UDim2.fromOffset(WINDOW_WIDTH - x - 10, WINDOW_HEIGHT - TITLE_HEIGHT - 10),
		UDim2.fromOffset(x, TITLE_HEIGHT)
	)

	-- Peça escolhida, em destaque.
	local cell = Instance.new("Frame")
	cell.Name = "Selected"
	cell.Size = UDim2.fromOffset(BIG_CELL, BIG_CELL)
	cell.Position = UDim2.fromOffset(14, 14)
	cell.BackgroundColor3 = COLORS.cell
	cell.Parent = side
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = cell
	bigStroke = makeStroke(cell, COLORS.disabled)
	local label = makeText(cell, "?", UDim2.fromScale(1, 1), UDim2.new(), 20)
	label.TextXAlignment = Enum.TextXAlignment.Center
	bigLabel = label
	bigBadge = makeBadge(cell, 16)
	bigCell = cell

	local textX = 14 + BIG_CELL + 12
	local name = makeText(side, "", UDim2.new(1, -(textX + 10), 0, 22), UDim2.fromOffset(textX, 18), 16)
	name.Name = "PieceName"
	name.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel = name
	local slot = makeText(side, "", UDim2.new(1, -(textX + 10), 0, 16), UDim2.fromOffset(textX, 44), 12)
	slot.TextColor3 = COLORS.dim
	slotLabel = slot

	local y = 14 + BIG_CELL + 16
	local function line(lineName: string, textSize: number, color: Color3): TextLabel
		local text = makeText(side, "", UDim2.new(1, -28, 0, textSize + 6), UDim2.fromOffset(14, y), textSize)
		text.Name = lineName
		text.TextColor3 = color
		text.TextWrapped = true
		y += textSize + 12
		return text
	end
	nowLabel = line("Now", 14, COLORS.text)
	nextLabel = line("Next", 14, COLORS.ok)
	chanceLabel = line("Chance", 15, COLORS.text)
	costLabel = line("Cost", 15, COLORS.gold)
	riskLabel = line("Risk", 13, COLORS.dim)

	local button = makeButton(side, "Fortalecer", UDim2.new(1, -28, 0, 44), UDim2.fromOffset(14, y + 4), COLORS.button)
	button.Name = "EnhanceButton"
	button.TextSize = 18
	button.Activated:Connect(onEnhanceClicked)
	enhanceButton = button

	local message = makeText(side, "", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, y + 56), 14)
	message.Name = "Message"
	message.TextWrapped = true
	messageLabel = message

	local rules = makeText(
		side,
		`+1 a +3 nunca falham  ·  falhar do +{Forge.dropOnFailFrom} em diante tira 1 nível`,
		UDim2.new(1, -28, 0, 14),
		UDim2.new(0, 14, 1, -22),
		11
	)
	rules.TextColor3 = COLORS.dim
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ForgeGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame.BackgroundColor3 = COLORS.window
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	window = frame

	-- Telas baixas (celular deitado): a janela encolhe para caber.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function updateScale()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		scale.Scale = math.clamp(math.min((size.Y - 16) / WINDOW_HEIGHT, (size.X - 16) / WINDOW_WIDTH), 0.4, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()

	local title = makeText(frame, "Forja", UDim2.fromOffset(90, 28), UDim2.fromOffset(14, 10), 20)
	title.TextColor3 = COLORS.forge
	-- Aba única por enquanto; incrustar, fundir e extrair gemas entram como abas na etapa 3.
	local tab = makeButton(frame, "Fortalecer", UDim2.fromOffset(120, 30), UDim2.fromOffset(100, 9), COLORS.tabActive)
	tab.Name = "EnhanceTab"
	tab.TextSize = 15
	tab.AutoButtonColor = false
	local gold = makeText(frame, "Gold: 0", UDim2.fromOffset(160, 28), UDim2.new(1, -212, 0, 10), 16)
	gold.TextColor3 = COLORS.gold
	gold.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel = gold
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Name = "Close"
	close.Activated:Connect(function()
		setOpen(false)
	end)

	buildPiecesSide(frame)
	buildEnhanceSide(frame)
end

local function onForgeResult(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local message = data.message
	if typeof(message) ~= "string" then
		return
	end
	local ok = data.ok == true
	showMessage(message, ok)
	if data.rolled == true then -- houve sorteio: pisca a peça em verde (sucesso) ou vermelho (falha)
		flash(if ok then COLORS.ok else COLORS.fail)
	end
	refresh()
end

local function onGearDataChanged()
	snapshot = GearSnapshot.decode(localPlayer:GetAttribute(Keys.PlayerAttr.GearData))
	if selectedId ~= nil and GearSnapshot.find(snapshot, selectedId) == nil then
		selectedId = nil -- a peça saiu da conta (ex.: vendida)
	end
	if window and window.Visible then
		rebuildGrid()
	end
	refresh()
end

function ForgeController.init()
	build()
end

function ForgeController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			setOpen(true)
		end
	end)
	Remotes.get("ForgeResult").OnClientEvent:Connect(onForgeResult)
	localPlayer.AttributeChanged:Connect(function(name: string)
		if name == Keys.PlayerAttr.Gold or name == Keys.InRunAttr then
			refresh()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Keys.PlayerAttr.GearData):Connect(onGearDataChanged)
	onGearDataChanged()
	-- Fecha sozinha ao se afastar da bigorna (e desfaz o "Confirmar?" que expirou).
	RunService.Heartbeat:Connect(function()
		local frame = window
		if not frame or not frame.Visible then
			return
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = forgePosition()
		if root and root:IsA("BasePart") and position and (root.Position - position).Magnitude > CLOSE_DISTANCE then
			setOpen(false)
			return
		end
		if confirmUntil > 0 and os.clock() >= confirmUntil then
			confirmUntil = 0
			refresh()
		end
	end)
end

return ForgeController
