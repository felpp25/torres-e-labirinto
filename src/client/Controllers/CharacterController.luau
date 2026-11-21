--!strict
-- Painel "Personagem" com duas abas:
-- - Atributos (GDD > Atributos): onde colocar os pontos ganhos ao subir de nível. Mostra o valor distribuído e,
--   em verde, o que o equipamento soma; as prévias usam os valores EFETIVOS (só para mostrar).
-- - Equipamento (GDD > Equipamentos): os 7 slots do personagem e o baú da conta; equipar, trocar e tirar.
-- O cliente só PEDE (AllocateAttribute, AllocateRecommended, EquipGear, UnequipGear); o servidor valida tudo e
-- responde pelo GearResult. Os botões ficam cinza quando a ação é impossível (ex.: dentro da torre), mas a regra
-- de verdade é do servidor.
--
-- Abrir/fechar: tecla C, botão X do controle, ou o botão "Personagem" abaixo do HUD (sempre visível: no celular é
-- o único jeito de chegar na aba Equipamento).

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
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local GearSnapshot = require(Shared:WaitForChild("GearSnapshot"))
local Classes = require(Balance:WaitForChild("Classes"))
local Gear = require(Balance:WaitForChild("Gear"))

local localPlayer = Players.LocalPlayer

local ACTION_NAME = "ToggleCharacter"
local FONT = Enum.Font.GothamBold
local ROW_HEIGHT = 44
local PANEL_WIDTH = 380
local HEADER_HEIGHT = 48
local PAGE_HEIGHT = #AttributeInfo * ROW_HEIGHT + 72
local PANEL_HEIGHT = HEADER_HEIGHT + PAGE_HEIGHT
local GEAR_ROW_HEIGHT = 46
local WEAPON_SLOT: Types.EquipSlot = "Weapon"

local COLORS = {
	panel = Color3.fromRGB(20, 20, 28),
	row = Color3.fromRGB(36, 36, 46),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(170, 170, 185),
	gold = Color3.fromRGB(255, 205, 70),
	plus = Color3.fromRGB(70, 170, 90),
	disabled = Color3.fromRGB(70, 70, 80),
	recommended = Color3.fromRGB(70, 110, 200),
	tabActive = Color3.fromRGB(70, 110, 200),
	tabIdle = Color3.fromRGB(50, 50, 62),
	bonus = Color3.fromRGB(110, 220, 120),
	equip = Color3.fromRGB(70, 170, 90),
	remove = Color3.fromRGB(180, 70, 70),
	ok = Color3.fromRGB(110, 220, 120),
	fail = Color3.fromRGB(240, 110, 110),
	openButton = Color3.fromRGB(50, 50, 62),
}

type Tab = "Attributes" | "Equipment"
type Row = { value: TextLabel, preview: TextLabel, plus: TextButton }
-- Botão de ação de uma linha de equipamento: o que faz e por que está bloqueado (nil = liberado).
type GearAction = { button: TextButton, blockedReason: () -> string? }

local CharacterController = {}

local panel: Frame? = nil
local openButton: TextButton? = nil
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local currentTab: Tab = "Attributes"
local recommendedButton: TextButton? = nil
local rows: { [string]: Row } = {}
local gearInfoLabel: TextLabel? = nil
local gearList: ScrollingFrame? = nil
local gearMessage: TextLabel? = nil
local gearActions: { GearAction } = {}
local snapshot: Types.GearSnapshot = GearSnapshot.empty()

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function unspent(): number
	return numberAttr(Keys.PlayerAttr.UnspentPoints)
end

local function inRun(): boolean
	return localPlayer:GetAttribute(Keys.InRunAttr) == true
end

local function distributedAttributes(): Types.Attributes
	local attributes = Formulas.emptyAttributes()
	for _, info in AttributeInfo do
		attributes[info.key] = numberAttr(Keys.statAttr(info.key))
	end
	return attributes
end

local function gearAttributes(): Types.Attributes
	local attributes = Formulas.emptyAttributes()
	for _, info in AttributeInfo do
		attributes[info.key] = numberAttr(Keys.gearStatAttr(info.key))
	end
	return attributes
end

-- Tipo de dano da arma equipada (o Poder só vale nele). Nil = sem arma.
local function weaponDamageType(): Types.DamageType?
	local id = snapshot.equipped[WEAPON_SLOT]
	local entry = if id ~= nil then GearSnapshot.find(snapshot, id) else nil
	local def = if entry then Gear.byId[entry.defId] else nil
	return if def then def.damageType else nil
end

local function weaponPowerFor(damageType: Types.DamageType): number
	return if weaponDamageType() == damageType then numberAttr(Keys.PlayerAttr.WeaponPower) else 0
end

-- 0.055 -> "5,5%"; 0.1 -> "10%" (uma casa decimal só quando precisa, sem arredondar 5,5 para 6).
local function percent(fraction: number): string
	local value = math.round(fraction * 1000) / 10
	local text = if value == math.floor(value) then tostring(math.floor(value)) else string.format("%.1f", value)
	local withComma = string.gsub(text, "%.", ",") -- gsub devolve (texto, nº de trocas): fica só o texto
	return `{withComma}%`
end

-- Texto do efeito atual de cada atributo (só exibição), com os atributos efetivos e o Poder da arma.
local function preview(key: Types.AttributeName, attributes: Types.Attributes, classDef: Types.ClassDef): string
	if key == "Strength" then
		local damage = Formulas.damage(100, "Physical", attributes, classDef, weaponPowerFor("Physical"))
		return `Dano físico +{math.round(damage - 100)}%`
	elseif key == "Intelligence" then
		local damage = Formulas.damage(100, "Magical", attributes, classDef, weaponPowerFor("Magical"))
		return `Dano mágico +{math.round(damage - 100)}%`
	elseif key == "Vitality" then
		return `Vida máx {Formulas.maxHealth(classDef, attributes)}`
	elseif key == "Wisdom" then
		return `Mana máx {Formulas.maxMana(classDef, attributes)}`
	elseif key == "Dexterity" then
		return `Stamina máx {Formulas.maxStamina(classDef, attributes)}`
	elseif key == "Defense" then
		return `Reduz dano em {percent(Formulas.defenseReduction(attributes.Defense))}`
	else
		local finds = string.gsub(string.format("%.2f", Formulas.luckFindMultiplier(attributes.Luck)), "%.?0+$", "")
		local findsText = string.gsub(finds, "%.", ",")
		return `Crítico {percent(Formulas.critChance(attributes.Luck))}  ·  Achados ×{findsText}`
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

local function hexColor(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function showGearMessage(text: string, ok: boolean)
	local label = gearMessage
	if label then
		label.Text = text
		label.TextColor3 = if ok then COLORS.ok else COLORS.fail
	end
end

-- ===== Aba Atributos =====

local function refreshAttributes()
	local points = unspent()
	if recommendedButton then
		recommendedButton.BackgroundColor3 = if points > 0 then COLORS.recommended else COLORS.disabled
	end
	local classDef = Classes.byId[Classes.defaultClassId]
	local distributed = distributedAttributes()
	local bonus = gearAttributes()
	local effective = Formulas.addAttributes(distributed, bonus)
	for _, info in AttributeInfo do
		local row = rows[info.key]
		if row then
			local extra = bonus[info.key]
			row.value.Text = if extra > 0
				then `{distributed[info.key]} <font color="{hexColor(COLORS.bonus)}">+{extra}</font>`
				else tostring(distributed[info.key])
			row.preview.Text = preview(info.key, effective, classDef)
			row.plus.BackgroundColor3 = if points > 0 then COLORS.plus else COLORS.disabled
		end
	end
end

local function buildAttributesPage(page: Frame)
	local classDef = Classes.byId[Classes.defaultClassId]
	for index, info in AttributeInfo do
		local y = (index - 1) * ROW_HEIGHT
		local row = Instance.new("Frame")
		row.Name = `Row_{info.key}`
		row.Position = UDim2.fromOffset(10, y)
		row.Size = UDim2.new(1, -20, 0, ROW_HEIGHT - 6)
		row.BackgroundColor3 = COLORS.row
		row.Parent = page
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
		local value = makeText(row, "0", UDim2.fromOffset(80, 38), UDim2.new(1, -136, 0, 0), 18)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.RichText = true

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

	local footerY = #AttributeInfo * ROW_HEIGHT + 6
	local recommended =
		makeButton(page, "Recomendado", UDim2.new(1, -20, 0, 38), UDim2.fromOffset(10, footerY), COLORS.recommended)
	recommended.Activated:Connect(function()
		if unspent() > 0 then
			Remotes.get("AllocateRecommended"):FireServer()
		end
	end)
	recommended.Name = "Recommended"
	recommendedButton = recommended
	local hint = makeText(
		page,
		"★ = forte na sua classe (+50%)  ·  verde = equipamento",
		UDim2.new(1, -20, 0, 14),
		UDim2.fromOffset(12, footerY + 44),
		11
	)
	hint.TextColor3 = COLORS.dim
end

-- ===== Aba Equipamento =====

local function chestCount(): number
	return GearSnapshot.chestCount(snapshot)
end

local function refreshEquipment()
	local label = gearInfoLabel
	if label then
		local count = chestCount()
		local chestText = `Baú {count}/{Gear.chestCapacity}`
		if count > Gear.chestCapacity then
			chestText = `<font color="{hexColor(COLORS.fail)}">{chestText}</font>`
		end
		local power = numberAttr(Keys.PlayerAttr.WeaponPower)
		local damageType = weaponDamageType()
		local powerText = if power > 0 and damageType
			then `  ·  Poder +{percent(power)} ({if damageType == "Physical" then "físico" else "mágico"})`
			else ""
		local lobbyText = if inRun()
			then `  ·  <font color="{hexColor(COLORS.fail)}">Troca só no lobby</font>`
			else ""
		label.Text = chestText .. powerText .. lobbyText
	end
	for _, action in gearActions do
		action.button.BackgroundColor3 = if action.blockedReason() == nil
			then action.button:GetAttribute("ReadyColor") :: Color3
			else COLORS.disabled
	end
end

-- Uma linha da lista: nome (na cor da raridade), detalhes e, se houver, um botão de ação.
local function makeGearRow(
	list: ScrollingFrame,
	order: number,
	title: string,
	detail: string,
	buttonText: string?,
	buttonColor: Color3?,
	blockedReason: (() -> string?)?,
	onActivate: (() -> ())?
)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -8, 0, GEAR_ROW_HEIGHT - 4)
	row.BackgroundColor3 = COLORS.row
	row.Parent = list
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row
	local hasButton = buttonText ~= nil
	local textWidth = if hasButton then -100 else -16
	local titleLabel = makeText(row, title, UDim2.new(1, textWidth, 0, 18), UDim2.fromOffset(10, 3), 14)
	titleLabel.RichText = true
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local detailLabel = makeText(row, detail, UDim2.new(1, textWidth, 0, 14), UDim2.fromOffset(10, 22), 11)
	detailLabel.TextColor3 = COLORS.dim
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	if buttonText and buttonColor and blockedReason and onActivate then
		local button = makeButton(row, buttonText, UDim2.fromOffset(84, 30), UDim2.new(1, -90, 0, 6), buttonColor)
		button.TextSize = 14
		button:SetAttribute("ReadyColor", buttonColor)
		button.Activated:Connect(function()
			local reason = blockedReason()
			if reason then
				showGearMessage(reason, false)
				return
			end
			onActivate()
		end)
		table.insert(gearActions, { button = button, blockedReason = blockedReason })
	end
end

local function makeSectionHeader(list: ScrollingFrame, order: number, text: string)
	local label = makeText(list, text, UDim2.new(1, -8, 0, 20), UDim2.new(), 12)
	label.LayoutOrder = order
	label.TextColor3 = COLORS.gold
end

local function coloredName(def: Types.GearDef, rarity: Types.Rarity): string
	return `<font color="{hexColor(GearInfo.rarityColor(rarity))}">{def.displayName}</font>`
end

-- Reconstrói as linhas (só quando o GearData muda ou ao abrir: o refresh comum só troca textos e cores).
local function rebuildGearRows()
	local list = gearList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(gearActions)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function lobbyOnly(): string?
		return if inRun() then "Troca de equipamento só no lobby" else nil
	end

	makeSectionHeader(list, nextOrder(), "EQUIPADO")
	for _, slot: Types.EquipSlot in Gear.slots do
		local id = snapshot.equipped[slot]
		local entry = if id ~= nil then GearSnapshot.find(snapshot, id) else nil
		local def = if entry then Gear.byId[entry.defId] else nil
		local slotName = GearInfo.slotLabel(slot)
		if entry and def then
			local rarity: Types.Rarity = entry.rarity
			local detail = GearInfo.describe(def, rarity)
			if slot == "Weapon" then
				-- A arma não sai, só é trocada (decisão do designer): sem botão "Tirar".
				makeGearRow(
					list,
					nextOrder(),
					`{slotName}: {coloredName(def, rarity)}`,
					`{detail}  ·  troque pelo baú`
				)
			else
				makeGearRow(
					list,
					nextOrder(),
					`{slotName}: {coloredName(def, rarity)}`,
					detail,
					"Tirar",
					COLORS.remove,
					function(): string?
						if inRun() then
							return "Troca de equipamento só no lobby"
						end
						if chestCount() >= Gear.chestCapacity then
							return `Baú cheio ({Gear.chestCapacity}/{Gear.chestCapacity}): venda algo antes de tirar`
						end
						return nil
					end,
					function()
						Remotes.get("UnequipGear"):FireServer(slot)
					end
				)
			end
		else
			makeGearRow(list, nextOrder(), `{slotName}: <font color="{hexColor(COLORS.dim)}">vazio</font>`, "")
		end
	end

	-- Baú: por slot, Raro primeiro, nome e id.
	local chest: { Types.GearEntry } = {}
	for _, entry in snapshot.gear do
		if not entry.inUse then
			table.insert(chest, entry)
		end
	end
	local slotOrder: { [string]: number } = {}
	for index, slot in Gear.slots do
		slotOrder[slot] = index
	end
	table.sort(chest, function(a: Types.GearEntry, b: Types.GearEntry): boolean
		local defA, defB = Gear.byId[a.defId], Gear.byId[b.defId]
		if slotOrder[defA.slot] ~= slotOrder[defB.slot] then
			return slotOrder[defA.slot] < slotOrder[defB.slot]
		end
		if a.rarity ~= b.rarity then
			return a.rarity == "Rare"
		end
		if defA.displayName ~= defB.displayName then
			return defA.displayName < defB.displayName
		end
		return a.id < b.id
	end)

	makeSectionHeader(list, nextOrder(), `BAÚ {#chest}/{Gear.chestCapacity}`)
	if #chest == 0 then
		makeGearRow(list, nextOrder(), "Nenhum item no baú", "O chefe dá 1 item garantido; os mobs, raramente.")
	end
	for _, entry in chest do
		local def = Gear.byId[entry.defId]
		local rarity: Types.Rarity = entry.rarity
		local occupied = snapshot.equipped[def.slot] ~= nil
		local id = entry.id
		makeGearRow(
			list,
			nextOrder(),
			`{coloredName(def, rarity)}  ·  {GearInfo.rarityLabel(rarity)}`,
			`{GearInfo.slotLabel(def.slot)}  ·  {GearInfo.describe(def, rarity)}`,
			if occupied then "Trocar" else "Equipar",
			COLORS.equip,
			function(): string?
				local blocked = lobbyOnly()
				if blocked then
					return blocked
				end
				if def.classId ~= nil and def.classId ~= Classes.defaultClassId then
					return "Esta arma é de outra classe"
				end
				if numberAttr(Keys.PlayerAttr.Level) < def.minLevel then
					return `Precisa do nível {def.minLevel}`
				end
				return nil
			end,
			function()
				Remotes.get("EquipGear"):FireServer(id)
			end
		)
	end
	refreshEquipment()
end

local function buildEquipmentPage(page: Frame)
	local info = makeText(page, "", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 0), 12)
	info.RichText = true
	info.TextColor3 = COLORS.dim
	gearInfoLabel = info

	local list = Instance.new("ScrollingFrame")
	list.Name = "GearList"
	list.Position = UDim2.fromOffset(10, 22)
	list.Size = UDim2.new(1, -20, 0, PAGE_HEIGHT - 50)
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
	gearList = list

	local message = makeText(page, "", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, PAGE_HEIGHT - 24), 13)
	message.TextXAlignment = Enum.TextXAlignment.Center
	gearMessage = message
end

-- ===== Painel =====

local function refreshOpenButton()
	local button = openButton
	if not button then
		return
	end
	local points = unspent()
	if points > 0 then
		button.Text = `Personagem  +{points} pts  (C)`
		button.BackgroundColor3 = COLORS.gold
		button.TextColor3 = Color3.fromRGB(30, 25, 10)
	else
		button.Text = "Personagem  (C)"
		button.BackgroundColor3 = COLORS.openButton
		button.TextColor3 = COLORS.text
	end
end

local function refresh()
	refreshOpenButton()
	local frame = panel
	if not frame or not frame.Visible then
		return
	end
	local points = unspent()
	local attributesTab = tabButtons.Attributes
	if attributesTab then
		attributesTab.Text = if points > 0 then `Atributos ({points})` else "Atributos"
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then COLORS.tabActive else COLORS.tabIdle
	end
	if currentTab == "Attributes" then
		refreshAttributes()
	else
		refreshEquipment()
	end
end

local function selectTab(tab: Tab)
	currentTab = tab
	for name, page in pages do
		page.Visible = name == tab
	end
	if tab == "Equipment" then
		showGearMessage("", true)
		rebuildGearRows()
	end
	refresh()
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
	end
	if open then
		selectTab(currentTab)
	else
		refresh()
	end
end

local function toggle()
	setOpen(not (panel ~= nil and panel.Visible))
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Botão "Personagem" logo abaixo do painel do HUD (canto superior esquerdo). Dourado com pontos livres.
	local button = makeButton(gui, "", UDim2.fromOffset(190, 30), UDim2.fromOffset(12, 148), COLORS.openButton)
	button.Name = "CharacterButton"
	button.TextSize = 14
	button.Activated:Connect(toggle)
	openButton = button

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

	local attributesTab =
		makeButton(frame, "Atributos", UDim2.fromOffset(150, 32), UDim2.fromOffset(10, 8), COLORS.tabActive)
	attributesTab.Name = "AttributesTab"
	attributesTab.TextSize = 15
	attributesTab.Activated:Connect(function()
		selectTab("Attributes")
	end)
	local equipmentTab =
		makeButton(frame, "Equipamento", UDim2.fromOffset(150, 32), UDim2.fromOffset(166, 8), COLORS.tabIdle)
	equipmentTab.Name = "EquipmentTab"
	equipmentTab.TextSize = 15
	equipmentTab.Activated:Connect(function()
		selectTab("Equipment")
	end)
	tabButtons.Attributes = attributesTab
	tabButtons.Equipment = equipmentTab

	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Name = "Close"
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local function makePage(name: string): Frame
		local page = Instance.new("Frame")
		page.Name = name
		page.BackgroundTransparency = 1
		page.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
		page.Size = UDim2.new(1, 0, 0, PAGE_HEIGHT)
		page.Parent = frame
		return page
	end
	local attributesPage = makePage("AttributesPage")
	local equipmentPage = makePage("EquipmentPage")
	equipmentPage.Visible = false
	pages.Attributes = attributesPage
	pages.Equipment = equipmentPage
	buildAttributesPage(attributesPage)
	buildEquipmentPage(equipmentPage)
end

local function onToggleAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end

local function onGearDataChanged()
	snapshot = GearSnapshot.decode(localPlayer:GetAttribute(Keys.PlayerAttr.GearData))
	if panel and panel.Visible and currentTab == "Equipment" then
		rebuildGearRows()
	end
	refresh()
end

local function onGearResult(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local message = data.message
	if typeof(message) == "string" then
		showGearMessage(message, data.ok == true)
	end
end

function CharacterController.init()
	build()
end

function CharacterController.start()
	-- Sem botão de toque do ContextActionService: no celular, o botão "Personagem" da tela abre o painel.
	ContextActionService:BindAction(ACTION_NAME, onToggleAction, false, Enum.KeyCode.C, Enum.KeyCode.ButtonX)
	localPlayer.AttributeChanged:Connect(function(name: string)
		if
			name == Keys.PlayerAttr.UnspentPoints
			or name == Keys.PlayerAttr.WeaponPower
			or name == Keys.PlayerAttr.Level
			or name == Keys.InRunAttr
			or string.sub(name, 1, 5) == "Stat_"
			or Keys.isGearStatAttr(name)
		then
			refresh()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Keys.PlayerAttr.GearData):Connect(onGearDataChanged)
	Remotes.get("GearResult").OnClientEvent:Connect(onGearResult)
	onGearDataChanged()
end

return CharacterController
