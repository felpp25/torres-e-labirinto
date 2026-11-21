--!strict
-- Janela "Personagem" (layout inspirado na mochila do DDTank; arte final virá depois):
-- - à esquerda: o personagem no meio (visual 3D), os equipamentos do corpo numa coluna (Capacete, Armadura, Calças,
--   Botas) e a arma e os acessórios na outra (Arma, Pulseira, Colar); embaixo, os atributos efetivos;
-- - à direita: a mochila (baú da conta), uma grade com as peças que não estão equipadas;
-- - clicar numa peça (slot ou mochila) mostra os detalhes e a ação: Equipar/Trocar ou Tirar.
-- Distribuir pontos de atributo fica numa janela separada (botão "Distribuir pontos").
-- O cliente só PEDE (AllocateAttribute, AllocateRecommended, EquipGear, UnequipGear); o servidor valida tudo e
-- responde pelo GearResult. Botões cinza quando a ação é impossível (ex.: dentro da torre); a regra é do servidor.
--
-- Abrir/fechar: tecla C, botão X do controle, ou o botão "Personagem" abaixo do HUD (sempre visível: no celular é
-- o único jeito de abrir).

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

local ChatBlocker = require(script.Parent.Parent:WaitForChild("ChatBlocker"))

local localPlayer = Players.LocalPlayer

local ACTION_NAME = "ToggleCharacter"
local FONT = Enum.Font.GothamBold

-- Janela principal
local WINDOW_WIDTH = 780
local WINDOW_HEIGHT = 476
local TITLE_HEIGHT = 44
local LEFT_WIDTH = 380 -- painel do personagem
local SLOT_SIZE = 64
local SLOT_GAP = 8
local CELL_SIZE = 46 -- quadrado da mochila
local CELL_GAP = 5

-- Janela "Distribuir pontos"
local ROW_HEIGHT = 44
local ALLOC_WIDTH = 380
local ALLOC_HEIGHT = 48 + #AttributeInfo * ROW_HEIGHT + 72

local WEAPON_SLOT: Types.EquipSlot = "Weapon"
local LEFT_SLOTS: { Types.EquipSlot } = { "Helmet", "Armor", "Pants", "Boots" }
local RIGHT_SLOTS: { Types.EquipSlot } = { "Weapon", "Bracelet", "Necklace" }
-- Sigla no quadrado da peça (sem arte ainda).
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
	row = Color3.fromRGB(36, 36, 46),
	cell = Color3.fromRGB(44, 44, 56),
	cellEmpty = Color3.fromRGB(32, 32, 42),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(170, 170, 185),
	gold = Color3.fromRGB(255, 205, 70),
	plus = Color3.fromRGB(70, 170, 90),
	disabled = Color3.fromRGB(70, 70, 80),
	recommended = Color3.fromRGB(70, 110, 200),
	bonus = Color3.fromRGB(110, 220, 120),
	equip = Color3.fromRGB(70, 170, 90),
	remove = Color3.fromRGB(180, 70, 70),
	ok = Color3.fromRGB(110, 220, 120),
	fail = Color3.fromRGB(240, 110, 110),
	openButton = Color3.fromRGB(50, 50, 62),
	selected = Color3.fromRGB(255, 255, 255),
	emptyStroke = Color3.fromRGB(60, 60, 74),
}

type Row = { value: TextLabel, preview: TextLabel, plus: TextButton }
type SlotView = { button: TextButton, label: TextLabel, stroke: UIStroke }

local CharacterController = {}

-- Janela principal
local window: Frame? = nil
local openButton: TextButton? = nil
local previewViewport: ViewportFrame? = nil
local headerLabel: TextLabel? = nil
local slotViews: { [string]: SlotView } = {}
local statLabels: { [string]: TextLabel } = {}
local derivedLabel: TextLabel? = nil
local distributeButton: TextButton? = nil
local chestGrid: ScrollingFrame? = nil
local chestHeader: TextLabel? = nil
local goldLabel: TextLabel? = nil
local cellStrokes: { [number]: UIStroke } = {}
local detailName: TextLabel? = nil
local detailStats: TextLabel? = nil
local detailButton: TextButton? = nil
local messageLabel: TextLabel? = nil

-- Janela "Distribuir pontos"
local allocWindow: Frame? = nil
local recommendedButton: TextButton? = nil
local rows: { [string]: Row } = {}

-- Estado
local snapshot: Types.GearSnapshot = GearSnapshot.empty()
local selectedSlot: Types.EquipSlot? = nil -- peça escolhida num slot do personagem
local selectedId: number? = nil -- ou peça escolhida na mochila

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

local function hexColor(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

local function addScale(gui: ScreenGui, frame: Frame, width: number, height: number)
	-- Telas baixas (celular deitado): a janela encolhe para caber.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function update()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		scale.Scale = math.clamp(math.min((size.Y - 16) / height, (size.X - 16) / width), 0.4, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

local function showMessage(text: string, ok: boolean)
	local label = messageLabel
	if label then
		label.Text = text
		label.TextColor3 = if ok then COLORS.ok else COLORS.fail
	end
end

local function chestEntries(): { Types.GearEntry }
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
	return chest
end

local function equippedEntry(slot: Types.EquipSlot): Types.GearEntry?
	local id = snapshot.equipped[slot]
	return if id ~= nil then GearSnapshot.find(snapshot, id) else nil
end

-- ===== Detalhes da peça escolhida =====

-- Ação possível para a peça escolhida: texto, cor e motivo do bloqueio (nil = liberado).
local function currentAction(): (string?, Color3, string?)
	if selectedId ~= nil then
		local entry = GearSnapshot.find(snapshot, selectedId)
		local def = if entry then Gear.byId[entry.defId] else nil
		if not entry or not def or entry.inUse then
			return nil, COLORS.disabled, nil
		end
		local text = if snapshot.equipped[def.slot] ~= nil then "Trocar" else "Equipar"
		if inRun() then
			return text, COLORS.disabled, "Troca de equipamento só no lobby"
		end
		if def.classId ~= nil and def.classId ~= Classes.defaultClassId then
			return text, COLORS.disabled, "Esta arma é de outra classe"
		end
		if numberAttr(Keys.PlayerAttr.Level) < def.minLevel then
			return text, COLORS.disabled, `Precisa do nível {def.minLevel}`
		end
		return text, COLORS.equip, nil
	elseif selectedSlot ~= nil then
		if not equippedEntry(selectedSlot) then
			return nil, COLORS.disabled, nil
		end
		if selectedSlot == WEAPON_SLOT then
			return "Só trocar", COLORS.disabled, "A arma não pode ser tirada: escolha outra arma na mochila"
		end
		if inRun() then
			return "Tirar", COLORS.disabled, "Troca de equipamento só no lobby"
		end
		if GearSnapshot.chestCount(snapshot) >= Gear.chestCapacity then
			return "Tirar", COLORS.disabled, `Baú cheio ({Gear.chestCapacity}/{Gear.chestCapacity}): venda algo antes`
		end
		return "Tirar", COLORS.remove, nil
	end
	return nil, COLORS.disabled, nil
end

local function refreshDetail()
	local nameLabel, statsLabel, button = detailName, detailStats, detailButton
	if not nameLabel or not statsLabel or not button then
		return
	end
	local entry: Types.GearEntry? = nil
	local emptySlot: Types.EquipSlot? = nil
	if selectedId ~= nil then
		entry = GearSnapshot.find(snapshot, selectedId)
	elseif selectedSlot ~= nil then
		entry = equippedEntry(selectedSlot)
		if not entry then
			emptySlot = selectedSlot
		end
	end
	local def = if entry then Gear.byId[entry.defId] else nil
	if entry and def then
		local rarity: Types.Rarity = entry.rarity
		nameLabel.Text =
			`<font color="{hexColor(GearInfo.rarityColor(rarity))}">{def.displayName}</font>  ·  {GearInfo.rarityLabel(
				rarity
			)}`
		statsLabel.Text = `{GearInfo.slotLabel(def.slot)}  ·  {GearInfo.describe(def, rarity)}`
	elseif emptySlot then
		nameLabel.Text = `{GearInfo.slotLabel(emptySlot)}: vazio`
		statsLabel.Text = "Escolha uma peça deste tipo na mochila"
	else
		nameLabel.Text = "Clique numa peça"
		statsLabel.Text = "do personagem ou da mochila para ver os detalhes"
	end
	local text, color, _ = currentAction()
	button.Visible = text ~= nil
	button.Text = text or ""
	button.BackgroundColor3 = color
end

local function onDetailAction()
	local text, _, blocked = currentAction()
	if not text then
		return
	end
	if blocked then
		showMessage(blocked, false)
		return
	end
	if selectedId ~= nil then
		Remotes.get("EquipGear"):FireServer(selectedId)
	elseif selectedSlot ~= nil then
		Remotes.get("UnequipGear"):FireServer(selectedSlot)
	end
end

-- ===== Slots, mochila e atributos =====

local function refreshSlots()
	for _, slot: Types.EquipSlot in Gear.slots do
		local view = slotViews[slot]
		if view then
			local entry = equippedEntry(slot)
			if entry then
				view.label.Text = SLOT_SHORT[slot]
				view.label.TextColor3 = COLORS.text
				view.button.BackgroundColor3 = COLORS.cell
				view.stroke.Color = GearInfo.rarityColor(entry.rarity)
			else
				view.label.Text = GearInfo.slotLabel(slot)
				view.label.TextColor3 = COLORS.dim
				view.button.BackgroundColor3 = COLORS.cellEmpty
				view.stroke.Color = COLORS.emptyStroke
			end
			local isSelected = selectedSlot == slot
			view.stroke.Thickness = if isSelected then 3 else 2
			if isSelected then
				view.stroke.Color = COLORS.selected
			end
		end
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
end

local function refreshStats()
	local classDef = Classes.byId[Classes.defaultClassId]
	local distributed = distributedAttributes()
	local bonus = gearAttributes()
	local effective = Formulas.addAttributes(distributed, bonus)
	for _, info in AttributeInfo do
		local label = statLabels[info.key]
		if label then
			local extra = bonus[info.key]
			local value = if extra > 0
				then `{distributed[info.key]}<font color="{hexColor(COLORS.bonus)}">+{extra}</font>`
				else tostring(distributed[info.key])
			label.Text = `<font color="{hexColor(COLORS.dim)}">{info.short}</font>  {value}`
		end
	end
	local derived = derivedLabel
	if derived then
		local damage = Formulas.damage(100, "Physical", effective, classDef, weaponPowerFor("Physical"))
		derived.Text = `Vida {Formulas.maxHealth(classDef, effective)}  ·  Stamina {Formulas.maxStamina(
			classDef,
			effective
		)}` .. `  ·  Mana {Formulas.maxMana(classDef, effective)}  ·  Dano +{math.round(damage - 100)}%` .. `  ·  Defesa {percent(
			Formulas.defenseReduction(effective.Defense)
		)}`
	end
	local header = headerLabel
	if header then
		header.Text = `{classDef.displayName}  ·  Nível {numberAttr(Keys.PlayerAttr.Level)}`
	end
	local points = unspent()
	local distribute = distributeButton
	if distribute then
		distribute.Text = if points > 0 then `Distribuir pontos (+{points})` else "Distribuir pontos"
		distribute.BackgroundColor3 = if points > 0 then COLORS.gold else COLORS.openButton
		distribute.TextColor3 = if points > 0 then Color3.fromRGB(30, 25, 10) else COLORS.text
	end
	local gold = goldLabel
	if gold then
		gold.Text = `Gold: {numberAttr(Keys.PlayerAttr.Gold)}`
	end
end

local refresh: () -> () -- definido abaixo (as células chamam ao serem clicadas)

local function rebuildChest()
	local grid = chestGrid
	if not grid then
		return
	end
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	table.clear(cellStrokes)
	local chest = chestEntries()
	local header = chestHeader
	if header then
		header.Text = `Mochila  ·  {#chest}/{Gear.chestCapacity}`
		header.TextColor3 = if #chest > Gear.chestCapacity then COLORS.fail else COLORS.gold
	end
	local cells = math.max(Gear.chestCapacity, #chest)
	for index = 1, cells do
		local entry = chest[index]
		local cell = Instance.new("TextButton")
		cell.Name = if entry then `Item_{entry.id}` else `Empty_{index}`
		cell.LayoutOrder = index
		cell.AutoButtonColor = entry ~= nil
		cell.Text = ""
		cell.BackgroundColor3 = if entry then COLORS.cell else COLORS.cellEmpty
		cell.Parent = grid
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = cell
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = COLORS.emptyStroke
		stroke.Parent = cell
		if entry then
			local def = Gear.byId[entry.defId]
			local label = makeText(cell, SLOT_SHORT[def.slot], UDim2.fromScale(1, 1), UDim2.new(), 13)
			label.TextXAlignment = Enum.TextXAlignment.Center
			stroke.Color = GearInfo.rarityColor(entry.rarity)
			cellStrokes[entry.id] = stroke
			local id = entry.id
			cell.Activated:Connect(function()
				selectedId = id
				selectedSlot = nil
				showMessage("", true)
				refresh()
			end)
		end
	end
end

refresh = function()
	local button = openButton
	if button then
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
	if window and window.Visible then
		refreshStats()
		refreshSlots()
		refreshDetail()
	end
	local alloc = allocWindow
	if alloc and alloc.Visible then
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
end

-- ===== Visual 3D do personagem =====

-- Cópia do personagem para a janela (sem scripts: um LocalScript copiado rodaria dentro do PlayerGui).
local function refreshPreview()
	local viewport = previewViewport
	if not viewport then
		return
	end
	for _, child in viewport:GetChildren() do
		child:Destroy()
	end
	local character = localPlayer.Character
	if not character then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = wasArchivable
	if not clone then
		return
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	clone:PivotTo(CFrame.new())
	clone.Parent = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	-- O personagem olha para -Z: a câmera fica na frente dele, um pouco acima.
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.8, -9), Vector3.new(0, 0.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- ===== Montagem =====

local function buildSlotColumn(parent: Frame, slots: { Types.EquipSlot }, x: number, y: number)
	for index, slot: Types.EquipSlot in slots do
		local button = makeButton(
			parent,
			"",
			UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			UDim2.fromOffset(x, y + (index - 1) * (SLOT_SIZE + SLOT_GAP)),
			COLORS.cellEmpty
		)
		button.Name = `Slot_{slot}`
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = COLORS.emptyStroke
		stroke.Parent = button
		local label = makeText(button, "", UDim2.fromScale(1, 1), UDim2.new(), 12)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		button.Activated:Connect(function()
			selectedSlot = slot
			selectedId = nil
			showMessage("", true)
			refresh()
		end)
		slotViews[slot] = { button = button, label = label, stroke = stroke }
	end
end

local function buildCharacterSide(frame: Frame)
	local side = makeSection(
		frame,
		"CharacterSide",
		UDim2.fromOffset(LEFT_WIDTH, WINDOW_HEIGHT - TITLE_HEIGHT - 10),
		UDim2.fromOffset(10, TITLE_HEIGHT)
	)
	local header = makeText(side, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 14)
	header.TextColor3 = COLORS.gold
	headerLabel = header

	local slotsTop = 32
	buildSlotColumn(side, LEFT_SLOTS, 10, slotsTop)
	buildSlotColumn(side, RIGHT_SLOTS, LEFT_WIDTH - 10 - SLOT_SIZE, slotsTop)

	-- Personagem ao meio.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	local previewX = 10 + SLOT_SIZE + 10
	local previewHeight = 4 * SLOT_SIZE + 3 * SLOT_GAP
	viewport.Position = UDim2.fromOffset(previewX, slotsTop)
	viewport.Size = UDim2.fromOffset(LEFT_WIDTH - 2 * previewX, previewHeight)
	viewport.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Parent = side
	local viewportCorner = Instance.new("UICorner")
	viewportCorner.CornerRadius = UDim.new(0, 10)
	viewportCorner.Parent = viewport
	previewViewport = viewport

	-- Atributos (efetivos: distribuídos + equipamento em verde), em duas linhas.
	local statsTop = slotsTop + previewHeight + 12
	for index, info in AttributeInfo do
		local column = (index - 1) % 4
		local line = math.floor((index - 1) / 4)
		local label =
			makeText(side, "", UDim2.fromOffset(86, 20), UDim2.fromOffset(12 + column * 90, statsTop + line * 22), 14)
		label.RichText = true
		statLabels[info.key] = label
	end
	local derived = makeText(side, "", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, statsTop + 48), 11)
	derived.TextColor3 = COLORS.dim
	derived.TextWrapped = true
	derivedLabel = derived

	local distribute = makeButton(
		side,
		"Distribuir pontos",
		UDim2.new(1, -20, 0, 36),
		UDim2.fromOffset(10, statsTop + 72),
		COLORS.openButton
	)
	distribute.Name = "DistributeButton"
	distribute.TextSize = 15
	distributeButton = distribute
end

local function buildInventorySide(frame: Frame)
	local x = 10 + LEFT_WIDTH + 10
	local width = WINDOW_WIDTH - x - 10
	local side = makeSection(
		frame,
		"InventorySide",
		UDim2.fromOffset(width, WINDOW_HEIGHT - TITLE_HEIGHT - 10),
		UDim2.fromOffset(x, TITLE_HEIGHT)
	)
	local header = makeText(side, "Mochila", UDim2.new(1, -140, 0, 20), UDim2.fromOffset(12, 6), 14)
	header.TextColor3 = COLORS.gold
	chestHeader = header
	local gold = makeText(side, "Gold: 0", UDim2.fromOffset(120, 20), UDim2.new(1, -132, 0, 6), 14)
	gold.TextColor3 = COLORS.gold
	gold.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel = gold

	local detailHeight = 100
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(10, 32)
	grid.Size = UDim2.new(1, -20, 1, -(32 + detailHeight + 16))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = side
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	chestGrid = grid

	-- Detalhes da peça escolhida + ação.
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Position = UDim2.new(0, 10, 1, -(detailHeight + 8))
	detail.Size = UDim2.new(1, -20, 0, detailHeight)
	detail.BackgroundColor3 = COLORS.row
	detail.Parent = side
	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, 8)
	detailCorner.Parent = detail
	local name = makeText(detail, "", UDim2.new(1, -120, 0, 20), UDim2.fromOffset(10, 8), 14)
	name.RichText = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	detailName = name
	local stats = makeText(detail, "", UDim2.new(1, -120, 0, 32), UDim2.fromOffset(10, 30), 11)
	stats.TextColor3 = COLORS.dim
	stats.TextWrapped = true
	stats.TextYAlignment = Enum.TextYAlignment.Top
	detailStats = stats
	local action = makeButton(detail, "", UDim2.fromOffset(100, 34), UDim2.new(1, -110, 0, 10), COLORS.equip)
	action.Name = "Action"
	action.TextSize = 14
	action.Visible = false
	action.Activated:Connect(onDetailAction)
	detailButton = action
	local message = makeText(detail, "", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 1, -24), 12)
	messageLabel = message
end

local function buildAllocWindow(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "AllocWindow"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(ALLOC_WIDTH, ALLOC_HEIGHT)
	frame.BackgroundColor3 = COLORS.window
	frame.Visible = false
	frame.ZIndex = 5
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	addScale(gui, frame, ALLOC_WIDTH, ALLOC_HEIGHT)
	allocWindow = frame

	local title = makeText(frame, "Distribuir pontos", UDim2.new(1, -60, 0, 24), UDim2.fromOffset(14, 12), 18)
	title.TextColor3 = COLORS.gold
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Name = "Close"
	close.Activated:Connect(function()
		frame.Visible = false
	end)

	local classDef = Classes.byId[Classes.defaultClassId]
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
		"★ = forte na sua classe (+50%)  ·  verde = equipamento",
		UDim2.new(1, -20, 0, 14),
		UDim2.fromOffset(12, footerY + 44),
		11
	)
	hint.TextColor3 = COLORS.dim
end

local function setOpen(open: boolean)
	local frame = window
	if frame then
		frame.Visible = open
	end
	ChatBlocker.setHidden("Character", open)
	if open then
		showMessage("", true)
		rebuildChest()
		refreshPreview()
	elseif allocWindow then
		allocWindow.Visible = false
	end
	refresh()
end

local function toggle()
	setOpen(not (window ~= nil and window.Visible))
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	-- Sibling: cada elemento fica por cima de quem o contém (com Global, o fundo da janela "Distribuir pontos",
	-- de ZIndex maior, escondia os próprios botões dela).
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Botão "Personagem" logo abaixo do painel do HUD (canto superior esquerdo). Dourado com pontos livres.
	local button = makeButton(gui, "", UDim2.fromOffset(190, 30), UDim2.fromOffset(12, 148), COLORS.openButton)
	button.Name = "CharacterButton"
	button.TextSize = 14
	button.Activated:Connect(toggle)
	openButton = button

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
	addScale(gui, frame, WINDOW_WIDTH, WINDOW_HEIGHT)
	window = frame

	local title = makeText(frame, "Personagem", UDim2.new(1, -60, 0, 28), UDim2.fromOffset(14, 8), 20)
	title.TextColor3 = COLORS.gold
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 6), COLORS.disabled)
	close.Name = "Close"
	close.Activated:Connect(function()
		setOpen(false)
	end)

	buildCharacterSide(frame)
	buildInventorySide(frame)
	buildAllocWindow(gui)

	local distribute = distributeButton
	if distribute then
		distribute.Activated:Connect(function()
			local alloc = allocWindow
			if alloc then
				alloc.Visible = not alloc.Visible
				refresh()
			end
		end)
	end
end

local function onToggleAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end

local function onGearDataChanged()
	snapshot = GearSnapshot.decode(localPlayer:GetAttribute(Keys.PlayerAttr.GearData))
	-- A peça escolhida na mochila foi equipada: passa a mostrar o slot dela.
	if selectedId ~= nil then
		local entry = GearSnapshot.find(snapshot, selectedId)
		if not entry then
			selectedId = nil
		elseif entry.inUse then
			local slot: Types.EquipSlot = Gear.byId[entry.defId].slot
			selectedSlot = slot
			selectedId = nil
		end
	end
	if window and window.Visible then
		rebuildChest()
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
		showMessage(message, data.ok == true)
	end
end

function CharacterController.init()
	build()
end

function CharacterController.start()
	-- Sem botão de toque do ContextActionService: no celular, o botão "Personagem" da tela abre a janela.
	ContextActionService:BindAction(ACTION_NAME, onToggleAction, false, Enum.KeyCode.C, Enum.KeyCode.ButtonX)
	localPlayer.AttributeChanged:Connect(function(name: string)
		if
			name == Keys.PlayerAttr.UnspentPoints
			or name == Keys.PlayerAttr.WeaponPower
			or name == Keys.PlayerAttr.Level
			or name == Keys.PlayerAttr.Gold
			or name == Keys.InRunAttr
			or string.sub(name, 1, 5) == "Stat_"
			or Keys.isGearStatAttr(name)
		then
			refresh()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Keys.PlayerAttr.GearData):Connect(onGearDataChanged)
	localPlayer.CharacterAdded:Connect(function()
		if window and window.Visible then
			task.wait(0.5) -- acessórios e roupas do avatar chegam logo depois
			refreshPreview()
		end
	end)
	Remotes.get("GearResult").OnClientEvent:Connect(onGearResult)
	onGearDataChanged()
end

return CharacterController
