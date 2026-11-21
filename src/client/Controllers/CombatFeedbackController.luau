--!strict
-- Feedback visual do combate (só no cliente; nada aqui decide resultado de jogo).
-- - número de dano flutuante e flash no alvo: quando o servidor avisa que algo foi atingido (cura: número verde);
-- - tremor de câmera: no golpe final do combo do PRÓPRIO jogador;
-- - rastro do golpe e "fantasma" da esquiva: chamados pelo InputController na hora do input.

local Debris: Debris = game:GetService("Debris")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local TweenService: TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Combat = require(Shared:WaitForChild("Balance"):WaitForChild("Combat"))

local localPlayer = Players.LocalPlayer

local SWING_COLOR = Color3.fromRGB(255, 255, 255)
local FINISHER_COLOR = Color3.fromRGB(255, 170, 60)
local NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
local CRIT_COLOR = Color3.fromRGB(255, 220, 60)
local PLAYER_HIT_COLOR = Color3.fromRGB(255, 70, 70)
local REWARD_COLOR = Color3.fromRGB(120, 255, 140)
local HEAL_COLOR = Color3.fromRGB(90, 230, 110)
local REWARD_TEXT_DURATION = 1.4
local SWING_FADE_TIME = 0.15

local CombatFeedbackController = {}

local rng = Random.new()

-- Faixa brilhante no chão mostrando a área do golpe (greybox: substitui a animação por enquanto).
function CombatFeedbackController.playSwing(
	root: BasePart,
	direction: Vector3,
	range: number,
	width: number,
	isBig: boolean
)
	local origin = root.Position
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = if isBig then FINISHER_COLOR else SWING_COLOR
	part.Size = Vector3.new(width, 0.2, range)
	part.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, -1, -range / 2)
	part.Transparency = 0.4
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(SWING_FADE_TIME), { Transparency = 1 }):Play()
	Debris:AddItem(part, SWING_FADE_TIME + 0.05)
end

-- Golpe em círculo (Chute Giratório): disco brilhante no chão em volta do personagem.
function CombatFeedbackController.playSpin(root: BasePart, radius: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = FINISHER_COLOR
	-- O eixo do cilindro é o X: deitado (girado 90° em Z), vira um disco no chão.
	part.Size = Vector3.new(0.2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(root.Position - Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Transparency = 0.5
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(SWING_FADE_TIME * 2), { Transparency = 1 }):Play()
	Debris:AddItem(part, SWING_FADE_TIME * 2 + 0.05)
end

-- Sequência de golpes (Rajada de Cem Punhos): um rastro por golpe; o último é o grande.
function CombatFeedbackController.playBarrage(
	root: BasePart,
	direction: Vector3,
	range: number,
	width: number,
	hits: number,
	interval: number
)
	task.spawn(function()
		for i = 1, hits do
			if not root.Parent then
				return
			end
			CombatFeedbackController.playSwing(root, direction, range, width, i == hits)
			task.wait(interval)
		end
	end)
end

-- Personagem fica semitransparente durante a invencibilidade da esquiva.
function CombatFeedbackController.playDodge(character: Model, duration: number)
	local parts: { BasePart } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 0.6
			table.insert(parts, descendant)
		end
	end
	task.delay(duration, function()
		for _, part in parts do
			part.LocalTransparencyModifier = 0
		end
	end)
end

-- Texto que sobe e some acima de uma peça (números de dano, recompensas).
local function floatingText(adornee: BasePart, text: string, color: Color3, size: Vector2, duration: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.AlwaysOnTop = true
	gui.StudsOffset = Vector3.new(rng:NextNumber(-1, 1), 1.5, 0)
	gui.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, duration + 0.05)
end

local function showDamageNumber(target: Model, damage: number, isCrit: boolean, isPlayerTarget: boolean)
	local adornee = target:FindFirstChild("Head") or target.PrimaryPart
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	local color = if isPlayerTarget then PLAYER_HIT_COLOR elseif isCrit then CRIT_COLOR else NUMBER_COLOR
	local size = if isCrit then Vector2.new(120, 48) else Vector2.new(90, 36)
	floatingText(adornee, if isCrit then `{damage}!` else tostring(damage), color, size, Combat.damageNumberDuration)
end

-- "+20 XP  +4 Gold" onde o mob morreu. Precisa de uma peça como âncora: criamos uma invisível só no cliente.
local function showReward(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: Remotes.RewardPayload
	if typeof(data.position) ~= "Vector3" or typeof(data.xp) ~= "number" or typeof(data.gold) ~= "number" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = data.position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace
	Debris:AddItem(anchor, REWARD_TEXT_DURATION + 0.1)
	floatingText(anchor, `+{data.xp} XP  +{data.gold} Gold`, REWARD_COLOR, Vector2.new(200, 40), REWARD_TEXT_DURATION)
end

local function flash(target: Model)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = target
	highlight.Parent = target
	Debris:AddItem(highlight, Combat.hitFlashDuration)
end

-- Tremor via Humanoid.CameraOffset: não briga com o script de câmera padrão do Roblox.
local function shakeCamera()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local endsAt = os.clock() + Combat.cameraShakeDuration
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() >= endsAt or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			if connection then
				connection:Disconnect()
			end
			return
		end
		local i = Combat.cameraShakeIntensity
		humanoid.CameraOffset = Vector3.new(rng:NextNumber(-i, i), rng:NextNumber(-i, i), rng:NextNumber(-i, i))
	end)
end

local function onCombatFeedback(payload: unknown)
	-- Mesmo vindo do servidor, conferimos o formato antes de usar.
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: Remotes.CombatFeedbackPayload
	if typeof(data.target) ~= "Instance" or not data.target:IsA("Model") or typeof(data.damage) ~= "number" then
		return
	end
	if data.isHeal == true then
		local adornee = data.target:FindFirstChild("Head") or data.target.PrimaryPart
		if adornee and adornee:IsA("BasePart") then
			floatingText(adornee, `+{data.damage}`, HEAL_COLOR, Vector2.new(90, 36), Combat.damageNumberDuration)
		end
		return
	end
	local isPlayerTarget = Players:GetPlayerFromCharacter(data.target) ~= nil
	showDamageNumber(data.target, data.damage, data.isCrit == true, isPlayerTarget)
	flash(data.target)
	-- Treme no golpe final do próprio combo e quando o próprio personagem apanha.
	if (data.isFinisher and data.attacker == localPlayer) or data.target == localPlayer.Character then
		shakeCamera()
	end
end

function CombatFeedbackController.init() end

function CombatFeedbackController.start()
	Remotes.get("CombatFeedback").OnClientEvent:Connect(onCombatFeedback)
	Remotes.get("RewardGranted").OnClientEvent:Connect(showReward)
end

return CombatFeedbackController
