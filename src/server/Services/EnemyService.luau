--!strict
-- Inimigos: spawn, IA e morte.
-- IA do mob corpo a corpo: persegue o jogador vivo mais próximo (linha reta quando há linha de visão;
-- PathfindingService quando há parede no caminho) e ataca com AVISO: para, fica vermelho e mostra no chão
-- a área do golpe por `telegraphTime` segundos. O golpe acerta exatamente a área mostrada (justo e legível).
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
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

type Enemy = {
	model: Model,
	def: Types.MobDef,
	humanoid: Humanoid,
	root: BasePart,
	damageMultiplier: number,
	nextAttackAt: number,
	pathParams: { [string]: any },
	waypoints: { PathWaypoint },
	waypointIndex: number,
	nextRepathAt: number,
	originalColors: { [BasePart]: Color3 },
	aggroed: boolean, -- já viu um jogador (a partir daí persegue mesmo sem linha de visão)
}

local TELEGRAPH_COLOR = Color3.fromRGB(255, 40, 40)
local WAYPOINT_REACHED_DISTANCE = 2.5
local INDICATOR_TRANSPARENCY = 0.55

local EnemyService = {}

local rng = Random.new()
local isWakeSafe: (position: Vector3) -> boolean = function(_: Vector3): boolean
	return false
end

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
	local ignore: { Instance } = CollectionService:GetTagged(Keys.Tags.Enemy)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(from, to - from, params) == nil
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
		part.Color = if active then TELEGRAPH_COLOR else color
	end
end

-- Faixa vermelha no chão exatamente onde o golpe vai acertar.
local function makeIndicator(hitCFrame: CFrame, size: Vector3, groundY: number): Part
	local indicator = Instance.new("Part")
	indicator.Name = "TelegraphIndicator"
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CanQuery = false
	indicator.CanTouch = false
	indicator.CastShadow = false
	indicator.Material = Enum.Material.Neon
	indicator.Color = TELEGRAPH_COLOR
	indicator.Transparency = INDICATOR_TRANSPARENCY
	indicator.Size = Vector3.new(size.X, 0.2, size.Z)
	local position = hitCFrame.Position
	indicator.CFrame = CFrame.new(position.X, groundY + 0.1, position.Z) * hitCFrame.Rotation
	indicator.Parent = workspace
	return indicator
end

local function hitPlayersInBox(enemy: Enemy, hitCFrame: CFrame, size: Vector3)
	local characters: { Instance } = {}
	for player in aliveCharacterRoots() do
		table.insert(characters, player.Character :: Model)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = characters

	local hitPlayers: { [Player]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(hitCFrame, size, params) do
		local character = part:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and not hitPlayers[player] then
			hitPlayers[player] = true
			CombatService.damagePlayer(player, enemy.def.damage * enemy.damageMultiplier)
		end
	end
end

local function attack(enemy: Enemy, target: BasePart)
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
	local indicator = makeIndicator(hitCFrame, size, groundY)
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

local function runAI(enemy: Enemy)
	while enemy.humanoid.Health > 0 and enemy.model.Parent do
		local target = nearestTarget(enemy)
		if target then
			local distance = flatDistance(target.Position, enemy.root.Position)
			if distance <= enemy.def.attackRange then
				if os.clock() >= enemy.nextAttackAt then
					attack(enemy, target) -- espera o aviso terminar
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
	for player, root in aliveCharacterRoots() do
		if (root.Position - position).Magnitude <= Progression.xpShareRadius then
			local gold = rng:NextInteger(enemy.def.goldMin, enemy.def.goldMax)
			ProgressionService.addXp(player, enemy.def.xp)
			ProgressionService.addGold(player, gold)
			local payload: Remotes.RewardPayload = { xp = enemy.def.xp, gold = gold, position = position }
			Remotes.get("RewardGranted"):FireClient(player, payload)
		end
	end
end

local function onDied(enemy: Enemy)
	-- Sem a tag, o mob morto sai da hitbox e da assistência de mira na hora.
	CollectionService:RemoveTag(enemy.model, Keys.Tags.Enemy)
	setTelegraphColor(enemy, false)
	grantRewards(enemy)
	for part in enemy.originalColors do
		part.Transparency = 0.6
		part.CanCollide = false
	end
	Debris:AddItem(enemy.model, Combat.corpseLifetime)
end

-- Cria um mob com IA. `statMultiplier` escala vida e dano (dificuldade do andar).
function EnemyService.spawn(def: Types.MobDef, cframe: CFrame, statMultiplier: number, parent: Instance): Model
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

function EnemyService.init() end

function EnemyService.start() end

return EnemyService
