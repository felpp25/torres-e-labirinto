--!strict
-- HUD (só exibe; os valores vêm do servidor por Attributes do Player e do Humanoid).
-- Canto superior esquerdo (padrão de RPG): nível, barras de vida/stamina/mana/XP, Gold e atributos.
-- A janela de chat do Roblox, que fica nesse canto por padrão, é movida para o canto inferior esquerdo.
-- Embaixo, no centro: ícones de recarga da esquiva e da Palma de Ferro.
-- Centro da tela: aviso de "subiu de nível".

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local StarterGui: StarterGui = game:GetService("StarterGui")
local TextChatService: TextChatService = game:GetService("TextChatService")
local TweenService: TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = Shared:WaitForChild("Balance")
local Keys = require(Shared:WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Balance:WaitForChild("Combat"))
local Abilities = require(Balance:WaitForChild("Abilities"))

local localPlayer = Players.LocalPlayer

local ABILITY_ID = "IronPalm"
local PANEL_WIDTH = 260
local FONT = Enum.Font.GothamBold

local COLORS = {
	panel = Color3.fromRGB(20, 20, 28),
	barBack = Color3.fromRGB(45, 45, 55),
	health = Color3.fromRGB(220, 60, 60),
	stamina = Color3.fromRGB(235, 195, 60),
	mana = Color3.fromRGB(70, 130, 240),
	xp = Color3.fromRGB(170, 90, 230),
	gold = Color3.fromRGB(255, 205, 70),
	text = Color3.fromRGB(255, 255, 255),
	cooldown = Color3.fromRGB(0, 0, 0),
	unavailable = Color3.fromRGB(120, 40, 40),
}

-- Nomes dos atributos na interface (ordem de exibição).
local STAT_LABELS: { { key: string, short: string, long: string } } = {
	{ key = "Strength", short = "FOR", long = "Força" },
	{ key = "Vitality", short = "VIT", long = "Vitalidade" },
	{ key = "Intelligence", short = "INT", long = "Inteligência" },
	{ key = "Wisdom", short = "SAB", long = "Sabedoria" },
	{ key = "Dexterity", short = "DES", long = "Destreza" },
	{ key = "Defense", short = "DEF", long = "Defesa" },
	{ key = "Luck", short = "SOR", long = "Sorte" },
}

type Bar = { fill: Frame, label: TextLabel }
type CooldownIcon = { frame: Frame, overlay: Frame, timer: TextLabel }

local HudController = {}

local bars: { [string]: Bar } = {}
local levelLabel: TextLabel? = nil
local goldLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil
local floorLabel: TextLabel? = nil
local dodgeIcon: CooldownIcon? = nil
local abilityIcon: CooldownIcon? = nil
local screenGui: ScreenGui? = nil

local function numberAttr(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makeText(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.TextColor3 = COLORS.text
	label.TextStrokeTransparency = 0.5
	label.TextSize = textSize
	label.Font = FONT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function makeBar(parent: Instance, y: number, height: number, color: Color3, showText: boolean): Bar
	local back = Instance.new("Frame")
	back.BackgroundColor3 = COLORS.barBack
	back.BorderSizePixel = 0
	back.Position = UDim2.fromOffset(62, y)
	back.Size = UDim2.new(1, -70, 0, height)
	back.Parent = parent
	corner(back, 4)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	corner(fill, 4)

	local label = makeText(back, "", UDim2.fromScale(1, 1), UDim2.fromOffset(6, 0), math.max(height - 4, 10))
	label.Visible = showText
	return { fill = fill, label = label }
end

local function setBar(bar: Bar, current: number, max: number)
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	bar.fill.Size = UDim2.fromScale(ratio, 1)
	bar.label.Text = `{math.floor(current)} / {math.floor(max)}`
end

local function makeCooldownIcon(parent: Instance, x: number, title: string, key: string): CooldownIcon
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.2
	frame.Size = UDim2.fromOffset(64, 64)
	frame.Position = UDim2.new(0.5, x, 1, -80)
	frame.Parent = parent
	corner(frame, 10)

	local titleLabel = makeText(frame, title, UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 26), 12)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local keyLabel = makeText(frame, key, UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 6), 14)
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Cortina escura que desce conforme a recarga termina.
	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = COLORS.cooldown
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.ZIndex = 2
	overlay.Parent = frame
	corner(overlay, 10)

	local timer = makeText(frame, "", UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 44), 16)
	timer.TextXAlignment = Enum.TextXAlignment.Center
	timer.ZIndex = 3
	return { frame = frame, overlay = overlay, timer = timer }
end

local function updateCooldown(icon: CooldownIcon, readyAt: number, duration: number, affordable: boolean)
	local remaining = math.max(readyAt - workspace:GetServerTimeNow(), 0)
	icon.overlay.Size = UDim2.fromScale(1, if duration > 0 then math.clamp(remaining / duration, 0, 1) else 0)
	icon.timer.Text = if remaining > 0.05 then string.format("%.1f", remaining) else ""
	icon.frame.BackgroundColor3 = if affordable then COLORS.panel else COLORS.unavailable
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	screenGui = gui

	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.25
	panel.Position = UDim2.fromOffset(12, 8)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 134)
	panel.Parent = gui
	corner(panel, 10)

	local badge = Instance.new("Frame")
	badge.BackgroundColor3 = COLORS.xp
	badge.Position = UDim2.fromOffset(8, 8)
	badge.Size = UDim2.fromOffset(46, 46)
	badge.Parent = panel
	corner(badge, 23)
	local level = makeText(badge, "1", UDim2.fromScale(1, 1), UDim2.new(), 22)
	level.TextXAlignment = Enum.TextXAlignment.Center
	levelLabel = level
	local levelCaption = makeText(panel, "NÍVEL", UDim2.fromOffset(46, 12), UDim2.fromOffset(8, 56), 10)
	levelCaption.TextXAlignment = Enum.TextXAlignment.Center

	bars.health = makeBar(panel, 8, 18, COLORS.health, true)
	bars.stamina = makeBar(panel, 30, 13, COLORS.stamina, true)
	bars.mana = makeBar(panel, 47, 13, COLORS.mana, true)
	bars.xp = makeBar(panel, 64, 8, COLORS.xp, false)

	local gold = makeText(panel, "Gold: 0", UDim2.fromOffset(120, 16), UDim2.fromOffset(62, 76), 14)
	gold.TextColor3 = COLORS.gold
	goldLabel = gold
	statsLabel = makeText(panel, "", UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 94), 11)
	floorLabel = makeText(panel, "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 112), 13)

	dodgeIcon = makeCooldownIcon(gui, -72, "Esquiva", "Q")
	abilityIcon = makeCooldownIcon(gui, 8, "Palma", "E")
end

local function update()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setBar(bars.health, humanoid.Health, humanoid.MaxHealth)
	end
	setBar(bars.stamina, numberAttr(Keys.PlayerAttr.Stamina), numberAttr(Keys.PlayerAttr.MaxStamina))
	setBar(bars.mana, numberAttr(Keys.PlayerAttr.Mana), numberAttr(Keys.PlayerAttr.MaxMana))

	local toNext = numberAttr(Keys.PlayerAttr.XPToNext)
	if toNext > 0 then
		setBar(bars.xp, numberAttr(Keys.PlayerAttr.XP), toNext)
	else
		bars.xp.fill.Size = UDim2.fromScale(1, 1) -- nível máximo
	end

	if levelLabel then
		levelLabel.Text = tostring(math.max(numberAttr(Keys.PlayerAttr.Level), 1))
	end
	if goldLabel then
		goldLabel.Text = `Gold: {numberAttr(Keys.PlayerAttr.Gold)}`
	end
	if floorLabel then
		local floorNumber = workspace:GetAttribute(Keys.WorldAttr.FloorNumber)
		if typeof(floorNumber) == "number" then
			local active = workspace:GetAttribute(Keys.WorldAttr.PlatesActive)
			local total = workspace:GetAttribute(Keys.WorldAttr.PlatesTotal)
			local exitOpen = workspace:GetAttribute(Keys.WorldAttr.ExitOpen) == true
			local puzzle = if exitOpen then "Saída aberta!" else `Placas {active or 0}/{total or 0}`
			floorLabel.Text = `Andar {floorNumber}  ·  {puzzle}`
		else
			floorLabel.Text = "Lobby"
		end
	end
	if statsLabel then
		local parts: { string } = {}
		for _, stat in STAT_LABELS do
			table.insert(parts, `{stat.short} {numberAttr(Keys.statAttr(stat.key))}`)
		end
		statsLabel.Text = table.concat(parts, "  ")
	end

	local stamina = numberAttr(Keys.PlayerAttr.Stamina)
	if dodgeIcon then
		local readyAt = numberAttr(Keys.PlayerAttr.DodgeReadyAt)
		updateCooldown(dodgeIcon, readyAt, Combat.dodge.cooldown, stamina >= Combat.dodge.staminaCost)
	end
	local ability = Abilities[ABILITY_ID]
	if abilityIcon and ability then
		local readyAt = numberAttr(Keys.abilityReadyAttr(ABILITY_ID))
		local resource = if ability.resource == "Stamina" then stamina else numberAttr(Keys.PlayerAttr.Mana)
		updateCooldown(abilityIcon, readyAt, ability.cooldown, resource >= ability.cost)
	end
end

-- Aviso grande no centro da tela que some sozinho (subiu de nível, andar novo).
local function showToast(title: string, detailText: string, color: Color3, heightScale: number)
	local gui = screenGui
	if not gui then
		return
	end
	local toast = makeText(gui, title, UDim2.fromOffset(500, 50), UDim2.new(0.5, -250, heightScale, 0), 40)
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.TextColor3 = color
	toast.TextStrokeTransparency = 0
	local detail = makeText(toast, detailText, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 50), 20)
	detail.TextXAlignment = Enum.TextXAlignment.Center

	task.delay(1.8, function()
		local info = TweenInfo.new(0.6)
		TweenService:Create(toast, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(detail, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.7)
		toast:Destroy()
	end)
end

local function showLevelUp(payload: unknown)
	if typeof(payload) ~= "table" or not screenGui then
		return
	end
	local data = payload :: Remotes.LevelUpPayload
	if typeof(data.level) ~= "number" or typeof(data.gains) ~= "table" then
		return
	end
	local gainParts: { string } = {}
	for _, stat in STAT_LABELS do
		local gained = data.gains[stat.key]
		if typeof(gained) == "number" and gained > 0 then
			table.insert(gainParts, `+{gained} {stat.long}`)
		end
	end

	showToast(`NÍVEL {data.level}!`, table.concat(gainParts, "   "), COLORS.gold, 0.22)
end

local function onFloorChanged()
	local floorNumber = workspace:GetAttribute(Keys.WorldAttr.FloorNumber)
	if typeof(floorNumber) == "number" then
		showToast(`ANDAR {floorNumber}`, "Ative as placas na sala azul para abrir a saída", COLORS.text, 0.32)
	end
end

-- A barra de vida padrão do Roblox some: a do HUD a substitui. SetCoreGuiEnabled pode falhar se chamado
-- cedo demais, por isso as tentativas.
local function hideDefaultHealthBar()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

function HudController.init()
	build()
end

-- Leva a janela de chat para o canto inferior esquerdo, liberando o superior esquerdo para o HUD.
-- (O superior direito fica livre para a lista de jogadores do Roblox no coop.)
local function moveChatWindow()
	local config = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		or TextChatService:WaitForChild("ChatWindowConfiguration", 10)
	if config and config:IsA("ChatWindowConfiguration") then
		config.HorizontalAlignment = Enum.HorizontalAlignment.Left
		config.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
end

function HudController.start()
	task.spawn(hideDefaultHealthBar)
	task.spawn(moveChatWindow)
	Remotes.get("LevelUp").OnClientEvent:Connect(showLevelUp)
	workspace:GetAttributeChangedSignal(Keys.WorldAttr.FloorNumber):Connect(onFloorChanged)
	onFloorChanged()
	RunService.Heartbeat:Connect(update)
end

return HudController
