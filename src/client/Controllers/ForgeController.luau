--!strict
-- Janela da Forja (GDD > Forja; layout provisório, arte depois). Abre ao acionar o prompt da bigorna no lobby
-- (tecla F / direcional para cima no controle / toque) e fecha sozinha ao se afastar. Abas:
-- - "Fortalecer": à esquerda todas as peças da conta (as equipadas primeiro, marcadas com "E"), com o "+N" e a gema
--   no canto; à direita a peça escolhida, o que ela dá agora e no próximo nível, a chance, o custo e o risco.
-- - "Transferir": as mesmas peças à esquerda; à direita as peças que podem trocar o fortalecimento com a escolhida
--   (mesmo tipo, outro nível, torre igual ou mais baixa), a prévia das duas depois da troca e o custo (Gold).
-- - "Gemas": as mesmas peças à esquerda; à direita a gema da peça: incrustar uma gema do baú (Gold) ou extrair a
--   que está nela (gasta um Removedor do nível da gema; a gema volta inteira para o baú).
-- - "Fundir": à esquerda as gemas do baú; à direita a fusão de 3 iguais em 1 do nível seguinte (Gold).
-- O cliente só PEDE (EnhanceGear, TransferEnhance, SocketGem, ExtractGem, FuseGems); o servidor confere tudo,
-- sorteia, cobra e responde por ForgeResult. Os números mostrados vêm das mesmas fórmulas e tabelas do servidor.

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
local Gems = require(Balance:WaitForChild("Gems"))

local ChatBlocker = require(script.Parent.Parent:WaitForChild("ChatBlocker"))
local TextFit = require(script.Parent.Parent:WaitForChild("TextFit"))

local localPlayer = Players.LocalPlayer

local PROMPT_NAME = "ForgePrompt"
local CLOSE_DISTANCE = Forge.forgeRange + 6
local CONFIRM_WINDOW = 3 -- s: tentativa que pode tirar um nível pede um segundo clique
local FONT = Enum.Font.GothamBold

local WINDOW_WIDTH = 720
local WINDOW_HEIGHT = 440
local TITLE_HEIGHT = 48
local SIDE_HEIGHT = WINDOW_HEIGHT - TITLE_HEIGHT - 10
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
	extract = Color3.fromRGB(180, 70, 70),
	confirm = Color3.fromRGB(190, 70, 60),
	disabled = Color3.fromRGB(70, 70, 80),
	ok = Color3.fromRGB(110, 220, 120),
	fail = Color3.fromRGB(240, 110, 110),
	tabActive = Color3.fromRGB(70, 110, 200),
	tabIdle = Color3.fromRGB(50, 50, 62),
	gemText = Color3.fromRGB(20, 20, 28),
}

type Tab = "Enhance" | "Gems" | "Fuse" | "Transfer"

-- Peça escolhida em destaque (abas Fortalecer e Gemas): célula grande, nome e a linha raridade/slot.
type PieceHeader = {
	cell: Frame,
	label: TextLabel,
	badge: TextLabel,
	gemMark: TextLabel,
	stroke: UIStroke,
	name: TextLabel,
	slot: TextLabel,
}

-- Borda de uma célula de gema e a cor dela fora da seleção.
type StackView = { stroke: UIStroke, color: Color3 }

local ForgeController = {}

-- Janela
local window: Frame? = nil
local goldLabel: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
local sides: { [string]: Frame } = {} -- lado direito de cada aba
local messageLabels: { [string]: TextLabel } = {}
local leftHeader: TextLabel? = nil
local leftHint: TextLabel? = nil
local pieceGrid: ScrollingFrame? = nil
local stackGrid: ScrollingFrame? = nil
local stackEmptyLabel: TextLabel? = nil
local pieceStrokes: { [number]: UIStroke } = {}
local stackViews: { [string]: StackView } = {} -- gemas do baú (aba Fundir)
-- Aba Fortalecer
local enhanceHeader: PieceHeader? = nil
local nowLabel: TextLabel? = nil
local nextLabel: TextLabel? = nil
local chanceLabel: TextLabel? = nil
local costLabel: TextLabel? = nil
local riskLabel: TextLabel? = nil
local enhanceButton: TextButton? = nil
-- Aba Gemas
local gemHeader: PieceHeader? = nil
local gemLine: TextLabel? = nil
local chooseLabel: TextLabel? = nil
local choiceGrid: ScrollingFrame? = nil
local choiceViews: { [string]: StackView } = {}
local gemInfo: TextLabel? = nil
local gemButton: TextButton? = nil
-- Aba Fundir
local fuseStroke: UIStroke? = nil
local fuseCellLabel: TextLabel? = nil
local fuseLevelLabel: TextLabel? = nil
local fuseCountLabel: TextLabel? = nil
local fuseName: TextLabel? = nil
local fuseOwned: TextLabel? = nil
local recipeLabel: TextLabel? = nil
local fuseCostLabel: TextLabel? = nil
local fuseButton: TextButton? = nil
-- Aba Transferir
local transferHeader: PieceHeader? = nil
local transferChoose: TextLabel? = nil
local transferGrid: ScrollingFrame? = nil
local transferStrokes: { [number]: UIStroke } = {}
local afterLabel: TextLabel? = nil
local afterTo: TextLabel? = nil
local afterFrom: TextLabel? = nil
local transferCostLabel: TextLabel? = nil
local transferButton: TextButton? = nil

-- Estado
local snapshot: Types.GearSnapshot = GearSnapshot.empty()
local currentTab: Tab = "Enhance"
local selectedId: number? = nil -- peça (abas Fortalecer e Gemas)
local selectedGem: Types.Gem? = nil -- gema do baú escolhida para incrustar (aba Gemas)
local selectedStack: Types.Gem? = nil -- gemas do baú escolhidas para fundir (aba Fundir)
local transferTargetId: number? = nil -- peça que troca o fortalecimento com a escolhida (aba Transferir)
local confirmUntil = 0

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function inRun(): boolean
	return localPlayer:GetAttribute(Keys.InRunAttr) == true
end

local function gemKey(gem: Types.Gem): string
	return `{gem.attribute}:{gem.level}`
end

-- ===== Peças de interface =====

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

local function makeCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
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

-- Quadradinho da gema encaixada, no canto inferior direito da peça: cor do atributo e o nível. Some sem gema.
local function makeGemMark(parent: GuiObject, size: number): TextLabel
	local mark = Instance.new("TextLabel")
	mark.Name = "Gem"
	mark.AnchorPoint = Vector2.new(1, 1)
	mark.Position = UDim2.new(1, -3, 1, -3)
	mark.Size = UDim2.fromOffset(size, size)
	mark.Text = ""
	mark.TextColor3 = COLORS.gemText
	mark.TextSize = size - 3
	mark.Font = FONT
	mark.Visible = false
	mark.Parent = parent
	makeCorner(mark, 3)
	return mark
end

local function setGemMark(mark: TextLabel, gem: Types.Gem?)
	mark.Visible = gem ~= nil
	if gem then
		mark.BackgroundColor3 = GearInfo.gemColor(gem.attribute)
		mark.Text = tostring(gem.level)
	end
end

-- Célula de uma pilha de gemas do baú: sigla do atributo, "Nv2" no canto e a quantidade embaixo.
local function makeStackCell(parent: Instance, stack: Types.GemStack, order: number, onClick: () -> ()): StackView
	local color = GearInfo.gemColor(stack.attribute)
	local cell = Instance.new("TextButton")
	cell.Name = `Gem_{stack.attribute}_{stack.level}`
	cell.LayoutOrder = order
	cell.Text = ""
	cell.BackgroundColor3 = COLORS.cell
	cell.Parent = parent
	makeCorner(cell, 6)
	local stroke = makeStroke(cell, color)
	local label = makeText(cell, GearInfo.gemShort(stack.attribute), UDim2.fromScale(1, 1), UDim2.new(), 13)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = color
	local level = makeBadge(cell, 10)
	level.Text = `Nv{stack.level}`
	level.TextColor3 = COLORS.text
	local count = makeText(cell, `×{stack.count}`, UDim2.new(1, -4, 0, 12), UDim2.new(0, 0, 1, -14), 10)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = COLORS.dim
	cell.Activated:Connect(onClick)
	return { stroke = stroke, color = color }
end

local function showMessage(text: string, ok: boolean)
	local label = messageLabels[currentTab]
	if label then
		label.Text = text
		label.TextColor3 = if ok then COLORS.ok else COLORS.fail
	end
end

local function clearMessages()
	for _, label in messageLabels do
		label.Text = ""
	end
end

-- ===== Estado escolhido =====

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

-- Peças que podem trocar o fortalecimento com a escolhida (mesma regra do servidor: Formulas.transferCheck).
local function transferTargets(): { Types.GearEntry }
	local source, sourceDef = selectedEntry()
	local list: { Types.GearEntry } = {}
	if not source or not sourceDef then
		return list
	end
	for _, entry in orderedEntries() do
		local def = Gear.byId[entry.defId]
		if entry.id ~= source.id and Formulas.transferCheck(sourceDef, source.enhance, def, entry.enhance) == "Ok" then
			table.insert(list, entry)
		end
	end
	return list
end

local function transferTarget(): (Types.GearEntry?, Types.GearDef?)
	local entry = if transferTargetId ~= nil then GearSnapshot.find(snapshot, transferTargetId) else nil
	local def = if entry then Gear.byId[entry.defId] else nil
	return entry, def
end

-- Cabe mais 1 gema nesta pilha do baú, liberando `freed` espaços antes? (Mesma regra do servidor; só para o botão.)
local function gemFits(attribute: Types.GemAttribute, level: number, freed: number): boolean
	local have = GearSnapshot.gemCount(snapshot, attribute, level)
	if have >= Gems.stackMax then
		return false
	end
	return have > 0 or GearSnapshot.chestCount(snapshot) - freed < Gear.chestCapacity
end

-- ===== O que cada botão faz agora: texto, cor e motivo do bloqueio (nil = liberado) =====

local function enhanceAction(): (string, Color3, string?)
	local entry, def = selectedEntry()
	if not entry or not def then
		return "Fortalecer", COLORS.disabled, "Escolha uma peça à esquerda"
	end
	if entry.enhance >= Forge.maxEnhance then
		return "Máximo", COLORS.disabled, `Já está no máximo (+{Forge.maxEnhance})`
	end
	local target = entry.enhance + 1
	local cost = Formulas.enhanceCost(def, target)
	if inRun() then
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

local function gemAction(): (string, Color3, string?)
	local entry, _ = selectedEntry()
	if not entry then
		return "Incrustar", COLORS.disabled, "Escolha uma peça à esquerda"
	end
	local gem = entry.gem
	if gem then
		if inRun() then
			return "Extrair", COLORS.disabled, "Gemas só no lobby"
		end
		local removers = GearSnapshot.removerCount(snapshot, gem.level)
		if removers <= 0 then
			return "Extrair", COLORS.disabled, `Precisa de 1 {GearInfo.removerName(gem.level)} (compre na loja)`
		end
		if not gemFits(gem.attribute, gem.level, if removers == 1 then 1 else 0) then
			return "Extrair", COLORS.disabled, "Baú cheio: a gema não teria onde ficar"
		end
		return "Extrair", COLORS.extract, nil
	end
	if inRun() then
		return "Incrustar", COLORS.disabled, "Gemas só no lobby"
	end
	if #snapshot.gems == 0 then
		return "Incrustar", COLORS.disabled, "Você não tem gemas: compre na loja"
	end
	local chosen = selectedGem
	if not chosen then
		return "Incrustar", COLORS.disabled, "Escolha uma gema do baú"
	end
	if numberAttr(Keys.PlayerAttr.Gold) < Gems.socketCost then
		return "Incrustar", COLORS.disabled, `Gold insuficiente (custa {Gems.socketCost})`
	end
	return "Incrustar", COLORS.button, nil
end

local function fuseAction(): (string, Color3, string?)
	local stack = selectedStack
	if not stack then
		return "Fundir", COLORS.disabled, "Escolha uma gema à esquerda"
	end
	local cost = Formulas.fuseCost(stack.level)
	if cost == nil then
		return "Fundir", COLORS.disabled, GearInfo.fuseBlockedReason(stack.level)
	end
	if inRun() then
		return "Fundir", COLORS.disabled, "Gemas só no lobby"
	end
	local have = GearSnapshot.gemCount(snapshot, stack.attribute, stack.level)
	if have < Gems.fuseCount then
		return "Fundir", COLORS.disabled, `Precisa de {Gems.fuseCount} iguais (você tem {have})`
	end
	if numberAttr(Keys.PlayerAttr.Gold) < cost then
		return "Fundir", COLORS.disabled, `Gold insuficiente (custa {cost})`
	end
	if not gemFits(stack.attribute, stack.level + 1, if have == Gems.fuseCount then 1 else 0) then
		return "Fundir", COLORS.disabled, "Baú cheio: a gema nova não teria onde ficar"
	end
	return "Fundir", COLORS.button, nil
end

local function transferAction(): (string, Color3, string?)
	local source, sourceDef = selectedEntry()
	if not source or not sourceDef then
		return "Transferir", COLORS.disabled, "Escolha uma peça à esquerda"
	end
	local target, targetDef = transferTarget()
	if not target or not targetDef then
		return "Transferir", COLORS.disabled, "Escolha a peça que troca com ela"
	end
	local check: Formulas.TransferCheck = Formulas.transferCheck(sourceDef, source.enhance, targetDef, target.enhance)
	local blocked = GearInfo.transferBlockedReason(check)
	if blocked then
		return "Transferir", COLORS.disabled, blocked
	end
	if inRun() then
		return "Transferir", COLORS.disabled, "Transferência só no lobby"
	end
	local cost = Formulas.transferCost(sourceDef, source.enhance, targetDef, target.enhance)
	if numberAttr(Keys.PlayerAttr.Gold) < cost then
		return "Transferir", COLORS.disabled, `Gold insuficiente (custa {cost})`
	end
	if os.clock() < confirmUntil then
		return "Confirmar?", COLORS.confirm, nil
	end
	return "Transferir", COLORS.button, nil
end

local function paintButton(button: TextButton?, action: () -> (string, Color3, string?))
	if button then
		local text, color, _ = action()
		button.Text = text
		button.BackgroundColor3 = color
	end
end

-- ===== Atualizar a tela =====

local function refreshPieceHeader(header: PieceHeader?)
	if not header then
		return
	end
	local entry, def = selectedEntry()
	header.label.Text = if def then SLOT_SHORT[def.slot] else "?"
	header.badge.Text = if entry then GearInfo.enhanceLabel(entry.enhance) else ""
	header.stroke.Color = if entry then GearInfo.rarityColor(entry.rarity) else COLORS.disabled
	setGemMark(header.gemMark, if entry then entry.gem else nil)
	if entry and def then
		local rarity: Types.Rarity = entry.rarity
		-- Nome na cor da raridade; a raridade por extenso vai na linha de baixo (não cabia ao lado do nome).
		header.name.Text = GearInfo.displayName(def, entry.enhance)
		header.name.TextColor3 = GearInfo.rarityColor(rarity)
		local equipped = if entry.inUse then "  ·  equipada" else ""
		header.slot.Text = `{GearInfo.rarityLabel(rarity)}  ·  {GearInfo.slotLabel(def.slot)}{equipped}`
	else
		header.name.Text = "Escolha uma peça"
		header.name.TextColor3 = COLORS.text
		header.slot.Text = "Equipadas (E) ou da mochila"
	end
end

local function refreshEnhance()
	refreshPieceHeader(enhanceHeader)
	local entry, def = selectedEntry()
	local now, nextText, chance, cost, risk = nowLabel, nextLabel, chanceLabel, costLabel, riskLabel
	if not now or not nextText or not chance or not cost or not risk then
		return
	end
	if entry and def then
		local rarity: Types.Rarity = entry.rarity
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
		now.Text = ""
		nextText.Text = ""
		chance.Text = ""
		cost.Text = ""
		risk.Text = ""
	end
	paintButton(enhanceButton, enhanceAction)
end

local function paintStackViews(views: { [string]: StackView }, chosen: Types.Gem?)
	local chosenKey = if chosen then gemKey(chosen) else nil
	for key, view in views do
		local isSelected = key == chosenKey
		view.stroke.Color = if isSelected then COLORS.selected else view.color
		view.stroke.Thickness = if isSelected then 3 else 2
	end
end

local function refreshGems()
	refreshPieceHeader(gemHeader)
	local line, choose, choices, info = gemLine, chooseLabel, choiceGrid, gemInfo
	if not line or not choose or not choices or not info then
		return
	end
	local entry, _ = selectedEntry()
	local gem = if entry then entry.gem else nil
	if not entry then
		line.Text = ""
		info.Text = ""
		choose.Visible = false
		choices.Visible = false
	elseif gem then
		line.Text = `{GearInfo.gemName(gem.attribute, gem.level)} ({GearInfo.gemEffect(gem.attribute, gem.level)})`
		line.TextColor3 = GearInfo.gemColor(gem.attribute)
		choose.Visible = false
		choices.Visible = false
		local removers = GearSnapshot.removerCount(snapshot, gem.level)
		info.Text = `Extrair gasta 1 {GearInfo.removerName(gem.level)} (você tem {removers}). A gema volta inteira`
			.. " para o baú."
	else
		line.Text = "Sem gema"
		line.TextColor3 = COLORS.dim
		choose.Visible = true
		choices.Visible = true
		choose.Text = if #snapshot.gems > 0
			then "Escolha a gema (do baú):"
			else `Nenhuma gema no baú: compre na loja (Nv{Gems.shopLevel}, {Gems.shopPrice} Gold)`
		local chosen = selectedGem
		info.Text = if chosen
			then `{GearInfo.gemName(chosen.attribute, chosen.level)}: {GearInfo.gemEffect(
				chosen.attribute,
				chosen.level
			)}` .. `  ·  incrustar custa {Gems.socketCost} Gold`
			else `Incrustar custa {Gems.socketCost} Gold`
	end
	paintStackViews(choiceViews, selectedGem)
	paintButton(gemButton, gemAction)
end

local function refreshFuse()
	local stroke, cellLabel, levelLabel, countLabel = fuseStroke, fuseCellLabel, fuseLevelLabel, fuseCountLabel
	local name, owned, recipe, cost = fuseName, fuseOwned, recipeLabel, fuseCostLabel
	if not stroke or not cellLabel or not levelLabel or not countLabel then
		return
	end
	if not name or not owned or not recipe or not cost then
		return
	end
	local stack = selectedStack
	if stack then
		local color = GearInfo.gemColor(stack.attribute)
		local have = GearSnapshot.gemCount(snapshot, stack.attribute, stack.level)
		stroke.Color = color
		cellLabel.Text = GearInfo.gemShort(stack.attribute)
		cellLabel.TextColor3 = color
		levelLabel.Text = `Nv{stack.level}`
		countLabel.Text = `×{have}`
		name.Text = GearInfo.gemName(stack.attribute, stack.level)
		name.TextColor3 = color
		owned.Text = `No baú: {have}  ·  {GearInfo.gemEffect(stack.attribute, stack.level)} cada`
		local price = Formulas.fuseCost(stack.level)
		if price then
			local result = stack.level + 1
			recipe.Text = `{Gems.fuseCount} × Nv{stack.level} viram 1 {GearInfo.gemName(stack.attribute, result)}`
				.. ` ({GearInfo.gemEffect(stack.attribute, result)})`
			cost.Text = `Custo: {price} Gold`
		else
			recipe.Text = GearInfo.fuseBlockedReason(stack.level)
			cost.Text = ""
		end
	else
		stroke.Color = COLORS.disabled
		cellLabel.Text = "?"
		cellLabel.TextColor3 = COLORS.text
		levelLabel.Text = ""
		countLabel.Text = ""
		name.Text = "Escolha uma gema"
		name.TextColor3 = COLORS.text
		owned.Text = "As gemas do baú estão à esquerda"
		recipe.Text = ""
		cost.Text = ""
	end
	paintStackViews(stackViews, selectedStack)
	paintButton(fuseButton, fuseAction)
end

-- "Gibão do Combatente de Osso +7 (Raro): +2,2 FOR, +1,1 VIT" (como a peça fica com este fortalecimento).
local function pieceAfter(entry: Types.GearEntry, def: Types.GearDef, enhance: number): string
	local rarity: Types.Rarity = entry.rarity
	return `{GearInfo.fullName(def, rarity, enhance)}: {GearInfo.describe(def, rarity, enhance)}`
end

local function refreshTransfer()
	refreshPieceHeader(transferHeader)
	local choose, after, toLine, fromLine, cost = transferChoose, afterLabel, afterTo, afterFrom, transferCostLabel
	if not choose or not after or not toLine or not fromLine or not cost then
		return
	end
	local source, sourceDef = selectedEntry()
	local target, targetDef = transferTarget()
	if not source then
		choose.Text = ""
	elseif #transferTargets() == 0 then
		choose.Text =
			"Nenhuma peça para trocar: precisa ser do mesmo tipo, com outro nível, da mesma torre ou mais baixa"
	else
		choose.Text = "Trocar o fortalecimento com:"
	end
	if source and sourceDef and target and targetDef then
		after.Text = "Depois da troca:"
		toLine.Text = pieceAfter(target, targetDef, source.enhance)
		fromLine.Text = pieceAfter(source, sourceDef, target.enhance)
		cost.Text = `Custo: {Formulas.transferCost(sourceDef, source.enhance, targetDef, target.enhance)} Gold`
	else
		after.Text = ""
		toLine.Text = ""
		fromLine.Text = ""
		cost.Text = ""
	end
	for id, stroke in transferStrokes do
		local entry = GearSnapshot.find(snapshot, id)
		if transferTargetId == id then
			stroke.Color = COLORS.selected
			stroke.Thickness = 3
		elseif entry then
			stroke.Color = GearInfo.rarityColor(entry.rarity)
			stroke.Thickness = 2
		end
	end
	paintButton(transferButton, transferAction)
end

local function refresh()
	local frame = window
	if not frame or not frame.Visible then
		return
	end
	if goldLabel then
		goldLabel.Text = `Gold: {numberAttr(Keys.PlayerAttr.Gold)}`
	end
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then COLORS.tabActive else COLORS.tabIdle
	end
	for id, stroke in pieceStrokes do
		local entry = GearSnapshot.find(snapshot, id)
		if selectedId == id then
			stroke.Color = COLORS.selected
			stroke.Thickness = 3
		elseif entry then
			stroke.Color = GearInfo.rarityColor(entry.rarity)
			stroke.Thickness = 2
		end
	end
	if currentTab == "Enhance" then
		refreshEnhance()
	elseif currentTab == "Gems" then
		refreshGems()
	elseif currentTab == "Transfer" then
		refreshTransfer()
	else
		refreshFuse()
	end
end

-- ===== Grades =====

local function clearGrid(grid: ScrollingFrame)
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

-- Célula de uma peça: sigla do slot, "+N" no canto, a gema e o "E" de equipada. Devolve a borda.
local function makePieceCell(parent: Instance, entry: Types.GearEntry, order: number, onClick: () -> ()): UIStroke
	local def = Gear.byId[entry.defId]
	local cell = Instance.new("TextButton")
	cell.Name = `Item_{entry.id}`
	cell.LayoutOrder = order
	cell.Text = ""
	cell.BackgroundColor3 = COLORS.cell
	cell.Parent = parent
	makeCorner(cell, 6)
	local stroke = makeStroke(cell, GearInfo.rarityColor(entry.rarity))
	local label = makeText(cell, SLOT_SHORT[def.slot], UDim2.fromScale(1, 1), UDim2.new(), 13)
	label.TextXAlignment = Enum.TextXAlignment.Center
	makeBadge(cell, 11).Text = GearInfo.enhanceLabel(entry.enhance)
	setGemMark(makeGemMark(cell, 14), entry.gem)
	if entry.inUse then
		local mark = makeText(cell, "E", UDim2.fromOffset(14, 14), UDim2.new(0, 3, 1, -15), 11)
		mark.Name = "InUse"
		mark.TextColor3 = COLORS.inUse
	end
	cell.Activated:Connect(onClick)
	return stroke
end

-- Aba Transferir: as peças que podem trocar o fortalecimento com a escolhida à esquerda.
local function rebuildTransferGrid()
	local list = transferGrid
	if not list then
		return
	end
	clearGrid(list)
	table.clear(transferStrokes)
	local targets = transferTargets()
	local stillThere = false
	for index, entry in targets do
		local id = entry.id
		stillThere = stillThere or id == transferTargetId
		transferStrokes[id] = makePieceCell(list, entry, index, function()
			if transferTargetId ~= id then
				confirmUntil = 0
			end
			transferTargetId = id
			showMessage("", true)
			refresh()
		end)
	end
	if not stillThere then
		transferTargetId = nil -- a peça de destino não serve mais (vendida, mesmo nível...)
	end
end

local function rebuildPieceGrid()
	local list = pieceGrid
	if not list then
		return
	end
	clearGrid(list)
	table.clear(pieceStrokes)
	for index, entry in orderedEntries() do
		local id = entry.id
		pieceStrokes[id] = makePieceCell(list, entry, index, function()
			if selectedId ~= id then
				confirmUntil = 0
				selectedGem = nil
				transferTargetId = nil
			end
			selectedId = id
			showMessage("", true)
			rebuildTransferGrid()
			refresh()
		end)
	end
end

-- Gemas do baú numa grade (aba Fundir à esquerda; aba Gemas, as opções para incrustar).
local function rebuildStackGrid(grid: ScrollingFrame?, views: { [string]: StackView }, onPick: (gem: Types.Gem) -> ())
	if not grid then
		return
	end
	clearGrid(grid)
	table.clear(views)
	for index, stack in snapshot.gems do
		local gem: Types.Gem = { attribute = stack.attribute, level = stack.level }
		views[gemKey(gem)] = makeStackCell(grid, stack, index, function()
			onPick(gem)
		end)
	end
end

local function rebuildStacks()
	rebuildStackGrid(stackGrid, stackViews, function(gem: Types.Gem)
		selectedStack = gem
		showMessage("", true)
		refresh()
	end)
	rebuildStackGrid(choiceGrid, choiceViews, function(gem: Types.Gem)
		selectedGem = gem
		showMessage("", true)
		refresh()
	end)
	if stackEmptyLabel then
		stackEmptyLabel.Visible = currentTab == "Fuse" and #snapshot.gems == 0
	end
end

-- ===== Ações =====

local function flash(color: Color3)
	local header = enhanceHeader
	if not header then
		return
	end
	header.cell.BackgroundColor3 = color
	TweenService:Create(header.cell, TweenInfo.new(0.6), { BackgroundColor3 = COLORS.cell }):Play()
end

local function onEnhanceClicked()
	local _, _, blocked = enhanceAction()
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

local function onGemClicked()
	local _, _, blocked = gemAction()
	if blocked then
		showMessage(blocked, false)
		return
	end
	local entry, _ = selectedEntry()
	if not entry then
		return
	end
	if entry.gem then
		Remotes.get("ExtractGem"):FireServer(entry.id)
	else
		local chosen = selectedGem
		if chosen then
			Remotes.get("SocketGem"):FireServer(entry.id, chosen.attribute, chosen.level)
		end
	end
end

local function onFuseClicked()
	local _, _, blocked = fuseAction()
	if blocked then
		showMessage(blocked, false)
		return
	end
	local stack = selectedStack
	if stack then
		Remotes.get("FuseGems"):FireServer(stack.attribute, stack.level)
	end
end

-- Troca o fortalecimento das duas peças. Sempre pede um segundo clique (custa Gold; desfazer custa de novo).
local function onTransferClicked()
	local _, _, blocked = transferAction()
	if blocked then
		showMessage(blocked, false)
		return
	end
	local source, _ = selectedEntry()
	local target, _ = transferTarget()
	if not source or not target then
		return
	end
	if os.clock() >= confirmUntil then
		confirmUntil = os.clock() + CONFIRM_WINDOW
		showMessage("", true)
		refresh()
		return
	end
	confirmUntil = 0
	Remotes.get("TransferEnhance"):FireServer(source.id, target.id)
	refresh()
end

local function selectTab(tab: Tab)
	currentTab = tab
	confirmUntil = 0
	for name, side in sides do
		side.Visible = name == tab
	end
	local showStacks = tab == "Fuse"
	if pieceGrid then
		pieceGrid.Visible = not showStacks
	end
	if stackGrid then
		stackGrid.Visible = showStacks
	end
	if leftHeader then
		leftHeader.Text = if showStacks then "Suas gemas (no baú)" else "Suas peças"
	end
	if leftHint then
		leftHint.Text = if showStacks then "×N = quantidade" else "E = equipada"
	end
	if stackEmptyLabel then
		stackEmptyLabel.Visible = showStacks and #snapshot.gems == 0
	end
	clearMessages()
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
		clearMessages()
		rebuildPieceGrid()
		rebuildTransferGrid()
		rebuildStacks()
	end
	refresh()
end

local function forgePosition(): Vector3?
	local lobby = workspace:FindFirstChild("Lobby")
	local counter = lobby and lobby:FindFirstChild("ForgeCounter")
	return if counter and counter:IsA("BasePart") then counter.Position else nil
end

-- ===== Montagem =====

local function makeGrid(parent: Instance, name: string, size: UDim2, position: UDim2): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.Position = position
	list.Size = size
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

local function buildLeftSide(frame: Frame)
	local side =
		makeSection(frame, "PiecesSide", UDim2.fromOffset(LEFT_WIDTH, SIDE_HEIGHT), UDim2.fromOffset(10, TITLE_HEIGHT))
	local header = makeText(side, "Suas peças", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 14)
	header.TextColor3 = COLORS.gold
	leftHeader = header
	local hint = makeText(side, "E = equipada", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 11)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = COLORS.dim
	leftHint = hint
	pieceGrid = makeGrid(side, "Grid", UDim2.new(1, -20, 1, -42), UDim2.fromOffset(10, 32))
	local stacks = makeGrid(side, "GemGrid", UDim2.new(1, -20, 1, -42), UDim2.fromOffset(10, 32))
	stacks.Visible = false
	stackGrid = stacks
	-- Fora da grade (o UIGridLayout espremeria o texto no tamanho de uma célula).
	local empty = makeText(
		side,
		`Nenhuma gema no baú. A gema Nv{Gems.shopLevel} é vendida na loja ({Gems.shopPrice} Gold).`,
		UDim2.new(1, -24, 0, 36),
		UDim2.fromOffset(12, 36),
		12
	)
	empty.Name = "Empty"
	empty.TextColor3 = COLORS.dim
	empty.TextWrapped = true
	empty.Visible = false
	stackEmptyLabel = empty
end

local function makeRightSide(frame: Frame, name: string, tab: Tab): Frame
	local x = 10 + LEFT_WIDTH + 10
	local side = makeSection(
		frame,
		name,
		UDim2.fromOffset(WINDOW_WIDTH - x - 10, SIDE_HEIGHT),
		UDim2.fromOffset(x, TITLE_HEIGHT)
	)
	side.Visible = tab == currentTab
	sides[tab] = side
	return side
end

local function makeBigCell(side: Frame): (Frame, TextLabel, UIStroke)
	local cell = Instance.new("Frame")
	cell.Name = "Selected"
	cell.Size = UDim2.fromOffset(BIG_CELL, BIG_CELL)
	cell.Position = UDim2.fromOffset(14, 14)
	cell.BackgroundColor3 = COLORS.cell
	cell.Parent = side
	makeCorner(cell, 10)
	local stroke = makeStroke(cell, COLORS.disabled)
	local label = makeText(cell, "?", UDim2.fromScale(1, 1), UDim2.new(), 20)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return cell, label, stroke
end

-- Nome e linha de baixo, ao lado da célula grande.
local function makeTitleLines(side: Frame): (TextLabel, TextLabel)
	local textX = 14 + BIG_CELL + 12
	local name = makeText(side, "", UDim2.new(1, -(textX + 10), 0, 22), UDim2.fromOffset(textX, 18), 16)
	name.Name = "PieceName"
	TextFit.shrinkToFit(name, 12) -- nome longo + "+10" encolhe em vez de cortar
	local slot = makeText(side, "", UDim2.new(1, -(textX + 10), 0, 16), UDim2.fromOffset(textX, 44), 12)
	slot.TextColor3 = COLORS.dim
	return name, slot
end

local function buildPieceHeader(side: Frame): PieceHeader
	local cell, label, stroke = makeBigCell(side)
	local name, slot = makeTitleLines(side)
	return {
		cell = cell,
		label = label,
		badge = makeBadge(cell, 16),
		gemMark = makeGemMark(cell, 20),
		stroke = stroke,
		name = name,
		slot = slot,
	}
end

-- Mensagem do servidor; `lines` = linhas que cabem ali (as mensagens das gemas são mais longas).
local function makeMessage(side: Frame, tab: Tab, y: number, lines: number)
	local message = makeText(side, "", UDim2.new(1, -28, 0, 15 * lines + 2), UDim2.fromOffset(14, y), 13)
	message.Name = "Message"
	message.TextWrapped = true
	message.TextYAlignment = Enum.TextYAlignment.Top
	messageLabels[tab] = message
end

local function makeFooter(side: Frame, text: string, lines: number)
	local height = 14 * lines
	local rules = makeText(side, text, UDim2.new(1, -28, 0, height), UDim2.new(0, 14, 1, -(height + 8)), 11)
	rules.TextColor3 = COLORS.dim
	rules.TextWrapped = true
end

local function buildEnhanceSide(frame: Frame)
	local side = makeRightSide(frame, "EnhanceSide", "Enhance")
	enhanceHeader = buildPieceHeader(side)

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
	makeMessage(side, "Enhance", y + 56, 2)
	makeFooter(side, `+1 a +3 nunca falham  ·  falhar do +{Forge.dropOnFailFrom} em diante tira 1 nível`, 1)
end

local function buildGemSide(frame: Frame)
	local side = makeRightSide(frame, "GemSide", "Gems")
	gemHeader = buildPieceHeader(side)

	local line = makeText(side, "", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 108), 15)
	line.Name = "GemLine"
	gemLine = line
	local choose = makeText(side, "", UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, 132), 12)
	choose.Name = "Choose"
	choose.TextColor3 = COLORS.dim
	chooseLabel = choose
	choiceGrid =
		makeGrid(side, "Choices", UDim2.new(1, -28, 0, 2 * CELL_SIZE + CELL_GAP + 2), UDim2.fromOffset(14, 150))
	local info = makeText(side, "", UDim2.new(1, -28, 0, 28), UDim2.fromOffset(14, 252), 12)
	info.Name = "Info"
	info.TextColor3 = COLORS.gold
	info.TextWrapped = true
	info.TextYAlignment = Enum.TextYAlignment.Top
	gemInfo = info

	local button = makeButton(side, "Incrustar", UDim2.new(1, -28, 0, 40), UDim2.fromOffset(14, 284), COLORS.button)
	button.Name = "GemButton"
	button.TextSize = 18
	button.Activated:Connect(onGemClicked)
	gemButton = button
	makeMessage(side, "Gems", 326, 2)
	makeFooter(side, "1 gema por peça  ·  para trocar de gema, extraia antes", 1)
end

local function buildFuseSide(frame: Frame)
	local side = makeRightSide(frame, "FuseSide", "Fuse")
	local cell, label, stroke = makeBigCell(side)
	fuseStroke = stroke
	fuseCellLabel = label
	local level = makeBadge(cell, 14)
	level.TextColor3 = COLORS.text
	fuseLevelLabel = level
	local count = makeText(cell, "", UDim2.new(1, -6, 0, 16), UDim2.new(0, 0, 1, -18), 13)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = COLORS.dim
	fuseCountLabel = count
	local name, owned = makeTitleLines(side)
	name.Name = "GemName"
	fuseName = name
	fuseOwned = owned

	local recipe = makeText(side, "", UDim2.new(1, -28, 0, 36), UDim2.fromOffset(14, 114), 14)
	recipe.Name = "Recipe"
	recipe.TextWrapped = true
	recipe.TextYAlignment = Enum.TextYAlignment.Top
	recipeLabel = recipe
	local cost = makeText(side, "", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 156), 15)
	cost.Name = "Cost"
	cost.TextColor3 = COLORS.gold
	fuseCostLabel = cost

	local button = makeButton(side, "Fundir", UDim2.new(1, -28, 0, 44), UDim2.fromOffset(14, 188), COLORS.button)
	button.Name = "FuseButton"
	button.TextSize = 18
	button.Activated:Connect(onFuseClicked)
	fuseButton = button
	makeMessage(side, "Fuse", 240, 2)

	local fusions: { string } = {}
	for fromLevel = 1, Gems.maxLevel do
		local price = Gems.fuseCost[fromLevel]
		if price then
			table.insert(fusions, `de Nv{fromLevel} para Nv{fromLevel + 1} ({price} Gold)`)
		end
	end
	makeFooter(
		side,
		`{Gems.fuseCount} gemas iguais (nível e atributo) viram 1 do nível seguinte. Fusões: `
			.. `{table.concat(fusions, " e ")}. A gema Nv{Gems.shopLevel} da loja não funde.`,
		3
	)
end

local function buildTransferSide(frame: Frame)
	local side = makeRightSide(frame, "TransferSide", "Transfer")
	transferHeader = buildPieceHeader(side)

	-- Duas linhas quando não há peça compatível (a grade logo abaixo fica vazia nesse caso).
	local choose = makeText(side, "", UDim2.new(1, -28, 0, 30), UDim2.fromOffset(14, 108), 12)
	choose.Name = "Choose"
	choose.TextColor3 = COLORS.dim
	choose.TextWrapped = true
	choose.TextYAlignment = Enum.TextYAlignment.Top
	transferChoose = choose
	-- Uma linha de peças à vista (rola se houver mais).
	transferGrid = makeGrid(side, "Targets", UDim2.new(1, -28, 0, CELL_SIZE + 4), UDim2.fromOffset(14, 126))

	local after = makeText(side, "", UDim2.new(1, -28, 0, 14), UDim2.fromOffset(14, 180), 12)
	after.Name = "After"
	after.TextColor3 = COLORS.dim
	afterLabel = after
	local function previewLine(lineName: string, y: number, color: Color3): TextLabel
		local text = makeText(side, "", UDim2.new(1, -28, 0, 30), UDim2.fromOffset(14, y), 12)
		text.Name = lineName
		text.TextColor3 = color
		text.TextWrapped = true
		text.TextYAlignment = Enum.TextYAlignment.Top
		return text
	end
	afterTo = previewLine("AfterTarget", 196, COLORS.ok)
	afterFrom = previewLine("AfterSource", 228, COLORS.text)
	local cost = makeText(side, "", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 262), 15)
	cost.Name = "Cost"
	cost.TextColor3 = COLORS.gold
	transferCostLabel = cost

	local button = makeButton(side, "Transferir", UDim2.new(1, -28, 0, 40), UDim2.fromOffset(14, 284), COLORS.button)
	button.Name = "TransferButton"
	button.TextSize = 18
	button.Activated:Connect(onTransferClicked)
	transferButton = button
	makeMessage(side, "Transfer", 328, 2)
	makeFooter(side, "Mesmo tipo de peça  ·  só para torre igual ou menor", 1)
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
	makeCorner(frame, 12)
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
	local tabs: { { tab: Tab, name: string, text: string } } = {
		{ tab = "Enhance", name = "EnhanceTab", text = "Fortalecer" },
		{ tab = "Transfer", name = "TransferTab", text = "Transferir" },
		{ tab = "Gems", name = "GemsTab", text = "Gemas" },
		{ tab = "Fuse", name = "FuseTab", text = "Fundir" },
	}
	for index, info in tabs do
		local x = 90 + (index - 1) * 102
		local button = makeButton(frame, info.text, UDim2.fromOffset(96, 30), UDim2.fromOffset(x, 9), COLORS.tabIdle)
		button.Name = info.name
		button.TextSize = 14
		local tab: Tab = info.tab -- anotado: sem isso o verificador alarga para `string`
		button.Activated:Connect(function()
			selectTab(tab)
		end)
		tabButtons[tab] = button
	end
	local gold = makeText(frame, "Gold: 0", UDim2.fromOffset(160, 28), UDim2.new(1, -212, 0, 10), 16)
	gold.TextColor3 = COLORS.gold
	gold.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel = gold
	local close = makeButton(frame, "X", UDim2.fromOffset(32, 32), UDim2.new(1, -42, 0, 8), COLORS.disabled)
	close.Name = "Close"
	close.Activated:Connect(function()
		setOpen(false)
	end)

	buildLeftSide(frame)
	buildEnhanceSide(frame)
	buildGemSide(frame)
	buildFuseSide(frame)
	buildTransferSide(frame)
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
	if ok and currentTab == "Transfer" then
		-- Trocou: tira a escolha do destino (senão a prévia mostraria a troca de volta).
		transferTargetId = nil
		rebuildTransferGrid()
	end
	refresh()
end

-- A escolha ainda existe no baú? (Some quando a pilha acaba: gema incrustada ou fundida.)
local function stillInChest(gem: Types.Gem?): Types.Gem?
	if gem and GearSnapshot.gemCount(snapshot, gem.attribute, gem.level) > 0 then
		return gem
	end
	return nil
end

local function onGearDataChanged()
	snapshot = GearSnapshot.decode(localPlayer:GetAttribute(Keys.PlayerAttr.GearData))
	if selectedId ~= nil and GearSnapshot.find(snapshot, selectedId) == nil then
		selectedId = nil -- a peça saiu da conta (ex.: vendida)
	end
	selectedGem = stillInChest(selectedGem)
	selectedStack = stillInChest(selectedStack)
	if window and window.Visible then
		rebuildPieceGrid()
		rebuildTransferGrid()
		rebuildStacks()
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
