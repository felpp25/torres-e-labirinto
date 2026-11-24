--!strict
-- NPCs do lobby (GDD > Missão e história): o Observador (Crônicas), Ariadne, Brokk e Tanu (missão). Modelos greybox
-- montados por código em workspace.Lobby.Npcs, cada um com um ProximityPrompt "Falar" (tecla F, como os balcões).
-- Falar é validado aqui (vivo, fora da torre, perto, sem spam); o StoryService ou o MissionService decide o que
-- mostrar e já conta o progresso; o cliente só mostra a conversa (Remote NpcDialogue).
-- O "!" em cima de quem tem algo novo é do cliente (lê os Attributes da história e da missão).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Npcs = require(Shared.Story.Npcs)

local StoryService = require(script.Parent.StoryService)
local MissionService = require(script.Parent.MissionService)

local PROMPT_RANGE = 8 -- studs
local TALK_TOLERANCE = 4 -- studs a mais na validação (rede)
local TALK_COOLDOWN = 0.5 -- s entre conversas do mesmo jogador
local PROMPT_NAME = "NpcPrompt"
local LOOK_AT = Vector3.new(0, 0, 80) -- os NPCs olham para o spawn do lobby (Círculo Rúnico, LobbyService)

-- Onde cada um fica no Lobby 1 (chão em y = 0; GDD > Lobby e loja). Tanu e Brokk na ponta mais longe dos balcões
-- (loja e Forja de Cristal, no Mercado das Raízes, LobbyService): quem chega pelo lado da nave fica mais perto do
-- balcão, e o F abre a janela, não a conversa. Ariadne na avenida, entre as entradas das duas torres, fora do caminho
-- reto spawn -> altar. O Observador ao pé do Altar do Coração.
local POSITIONS: { [string]: Vector3 } = {
	Tanu = Vector3.new(89.5, 0, 100),
	Brokk = Vector3.new(124.5, 0, 140),
	Ariadne = Vector3.new(12, 0, 0),
	Observer = Vector3.new(-14, 0, -72),
}

local NpcService = {}

local lastTalkAt: { [Player]: number } = {}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function ball(name: string, diameter: number, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = makePart(name, Vector3.one * diameter, cframe, color, parent)
	part.Shape = Enum.PartType.Ball
	return part
end

local function nameTag(head: BasePart, def: Npcs.NpcDef)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(180, 40)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 60
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.6)
	name.BackgroundTransparency = 1
	name.Text = def.displayName
	name.TextColor3 = def.color
	name.TextStrokeTransparency = 0.2
	name.TextScaled = true
	name.Font = Enum.Font.GothamBlack
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.4)
	title.Position = UDim2.fromScale(0, 0.6)
	title.BackgroundTransparency = 1
	title.Text = def.title
	title.TextColor3 = Color3.fromRGB(220, 220, 230)
	title.TextStrokeTransparency = 0.3
	title.TextScaled = true
	title.Font = Enum.Font.GothamMedium
	title.Parent = gui
end

-- Pessoa greybox: pernas, corpo e cabeça. `scale` < 1 = mais baixo (Brokk). Devolve o corpo e a cabeça.
local function person(
	model: Model,
	base: CFrame,
	scale: number,
	width: number,
	bodyColor: Color3,
	legColor: Color3,
	skin: Color3
): (Part, Part)
	local legH = 2 * scale
	local bodyH = 2.6 * scale
	makePart("Legs", Vector3.new(1.6 * width, legH, 1), base * CFrame.new(0, legH / 2, 0), legColor, model)
	local body = makePart(
		"Body",
		Vector3.new(2.2 * width, bodyH, 1.2 * width),
		base * CFrame.new(0, legH + bodyH / 2, 0),
		bodyColor,
		model
	)
	body.CanCollide = true
	local head = ball("Head", 1.5, base * CFrame.new(0, legH + bodyH + 0.75, 0), skin, model)
	return body, head
end

local BUILDERS: { [string]: (model: Model, base: CFrame) -> (Part, Part) } = {
	-- Túnica branca e dourada; o carretel de fio vermelho do mito na mão.
	Ariadne = function(model: Model, base: CFrame): (Part, Part)
		local body, head = person(
			model,
			base,
			1,
			1,
			Color3.fromRGB(235, 228, 205),
			Color3.fromRGB(200, 170, 90),
			Color3.fromRGB(225, 185, 150)
		)
		makePart(
			"Hair",
			Vector3.new(1.6, 1.4, 0.6),
			head.CFrame * CFrame.new(0, 0.1, 0.55),
			Color3.fromRGB(80, 50, 30),
			model
		)
		local spool = makePart(
			"Spool",
			Vector3.new(0.6, 0.6, 0.6),
			body.CFrame * CFrame.new(1.4, -0.4, -0.4),
			Color3.fromRGB(200, 40, 40),
			model
		)
		spool.Shape = Enum.PartType.Cylinder
		return body, head
	end,
	-- Anão: baixo e largo, barba ruiva e avental de couro.
	Brokk = function(model: Model, base: CFrame): (Part, Part)
		local body, head = person(
			model,
			base,
			0.75,
			1.3,
			Color3.fromRGB(95, 70, 50),
			Color3.fromRGB(60, 50, 45),
			Color3.fromRGB(215, 170, 135)
		)
		makePart(
			"Beard",
			Vector3.new(1.2, 1.1, 0.4),
			head.CFrame * CFrame.new(0, -0.6, -0.6),
			Color3.fromRGB(190, 80, 30),
			model
		)
		makePart(
			"Apron",
			Vector3.new(1.8, 1.6, 0.2),
			body.CFrame * CFrame.new(0, -0.1, -1.0),
			Color3.fromRGB(70, 45, 30),
			model
		)
		return body, head
	end,
	-- Tanuki: corpo marrom redondo, máscara escura nos olhos, orelhas e chapéu de palha.
	Tanu = function(model: Model, base: CFrame): (Part, Part)
		local brown = Color3.fromRGB(140, 100, 65)
		local body, head = person(model, base, 0.9, 1.2, brown, Color3.fromRGB(70, 50, 35), brown)
		makePart(
			"Belly",
			Vector3.new(1.6, 1.6, 0.2),
			body.CFrame * CFrame.new(0, -0.2, -0.75),
			Color3.fromRGB(215, 190, 150),
			model
		)
		makePart(
			"Mask",
			Vector3.new(1.3, 0.4, 0.2),
			head.CFrame * CFrame.new(0, 0.1, -0.7),
			Color3.fromRGB(35, 25, 20),
			model
		)
		makePart(
			"EarL",
			Vector3.new(0.4, 0.4, 0.3),
			head.CFrame * CFrame.new(-0.55, 0.75, 0),
			Color3.fromRGB(70, 50, 35),
			model
		)
		makePart(
			"EarR",
			Vector3.new(0.4, 0.4, 0.3),
			head.CFrame * CFrame.new(0.55, 0.75, 0),
			Color3.fromRGB(70, 50, 35),
			model
		)
		local hat = makePart(
			"Hat",
			Vector3.new(0.3, 2.6, 2.6),
			head.CFrame * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(215, 180, 110),
			model
		)
		hat.Shape = Enum.PartType.Cylinder
		return body, head
	end,
	-- Manto longo e capuz com o rosto na sombra, olhos de Mana (ciano), partículas e um anel da Fenda (roxo) no chão.
	-- Flutua um pouco acima do chão.
	Observer = function(model: Model, base: CFrame): (Part, Part)
		local cloak = Color3.fromRGB(22, 20, 40)
		local float = base * CFrame.new(0, 1, 0)
		local robe = makePart("Body", Vector3.new(2.6, 5, 1.8), float * CFrame.new(0, 2.5, 0), cloak, model)
		robe.Material = Enum.Material.Fabric
		robe.CanCollide = true
		local hood = ball("Head", 2.1, float * CFrame.new(0, 5.6, 0), cloak, model)
		hood.Material = Enum.Material.Fabric
		makePart(
			"Face",
			Vector3.new(1.3, 1.1, 0.2),
			hood.CFrame * CFrame.new(0, -0.05, -0.95),
			Color3.new(0, 0, 0),
			model
		)
		local mana = Color3.fromRGB(90, 220, 255)
		for _, x in { -0.3, 0.3 } do
			local eye = ball("Eye", 0.25, hood.CFrame * CFrame.new(x, 0.05, -1.08), mana, model)
			eye.Material = Enum.Material.Neon
		end
		for index, offset in { Vector3.new(-2.2, 4.2, 0), Vector3.new(2.2, 3.4, 0.6) } do
			local orb = ball(`Orb{index}`, 0.45, float * CFrame.new(offset), mana, model)
			orb.Material = Enum.Material.Neon
		end
		local ring = makePart(
			"Ring",
			Vector3.new(0.1, 5, 5),
			base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(150, 70, 230),
			model
		)
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.5
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(mana)
		sparks.LightEmission = 1
		sparks.Rate = 6
		sparks.Lifetime = NumberRange.new(1.5, 2.5)
		sparks.Speed = NumberRange.new(0.3, 0.8)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new(0.15)
		sparks.Parent = robe
		local light = Instance.new("PointLight")
		light.Color = mana
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = hood
		return robe, hood
	end,
}

local function isNear(player: Player, position: Vector3, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
	return flat.Magnitude <= range and math.abs(root.Position.Y - position.Y) < 12
end

local function onTalk(player: Player, npcId: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or player:GetAttribute(Keys.InRunAttr) == true then
		return
	end
	local position = POSITIONS[npcId]
	if not position or not isNear(player, position, PROMPT_RANGE + TALK_TOLERANCE) then
		return
	end
	local now = os.clock()
	if now - (lastTalkAt[player] or 0) < TALK_COOLDOWN then
		return
	end
	lastTalkAt[player] = now
	local payload: Remotes.NpcDialoguePayload? = if npcId == "Observer"
		then StoryService.talk(player)
		else MissionService.talk(player, npcId)
	if payload then
		Remotes.get("NpcDialogue"):FireClient(player, payload)
	end
end

local function build()
	local lobby = workspace:FindFirstChild("Lobby")
	assert(lobby, "NpcService: o lobby precisa existir antes (LobbyService.init)")
	local folder = Instance.new("Folder")
	folder.Name = "Npcs"
	folder.Parent = lobby
	for _, def in Npcs.list do
		local position = POSITIONS[def.id]
		local builder = BUILDERS[def.id]
		assert(position and builder, `NpcService: falta posição ou modelo para {def.id}`)
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("NpcId", def.id)
		local facing = Vector3.new(LOOK_AT.X, position.Y, LOOK_AT.Z)
		local base = CFrame.lookAt(position, facing)
		local body, head = builder(model, base)
		model.PrimaryPart = body
		nameTag(head, def)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Falar"
		prompt.ObjectText = def.displayName
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PROMPT_RANGE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
		prompt.Parent = body
		local npcId = def.id
		prompt.Triggered:Connect(function(player: Player)
			onTalk(player, npcId)
		end)
		model.Parent = folder
	end
end

function NpcService.init()
	build()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTalkAt[player] = nil
	end)
end

function NpcService.start() end

return NpcService
