--!strict
-- Feedback visual do combate (só no cliente; nada aqui decide resultado de jogo).
-- - número de dano flutuante e flash no alvo: quando o servidor avisa que algo foi atingido;
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

local function showDamageNumber(target: Model, damage: number, isCrit: boolean)
	local adornee = target:FindFirstChild("Head") or target.PrimaryPart
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if isCrit then 120 else 90, if isCrit then 48 else 36)
	gui.AlwaysOnTop = true
	gui.StudsOffset = Vector3.new(rng:NextNumber(-1, 1), 1.5, 0)
	gui.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = if isCrit then `{damage}!` else tostring(damage)
	label.TextColor3 = if isCrit then CRIT_COLOR else NUMBER_COLOR
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local info = TweenInfo.new(Combat.damageNumberDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, Combat.damageNumberDuration + 0.05)
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
	showDamageNumber(data.target, data.damage, data.isCrit == true)
	flash(data.target)
	if data.isFinisher and data.attacker == localPlayer then
		shakeCamera()
	end
end

function CombatFeedbackController.init() end

function CombatFeedbackController.start()
	Remotes.get("CombatFeedback").OnClientEvent:Connect(onCombatFeedback)
end

return CombatFeedbackController
