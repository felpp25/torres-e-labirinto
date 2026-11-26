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
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

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
	highlight: Highlight?, -- brilho do aviso no modelo vestido (a cor da peça não muda a textura)
}

local VISUAL_JOINT = Keys.BossVisual.Joint
local VISUAL_TELEGRAPH = Keys.BossVisual.Telegraph
local VISUAL_ATTACK = Keys.BossVisual.Attack
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

-- `attackId`: o golpe do aviso (o cliente escolhe o movimento por ele: braços no golpe pesado, perna no pisão)
local function setTelegraphColor(boss: Boss, active: boolean, attackId: string?)
	for part, color in boss.originalColors do
		part.Color = if active then Telegraph.COLOR else color
	end
	if boss.highlight then
		boss.highlight.Enabled = active
	end
	-- o cliente (BossVisualController) arma o golpe no aviso e bate quando ele acaba
	if active then
		boss.model:SetAttribute(VISUAL_ATTACK, attackId)
	end
	boss.model:SetAttribute(VISUAL_TELEGRAPH, active)
end

-- Veste o chefão com o modelo dele (ServerStorage.ChefoesModelos.<bossId>, montado por scripts/chefoes-modelos.luau):
-- as peças do modelo (só aparência, sem colisão nem consulta) ficam presas por Motor6D, cada uma na peça "Pai" dela
-- (ou no corpo), girando em volta da "Junta" (Attributes do modelo). O corpo do código (a caixa) fica invisível, mas
-- continua sendo a colisão e o alvo dos golpes. Sem modelo, fica o greybox.
local function dress(model: Model, def: Types.BossDef): Highlight?
	local folder = ServerStorage:FindFirstChild("ChefoesModelos")
	local template = folder and folder:FindFirstChild(def.id)
	local root = model.PrimaryPart
	if not template or not template:IsA("Model") or not root then
		return nil
	end
	local ground = root.CFrame * CFrame.new(0, -(def.body.size.Y / 2 + EnemyFactory.HOVER_HEIGHT), 0)
	local pivot = template:GetPivot()
	local pieces: { [string]: BasePart } = {}
	for _, child in template:GetChildren() do
		if child:IsA("BasePart") then
			local part = child:Clone()
			part.CFrame = ground * pivot:ToObjectSpace(child.CFrame)
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			pieces[child.Name] = part
		end
	end
	if next(pieces) == nil then
		return nil
	end
	for _, part in pieces do
		local parentName = part:GetAttribute("Pai")
		local joint = part:GetAttribute("Junta")
		local part0: BasePart = if type(parentName) == "string" and pieces[parentName] then pieces[parentName] else root
		local jointWorld = ground
			* CFrame.new(pivot:PointToObjectSpace(if typeof(joint) == "Vector3" then joint else pivot.Position))
		local motor = Instance.new("Motor6D")
		motor.Name = VISUAL_JOINT
		motor.Part0 = part0
		motor.Part1 = part
		motor.C0 = part0.CFrame:ToObjectSpace(jointWorld)
		motor.C1 = part.CFrame:ToObjectSpace(jointWorld)
		motor.Parent = part
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = 1 -- caixa, cabeça, nariz e pernas do greybox
		end
	end
	for _, part in pieces do
		part.Parent = model
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Telegraph.COLOR
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = Telegraph.COLOR
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = model
	highlight.Parent = model
	return highlight
end

-- Escolhe, entre os ataques que alcançam o alvo, um ao acaso.
local function chooseAttack(boss: Boss, distance: number): Types.BossAttackDef?
	local options: { Types.BossAttackDef } = {}
	for _, attack in boss.def.attacks do
		if distance <= attack.triggerRange and distance >= (attack.minRange or 0) then
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
	local effect: () -> () = function() end
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
		if attack.effect == "MagmaFissure" then
			effect = function()
				Telegraph.magmaFissure(hitCFrame, attack.range, attack.width, boss.groundY)
			end
		end
	end
	task.wait(attack.telegraphTime)
	indicator:Destroy()
	if boss.humanoid.Health <= 0 then
		return false
	end
	effect()
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

	setTelegraphColor(boss, true, attack.id)
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
		if part.Transparency < 1 then -- a caixa de um chefão vestido continua invisível
			part.Transparency = 0.6
		end
		part.CanCollide = false
	end
	if boss.highlight then
		boss.highlight.Enabled = false
	end
	boss.model:SetAttribute(VISUAL_TELEGRAPH, false)
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
	local highlight = dress(model, def)
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
		highlight = highlight,
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
