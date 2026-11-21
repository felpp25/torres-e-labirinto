--!strict
-- Entrada do jogador (PC, controle e celular) -> intenções para o servidor.
-- ContextActionService: cada ação vale para teclado/mouse/controle e, no celular, ganha um botão na tela.
-- O cliente faz uma PREVISÃO (recarga, stamina, combo) só para responder na hora; quem decide é o servidor.
--
-- PC: clique = ataque (combo de 3) | Q = esquiva | 1 = Palma de Ferro | 2 = Foco Interior | 3 = Chute Giratório
--     | 4 = ultimate (Rajada de Cem Punhos)
-- Controle: R2 = ataque | B = esquiva | Y = Palma | R1 = Foco | L2 = Chute | L1 = ultimate
-- Celular: botões "Atacar", "Esquiva", "Palma", "Foco", "Chute" e "Rajada" na tela
-- As teclas das habilidades vêm de client/Hotkeys, na ordem das habilidades da classe.

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

local Hotkeys = require(script.Parent.Parent:WaitForChild("Hotkeys"))
local CombatFeedbackController = require(script.Parent.CombatFeedbackController)

local localPlayer = Players.LocalPlayer

-- Posições dos botões no celular (perto do botão de pular, canto inferior direito). Habilidades: Hotkeys.
local TOUCH_LAYOUT: { [string]: UDim2 } = {
	Attack = UDim2.new(1, -190, 1, -120),
	Dodge = UDim2.new(1, -120, 1, -200),
}

local InputController = {}

-- Previsões locais, no relógio do servidor (workspace:GetServerTimeNow).
local nextAttackAt = 0
local comboIndex = 0
local comboExpiresAt = 0
local dodgeReadyAt = 0
local abilityReadyAt: { [string]: number } = {}
local channelUntil = 0 -- preso na Rajada: sem esquiva nem outras habilidades até aqui (o servidor também trava)

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
	if t < math.max(dodgeReadyAt, numberAttribute(Keys.PlayerAttr.DodgeReadyAt), channelUntil) then
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

local function makeAbilityHandler(abilityId: string)
	return function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local def = Abilities[abilityId]
		local _, _, root = getAliveCharacter()
		local t = now()
		if not def or not root or t < math.max(nextAttackAt, channelUntil) then
			return Enum.ContextActionResult.Sink
		end
		if t < math.max(abilityReadyAt[abilityId] or 0, numberAttribute(Keys.abilityReadyAttr(abilityId))) then
			return Enum.ContextActionResult.Sink
		end
		if numberAttribute(Keys.resourceAttr(def.resource)) < def.cost then
			return Enum.ContextActionResult.Sink
		end
		abilityReadyAt[abilityId] = t + def.cooldown
		nextAttackAt = t + def.recovery
		comboExpiresAt = 0

		if def.kind == "Strike" and def.shape == "Circle" then
			Remotes.get("AbilityRequest"):FireServer(abilityId)
			CombatFeedbackController.playSpin(root, def.range)
		elseif def.kind == "Strike" then
			local range = def.range + Combat.rangeTolerance
			local direction = aimDirection(root, range)
			face(root, direction)
			Remotes.get("AbilityRequest"):FireServer(abilityId)
			CombatFeedbackController.playSwing(root, direction, def.range, def.width, true)
		elseif def.kind == "Barrage" then
			local duration = def.hits * def.hitInterval
			channelUntil = t + duration
			nextAttackAt = t + duration + def.recovery
			local range = def.range + Combat.rangeTolerance
			local direction = aimDirection(root, range)
			face(root, direction)
			Remotes.get("AbilityRequest"):FireServer(abilityId)
			CombatFeedbackController.playBarrage(root, direction, def.range, def.width, def.hits, def.hitInterval)
		else
			-- Efeito em si mesmo: a cura (número verde) e a aura vêm do servidor.
			Remotes.get("AbilityRequest"):FireServer(abilityId)
		end
		return Enum.ContextActionResult.Sink
	end
end

function InputController.init() end

function InputController.start()
	ContextActionService:BindAction("Attack", onAttack, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("Dodge", onDodge, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)

	ContextActionService:SetTitle("Attack", "Atacar")
	ContextActionService:SetTitle("Dodge", "Esquiva")
	for action, position in TOUCH_LAYOUT do
		ContextActionService:SetPosition(action, position)
	end

	-- Uma ação por habilidade da classe e uma para a ultimate (o nome da ação é o id da habilidade).
	local function bindAbility(abilityId: string, slot: Hotkeys.Slot)
		local def = Abilities[abilityId]
		if not def then
			return
		end
		ContextActionService:BindAction(abilityId, makeAbilityHandler(abilityId), true, slot.key, slot.pad)
		ContextActionService:SetTitle(abilityId, def.shortName)
		ContextActionService:SetPosition(abilityId, slot.touch)
	end
	local classDef = Classes.byId[Classes.defaultClassId]
	for index, abilityId in classDef.abilities do
		local slot = Hotkeys.abilities[index]
		if slot then
			bindAbility(abilityId, slot)
		end
	end
	bindAbility(classDef.ultimate, Hotkeys.ultimate)
end

return InputController
