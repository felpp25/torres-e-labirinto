--!strict
-- Conversa com os NPCs do lobby (GDD > Missão e história). O servidor decide o que mostrar (Remote NpcDialogue) e já
-- contou o progresso da missão; aqui só a tela:
-- - caixa embaixo com o nome de quem fala e efeito de máquina de escrever; avança com clique, toque, Espaço, Enter ou
--   o botão A (durante a digitação, mostra a fala inteira);
-- - "Pular" só quando o servidor deixa (não na 1ª vez de um capítulo nem de uma etapa da missão);
-- - a câmera fecha no rosto do NPC; o personagem fica parado e invisível (só para o próprio jogador: ele ficava entre a
--   câmera e o NPC) e os prompts somem enquanto a conversa está aberta;
-- - o Observador sem nada novo abre o menu das Crônicas: rever qualquer capítulo liberado (com "Pular").
-- As cutscenes das Crônicas (cenas e cenários) entram depois, por cima desta caixa.

local Players: Players = game:GetService("Players")
local ProximityPromptService: ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService: TweenService = game:GetService("TweenService")
local UserInputService: UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Story = Shared:WaitForChild("Story")
local Npcs = require(Story:WaitForChild("Npcs"))
local Dialogues = require(Story:WaitForChild("Dialogues"))
local Chronicles = require(Story:WaitForChild("Chronicles"))

local ChatBlocker = require(script.Parent.Parent:WaitForChild("ChatBlocker"))

local localPlayer = Players.LocalPlayer

local CHARS_PER_SECOND = 45
local CAMERA_DISTANCE = 8 -- studs à frente do NPC
local CAMERA_TWEEN = 0.5 -- s
local PANEL_HEIGHT = 150
local CHAT_OWNER = "Dialogue"

local COLORS = {
	panel = Color3.fromRGB(16, 16, 24),
	stroke = Color3.fromRGB(90, 220, 255),
	text = Color3.fromRGB(240, 240, 245),
	dim = Color3.fromRGB(160, 160, 175),
	button = Color3.fromRGB(45, 45, 60),
	gold = Color3.fromRGB(255, 205, 70),
}

type Conversation = {
	npc: string,
	lines: { string },
	subtitle: string?,
	canSkip: boolean,
	index: number,
	fromMenu: boolean, -- capítulo aberto pelo menu: ao terminar, volta para o menu
}

type Ui = {
	gui: ScreenGui,
	panel: TextButton,
	name: TextLabel,
	subtitle: TextLabel,
	text: TextLabel,
	hint: TextLabel,
	counter: TextLabel,
	skip: TextButton,
	menu: Frame,
	menuList: Frame,
}

local DialogueController = {}

local ui: Ui? = nil
local current: Conversation? = nil
local menuOpen = false
local typing = false
local typingToken = 0 -- muda a cada fala: cancela a digitação da anterior
local savedCameraType: Enum.CameraType? = nil
local frozen = false

-- ===== Personagem parado, prompts e chat escondidos, câmera no NPC =====

local function getControls(): any
	local playerScripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall(require, module)
	if not ok or playerModule == nil then
		return nil
	end
	return (playerModule :: any):GetControls()
end

-- Esconde o próprio personagem só na tela deste jogador (LocalTransparencyModifier não replica).
local function setCharacterHidden(hidden: boolean)
	local character = localPlayer.Character
	if not character then
		return
	end
	local value = if hidden then 1 else 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			-- As duas classes têm LocalTransparencyModifier; o verificador não aceita a propriedade na união.
			(descendant :: any).LocalTransparencyModifier = value
		end
	end
end

local function setFrozen(value: boolean)
	if frozen == value then
		return
	end
	frozen = value
	localPlayer:SetAttribute(Keys.DialogueOpenAttr, value)
	setCharacterHidden(value)
	local controls = getControls()
	if controls then
		if value then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	ProximityPromptService.Enabled = not value
	ChatBlocker.setHidden(CHAT_OWNER, value)
end

local function focusCamera(npcId: string)
	local camera = workspace.CurrentCamera
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Npcs")
	local model = folder and folder:FindFirstChild(npcId)
	local head = model and model:FindFirstChild("Head")
	local body = if model and model:IsA("Model") then model.PrimaryPart else nil
	if not camera or not head or not head:IsA("BasePart") or not body then
		return
	end
	if savedCameraType == nil then
		savedCameraType = camera.CameraType
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local facing = body.CFrame
	local eye = head.Position + facing.LookVector * CAMERA_DISTANCE + facing.RightVector * 2 + Vector3.new(0, 0.8, 0)
	-- Olha um pouco abaixo da cabeça: o rosto fica acima da caixa de conversa.
	local target = CFrame.lookAt(eye, head.Position - Vector3.new(0, 0.6, 0))
	local info = TweenInfo.new(CAMERA_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(camera, info, { CFrame = target }):Play()
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	if camera and savedCameraType then
		camera.CameraType = savedCameraType
	end
	savedCameraType = nil
end

-- ===== Conversa =====

local function finishTyping()
	local view = ui
	if not view then
		return
	end
	typingToken += 1
	typing = false
	view.text.MaxVisibleGraphemes = -1
	view.hint.Visible = true
end

local function showLine()
	local view, conversation = ui, current
	if not view or not conversation then
		return
	end
	local line = conversation.lines[conversation.index]
	view.text.Text = line
	view.text.MaxVisibleGraphemes = 0
	view.counter.Text = `{conversation.index}/{#conversation.lines}`
	view.hint.Visible = false
	typingToken += 1
	local token = typingToken
	typing = true
	local total = utf8.len(line) or #line
	task.spawn(function()
		local shown = 0
		while shown < total and token == typingToken do
			shown += 1
			view.text.MaxVisibleGraphemes = shown
			task.wait(1 / CHARS_PER_SECOND)
		end
		if token == typingToken then
			finishTyping()
		end
	end)
end

local openMenu: () -> ()

local function closeAll()
	local view = ui
	current = nil
	menuOpen = false
	typingToken += 1
	typing = false
	if view then
		view.panel.Visible = false
		view.menu.Visible = false
	end
	restoreCamera()
	setFrozen(false)
end

local function endConversation()
	local conversation = current
	current = nil
	local view = ui
	if view then
		view.panel.Visible = false
	end
	if conversation and conversation.fromMenu then
		openMenu()
	else
		closeAll()
	end
end

local function advance()
	local conversation = current
	if not conversation then
		return
	end
	if typing then
		finishTyping()
		return
	end
	if conversation.index < #conversation.lines then
		conversation.index += 1
		showLine()
	else
		endConversation()
	end
end

local function open(conversation: Conversation)
	local view = ui
	local npc = Npcs.byId[conversation.npc]
	if not view or not npc then
		return
	end
	current = conversation
	menuOpen = false
	view.menu.Visible = false
	view.name.Text = npc.displayName
	view.name.TextColor3 = npc.color
	view.subtitle.Text = conversation.subtitle or npc.title
	view.skip.Visible = conversation.canSkip
	view.panel.Visible = true
	setFrozen(true)
	focusCamera(conversation.npc)
	showLine()
end

-- ===== Menu das Crônicas (o Observador sem nada novo) =====

local function unlockedChapters(): { number }
	local raw = localPlayer:GetAttribute(Keys.ChaptersUnlockedAttr)
	local ids: { number } = {}
	if typeof(raw) == "string" then
		for piece in string.gmatch(raw, "%d+") do
			local id = tonumber(piece)
			if id and Chronicles.byId[id] then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

local function makeButton(parent: Instance, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 40)
	button.LayoutOrder = order
	button.BackgroundColor3 = COLORS.button
	button.TextColor3 = COLORS.text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.Parent = button
	return button
end

function openMenu()
	local view = ui
	if not view then
		return
	end
	current = nil
	menuOpen = true
	view.panel.Visible = false
	for _, child in view.menuList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for order, id in unlockedChapters() do
		local chapter = Chronicles.byId[id]
		local button = makeButton(view.menuList, `Capítulo {chapter.id} · {chapter.title}`, order)
		button.Name = `Chapter_{chapter.id}`
		button.Activated:Connect(function()
			open({
				npc = "Observer",
				lines = chapter.lines,
				subtitle = `Capítulo {chapter.id} · {chapter.title}`,
				canSkip = true,
				index = 1,
				fromMenu = true,
			})
		end)
	end
	local close = makeButton(view.menuList, "Fechar", 1000)
	close.Name = "Close"
	close.TextXAlignment = Enum.TextXAlignment.Center
	close.BackgroundColor3 = Color3.fromRGB(70, 45, 45)
	close.Activated:Connect(closeAll)
	view.menu.Visible = true
	setFrozen(true)
	focusCamera("Observer")
end

-- ===== Remote =====

local function onDialogue(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local npc = data.npc
	if typeof(npc) ~= "string" or not Npcs.byId[npc] then
		return
	end
	if data.menu == true then
		openMenu()
		return
	end
	local canSkip = data.canSkip == true
	local chapterId = data.chapter
	local dialogueId = data.dialogue
	if typeof(chapterId) == "number" then
		local chapter = Chronicles.byId[chapterId]
		if chapter then
			open({
				npc = npc,
				lines = chapter.lines,
				subtitle = `Capítulo {chapter.id} · {chapter.title}`,
				canSkip = canSkip,
				index = 1,
				fromMenu = false,
			})
		end
	elseif typeof(dialogueId) == "string" then
		local dialogue = Dialogues[dialogueId]
		if dialogue then
			open({ npc = dialogue.npc, lines = dialogue.lines, canSkip = canSkip, index = 1, fromMenu = false })
		end
	end
end

-- ===== Tela =====

local function makeText(parent: Instance, size: UDim2, position: UDim2, textSize: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.text
	label.TextSize = textSize
	label.Font = font
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = parent
	return label
end

local function build(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DialogueGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8 -- acima das janelas (loja e Forja 6) e do HUD
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("TextButton")
	panel.Name = "Panel"
	panel.Text = ""
	panel.AutoButtonColor = false
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -16)
	panel.Size = UDim2.new(1, -32, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0 -- opaco: a barra de ações fica embaixo da caixa
	panel.Visible = false
	panel.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(760, PANEL_HEIGHT)
	limit.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.stroke
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = panel

	local name = makeText(panel, UDim2.new(1, -140, 0, 24), UDim2.fromOffset(18, 10), 20, Enum.Font.GothamBlack)
	name.Name = "Speaker"
	local subtitle = makeText(panel, UDim2.new(1, -140, 0, 16), UDim2.fromOffset(18, 34), 13, Enum.Font.GothamMedium)
	subtitle.Name = "Subtitle"
	subtitle.TextColor3 = COLORS.dim
	local text = makeText(panel, UDim2.new(1, -36, 0, 64), UDim2.fromOffset(18, 56), 18, Enum.Font.GothamMedium)
	text.Name = "Line"
	text.TextWrapped = true
	local hint = makeText(panel, UDim2.fromOffset(240, 16), UDim2.new(1, -18, 1, -10), 12, Enum.Font.GothamMedium)
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextYAlignment = Enum.TextYAlignment.Bottom
	hint.TextColor3 = COLORS.gold
	hint.Text = "toque para continuar"
	local counter = makeText(panel, UDim2.fromOffset(80, 16), UDim2.new(0, 18, 1, -10), 12, Enum.Font.GothamMedium)
	counter.Name = "Counter"
	counter.AnchorPoint = Vector2.new(0, 1)
	counter.TextYAlignment = Enum.TextYAlignment.Bottom
	counter.TextColor3 = COLORS.dim

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -14, 0, 12)
	skip.Size = UDim2.fromOffset(96, 30)
	skip.BackgroundColor3 = COLORS.button
	skip.TextColor3 = COLORS.text
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 14
	skip.Text = "Pular"
	skip.Visible = false
	skip.Parent = panel
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip

	-- Menu das Crônicas
	local menu = Instance.new("Frame")
	menu.Name = "ChroniclesMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.5)
	menu.Size = UDim2.new(1, -32, 0, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundColor3 = COLORS.panel
	menu.BackgroundTransparency = 0.06
	menu.Visible = false
	menu.Parent = gui
	local menuLimit = Instance.new("UISizeConstraint")
	menuLimit.MaxSize = Vector2.new(440, 640)
	menuLimit.Parent = menu
	local menuCorner = Instance.new("UICorner")
	menuCorner.CornerRadius = UDim.new(0, 12)
	menuCorner.Parent = menu
	local menuStroke = stroke:Clone()
	menuStroke.Parent = menu
	local menuPadding = Instance.new("UIPadding")
	menuPadding.PaddingTop = UDim.new(0, 14)
	menuPadding.PaddingBottom = UDim.new(0, 14)
	menuPadding.PaddingLeft = UDim.new(0, 14)
	menuPadding.PaddingRight = UDim.new(0, 14)
	menuPadding.Parent = menu
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 8)
	menuLayout.Parent = menu
	local menuTitle = makeText(menu, UDim2.new(1, 0, 0, 24), UDim2.new(), 18, Enum.Font.GothamBlack)
	menuTitle.Name = "Title"
	menuTitle.LayoutOrder = 0
	menuTitle.TextColor3 = COLORS.stroke
	menuTitle.Text = "Crônicas do Observador"
	local menuHint = makeText(menu, UDim2.new(1, 0, 0, 16), UDim2.new(), 13, Enum.Font.GothamMedium)
	menuHint.Name = "Hint"
	menuHint.LayoutOrder = 1
	menuHint.TextColor3 = COLORS.dim
	menuHint.Text = "Escolha um capítulo para ouvir de novo."
	local menuList = Instance.new("Frame")
	menuList.Name = "List"
	menuList.LayoutOrder = 2
	menuList.Size = UDim2.fromScale(1, 0)
	menuList.AutomaticSize = Enum.AutomaticSize.Y
	menuList.BackgroundTransparency = 1
	menuList.Parent = menu
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = menuList

	panel.Activated:Connect(advance)
	skip.Activated:Connect(endConversation)

	return {
		gui = gui,
		panel = panel,
		name = name,
		subtitle = subtitle,
		text = text,
		hint = hint,
		counter = counter,
		skip = skip,
		menu = menu,
		menuList = menuList,
	}
end

function DialogueController.init()
	ui = build()
	Remotes.get("NpcDialogue").OnClientEvent:Connect(onDialogue)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not current then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			advance()
		end
	end)
	-- Morreu, renasceu ou entrou na torre no meio da conversa: fecha tudo.
	localPlayer.CharacterAdded:Connect(function()
		if current or menuOpen then
			closeAll()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Keys.InRunAttr):Connect(function()
		if current or menuOpen then
			closeAll()
		end
	end)
end

function DialogueController.start() end

return DialogueController
