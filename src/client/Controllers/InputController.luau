--!strict
-- Entrada do jogador (PC, controle e celular) -> intenções para o servidor.
-- ContextActionService: cada ação vale para teclado/mouse/controle e, no celular, ganha um botão na tela.
-- O cliente faz uma PREVISÃO (recarga, stamina, combo) só para responder na hora; quem decide é o servidor.
--
-- PC: clique = ataque (combo de 3) | Q = esquiva | E = Palma de Ferro
-- Controle: R2 = ataque | B = esquiva | Y = Palma de Ferro
-- Celular: botões "Atacar", "Esquiva" e "Palma" na tela

local CollectionService: CollectionService = game:GetService("CollectionService")
local ContextActionService: ContextActionService = game:GetService("ContextActionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = Shared:WaitForChild("Balance")
local Formulas = require(Shared:WaitForChild("Formulas"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Keys = require(Shared:WaitForChild("Keys"))
local Motion = require(Shared:WaitForChild("Motion"))
local Combat = require(Balance:WaitForChild("Combat"))
local Classes = require(Balance:WaitForChild("Classes"))
local Abilities = require(Balance:WaitForChild("Abilities"))

local CombatFeedbackController = require(script.Parent.CombatFeedbackController)

local localPlayer = Players.LocalPlayer

local ABILITY_ID = "IronPalm" -- única habilidade do protótipo

-- Posições dos botões no celular (perto do botão de pular, canto inferior direito).
local TOUCH_LAYOUT: { [string]: UDim2 } = {
	Attack = UDim2.new(1, -190, 1, -120),
	Dodge = UDim2.new(1, -120, 1, -200),
	IronPalm = UDim2.new(1, -230, 1, -210),
}

local InputController = {}

-- Previsões locais, no relógio do servidor (workspace:GetServerTimeNow).
local nextAttackAt = 0
local comboIndex = 0
local comboExpiresAt = 0
local dodgeReadyAt = 0
local abilityReadyAt = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function numberAttribute(name: string): number
	local value = localPlayer:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function getAliveCharacter(): (Model?, Humanoid?, BasePart?)
	local character = localPlayer.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- Mesma assistência de mira do servidor, para o visual apontar para onde o golpe vai.
local function aimDirection(root: BasePart, range: number): Vector3
	local positions: { Vector3 } = {}
	for _, instance in CollectionService:GetTagged(Keys.Tags.Enemy) do
		if instance:IsA("Model") and instance.PrimaryPart then
			table.insert(positions, instance.PrimaryPart.Position)
		end
	end
	return Formulas.chooseAimDirection(root.Position, root.CFrame.LookVector, positions, range, Combat.aimAssistAngle)
end

-- Vira o personagem para a direção do golpe (o servidor vê essa rotação porque a física do personagem é do cliente).
local function face(root: BasePart, direction: Vector3)
	local origin = root.Position
	root.CFrame = CFrame.lookAt(origin, origin + direction)
end

local function onAttack(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local _, _, root = getAliveCharacter()
	local t = now()
	if not root or t < nextAttackAt then
		return Enum.ContextActionResult.Sink
	end

	local combo = Classes.byId[Classes.defaultClassId].combo
	comboIndex = if t > comboExpiresAt then 1 else comboIndex % #combo + 1
	local hit = combo[comboIndex]
	nextAttackAt = t + hit.recovery
	comboExpiresAt = t + hit.recovery + Combat.comboWindow

	local range = hit.range + Combat.rangeTolerance
	local direction = aimDirection(root, range)
	face(root, direction)
	Remotes.get("AttackRequest"):FireServer()
	CombatFeedbackController.playSwing(root, direction, hit.range, hit.width, hit.isFinisher)
	return Enum.ContextActionResult.Sink
end

-- Esquiva: Motion.push para antes de paredes e mobs (sem isso, esquivar contra a parede arremessava o jogador).
-- Personagens de jogadores não contam como obstáculo para a medição.
local function startDash(root: BasePart, direction: Vector3)
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	Motion.push(root, direction, Combat.dodge.speed, Combat.dodge.duration, ignore)
end

local function onDodge(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local character, humanoid, root = getAliveCharacter()
	local t = now()
	if not character or not humanoid or not root then
		return Enum.ContextActionResult.Sink
	end
	if t < math.max(dodgeReadyAt, numberAttribute(Keys.PlayerAttr.DodgeReadyAt)) then
		return Enum.ContextActionResult.Sink
	end
	if numberAttribute(Keys.PlayerAttr.Stamina) < Combat.dodge.staminaCost then
		return Enum.ContextActionResult.Sink
	end
	dodgeReadyAt = t + Combat.dodge.cooldown

	-- Esquiva para onde o jogador está andando; parado, esquiva para a frente.
	local move = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	local direction = if move.Magnitude > 0.1 then move.Unit else (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit

	Remotes.get("DodgeRequest"):FireServer()
	startDash(root, direction)
	CombatFeedbackController.playDodge(character, Combat.dodge.invulnerableTime)
	return Enum.ContextActionResult.Sink
end

local function onAbility(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local def = Abilities[ABILITY_ID]
	local _, _, root = getAliveCharacter()
	local t = now()
	if not root or t < nextAttackAt then
		return Enum.ContextActionResult.Sink
	end
	if t < math.max(abilityReadyAt, numberAttribute(Keys.abilityReadyAttr(ABILITY_ID))) then
		return Enum.ContextActionResult.Sink
	end
	local resourceAttr = if def.resource == "Stamina" then Keys.PlayerAttr.Stamina else Keys.PlayerAttr.Mana
	if numberAttribute(resourceAttr) < def.cost then
		return Enum.ContextActionResult.Sink
	end
	abilityReadyAt = t + def.cooldown
	nextAttackAt = t + def.recovery
	comboExpiresAt = 0

	local range = def.range + Combat.rangeTolerance
	local direction = aimDirection(root, range)
	face(root, direction)
	Remotes.get("AbilityRequest"):FireServer(ABILITY_ID)
	CombatFeedbackController.playSwing(root, direction, def.range, def.width, true)
	return Enum.ContextActionResult.Sink
end

function InputController.init() end

function InputController.start()
	ContextActionService:BindAction("Attack", onAttack, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("Dodge", onDodge, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("IronPalm", onAbility, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)

	ContextActionService:SetTitle("Attack", "Atacar")
	ContextActionService:SetTitle("Dodge", "Esquiva")
	ContextActionService:SetTitle("IronPalm", "Palma")
	for action, position in TOUCH_LAYOUT do
		ContextActionService:SetPosition(action, position)
	end
end

return InputController
