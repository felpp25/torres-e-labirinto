--!strict
-- Boss do último andar da torre. A IA é GENÉRICA: executa a lista de ataques do BossDef (Balance/Bosses),
-- então cada boss novo (tema e moveset próprios) é principalmente uma nova entrada de dados.
--
-- Comportamento:
-- - fica na arena; só persegue e ataca jogadores que estão DENTRO dela (fora dela, volta ao centro);
-- - escolhe um ataque cujo `triggerRange` alcança o alvo, mostra o aviso no chão por `telegraphTime`,
--   acerta exatamente a área mostrada e fica parado `recovery` segundos (janela para revidar);
-- - não é empurrado; vida escala com o nº de jogadores (coop);
-- - morto: cada jogador da run recebe o XP e o Gold do boss, e o handler de "boss derrotado" é chamado.
-- Vida do boss vai para Attributes do workspace (barra no HUD).

local Debris: Debris = game:GetService("Debris")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Combat = require(Shared.Balance.Combat)

local EnemyFactory = require(script.Parent.Parent.Enemies.EnemyFactory)
local Telegraph = require(script.Parent.Parent.Enemies.Telegraph)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

export type ArenaBounds = {
	center: Vector3,
	halfX: number,
	halfZ: number,
	bossSpawn: Vector3,
}

type Boss = {
	def: Types.BossDef,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	arena: ArenaBounds,
	groundY: number,
	nextAttackAt: number,
	originalColors: { [BasePart]: Color3 },
}

local THINK_INTERVAL = 0.1
local HOME_TOLERANCE = 4 -- studs: perto o bastante do centro, para de andar

local BossService = {}

local rng = Random.new()
local current: Boss? = nil
local onDefeated: () -> () = function() end

local function publishHealth(boss: Boss?)
	if boss then
		workspace:SetAttribute(Keys.WorldAttr.BossName, boss.def.displayName)
		workspace:SetAttribute(Keys.WorldAttr.BossHealth, math.max(math.floor(boss.humanoid.Health), 0))
		workspace:SetAttribute(Keys.WorldAttr.BossMaxHealth, boss.humanoid.MaxHealth)
	else
		workspace:SetAttribute(Keys.WorldAttr.BossHealth, 0)
		workspace:SetAttribute(Keys.WorldAttr.BossMaxHealth, 0)
	end
end

local function inArena(boss: Boss, position: Vector3): boolean
	local c = boss.arena.center
	return math.abs(position.X - c.X) <= boss.arena.halfX and math.abs(position.Z - c.Z) <= boss.arena.halfZ
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Jogador vivo mais próximo DENTRO da arena.
local function nearestTarget(boss: Boss): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and inArena(boss, root.Position) then
			local distance = flatDistance(root.Position, boss.root.Position)
			if distance < bestDistance then
				best = root
				bestDistance = distance
			end
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

local function perform(boss: Boss, attack: Types.BossAttackDef, target: BasePart)
	boss.humanoid:MoveTo(boss.root.Position)
	boss.humanoid.AutoRotate = false
	boss.humanoid.WalkSpeed = 0
	local origin = boss.root.Position
	boss.root.CFrame = CFrame.lookAt(origin, Vector3.new(target.Position.X, origin.Y, target.Position.Z))

	-- A área do golpe é "congelada" no início do aviso: o jogador tem `telegraphTime` para sair dela.
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

	setTelegraphColor(boss, true)
	task.wait(attack.telegraphTime)
	indicator:Destroy()
	if boss.humanoid.Health <= 0 then
		return
	end
	setTelegraphColor(boss, false)
	for _, player in hitPlayers() do
		CombatService.damagePlayer(player, attack.damage)
	end

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
	print(`[Boss] {boss.def.displayName} derrotado!`)
	publishHealth(nil)
	-- O boss dá o grosso da recompensa da torre: para CADA jogador da run (vivo ou espectando).
	for _, player in Players:GetPlayers() do
		ProgressionService.addXp(player, boss.def.xp)
		ProgressionService.addGold(player, boss.def.gold)
		local payload: Remotes.RewardPayload = { xp = boss.def.xp, gold = boss.def.gold, position = boss.root.Position }
		Remotes.get("RewardGranted"):FireClient(player, payload)
	end
	for part in boss.originalColors do
		part.Transparency = 0.6
		part.CanCollide = false
	end
	Debris:AddItem(boss.model, Combat.corpseLifetime * 2)
	if current == boss then
		current = nil
	end
	onDefeated()
end

-- Cria o boss na arena. A vida escala com o nº de jogadores no servidor (coop).
function BossService.spawn(def: Types.BossDef, arena: ArenaBounds, groundY: number, parent: Instance)
	local extraPlayers = math.max(#Players:GetPlayers() - 1, 0)
	local healthMultiplier = 1 + def.healthPerExtraPlayer * extraPlayers
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
		def = def,
		model = model,
		humanoid = humanoid,
		root = root,
		arena = arena,
		groundY = groundY,
		nextAttackAt = os.clock() + 1.5, -- pequena folga ao primeiro contato
		originalColors = originalColors,
	}
	current = boss
	publishHealth(boss)
	humanoid.HealthChanged:Connect(function()
		if current == boss then
			publishHealth(boss)
		end
	end)
	humanoid.Died:Connect(function()
		onDied(boss)
	end)
	task.spawn(runAI, boss)
	print(`[Boss] {def.displayName} apareceu com {humanoid.MaxHealth} de vida ({extraPlayers + 1} jogador(es))`)
end

-- Andar sem boss (ou andar trocado): esconde a barra do HUD.
function BossService.clear()
	current = nil
	publishHealth(nil)
end

function BossService.setDefeatedHandler(handler: () -> ())
	onDefeated = handler
end

function BossService.init()
	publishHealth(nil)
end

function BossService.start() end

return BossService
