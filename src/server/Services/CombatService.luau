--!strict
-- Combate: recebe as INTENÇÕES do cliente (atacar, esquivar, usar habilidade), valida e aplica o resultado.
-- O servidor decide tudo: em que golpe do combo o jogador está, recargas, custo, hitbox, dano, crítico, empurrão.
-- O cliente nunca informa alvo, posição ou dano.

local CollectionService: CollectionService = game:GetService("CollectionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Keys = require(Shared.Keys)
local Motion = require(Shared.Motion)
local Combat = require(Shared.Balance.Combat)
local Abilities = require(Shared.Balance.Abilities)

local ProgressionService = require(script.Parent.ProgressionService)

type CombatState = {
	comboIndex: number, -- golpe atual do combo (0 = nenhum ainda)
	nextAttackAt: number, -- tempo do servidor a partir do qual pode atacar de novo
	comboExpiresAt: number, -- depois disso, o próximo ataque volta ao 1º golpe
	dodgeReadyAt: number,
	invulnerableUntil: number,
	abilityReadyAt: { [string]: number },
	stamina: number,
	mana: number,
	lastStaminaUseAt: number,
}

local RESOURCE_TICK = 0.1 -- s entre atualizações de regeneração
local MAX_ABILITY_ID_LENGTH = 32

local CombatService = {}

local states: { [Player]: CombatState } = {}
local rng = Random.new()

-- Relógio sincronizado com os clientes (os horários de recarga são replicados nele).
local function now(): number
	return workspace:GetServerTimeNow()
end

local function newState(player: Player): CombatState
	local classDef = ProgressionService.getClass(player)
	local attributes = ProgressionService.getAttributes(player)
	return {
		comboIndex = 0,
		nextAttackAt = 0,
		comboExpiresAt = 0,
		dodgeReadyAt = 0,
		invulnerableUntil = 0,
		abilityReadyAt = {},
		stamina = Formulas.maxStamina(classDef, attributes),
		mana = Formulas.maxMana(classDef, attributes),
		lastStaminaUseAt = 0,
	}
end

local function setIfChanged(player: Player, name: string, value: number)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function replicateResources(player: Player, state: CombatState, maxStamina: number, maxMana: number)
	setIfChanged(player, Keys.PlayerAttr.Stamina, math.floor(state.stamina))
	setIfChanged(player, Keys.PlayerAttr.MaxStamina, maxStamina)
	setIfChanged(player, Keys.PlayerAttr.Mana, math.floor(state.mana))
	setIfChanged(player, Keys.PlayerAttr.MaxMana, maxMana)
end

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function enemyFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") and CollectionService:HasTag(current, Keys.Tags.Enemy) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function aliveEnemies(): { Model }
	local result: { Model } = {}
	for _, instance in CollectionService:GetTagged(Keys.Tags.Enemy) do
		if instance:IsA("Model") and instance.PrimaryPart then
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(result, instance)
			end
		end
	end
	return result
end

-- Direção do golpe com assistência de mira (mesma função que o cliente usa para o visual).
local function aimDirection(root: BasePart, range: number): Vector3
	local positions: { Vector3 } = {}
	for _, enemy in aliveEnemies() do
		local primary = enemy.PrimaryPart
		if primary then
			table.insert(positions, primary.Position)
		end
	end
	return Formulas.chooseAimDirection(root.Position, root.CFrame.LookVector, positions, range, Combat.aimAssistAngle)
end

-- Inimigos vivos dentro da caixa à frente do personagem (na direção `direction`).
local function queryEnemies(root: BasePart, direction: Vector3, range: number, width: number): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Keys.Tags.Enemy)

	local origin = root.Position
	local boxCFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -range / 2)
	local parts = workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(width, Combat.hitboxHeight, range), params)

	local found: { Model } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in parts do
		local enemy = enemyFromPart(part)
		if enemy and not seen[enemy] then
			seen[enemy] = true
			table.insert(found, enemy)
		end
	end
	return found
end

-- Empurrão via Motion.push (LinearVelocity por um instante, parando antes de paredes, força limitada).
-- Só mudar a velocidade não funciona: o Humanoid freia na hora (a Palma movia o alvo ~1 stud).
local function applyKnockback(enemy: Model, direction: Vector3, strength: number)
	local root = enemy.PrimaryPart
	-- Bosses não são empurrados (Attribute "KnockbackImmune" no modelo).
	if strength <= 0 or not root or enemy:GetAttribute("KnockbackImmune") == true then
		return
	end
	local ignore: { Instance } = { enemy }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	Motion.push(root, direction, strength, Combat.knockbackDuration, ignore)
end

local function damageEnemy(
	attacker: Player,
	enemy: Model,
	baseDamage: number,
	damageType: Types.DamageType,
	direction: Vector3,
	knockback: number,
	isFinisher: boolean
)
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local classDef = ProgressionService.getClass(attacker)
	local attributes = ProgressionService.getAttributes(attacker)
	local raw = Formulas.damage(baseDamage, damageType, attributes, classDef)
	local isCrit = Formulas.rollCrit(attributes.Luck, rng:NextNumber())
	if isCrit then
		raw *= Combat.critMultiplier
	end
	local defenseValue = enemy:GetAttribute("Defense")
	local defense = if typeof(defenseValue) == "number" then defenseValue else 0
	local damage = math.max(1, math.round(Formulas.applyDefense(raw, defense)))

	humanoid.Health = math.max(humanoid.Health - damage, 0)
	applyKnockback(enemy, direction, knockback)

	local payload: Remotes.CombatFeedbackPayload = {
		target = enemy,
		attacker = attacker,
		damage = damage,
		isCrit = isCrit,
		isFinisher = isFinisher,
	}
	Remotes.get("CombatFeedback"):FireAllClients(payload)
end

local function trySpend(state: CombatState, resource: Types.ResourceType, cost: number): boolean
	if resource == "Stamina" then
		if state.stamina < cost then
			return false
		end
		state.stamina -= cost
		state.lastStaminaUseAt = now()
	else
		if state.mana < cost then
			return false
		end
		state.mana -= cost
	end
	return true
end

local function onAttackRequest(player: Player)
	local state = states[player]
	local root = getAliveRoot(player)
	if not state or not root then
		return
	end
	local t = now()
	if t + Combat.serverTimingTolerance < state.nextAttackAt then
		return -- ainda na recuperação do golpe anterior
	end

	local combo = ProgressionService.getClass(player).combo
	state.comboIndex = if t > state.comboExpiresAt then 1 else state.comboIndex % #combo + 1
	local hit = combo[state.comboIndex]
	state.nextAttackAt = t + hit.recovery
	state.comboExpiresAt = t + hit.recovery + Combat.comboWindow

	local range = hit.range + Combat.rangeTolerance
	local direction = aimDirection(root, range)
	for _, enemy in queryEnemies(root, direction, range, hit.width) do
		damageEnemy(player, enemy, hit.baseDamage, "Physical", direction, hit.knockback, hit.isFinisher)
	end
end

local function onDodgeRequest(player: Player)
	local state = states[player]
	if not state or not getAliveRoot(player) then
		return
	end
	local t = now()
	if t + Combat.serverTimingTolerance < state.dodgeReadyAt then
		return
	end
	if not trySpend(state, "Stamina", Combat.dodge.staminaCost) then
		return
	end
	state.dodgeReadyAt = t + Combat.dodge.cooldown
	state.invulnerableUntil = t + Combat.dodge.invulnerableTime
	player:SetAttribute(Keys.PlayerAttr.DodgeReadyAt, state.dodgeReadyAt)
end

local function onAbilityRequest(player: Player, abilityId: unknown)
	-- Validação do que veio do cliente: tipo, tamanho e se a classe do jogador tem essa habilidade.
	if typeof(abilityId) ~= "string" or #abilityId > MAX_ABILITY_ID_LENGTH then
		return
	end
	local classDef = ProgressionService.getClass(player)
	local def = Abilities[abilityId]
	if not def or not table.find(classDef.abilities, abilityId) then
		return
	end

	local state = states[player]
	local root = getAliveRoot(player)
	if not state or not root then
		return
	end
	local t = now()
	if t + Combat.serverTimingTolerance < (state.abilityReadyAt[abilityId] or 0) then
		return
	end
	if not trySpend(state, def.resource, def.cost) then
		return
	end
	state.abilityReadyAt[abilityId] = t + def.cooldown
	state.nextAttackAt = math.max(state.nextAttackAt, t + def.recovery)
	state.comboExpiresAt = 0 -- habilidade quebra o combo
	player:SetAttribute(Keys.abilityReadyAttr(abilityId), state.abilityReadyAt[abilityId])

	local range = def.range + Combat.rangeTolerance
	local direction = aimDirection(root, range)
	for _, enemy in queryEnemies(root, direction, range, def.width) do
		damageEnemy(player, enemy, def.baseDamage, def.damageType, direction, def.knockback, true)
	end
end

local function resetState(player: Player)
	local state = newState(player)
	states[player] = state
	local classDef = ProgressionService.getClass(player)
	local attributes = ProgressionService.getAttributes(player)
	replicateResources(player, state, Formulas.maxStamina(classDef, attributes), Formulas.maxMana(classDef, attributes))
end

local function onPlayerAdded(player: Player)
	resetState(player)
	player.CharacterAdded:Connect(function()
		resetState(player)
	end)
end

-- Poção de stamina: soma `fraction` da stamina máxima.
function CombatService.addStamina(player: Player, fraction: number)
	local state = states[player]
	if not state then
		return
	end
	local maxStamina =
		Formulas.maxStamina(ProgressionService.getClass(player), ProgressionService.getAttributes(player))
	state.stamina = math.min(maxStamina, state.stamina + maxStamina * fraction)
	replicateResources(
		player,
		state,
		maxStamina,
		Formulas.maxMana(ProgressionService.getClass(player), ProgressionService.getAttributes(player))
	)
end

function CombatService.isStaminaFull(player: Player): boolean
	local state = states[player]
	if not state then
		return true
	end
	return state.stamina
		>= Formulas.maxStamina(ProgressionService.getClass(player), ProgressionService.getAttributes(player))
end

-- Stamina e mana cheias (checkpoint).
function CombatService.restoreResources(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local classDef = ProgressionService.getClass(player)
	local attributes = ProgressionService.getAttributes(player)
	state.stamina = Formulas.maxStamina(classDef, attributes)
	state.mana = Formulas.maxMana(classDef, attributes)
	replicateResources(player, state, state.stamina, state.mana)
end

-- Usado por quem causa dano ao jogador (mobs, M3): durante a esquiva o jogador não toma dano.
function CombatService.isInvulnerable(player: Player): boolean
	local state = states[player]
	return state ~= nil and now() < state.invulnerableUntil
end

-- Dano em um jogador (vindo de mobs). Respeita a invencibilidade da esquiva e a Defesa do jogador.
-- Devolve true se o dano foi aplicado.
function CombatService.damagePlayer(player: Player, rawDamage: number): boolean
	if CombatService.isInvulnerable(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local attributes = ProgressionService.getAttributes(player)
	local damage = math.max(1, math.round(Formulas.applyDefense(rawDamage, attributes.Defense)))
	humanoid.Health = math.max(humanoid.Health - damage, 0)

	local payload: Remotes.CombatFeedbackPayload = {
		target = character,
		attacker = nil,
		damage = damage,
		isCrit = false,
		isFinisher = false,
	}
	Remotes.get("CombatFeedback"):FireAllClients(payload)
	return true
end

function CombatService.init()
	Remotes.get("AttackRequest").OnServerEvent:Connect(onAttackRequest)
	Remotes.get("DodgeRequest").OnServerEvent:Connect(onDodgeRequest)
	Remotes.get("AbilityRequest").OnServerEvent:Connect(onAbilityRequest)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

-- Regeneração de stamina (depois de um tempo sem gastar) e de mana (contínua).
function CombatService.start()
	while true do
		local dt = task.wait(RESOURCE_TICK)
		local t = now()
		for player, state in states do
			local classDef = ProgressionService.getClass(player)
			local attributes = ProgressionService.getAttributes(player)
			local maxStamina = Formulas.maxStamina(classDef, attributes)
			local maxMana = Formulas.maxMana(classDef, attributes)
			if t - state.lastStaminaUseAt >= Combat.staminaRegenDelay then
				state.stamina = math.min(maxStamina, state.stamina + Combat.staminaRegenPerSecond * dt)
			end
			state.mana = math.min(maxMana, state.mana + Combat.manaRegenPerSecond * dt)
			replicateResources(player, state, maxStamina, maxMana)
		end
	end
end

return CombatService
