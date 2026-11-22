--!strict
-- Modo espectador (GDD > Morte e checkpoint): enquanto o jogador está morto, a câmera segue um aliado vivo.
-- Trocar de aliado: tecla F / R1 no controle / botão "Próximo" no celular.
-- É só câmera: nada aqui afeta o jogo. Quando o personagem renasce, a câmera volta para ele.

local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keys = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keys"))

local localPlayer = Players.LocalPlayer

local ACTION_NAME = "SpectateNext"
local CHECK_INTERVAL = 0.5 -- s entre verificações (o aliado espectado pode morrer ou sair)
local TOUCH_POSITION = UDim2.new(1, -320, 1, -120) -- à esquerda dos botões de combate

local SpectateController = {}

local spectating = false
local spectateIndex = 0
local label: TextLabel? = nil

-- Aliados vivos da MESMA run (várias runs por servidor: os outros grupos não contam).
local function aliveAllies(): { Player }
	local result: { Player } = {}
	local runId = localPlayer:GetAttribute(Keys.RunAttr.RunId)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local sameRun = runId ~= nil and player:GetAttribute(Keys.RunAttr.RunId) == runId
		if player ~= localPlayer and sameRun and humanoid and humanoid.Health > 0 then
			table.insert(result, player)
		end
	end
	return result
end

local function setLabel(text: string?)
	if not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "SpectateGui"
		gui.ResetOnSpawn = false
		local newLabel = Instance.new("TextLabel")
		newLabel.AnchorPoint = Vector2.new(0.5, 0)
		newLabel.Position = UDim2.new(0.5, 0, 0, 60)
		newLabel.Size = UDim2.fromOffset(420, 36)
		newLabel.BackgroundTransparency = 0.4
		newLabel.BackgroundColor3 = Color3.new(0, 0, 0)
		newLabel.TextColor3 = Color3.new(1, 1, 1)
		newLabel.TextScaled = true
		newLabel.Font = Enum.Font.GothamBold
		newLabel.Parent = gui
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
		label = newLabel
	end
	local current = label :: TextLabel
	current.Visible = text ~= nil
	current.Text = text or ""
end

local function setCameraSubject(humanoid: Humanoid)
	local camera = workspace.CurrentCamera
	camera.CameraSubject = humanoid
end

local function focusAlly(step: number)
	local allies = aliveAllies()
	if #allies == 0 then
		setLabel("Você morreu. Aguardando...")
		return
	end
	spectateIndex = (spectateIndex + step - 1) % #allies + 1
	local ally = allies[spectateIndex]
	local humanoid = ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setCameraSubject(humanoid)
		setLabel(`Espectando: {ally.DisplayName}`)
	end
end

local function onNext(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		focusAlly(1)
	end
	return Enum.ContextActionResult.Sink
end

local function startSpectating()
	spectating = true
	spectateIndex = 0
	ContextActionService:BindAction(ACTION_NAME, onNext, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(ACTION_NAME, "Próximo")
	ContextActionService:SetPosition(ACTION_NAME, TOUCH_POSITION)
	focusAlly(1)
	task.spawn(function()
		while spectating do
			task.wait(CHECK_INTERVAL)
			local subject = workspace.CurrentCamera.CameraSubject
			local subjectAlive = subject ~= nil and subject:IsA("Humanoid") and subject.Health > 0
			if spectating and not subjectAlive then
				focusAlly(0)
			end
		end
	end)
end

local function stopSpectating(character: Model)
	spectating = false
	ContextActionService:UnbindAction(ACTION_NAME)
	setLabel(nil)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		setCameraSubject(humanoid)
	end
end

local function onCharacterAdded(character: Model)
	if spectating then
		stopSpectating(character)
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(startSpectating)
	end
end

function SpectateController.init() end

function SpectateController.start()
	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return SpectateController
