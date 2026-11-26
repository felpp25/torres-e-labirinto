--!strict
-- Missão no HUD e o "!" dos NPCs (GDD > Missão e história). Só lê Attributes do jogador: o MissionService publica a
-- etapa e o contador de cada missão; o StoryService, os capítulos liberados e ouvidos. O servidor conta tudo.
-- - Quadro no canto direito: o nome da missão e o objetivo atual ("Derrote o Golem de Obsidiana e Magma (2/4)", "Fale com
--   Tanu, na loja"); pisca em dourado quando a etapa muda; some sem missão ou com ela concluída.
-- - "!" dourado em cima de quem tem algo novo: o Observador com capítulo liberado e não ouvido; o NPC da etapa atual.
-- O jogo usa Streaming: as peças dos NPCs chegam (e saem) aos poucos. O "!" é criado quando a cabeça chega e de novo
-- se ela sair e voltar (medido: no começo do jogo as cabeças ainda não tinham chegado e o "!" não aparecia).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService: TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))
local Missions = require(Shared:WaitForChild("Balance"):WaitForChild("Missions"))
local Npcs = require(Shared:WaitForChild("Story"):WaitForChild("Npcs"))

local localPlayer = Players.LocalPlayer

local COLORS = {
	panel = Color3.fromRGB(16, 16, 24),
	flash = Color3.fromRGB(110, 85, 20),
	gold = Color3.fromRGB(255, 205, 70),
	text = Color3.fromRGB(240, 240, 245),
}
local MARKER_NAME = "NewsMarker"
local NPC_WAIT = 30 -- s esperando os NPCs do lobby aparecerem

type Tracker = { frame: Frame, title: TextLabel, objective: TextLabel }

local MissionController = {}

local tracker: Tracker? = nil
local markers: { [string]: BillboardGui } = {}
local shownStep: { [string]: number } = {}

local function idList(attribute: string): { number }
	local raw = localPlayer:GetAttribute(attribute)
	local ids: { number } = {}
	if typeof(raw) == "string" then
		for piece in string.gmatch(raw, "%d+") do
			local id = tonumber(piece)
			if id then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-- Etapa atual de cada missão em andamento (nil = sem missão ou concluída).
local function currentStep(def: Missions.MissionDef): (Missions.MissionStep?, number, number)
	local step = localPlayer:GetAttribute(Keys.missionAttr(def.id, "Step"))
	local count = localPlayer:GetAttribute(Keys.missionAttr(def.id, "Count"))
	local done = localPlayer:GetAttribute(Keys.missionAttr(def.id, "Done"))
	if typeof(step) ~= "number" or done == true then
		return nil, 0, 0
	end
	return def.steps[step], step, if typeof(count) == "number" then count else 0
end

local function objectiveText(step: Missions.MissionStep, count: number): string
	if step.kind == "Talk" or step.kind == "Chapter" then
		local npc = if step.npc then Npcs.byId[step.npc] else nil
		return if npc then `{step.objective}, {npc.place}` else step.objective
	elseif step.kind == "Enhance" then
		return `{step.objective} (+{count}/+{step.target})`
	elseif step.target > 1 then
		return `{step.objective} ({count}/{step.target})`
	end
	return step.objective
end

local function npcsWithNews(): { [string]: boolean }
	local news: { [string]: boolean } = {}
	local seen = idList(Keys.ChaptersSeenAttr)
	for _, id in idList(Keys.ChaptersUnlockedAttr) do
		if not table.find(seen, id) then
			news.Observer = true
		end
	end
	for _, def in Missions.list do
		local step = currentStep(def)
		if step and (step.kind == "Talk" or step.kind == "Chapter") and step.npc then
			news[step.npc] = true
		end
	end
	return news
end

local function flash(view: Tracker)
	view.frame.BackgroundColor3 = COLORS.flash
	local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(view.frame, info, { BackgroundColor3 = COLORS.panel }):Play()
end

local function refresh()
	local view = tracker
	if view then
		local visible = false
		for _, def in Missions.list do
			local step, index, count = currentStep(def)
			if step and not visible then
				visible = true
				view.title.Text = string.upper(def.displayName)
				view.objective.Text = objectiveText(step, count)
				if shownStep[def.id] ~= nil and shownStep[def.id] ~= index then
					flash(view)
				end
			end
			shownStep[def.id] = index
		end
		view.frame.Visible = visible
	end
	local news = npcsWithNews()
	for npcId, marker in markers do
		marker.Enabled = news[npcId] == true
	end
end

local function addMarker(model: Instance)
	local npcId = model:GetAttribute("NpcId")
	local head = model:FindFirstChild("Head")
	local existing = if typeof(npcId) == "string" then markers[npcId] else nil
	if typeof(npcId) ~= "string" or not head or not head:IsA("BasePart") or (existing and existing.Parent) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = MARKER_NAME
	gui.Size = UDim2.fromOffset(40, 56)
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Enabled = false
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextColor3 = COLORS.gold
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	markers[npcId] = gui
end

local function buildTracker(): Tracker
	local gui = Instance.new("ScreenGui")
	gui.Name = "MissionGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1 -- acima do HUD, abaixo das janelas
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Tracker"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -16, 0, 140)
	frame.Size = UDim2.fromOffset(290, 58)
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.15
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.gold
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 7)
	title.Size = UDim2.new(1, -24, 0, 16)
	title.BackgroundTransparency = 1
	title.TextColor3 = COLORS.gold
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local objective = Instance.new("TextLabel")
	objective.Name = "Objective"
	objective.Position = UDim2.fromOffset(12, 25)
	objective.Size = UDim2.new(1, -24, 0, 28)
	objective.BackgroundTransparency = 1
	objective.TextColor3 = COLORS.text
	objective.Font = Enum.Font.GothamMedium
	objective.TextSize = 13
	objective.TextWrapped = true
	objective.TextXAlignment = Enum.TextXAlignment.Left
	objective.TextYAlignment = Enum.TextYAlignment.Top
	objective.Parent = frame
	return { frame = frame, title = title, objective = objective }
end

function MissionController.init()
	tracker = buildTracker()
	localPlayer.AttributeChanged:Connect(function(name: string)
		if
			string.sub(name, 1, 8) == "Mission_"
			or name == Keys.ChaptersUnlockedAttr
			or name == Keys.ChaptersSeenAttr
		then
			refresh()
		end
	end)
end

function MissionController.start()
	refresh()
	local lobby = workspace:WaitForChild("Lobby", NPC_WAIT)
	local folder = lobby and lobby:WaitForChild("Npcs", NPC_WAIT)
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		addMarker(model)
	end
	folder.DescendantAdded:Connect(function(descendant: Instance)
		local model = descendant.Parent
		if descendant.Name == "Head" and model then
			addMarker(model)
			refresh()
		end
	end)
	refresh()
end

return MissionController
