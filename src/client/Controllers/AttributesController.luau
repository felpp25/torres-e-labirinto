--!strict
-- Painel de atributos (GDD > Atributos): o jogador escolhe onde colocar os pontos ganhos ao subir de nível.
-- O cliente só PEDE (AllocateAttribute / AllocateRecommended); o servidor valida e aplica.
-- As prévias ("Vida máx 150", "Crítico 10%") usam Formulas só para MOSTRAR o efeito; quem decide é o servidor.
--
-- Abrir/fechar: tecla C, botão X do controle, ou o botão "+N pontos" que aparece abaixo do HUD (toque no celular).

local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = Shared:WaitForChild("Balance")
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local AttributeInfo = require(Shared:WaitForChild("AttributeInfo"))
local Classes = require(Balance:WaitForChild("Classes"))

local localPlayer = Players.LocalPlayer

local ACTION_NAME = "ToggleAttributes"
local FONT = Enum.Font.GothamBold
local ROW_HEIGHT = 44
local PANEL_WIDTH = 380

local COLORS = {
	panel = Color3.fromRGB(20, 20, 28),
	row = Color3.fromRGB(36, 36, 46),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(170, 170, 185),
	gold = Color3.fromRGB(255, 205, 70),
	plus = Color3.fromRGB(70, 170, 90),
	disabled = Color3.fromRGB(70, 70, 80),
	recommended = Color3.fromRGB(70, 110, 200),
}

type Row = { value: TextLabel, preview: TextLabel, plus: TextButton }

local AttributesController = {}

local panel: Frame? = nil
local pointsButton: TextButton? = nil
local titleLabel: TextLabel? = nil
local recommendedButton: TextButton? = nil
local rows: { [string]: Row } = {}

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function unspent(): number
	return numberAttr(Keys.PlayerAttr.UnspentPoints)
end

local function currentAttributes(): Types.Attributes
	local attributes = Formulas.emptyAttributes()
	for _, info in AttributeInfo do
		attributes[info.key] = numberAttr(Keys.statAttr(info.key))
	end
	return attributes
end

-- 0.055 -> "5,5%"; 0.1 -> "10%" (uma casa decimal só quando precisa, sem arredondar 5,5 para 6).
local function percent(fraction: number): string
	local value = math.round(fraction * 1000) / 10
	local text = if value == math.floor(value) then tostring(math.floor(value)) else string.format("%.1f", value)
	local withComma = string.gsub(text, "%.", ",") -- gsub devolve (texto, nº de trocas): fica só o texto
	return `{withComma}%`
end

-- Texto do efeito atual de cada atributo (só exibição).
local function preview(key: Types.AttributeName, attributes: Types.Attributes, classDef: Types.ClassDef): string
	if key == "Strength" then
		return `Dano físico +{math.round(Formulas.damage(100, "Physical", attributes, classDef) - 100)}%`
	elseif key == "Intelligence" then
		return `Dano mágico +{math.round(Formulas.damage(100, "Magical", attributes, classDef) - 100)}%`
	elseif key == "Vitality" then
		return `Vida máx {Formulas.maxHealth(classDef, attributes)}`
	elseif key == "Wisdom" then
		return `Mana máx {Formulas.maxMana(classDef, attributes)}`
	elseif key == "Dexterity" then
		return `Stamina máx {Formulas.maxStamina(classDef, attributes)}`
	elseif key == "Defense" then
		return `Reduz dano em {percent(Formulas.defenseReduction(attributes.Defense))}`
	else
		return `Crítico {percent(Formulas.critChance(attributes.Luck))}`
	end
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
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local function refresh()
	local points = unspent()
	if pointsButton then
		pointsButton.Visible = points > 0
		pointsButton.Text = `+{points} {if points == 1 then "ponto" else "pontos"}  (C)`
	end
	local frame = panel
	if not frame or not frame.Visible then
		return
	end
	if titleLabel then
		titleLabel.Text = `Atributos  ·  {points} {if points == 1 then "ponto livre" else "pontos livres"}`
	end
	if recommendedButton then
		recommendedButton.BackgroundColor3 = if points > 0 then COLORS.recommended else COLORS.disabled
	end
	local classDef = Classes.byId[Classes.defaultClassId]
	local attributes = currentAttributes()
	for _, info in AttributeInfo do
		local row = rows[info.key]
		if row then
			row.value.Text = tostring(attributes[info.key])
			row.preview.Text = preview(info.key, attributes, classDef)
			row.plus.BackgroundColor3 = if points > 0 then COLORS.plus else COLORS.disabled
		end
	end
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
	end
	refresh()
end

local function toggle()
	setOpen(not (panel ~= nil and panel.Visible))
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AttributesGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Botão "+N pontos" logo abaixo do painel do HUD (canto superior esquerdo). Só aparece com pontos livres.
	local button = makeButton(gui, "", UDim2.fromOffset(190, 30), UDim2.fromOffset(12, 148), COLORS.gold)
	button.TextColor3 = Color3.fromRGB(30, 25, 10)
	button.Name = "PointsButton"
	button.Visible = false
	button.Activated:Connect(toggle)
	pointsButton = button

	local classDef = Classes.byId[Classes.defaultClassId]
	local height = 48 + #AttributeInfo * ROW_HEIGHT + 72
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

	titleLabel = makeText(frame, "Atributos", UDim2.new(1, -60, 0, 24), UDim2.fromOffset(14, 12), 18)
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	for index, info in AttributeInfo do
		local y = 48 + (index - 1) * ROW_HEIGHT
		local row = Instance.new("Frame")
		row.Name = `Row_{info.key}`
		row.Position = UDim2.fromOffset(10, y)
		row.Size = UDim2.new(1, -20, 0, ROW_HEIGHT - 6)
		row.BackgroundColor3 = COLORS.row
		row.Parent = frame
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local isScaling = Formulas.isScaling(classDef, info.key)
		local name = makeText(
			row,
			`{info.long}{if isScaling then "  ★" else ""}`,
			UDim2.fromOffset(170, 18),
			UDim2.fromOffset(10, 3),
			15
		)
		if isScaling then
			name.TextColor3 = COLORS.gold
		end
		local previewLabel = makeText(row, "", UDim2.fromOffset(200, 14), UDim2.fromOffset(10, 21), 12)
		previewLabel.TextColor3 = COLORS.dim
		local value = makeText(row, "0", UDim2.fromOffset(40, 38), UDim2.new(1, -96, 0, 0), 18)
		value.TextXAlignment = Enum.TextXAlignment.Right

		local plus = makeButton(row, "+1", UDim2.fromOffset(44, 30), UDim2.new(1, -50, 0, 4), COLORS.plus)
		plus.Name = "Plus"
		local key = info.key
		plus.Activated:Connect(function()
			if unspent() > 0 then
				Remotes.get("AllocateAttribute"):FireServer(key)
			end
		end)
		rows[key] = { value = value, preview = previewLabel, plus = plus }
	end

	local footerY = 48 + #AttributeInfo * ROW_HEIGHT + 6
	local recommended =
		makeButton(frame, "Recomendado", UDim2.new(1, -20, 0, 38), UDim2.fromOffset(10, footerY), COLORS.recommended)
	recommended.Activated:Connect(function()
		if unspent() > 0 then
			Remotes.get("AllocateRecommended"):FireServer()
		end
	end)
	recommended.Name = "Recommended"
	recommendedButton = recommended
	local hint = makeText(
		frame,
		"★ = atributo forte da sua classe (rende 50% mais)",
		UDim2.new(1, -20, 0, 14),
		UDim2.fromOffset(12, footerY + 44),
		11
	)
	hint.TextColor3 = COLORS.dim
end

local function onToggleAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end

function AttributesController.init()
	build()
end

function AttributesController.start()
	-- Sem botão de toque do ContextActionService: no celular, o botão "+N pontos" da tela abre o painel.
	ContextActionService:BindAction(ACTION_NAME, onToggleAction, false, Enum.KeyCode.C, Enum.KeyCode.ButtonX)
	localPlayer.AttributeChanged:Connect(function(name: string)
		if name == Keys.PlayerAttr.UnspentPoints or string.sub(name, 1, 5) == "Stat_" then
			refresh()
		end
	end)
	refresh()
end

return AttributesController
