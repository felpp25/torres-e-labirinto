--!strict
-- HUD (só exibe; os valores vêm do servidor por Attributes do Player e do Humanoid).
-- Canto superior esquerdo (padrão de RPG): nível, barras de vida/stamina/mana/XP, Gold e atributos.
-- A janela de chat do Roblox, que fica nesse canto por padrão, é movida para o canto inferior esquerdo.
-- Embaixo, no centro: ícones de recarga da esquiva e das habilidades da classe (e o bônus de dano ativo).
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
local AttributeInfo = require(Shared:WaitForChild("AttributeInfo"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local GearInfo = require(Shared:WaitForChild("GearInfo"))
local Gear = require(Balance:WaitForChild("Gear"))
local Combat = require(Balance:WaitForChild("Combat"))
local Abilities = require(Balance:WaitForChild("Abilities"))
local Classes = require(Balance:WaitForChild("Classes"))
local Hotkeys = require(script.Parent.Parent:WaitForChild("Hotkeys"))
local ActionBar = require(script.Parent.Parent:WaitForChild("ActionBar"))

local localPlayer = Players.LocalPlayer

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
	buff = Color3.fromRGB(150, 200, 255),
	ultimateReady = Color3.fromRGB(200, 150, 30),
}

-- Nomes dos atributos na interface (ordem de exibição).
local STAT_LABELS = AttributeInfo

type Bar = { fill: Frame, label: TextLabel }
type CooldownIcon = { frame: Frame, overlay: Frame, timer: TextLabel }

local HudController = {}

local bars: { [string]: Bar } = {}
local levelLabel: TextLabel? = nil
local goldLabel: TextLabel? = nil
local livesLabel: TextLabel? = nil
local lastLives: number? = nil
local statsLabel: TextLabel? = nil
local floorLabel: TextLabel? = nil
local saveWarningLabel: TextLabel? = nil
local bossFrame: Frame? = nil
local bossBar: Bar? = nil
local bossNameLabel: TextLabel? = nil
local dodgeIcon: CooldownIcon? = nil
local abilityIcons: { [string]: CooldownIcon } = {} -- por id da habilidade
local ultimateIcon: CooldownIcon? = nil
local buffLabel: TextLabel? = nil
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

local function makeCooldownIcon(parent: Instance, position: UDim2, title: string, key: string): CooldownIcon
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.2
	frame.Size = UDim2.fromOffset(ActionBar.iconSize, ActionBar.iconSize)
	frame.Position = position
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
	local livesText = makeText(panel, "", UDim2.fromOffset(90, 16), UDim2.fromOffset(170, 76), 14)
	livesText.TextColor3 = COLORS.health
	livesLabel = livesText
	local stats = makeText(panel, "", UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 94), 11)
	-- Com o fortalecimento os atributos têm décimos (FOR 16,8): a linha encolhe para caber no painel.
	stats.TextScaled = true
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 11
	sizeLimit.Parent = stats
	statsLabel = stats
	floorLabel = makeText(panel, "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 112), 13)

	-- Aviso quando o progresso NÃO está sendo salvo (falha ao carregar do DataStore). Abaixo do botão de pontos.
	local saveWarning =
		makeText(gui, "⚠ Progresso NÃO está sendo salvo", UDim2.fromOffset(260, 18), UDim2.fromOffset(14, 184), 13)
	saveWarning.TextColor3 = COLORS.health
	saveWarning.TextStrokeTransparency = 0
	saveWarning.Visible = false
	saveWarningLabel = saveWarning

	dodgeIcon = makeCooldownIcon(gui, ActionBar.position(1), "Esquiva", "Q")
	local classDef = Classes.byId[Classes.defaultClassId]
	for index, abilityId in classDef.abilities do
		local def = Abilities[abilityId]
		local slot = Hotkeys.abilities[index]
		if def and slot then
			local position = ActionBar.position(ActionBar.abilitySlot(index))
			abilityIcons[abilityId] = makeCooldownIcon(gui, position, def.shortName, slot.label)
		end
	end
	local ultimateDef = Abilities[classDef.ultimate]
	if ultimateDef then
		local position = ActionBar.position(ActionBar.ultimateSlot())
		ultimateIcon = makeCooldownIcon(gui, position, ultimateDef.shortName, Hotkeys.ultimate.label)
	end
	-- Bônus de dano ativo (ex.: Foco Interior), logo acima da barra de ações.
	local buffPosition = ActionBar.position(1) + UDim2.fromOffset(0, -24)
	local buff = makeText(gui, "", UDim2.fromOffset(240, 18), buffPosition, 14)
	buff.TextColor3 = COLORS.buff
	buff.TextStrokeTransparency = 0
	buff.Visible = false
	buffLabel = buff

	-- Barra do chefe: topo central, escondida até existir um chefe vivo.
	local boss = Instance.new("Frame")
	boss.Name = "BossBar"
	boss.BackgroundColor3 = COLORS.panel
	boss.BackgroundTransparency = 0.25
	boss.AnchorPoint = Vector2.new(0.5, 0)
	boss.Position = UDim2.new(0.5, 0, 0, 8)
	boss.Size = UDim2.fromOffset(420, 52)
	boss.Visible = false
	boss.Parent = gui
	corner(boss, 10)
	local name = makeText(boss, "", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 4), 15)
	name.TextXAlignment = Enum.TextXAlignment.Center
	bossNameLabel = name
	local bar = makeBar(boss, 26, 18, COLORS.health, true)
	-- makeBar deixa espaço à esquerda para o círculo de nível do painel; aqui a barra ocupa a largura toda.
	local back = bar.fill.Parent :: Frame
	back.Position = UDim2.fromOffset(8, 26)
	back.Size = UDim2.new(1, -16, 0, 18)
	bossBar = bar
	bossFrame = boss
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
	if livesLabel then
		local lives = workspace:GetAttribute(Keys.WorldAttr.Lives)
		local inRun = localPlayer:GetAttribute(Keys.InRunAttr) == true
		livesLabel.Text = if inRun and typeof(lives) == "number" then `Vidas: {lives}` else ""
	end
	if saveWarningLabel then
		saveWarningLabel.Visible = localPlayer:GetAttribute(Keys.PlayerAttr.SaveStatus) == "offline"
	end
	if floorLabel then
		local floorNumber = workspace:GetAttribute(Keys.WorldAttr.FloorNumber)
		local inRun = localPlayer:GetAttribute(Keys.InRunAttr) == true
		if inRun and typeof(floorNumber) == "number" then
			local active = workspace:GetAttribute(Keys.WorldAttr.PlatesActive)
			local total = workspace:GetAttribute(Keys.WorldAttr.PlatesTotal)
			local exitOpen = workspace:GetAttribute(Keys.WorldAttr.ExitOpen) == true
			local isBossFloor = workspace:GetAttribute(Keys.WorldAttr.IsBossFloor) == true
			local goal = if isBossFloor
				then "Chefe"
				elseif exitOpen then "Saída aberta!"
				else `Placas {active or 0}/{total or 0}`
			floorLabel.Text = `Andar {floorNumber}  ·  {goal}`
		else
			floorLabel.Text = "Lobby"
		end
	end
	if statsLabel then
		local parts: { string } = {}
		-- Valores EFETIVOS: pontos distribuídos + equipamento (o painel Personagem mostra a divisão).
		for _, stat in STAT_LABELS do
			local value = numberAttr(Keys.statAttr(stat.key)) + numberAttr(Keys.gearStatAttr(stat.key))
			table.insert(parts, `{stat.short} {GearInfo.formatNumber(value)}`) -- fortalecimento dá décimos
		end
		statsLabel.Text = table.concat(parts, "  ")
	end

	local stamina = numberAttr(Keys.PlayerAttr.Stamina)
	if dodgeIcon then
		local readyAt = numberAttr(Keys.PlayerAttr.DodgeReadyAt)
		updateCooldown(dodgeIcon, readyAt, Combat.dodge.cooldown, stamina >= Combat.dodge.staminaCost)
	end
	for abilityId, icon in abilityIcons do
		local ability = Abilities[abilityId]
		local readyAt = numberAttr(Keys.abilityReadyAttr(abilityId))
		local affordable = numberAttr(Keys.resourceAttr(ability.resource)) >= ability.cost
		updateCooldown(icon, readyAt, ability.cooldown, affordable)
	end
	-- Ultimate: a cortina escura cobre a parte da barra que falta encher; cheia, o ícone fica dourado.
	local ultimate = Abilities[Classes.byId[Classes.defaultClassId].ultimate]
	if ultimateIcon and ultimate then
		local charge = numberAttr(Keys.PlayerAttr.UltimateCharge)
		local ready = charge >= ultimate.cost
		ultimateIcon.overlay.Size = UDim2.fromScale(1, 1 - math.clamp(charge / ultimate.cost, 0, 1))
		ultimateIcon.timer.Text = if ready then "" else `{charge}%`
		ultimateIcon.frame.BackgroundColor3 = if ready then COLORS.ultimateReady else COLORS.panel
	end
	if buffLabel then
		local remaining = numberAttr(Keys.PlayerAttr.DamageBonusUntil) - workspace:GetServerTimeNow()
		local bonus = numberAttr(Keys.PlayerAttr.DamageBonus)
		buffLabel.Visible = remaining > 0 and bonus > 0
		if buffLabel.Visible then
			buffLabel.Text = `Dano +{math.round(bonus * 100)}% ({math.ceil(remaining)} s)`
		end
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
	if typeof(data.level) ~= "number" or typeof(data.points) ~= "number" then
		return
	end
	showToast(
		`NÍVEL {data.level}!`,
		`+{data.points} pontos de atributo (tecla C ou botão "Personagem" para distribuir)`,
		COLORS.gold,
		0.22
	)
end

-- Ganhou uma peça de equipamento (ou Gold, se o baú estava cheio). O aviso não depende de o GearData ou o Gold
-- já terem chegado (o Roblox não garante a ordem entre Remotes e Attributes). Altura 0.42: a 0.22 é do nível e da
-- torre concluída, que chegam junto com a peça do chefe.
local function onGearNotice(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local defId = data.defId
	local rarity: Types.Rarity? = Formulas.parseRarity(data.rarity)
	local goldInstead = data.goldInstead
	local def = if typeof(defId) == "string" then Gear.byId[defId] else nil
	if not def or not rarity or typeof(goldInstead) ~= "number" or goldInstead < 0 then
		return
	end
	local name = GearInfo.fullName(def, rarity)
	if goldInstead > 0 then
		showToast("BAÚ CHEIO", `{name} virou {goldInstead} Gold`, COLORS.gold, 0.42)
	else
		showToast("ITEM NOVO!", `{name} foi para o baú`, GearInfo.rarityColor(rarity), 0.42)
	end
end

-- Vidas mudaram: perdeu (wipe) ou ganhou (Coração). O game over é avisado por onGameOver.
-- Ao começar uma run nova as vidas voltam ao máximo junto com a troca do nº da run: essa subida não é
-- "+1 VIDA". Espera um instante para os Attributes chegarem e compara o nº da run de agora com o da última vez.
-- Fora da torre (no lobby) nada é avisado.
local livesRunNumber: unknown = nil
local function onLivesChanged()
	task.wait(0.2)
	local lives = workspace:GetAttribute(Keys.WorldAttr.Lives)
	if typeof(lives) ~= "number" then
		return
	end
	local runNumber = workspace:GetAttribute(Keys.WorldAttr.RunNumber)
	local sameRun = livesRunNumber == nil or runNumber == livesRunNumber
	livesRunNumber = runNumber
	local previous = lastLives
	lastLives = lives
	local inRun = localPlayer:GetAttribute(Keys.InRunAttr) == true
	if previous == nil or not sameRun or not inRun or workspace:GetAttribute(Keys.WorldAttr.RunActive) ~= true then
		return
	end
	if lives < previous then
		local suffix = if lives == 1 then "ÚLTIMA VIDA!" else `restam {lives} vidas`
		showToast("VIDA PERDIDA", `O andar recomeçou: {suffix}`, COLORS.health, 0.32)
	elseif lives > previous then
		showToast("+1 VIDA!", `Vidas: {lives}`, COLORS.health, 0.32)
	end
end

local lastGameOvers: number? = nil
local function onGameOver()
	local count = workspace:GetAttribute(Keys.WorldAttr.GameOvers)
	if typeof(count) ~= "number" then
		return
	end
	local previous = lastGameOvers
	lastGameOvers = count
	if previous ~= nil and count > previous then
		showToast("GAME OVER", "De volta ao lobby. Seu XP e Gold foram mantidos.", COLORS.health, 0.32)
	end
end

local function onFloorChanged()
	task.wait(0.2) -- o Attribute "InRun" pode chegar logo depois do andar
	local floorNumber = workspace:GetAttribute(Keys.WorldAttr.FloorNumber)
	if typeof(floorNumber) == "number" and localPlayer:GetAttribute(Keys.InRunAttr) == true then
		local isBossFloor = workspace:GetAttribute(Keys.WorldAttr.IsBossFloor) == true
		local hint = if isBossFloor
			then "Último andar: o chefe espera na arena vermelha"
			else "Ative as placas na sala azul para abrir a saída"
		showToast(`ANDAR {floorNumber}`, hint, if isBossFloor then COLORS.health else COLORS.text, 0.32)
	end
end

local lastTowersCompleted: number? = nil
local function onTowersCompletedChanged()
	local count = workspace:GetAttribute(Keys.WorldAttr.TowersCompleted)
	if typeof(count) ~= "number" then
		return
	end
	local previous = lastTowersCompleted
	lastTowersCompleted = count
	if previous ~= nil and count > previous then
		showToast(
			"TORRE CONCLUÍDA!",
			"Recompensa do chefe recebida. Uma nova torre começa em instantes.",
			COLORS.gold,
			0.22
		)
	end
end

-- Barra de vida do chefe no topo central (só aparece com um chefe vivo).
local function updateBossBar()
	local frame = bossFrame
	if not frame then
		return
	end
	local maxHealth = workspace:GetAttribute(Keys.WorldAttr.BossMaxHealth)
	local health = workspace:GetAttribute(Keys.WorldAttr.BossHealth)
	local active = typeof(maxHealth) == "number" and maxHealth > 0 and typeof(health) == "number" and health > 0
	frame.Visible = active
	if active and bossBar and bossNameLabel then
		local name = workspace:GetAttribute(Keys.WorldAttr.BossName)
		bossNameLabel.Text = if typeof(name) == "string" then name else "Chefe"
		setBar(bossBar, health :: number, maxHealth :: number)
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
	Remotes.get("GearNotice").OnClientEvent:Connect(onGearNotice)
	workspace:GetAttributeChangedSignal(Keys.WorldAttr.FloorNumber):Connect(onFloorChanged)
	task.spawn(onFloorChanged)
	workspace:GetAttributeChangedSignal(Keys.WorldAttr.GameOvers):Connect(onGameOver)
	workspace:GetAttributeChangedSignal(Keys.WorldAttr.Lives):Connect(onLivesChanged)
	onGameOver()
	task.spawn(onLivesChanged)
	workspace:GetAttributeChangedSignal(Keys.WorldAttr.TowersCompleted):Connect(onTowersCompletedChanged)
	onTowersCompletedChanged()
	RunService.Heartbeat:Connect(update)
	RunService.Heartbeat:Connect(updateBossBar)
end

return HudController
