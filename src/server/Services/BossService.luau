--!strict
-- Boss do último andar da torre. A IA é GENÉRICA: executa a lista de ataques do BossDef (Balance/Bosses),
-- então cada boss novo (tema e moveset próprios) é principalmente uma nova entrada de dados.
--
-- Comportamento:
-- - fica na arena; só persegue e ataca jogadores que estão DENTRO dela (fora dela, volta ao centro);
-- - escolhe um ataque cujo `triggerRange` alcança o alvo, mostra o aviso no chão por `telegraphTime`,
--   acerta exatamente a área mostrada e fica parado `recovery` segundos (janela para revidar);
-- - "AtPlayers" (ex.: Chuva de Rochas): um círculo embaixo de cada participante vivo na arena, em ondas seguidas
--   (cada onda mira de novo: quem anda escapa);
-- - não é empurrado; vida escala com o nº de participantes da run (coop);
-- - morto: quem tem direito (filtro do RunSessionService: na run desde antes do andar do boss) recebe o XP e o
--   Gold do boss, e o handler de "boss derrotado" é chamado com a run e a posição dele (o item garantido sai de lá).
-- Um boss por run (várias runs por servidor). A vida dele vai para o estado da run (barra no HUD).

local Debris: Debris = game:GetService("Debris")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Combat = require(Shared.Balance.Combat)

local EnemyFactory = require(script.Parent.Parent.Enemies.EnemyFactory)
local Telegraph = require(script.Parent.Parent.Enemies.Telegraph)
local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

export type ArenaBounds = {
	center: Vector3,
	halfX: number,
	halfZ: number,
	bossSpawn: Vector3,
}

type Boss = {
	run: RunRegistry.Run,
	def: Types.BossDef,
	statMultiplier: number, -- força da torre: vida (já aplicada no modelo) e dano dos ataques
	rewardMultiplier: number, -- recompensa da torre: XP e Gold
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	arena: ArenaBounds,
	groundY: number,
	nextAttackAt: number,
	originalColors: { [BasePart]: Color3 },
}

local THINK_INTERVAL = 0.1
local RAIN_ROCK_SIZE = 4 -- pedra da Chuva de Rochas (só visual)
local HOME_TOLERANCE = 4 -- studs: perto o bastante do centro, para de andar

local BossService = {}

local rng = Random.new()
local bosses: { [RunRegistry.Run]: Boss } = {}
local onDefeated: (run: RunRegistry.Run, position: Vector3) -> () = function(_: RunRegistry.Run, _: Vector3) end
local rewardFilter: (run: RunRegistry.Run, player: Player) -> boolean = function(_: RunRegistry.Run, _: Player): boolean
	return true
end

local function publishHealth(run: RunRegistry.Run, boss: Boss?)
	if boss then
		RunRegistry.setState(run, Keys.RunAttr.BossName, boss.def.displayName)
		RunRegistry.setState(run, Keys.RunAttr.BossHealth, math.max(math.floor(boss.humanoid.Health), 0))
		RunRegistry.setState(run, Keys.RunAttr.BossMaxHealth, boss.humanoid.MaxHealth)
	else
		RunRegistry.setState(run, Keys.RunAttr.BossHealth, 0)
		RunRegistry.setState(run, Keys.RunAttr.BossMaxHealth, 0)
	end
end

local function inArena(boss: Boss, position: Vector3): boolean
	local c = boss.arena.center
	return math.abs(position.X - c.X) <= boss.arena.halfX and math.abs(position.Z - c.Z) <= boss.arena.halfZ
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Participantes vivos DENTRO da arena (o corpo de cada um).
local function targetsInArena(boss: Boss): { BasePart }
	local result: { BasePart } = {}
	for _, player in boss.run.members do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and inArena(boss, root.Position) then
			table.insert(result, root)
		end
	end
	return result
end

-- Participante vivo mais próximo DENTRO da arena.
local function nearestTarget(boss: Boss): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, root in targetsInArena(boss) do
		local distance = flatDistance(root.Position, boss.root.Position)
		if distance < bestDistance then
			best = root
			bestDistance = distance
		end
	end
	return best
end

local function setTelegraphColor(boss: Boss, active: boolean)
	for part, color in boss.originalColors do
		part.Color = if active then Telegraph.COLOR else color
	end
end

-- Escolhe, entre os ataques que alcançam o alvo, um ao acaso.
local function chooseAttack(boss: Boss, distance: number): Types.BossAttackDef?
	local options: { Types.BossAttackDef } = {}
	for _, attack in boss.def.attacks do
		if distance <= attack.triggerRange then
			table.insert(options, attack)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

-- Ondas de círculos embaixo de cada participante na arena. Cada onda congela a posição de cada um no início do
-- aviso; quem está em mais de um círculo leva o golpe uma vez só. Devolve false se o boss morreu no meio.
local function performAtPlayers(boss: Boss, attack: Types.BossAttackDef): boolean
	for _ = 1, attack.waves or 1 do
		local targets = targetsInArena(boss)
		if #targets == 0 then
			break -- ninguém mais na arena: as ondas param
		end
		local centers: { Vector3 } = {}
		local indicators: { Part } = {}
		for _, root in targets do
			local center = Vector3.new(root.Position.X, boss.groundY, root.Position.Z)
			table.insert(centers, center)
			table.insert(indicators, Telegraph.circle(center, attack.range, boss.groundY))
			Telegraph.rockFall(center, boss.groundY, attack.telegraphTime, RAIN_ROCK_SIZE)
		end
		task.wait(attack.telegraphTime)
		for _, indicator in indicators do
			indicator:Destroy()
		end
		if boss.humanoid.Health <= 0 then
			return false
		end
		local hit: { [Player]: boolean } = {}
		for _, center in centers do
			for _, player in Telegraph.playersInRadius(center, attack.range, boss.groundY) do
				if not hit[player] then
					hit[player] = true
					CombatService.damagePlayer(player, attack.damage * boss.statMultiplier)
				end
			end
		end
	end
	return true
end

-- Área fixa ("Front" ou "Circle"), congelada no início do aviso: o jogador tem `telegraphTime` para sair dela.
-- Devolve false se o boss morreu durante o aviso (o golpe não sai).
local function performArea(boss: Boss, attack: Types.BossAttackDef): boolean
	local indicator: Part
	local hitPlayers: () -> { Player }
	if attack.shape == "Circle" then
		local center = boss.root.Position
		indicator = Telegraph.circle(center, attack.range, boss.groundY)
		hitPlayers = function()
			return Telegraph.playersInRadius(center, attack.range, boss.groundY)
		end
	else
		local size = Vector3.new(attack.width, Combat.hitboxHeight * 1.5, attack.range)
		local hitCFrame = boss.root.CFrame * CFrame.new(0, 0, -(boss.def.body.size.Z / 2 + attack.range / 2))
		indicator = Telegraph.rect(hitCFrame, size, boss.groundY)
		hitPlayers = function()
			return Telegraph.playersInBox(hitCFrame, size)
		end
	end
	task.wait(attack.telegraphTime)
	indicator:Destroy()
	if boss.humanoid.Health <= 0 then
		return false
	end
	for _, player in hitPlayers() do
		CombatService.damagePlayer(player, attack.damage * boss.statMultiplier)
	end
	return true
end

local function perform(boss: Boss, attack: Types.BossAttackDef, target: BasePart)
	boss.humanoid:MoveTo(boss.root.Position)
	boss.humanoid.AutoRotate = false
	boss.humanoid.WalkSpeed = 0
	local origin = boss.root.Position
	boss.root.CFrame = CFrame.lookAt(origin, Vector3.new(target.Position.X, origin.Y, target.Position.Z))

	setTelegraphColor(boss, true)
	local alive = if attack.shape == "AtPlayers" then performAtPlayers(boss, attack) else performArea(boss, attack)
	if not alive then
		return
	end
	setTelegraphColor(boss, false)

	task.wait(attack.recovery)
	if boss.humanoid.Health > 0 then
		boss.humanoid.AutoRotate = true
		boss.humanoid.WalkSpeed = boss.def.body.walkSpeed
	end
	boss.nextAttackAt = os.clock() + boss.def.attackCooldown
end

local function runAI(boss: Boss)
	while boss.humanoid.Health > 0 and boss.model.Parent do
		local target = nearestTarget(boss)
		if target then
			local distance = flatDistance(target.Position, boss.root.Position)
			local attack = if os.clock() >= boss.nextAttackAt then chooseAttack(boss, distance) else nil
			if attack then
				perform(boss, attack, target)
			else
				boss.humanoid:MoveTo(target.Position)
			end
		elseif flatDistance(boss.root.Position, boss.arena.bossSpawn) > HOME_TOLERANCE then
			boss.humanoid:MoveTo(boss.arena.bossSpawn) -- ninguém na arena: volta ao centro
		else
			boss.humanoid:MoveTo(boss.root.Position)
		end
		task.wait(THINK_INTERVAL)
	end
end

local function onDied(boss: Boss)
	local run = boss.run
	print(`[Boss] {boss.def.displayName} derrotado (run {run.id})!`)
	publishHealth(run, nil)
	local position = boss.root.Position
	-- O boss dá o grosso da recompensa da torre: para cada participante com direito (vivo ou espectando).
	local xp = math.round(boss.def.xp * boss.rewardMultiplier)
	local gold = math.round(boss.def.gold * boss.rewardMultiplier)
	for _, player in RunRegistry.members(run) do
		if rewardFilter(run, player) then
			ProgressionService.addXp(player, xp)
			ProgressionService.addGold(player, gold)
			local payload: Remotes.RewardPayload = { xp = xp, gold = gold, position = position }
			Remotes.get("RewardGranted"):FireClient(player, payload)
		end
	end
	for part in boss.originalColors do
		part.Transparency = 0.6
		part.CanCollide = false
	end
	Debris:AddItem(boss.model, Combat.corpseLifetime * 2)
	if bosses[run] == boss then
		bosses[run] = nil
	end
	onDefeated(run, position)
end

-- Cria o boss na arena da run. A vida escala com o nº de participantes da run (coop) e com a força da torre
-- (`statMultiplier`, que também vale para o dano dos ataques); `rewardMultiplier` escala o XP e o Gold.
function BossService.spawn(
	run: RunRegistry.Run,
	def: Types.BossDef,
	arena: ArenaBounds,
	groundY: number,
	parent: Instance,
	statMultiplier: number,
	rewardMultiplier: number
)
	local extraPlayers = math.max(#run.members - 1, 0)
	local healthMultiplier = (1 + def.healthPerExtraPlayer * extraPlayers) * statMultiplier
	local spawnPosition = arena.bossSpawn + Vector3.new(0, def.body.size.Y / 2 + 3, 0)
	local model = EnemyFactory.create(def.body, CFrame.new(spawnPosition), healthMultiplier)
	model:SetAttribute("KnockbackImmune", true)
	model:SetAttribute("BossId", def.id)
	model.Parent = parent
	EnemyFactory.setServerOwned(model)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	assert(humanoid and root, "boss sem Humanoid ou PrimaryPart")

	local originalColors: { [BasePart]: Color3 } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Nose" and descendant.Name ~= "Legs" then
			originalColors[descendant] = descendant.Color
		end
	end

	local boss: Boss = {
		run = run,
		def = def,
		statMultiplier = statMultiplier,
		rewardMultiplier = rewardMultiplier,
		model = model,
		humanoid = humanoid,
		root = root,
		arena = arena,
		groundY = groundY,
		nextAttackAt = os.clock() + 1.5, -- pequena folga ao primeiro contato
		originalColors = originalColors,
	}
	bosses[run] = boss
	publishHealth(run, boss)
	humanoid.HealthChanged:Connect(function()
		if bosses[run] == boss then
			publishHealth(run, boss)
		end
	end)
	humanoid.Died:Connect(function()
		onDied(boss)
	end)
	task.spawn(runAI, boss)
	print(
		`[Boss] {def.displayName} apareceu na run {run.id} com {humanoid.MaxHealth} de vida ({extraPlayers + 1} jogador(es))`
	)
end

-- Andar sem boss (andar trocado ou run encerrada): esconde a barra do HUD.
function BossService.clear(run: RunRegistry.Run)
	bosses[run] = nil
	publishHealth(run, nil)
end

function BossService.setDefeatedHandler(handler: (run: RunRegistry.Run, position: Vector3) -> ())
	onDefeated = handler
end

-- Quem recebe o XP e o Gold do boss (padrão: todos os participantes). O RunSessionService restringe aos que têm
-- direito.
function BossService.setRewardFilter(filter: (run: RunRegistry.Run, player: Player) -> boolean)
	rewardFilter = filter
end

function BossService.init() end

function BossService.start() end

return BossService
