--!strict
-- Inimigos: spawn, IA e morte.
-- IA: persegue o jogador vivo mais próximo (linha reta quando há linha de visão; PathfindingService quando há parede
-- no caminho) e ataca com AVISO: para, fica vermelho e mostra no chão a área do golpe por `telegraphTime` segundos.
-- O golpe acerta exatamente a área mostrada (justo e legível).
-- - "Melee" (Brutamontes): faixa à frente do mob; se ele morrer durante o aviso, o golpe não sai.
-- - "Lob" (Arremessador): círculo onde o jogador estava; ataca de longe (precisa de linha de visão) e não se afasta.
--   A pedra já está no ar: cai mesmo se ele morrer durante o aviso (círculo no chão = perigo, sempre).
-- Morte: XP inteiro para cada jogador vivo por perto; Gold sorteado individualmente para cada um.

local CollectionService: CollectionService = game:GetService("CollectionService")
local Debris: Debris = game:GetService("Debris")
local PathfindingService: PathfindingService = game:GetService("PathfindingService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Combat = require(Shared.Balance.Combat)
local Progression = require(Shared.Balance.Progression)

local EnemyFactory = require(script.Parent.Parent.Enemies.EnemyFactory)
local Telegraph = require(script.Parent.Parent.Enemies.Telegraph)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

type Enemy = {
	model: Model,
	def: Types.MobDef,
	humanoid: Humanoid,
	root: BasePart,
	damageMultiplier: number,
	rewardMultiplier: number, -- XP e Gold (recompensa da torre)
	nextAttackAt: number,
	pathParams: { [string]: any },
	waypoints: { PathWaypoint },
	waypointIndex: number,
	nextRepathAt: number,
	originalColors: { [BasePart]: Color3 },
	aggroed: boolean, -- já viu um jogador (a partir daí persegue mesmo sem linha de visão)
}

local WAYPOINT_REACHED_DISTANCE = 2.5
local ROCK_SIZE = 2.5 -- pedra do "Lob" (só visual: Telegraph.rockFall)
local GROUND_PROBE = 20 -- studs procurando o chão embaixo do alvo
local TORSO_HEIGHT = 3 -- sem chão achado: o chão fica esta distância abaixo do centro do personagem

local EnemyService = {}

local rng = Random.new()
local isWakeSafe: (position: Vector3) -> boolean = function(_: Vector3): boolean
	return false
end
-- Chamado quando um mob morre (drops da run, ex.: Coração). `parent` = pasta onde o mob estava.
local deathHandler: (def: Types.MobDef, position: Vector3, parent: Instance) -> () = function(
	_: Types.MobDef,
	_: Vector3,
	_: Instance
)
end

-- Ouvintes do crédito de cada mob derrotado (ex.: MissionService): quem recebeu o XP dele e a pasta onde ele estava.
local killListeners: { (player: Player, def: Types.MobDef, parent: Instance) -> () } = {}

local function aliveCharacterRoots(): { [Player]: BasePart }
	local result: { [Player]: BasePart } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			result[player] = root
		end
	end
	return result
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Raycast que só enxerga o mapa (ignora inimigos e personagens; os avisos no chão já não são consultáveis).
local function mapOnlyParams(): RaycastParams
	local ignore: { Instance } = CollectionService:GetTagged(Keys.Tags.Enemy)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

-- Linha de visão: nada além de inimigos e personagens entre o mob e o alvo.
local hasLineOfSight: (from: Vector3, to: Vector3) -> boolean

-- Mob "dormindo" só acorda ao VER um jogador dentro do aggroRange (paredes bloqueiam).
-- Acordado, persegue o jogador vivo mais próximo dentro do aggroRange × leash, mesmo atrás de paredes.
local function nearestTarget(enemy: Enemy): BasePart?
	local best: BasePart? = nil
	local maxDistance = if enemy.aggroed
		then enemy.def.aggroRange * Combat.enemyLeashMultiplier
		else enemy.def.aggroRange
	local bestDistance = maxDistance
	for _, root in aliveCharacterRoots() do
		local distance = (root.Position - enemy.root.Position).Magnitude
		local canWake = not isWakeSafe(root.Position) and hasLineOfSight(enemy.root.Position, root.Position)
		if distance <= bestDistance and (enemy.aggroed or canWake) then
			best = root
			bestDistance = distance
		end
	end
	if best then
		enemy.aggroed = true
	end
	return best
end

function hasLineOfSight(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, mapOnlyParams()) == nil
end

-- Altura do chão embaixo de uma posição (ex.: o jogador no ar, pulando).
local function groundBelow(position: Vector3): number
	local hit = workspace:Raycast(position, Vector3.new(0, -GROUND_PROBE, 0), mapOnlyParams())
	return if hit then hit.Position.Y else position.Y - TORSO_HEIGHT
end

local function moveTowards(enemy: Enemy, targetPosition: Vector3)
	if hasLineOfSight(enemy.root.Position, targetPosition) then
		enemy.waypoints = {}
		enemy.humanoid:MoveTo(targetPosition)
		return
	end

	local t = os.clock()
	if t >= enemy.nextRepathAt then
		enemy.nextRepathAt = t + Combat.enemyRepathInterval
		local path = PathfindingService:CreatePath(enemy.pathParams)
		local ok = pcall(function()
			path:ComputeAsync(enemy.root.Position, targetPosition)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			enemy.waypoints = path:GetWaypoints()
			enemy.waypointIndex = 2 -- o 1º waypoint é a posição atual
		else
			enemy.waypoints = {}
		end
	end

	local waypoint = enemy.waypoints[enemy.waypointIndex]
	if waypoint and flatDistance(waypoint.Position, enemy.root.Position) < WAYPOINT_REACHED_DISTANCE then
		enemy.waypointIndex += 1
		waypoint = enemy.waypoints[enemy.waypointIndex]
	end
	if waypoint then
		enemy.humanoid:MoveTo(waypoint.Position)
	end
end

local function stop(enemy: Enemy)
	enemy.humanoid:MoveTo(enemy.root.Position)
end

local function setTelegraphColor(enemy: Enemy, active: boolean)
	for part, color in enemy.originalColors do
		part.Color = if active then Telegraph.COLOR else color
	end
end

local function hitPlayersInBox(enemy: Enemy, hitCFrame: CFrame, size: Vector3)
	for _, player in Telegraph.playersInBox(hitCFrame, size) do
		CombatService.damagePlayer(player, enemy.def.damage * enemy.damageMultiplier)
	end
end

local function meleeAttack(enemy: Enemy, target: BasePart)
	stop(enemy)
	enemy.humanoid.AutoRotate = false
	enemy.humanoid.WalkSpeed = 0

	-- Vira para o alvo e "congela" a área do golpe neste instante.
	local origin = enemy.root.Position
	enemy.root.CFrame = CFrame.lookAt(origin, Vector3.new(target.Position.X, origin.Y, target.Position.Z))
	local size = Vector3.new(enemy.def.hitWidth, Combat.hitboxHeight, enemy.def.hitRange)
	local hitCFrame = enemy.root.CFrame * CFrame.new(0, 0, -enemy.def.hitRange / 2)
	local groundY = origin.Y - enemy.root.Size.Y / 2 - enemy.humanoid.HipHeight

	setTelegraphColor(enemy, true)
	local indicator = Telegraph.rect(hitCFrame, size, groundY)
	task.wait(enemy.def.telegraphTime)
	indicator:Destroy()

	if enemy.humanoid.Health > 0 then
		setTelegraphColor(enemy, false)
		hitPlayersInBox(enemy, hitCFrame, size)
		enemy.humanoid.AutoRotate = true
		enemy.humanoid.WalkSpeed = enemy.def.walkSpeed
	end
	enemy.nextAttackAt = os.clock() + enemy.def.attackCooldown
end

local function lobAttack(enemy: Enemy, target: BasePart)
	stop(enemy)
	local origin = enemy.root.Position
	enemy.root.CFrame = CFrame.lookAt(origin, Vector3.new(target.Position.X, origin.Y, target.Position.Z))

	-- O círculo fica onde o jogador está AGORA: dá para sair dele durante o aviso.
	local center = target.Position
	local groundY = groundBelow(center)
	local radius = enemy.def.areaRadius or 0
	local damage = enemy.def.damage * enemy.damageMultiplier
	local telegraphTime = enemy.def.telegraphTime

	setTelegraphColor(enemy, true)
	local indicator = Telegraph.circle(center, radius, groundY)
	Telegraph.rockFall(center, groundY, telegraphTime, ROCK_SIZE)
	task.wait(telegraphTime)
	indicator:Destroy()
	for _, player in Telegraph.playersInRadius(center, radius, groundY) do
		CombatService.damagePlayer(player, damage)
	end

	if enemy.humanoid.Health > 0 then
		setTelegraphColor(enemy, false)
	end
	enemy.nextAttackAt = os.clock() + enemy.def.attackCooldown
end

-- Pode atacar daqui? Corpo a corpo: basta o alcance. À distância: alcance + linha de visão (não arremessa por cima
-- da parede em quem não vê; sem linha de visão, anda até enxergar).
local function canAttackFrom(enemy: Enemy, target: BasePart, distance: number): boolean
	if distance > enemy.def.attackRange then
		return false
	end
	return enemy.def.attack ~= "Lob" or hasLineOfSight(enemy.root.Position, target.Position)
end

local function runAI(enemy: Enemy)
	while enemy.humanoid.Health > 0 and enemy.model.Parent do
		local target = nearestTarget(enemy)
		if target then
			local distance = flatDistance(target.Position, enemy.root.Position)
			if canAttackFrom(enemy, target, distance) then
				if os.clock() >= enemy.nextAttackAt then
					-- espera o aviso terminar
					if enemy.def.attack == "Lob" then
						lobAttack(enemy, target)
					else
						meleeAttack(enemy, target)
					end
				else
					stop(enemy) -- perto, esperando a recarga do golpe
				end
			else
				moveTowards(enemy, target.Position)
			end
		else
			stop(enemy)
		end
		task.wait(Combat.enemyThinkInterval)
	end
end

local function grantRewards(enemy: Enemy)
	local position = enemy.root.Position
	local parent = enemy.model.Parent
	for player, root in aliveCharacterRoots() do
		if (root.Position - position).Magnitude <= Progression.xpShareRadius then
			if parent and enemy.def.xp > 0 then
				for _, listener in killListeners do
					task.spawn(listener, player, enemy.def, parent)
				end
			end
			local gold = math.round(rng:NextInteger(enemy.def.goldMin, enemy.def.goldMax) * enemy.rewardMultiplier)
			local xp = math.round(enemy.def.xp * enemy.rewardMultiplier)
			ProgressionService.addXp(player, xp)
			ProgressionService.addGold(player, gold)
			local payload: Remotes.RewardPayload = { xp = xp, gold = gold, position = position }
			Remotes.get("RewardGranted"):FireClient(player, payload)
		end
	end
end

local function onDied(enemy: Enemy)
	-- Sem a tag, o mob morto sai da hitbox e da assistência de mira na hora.
	CollectionService:RemoveTag(enemy.model, Keys.Tags.Enemy)
	setTelegraphColor(enemy, false)
	grantRewards(enemy)
	local parent = enemy.model.Parent
	if parent then
		deathHandler(enemy.def, enemy.root.Position, parent)
	end
	for part in enemy.originalColors do
		part.Transparency = 0.6
		part.CanCollide = false
	end
	Debris:AddItem(enemy.model, Combat.corpseLifetime)
end

-- Cria um mob com IA. `statMultiplier` escala vida e dano (dificuldade do andar e da torre); `rewardMultiplier`
-- escala o XP e o Gold (recompensa da torre; padrão 1).
function EnemyService.spawn(
	def: Types.MobDef,
	cframe: CFrame,
	statMultiplier: number,
	parent: Instance,
	rewardMultiplier: number?
): Model
	local model = EnemyFactory.create(def, cframe, statMultiplier)
	model.Parent = parent
	EnemyFactory.setServerOwned(model)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	assert(humanoid and root, "inimigo sem Humanoid ou PrimaryPart")

	local originalColors: { [BasePart]: Color3 } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Nose" and descendant.Name ~= "Legs" then
			originalColors[descendant] = descendant.Color
		end
	end

	local enemy: Enemy = {
		model = model,
		def = def,
		humanoid = humanoid,
		root = root,
		damageMultiplier = statMultiplier,
		rewardMultiplier = rewardMultiplier or 1,
		nextAttackAt = 0,
		pathParams = {
			AgentRadius = math.max(def.size.X, def.size.Z) / 2 + 0.5,
			AgentHeight = def.size.Y + 2,
			AgentCanJump = false,
		},
		waypoints = {},
		waypointIndex = 1,
		nextRepathAt = 0,
		originalColors = originalColors,
		aggroed = false,
	}
	humanoid.Died:Connect(function()
		onDied(enemy)
	end)
	task.spawn(runAI, enemy)
	return model
end

-- Zona segura para ACORDAR mobs (ex.: a sala de Entrada do andar): um jogador ali não acorda mobs dormindo,
-- mas mobs já acordados continuam perseguindo. Evita emboscada no instante em que o jogador nasce.
function EnemyService.setWakeSafeZone(predicate: (position: Vector3) -> boolean)
	isWakeSafe = predicate
end

-- Chamado para CADA jogador que recebe o XP de um mob derrotado (mobs sem recompensa, como o boneco, não contam).
function EnemyService.addKillListener(listener: (player: Player, def: Types.MobDef, parent: Instance) -> ())
	table.insert(killListeners, listener)
end

function EnemyService.setDeathHandler(handler: (def: Types.MobDef, position: Vector3, parent: Instance) -> ())
	deathHandler = handler
end

function EnemyService.init() end

function EnemyService.start() end

return EnemyService
