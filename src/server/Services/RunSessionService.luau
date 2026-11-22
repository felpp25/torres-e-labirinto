--!strict
-- As runs (torres) e quem está em cada uma (GDD > Torre 2 e escolha de torre, > Vidas, > Lobby e loja):
-- - VÁRIAS runs no mesmo servidor: cada grupo (1 a 4) tem a sua, num ponto separado do mapa (RunRegistry).
-- - Um portal por torre, com ESPERA: pisar no portal abre uma espera de `Run.queueSeconds`; quem pisar no mesmo
--   portal nesse tempo entra no grupo; com o grupo cheio (ou o tempo acabado) a run começa. Sair do portal sai da
--   espera. Portal trancado (nível ou acesso da conta, TowerService): quem pisa vê o motivo e não entra.
-- - Chefão derrotado: além do item, quem tem direito e não tem o acesso à próxima torre sorteia a chave dela.
-- - Entrar no meio: só AMIGOS. Quem pisa no portal com um amigo numa run daquela torre (com vaga) entra nela, no
--   andar atual. Decisão do designer: quem entra (ou volta) só no andar do boss não ganha o item, o XP e o Gold do
--   boss, e a Sorte dele não conta no sorteio do Raro.
-- - 3 vidas do GRUPO por run. Wipe (todos os participantes daquela run mortos) gasta 1 vida e recomeça o andar.
-- - Sem vidas: GAME OVER -> o grupo volta ao lobby. XP, níveis e Gold ganhos FICAM.
-- - Boss derrotado: TORRE CONCLUÍDA -> depois de um tempo, o grupo volta ao lobby.
-- - Coração: drop raro dos mobs que devolve 1 vida (até o máximo) à run dele.
-- - Equipamento (GDD > Equipamentos > Obtenção), loot individual:
--   - boss: 1 peça garantida para cada participante COM DIREITO;
--   - mobs: cada participante perto do mob tem a sua chance de uma peça Comum.
--   Um erro no drop nunca impede o save e a volta ao lobby (cada peça é dada dentro de pcall).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Formulas = require(Shared.Formulas)
local Run = require(Shared.Balance.Run)
local Progression = require(Shared.Balance.Progression)
local Dungeon = require(Shared.Balance.Dungeon)

local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)
local BossService = require(script.Parent.BossService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local DungeonService = require(script.Parent.DungeonService)
local EnemyService = require(script.Parent.EnemyService)
local GearService = require(script.Parent.GearService)
local LifeService = require(script.Parent.LifeService)
local LobbyService = require(script.Parent.LobbyService)
local ProgressionService = require(script.Parent.ProgressionService)
local TowerService = require(script.Parent.TowerService)

local HEART_COLOR = Color3.fromRGB(255, 60, 90)
local HEART_SIZE = 2

-- Espera no portal de uma torre: o grupo que está se formando.
type Queue = {
	towerId: number,
	members: { Player },
	startsAt: number, -- workspace:GetServerTimeNow()
}

local RunSessionService = {}

local rng = Random.new()
local queues: { [number]: Queue } = {}
local hearts: { [RunRegistry.Run]: { Part } } = {}
local ending: { [RunRegistry.Run]: boolean } = {} -- torre concluída: esperando para voltar ao lobby
local bossLootGiven: { [RunRegistry.Run]: boolean } = {}
local blockedOn: { [Player]: number } = {} -- em cima de um portal trancado: torre do portal
local friendCache: { [string]: boolean } = {}
local friendPending: { [string]: boolean } = {}
local debugAllFriends = false -- SÓ TESTES (DevService): todo mundo conta como amigo

-- ===== Amizade (entrar no meio da run de um amigo) =====

local function pairKey(a: Player, b: Player): string
	return if a.UserId < b.UserId then `{a.UserId}:{b.UserId}` else `{b.UserId}:{a.UserId}`
end

-- IsFriendsWith consulta a web (pode demorar ou falhar): a resposta fica em cache e, até chegar, vale "não".
local function areFriends(a: Player, b: Player): boolean
	if debugAllFriends then
		return true
	end
	local key = pairKey(a, b)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	if not friendPending[key] then
		friendPending[key] = true
		task.spawn(function()
			local ok, result = pcall(function(): boolean
				return a:IsFriendsWithAsync(b.UserId)
			end)
			friendCache[key] = ok and result == true
			friendPending[key] = nil
		end)
	end
	return false
end

-- ===== Participantes =====

-- Entrou numa run: a Ressonância é recalculada para a torre dela (peças da torre ou de cima ressoam) e vida, mana
-- e stamina enchem.
local function restoreForRun(player: Player)
	ProgressionService.refreshEquipment(player)
	ProgressionService.restoreHealth(player)
	CombatService.restoreResources(player)
	CombatService.resetUltimate(player) -- a barra carregada nos bonecos de treino do lobby não entra na torre
end

local function clearQueueAttrs(player: Player)
	player:SetAttribute(Keys.RunAttr.QueueTower, nil)
	player:SetAttribute(Keys.RunAttr.QueueStartsAt, nil)
	player:SetAttribute(Keys.RunAttr.QueueSize, nil)
end

-- Participante que entrou na run antes do andar do boss: recebe XP, Gold e o item do boss.
local function isBossEligible(run: RunRegistry.Run, player: Player): boolean
	return RunRegistry.isMember(run, player) and run.bossEligible[player] == true
end

-- Começa uma run nova da torre com o grupo que estava na espera do portal.
local function startRun(towerId: number, players: { Player })
	local run = RunRegistry.create(towerId)
	run.lives = Run.startingLives
	RunRegistry.setState(run, Keys.RunAttr.Lives, run.lives)
	local names: { string } = {}
	for _, player in players do
		clearQueueAttrs(player)
		run.bossEligible[player] = true
		-- Participante ANTES de criar o andar: o HUD só avisa "ANDAR N" para quem está na torre.
		RunRegistry.addMember(run, player)
		restoreForRun(player)
		table.insert(names, player.Name)
	end
	DungeonService.startFloor(run, 1) -- já leva os participantes para a entrada
	print(`[Run] run {run.id} (torre {towerId}) começou com {table.concat(names, ", ")}`)
end

-- Entra numa run em andamento (amigo), no andar atual.
local function joinRun(run: RunRegistry.Run, player: Player)
	clearQueueAttrs(player)
	run.bossEligible[player] = DungeonService.getCurrentFloor(run) < Dungeon.floorsPerTower
	RunRegistry.addMember(run, player)
	local target = DungeonService.entranceCFrameFor(run, player)
	if target and player.Character then
		player.Character:PivotTo(target)
	end
	restoreForRun(player)
	print(`[Run] {player.Name} entrou na run {run.id} (andar {DungeonService.getCurrentFloor(run)})`)
end

-- Run de um amigo nesta torre, em andamento e com vaga (ou nil).
local function friendRunFor(player: Player, towerId: number): RunRegistry.Run?
	for _, run in RunRegistry.all() do
		if run.active and not ending[run] and run.towerId == towerId and #run.members < Run.maxGroupSize then
			for _, member in run.members do
				if areFriends(player, member) then
					return run
				end
			end
		end
	end
	return nil
end

-- Fim da run (torre concluída, game over ou todos saíram): o grupo volta ao lobby; mortos renascem lá.
local function endRun(run: RunRegistry.Run, reason: string)
	if not run.active then
		return
	end
	print(`[Run] run {run.id} terminou ({reason}): o grupo volta ao lobby`)
	local members = RunRegistry.members(run)
	for _, player in members do
		RunRegistry.removeMember(run, player)
	end
	DungeonService.clear(run)
	hearts[run] = nil
	ending[run] = nil
	bossLootGiven[run] = nil
	RunRegistry.destroy(run)
	for _, player in members do
		if player.Parent then
			ProgressionService.refreshEquipment(player) -- fora da torre nada ressoa
		end
		if player.Parent and LifeService.isAlive(player) and player.Character then
			player.Character:PivotTo(LobbyService.spawnCFrame(player))
			ProgressionService.restoreHealth(player)
			CombatService.restoreResources(player)
		end
	end
	LifeService.reviveDead(members) -- o spawn provider agora aponta o lobby
end

-- ===== Portais (espera do grupo) =====

local function publishQueue(queue: Queue)
	for _, player in queue.members do
		player:SetAttribute(Keys.RunAttr.QueueTower, queue.towerId)
		player:SetAttribute(Keys.RunAttr.QueueStartsAt, queue.startsAt)
		player:SetAttribute(Keys.RunAttr.QueueSize, #queue.members)
	end
end

local function clearBlocked(player: Player)
	blockedOn[player] = nil
	player:SetAttribute(Keys.RunAttr.PortalBlocked, nil)
	player:SetAttribute(Keys.RunAttr.PortalBlockedTower, nil)
end

-- Chamado pelo LobbyService a cada verificação, com quem está em cima do portal da torre (vivo, fora de run).
local function onPortalTick(towerId: number, onPortal: { Player })
	-- Portal trancado (nível ou acesso): quem saiu dele deixa de ver o aviso; quem está em cima vê o motivo e não
	-- entra na espera nem na run de um amigo (no portal, cada um do grupo precisa do nível e do acesso).
	for player, blockedTower in blockedOn do
		if blockedTower == towerId and not table.find(onPortal, player) then
			clearBlocked(player)
		end
	end
	local allowed: { Player } = {}
	for _, player in onPortal do
		local ok, reason = TowerService.canEnter(player, towerId)
		if ok then
			if blockedOn[player] then
				clearBlocked(player)
			end
			table.insert(allowed, player)
		elseif player:GetAttribute(Keys.RunAttr.PortalBlocked) ~= reason then
			blockedOn[player] = towerId
			player:SetAttribute(Keys.RunAttr.PortalBlockedTower, towerId)
			player:SetAttribute(Keys.RunAttr.PortalBlocked, reason)
		end
	end
	onPortal = allowed

	local queue = queues[towerId]
	-- Quem saiu do portal (ou do jogo) sai da espera.
	if queue then
		for i = #queue.members, 1, -1 do
			local member = queue.members[i]
			if not member.Parent or not table.find(onPortal, member) or RunRegistry.runOf(member) then
				table.remove(queue.members, i)
				if member.Parent then
					clearQueueAttrs(member)
				end
			end
		end
	end
	for _, player in onPortal do
		local waiting = queue ~= nil and table.find(queue.members, player) ~= nil
		if not waiting and RunRegistry.runOf(player) == nil then
			local friendRun = friendRunFor(player, towerId)
			if friendRun then
				joinRun(friendRun, player)
			else
				local current: Queue = queue
					or {
						towerId = towerId,
						members = {},
						startsAt = workspace:GetServerTimeNow() + Run.queueSeconds,
					}
				queues[towerId] = current
				queue = current
				if #current.members < Run.maxGroupSize then
					table.insert(current.members, player)
				end
			end
		end
	end
	if not queue then
		return
	end
	if #queue.members == 0 then
		queues[towerId] = nil
	elseif #queue.members >= Run.maxGroupSize or workspace:GetServerTimeNow() >= queue.startsAt then
		queues[towerId] = nil
		startRun(towerId, queue.members)
	else
		publishQueue(queue)
	end
end

-- ===== Recompensas =====

-- Participantes vivos da run perto de `position` (os mesmos que recebem o XP do mob).
local function membersNear(run: RunRegistry.Run, position: Vector3): { Player }
	local list: { Player } = {}
	for _, player in run.members do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if
			root
			and root:IsA("BasePart")
			and LifeService.isAlive(player)
			and (root.Position - position).Magnitude <= Progression.xpShareRadius
		then
			table.insert(list, player)
		end
	end
	return list
end

-- Maior Sorte (efetiva) entre os participantes vivos perto de `position` que passam no filtro.
-- No coop, ter alguém "sortudo" no grupo melhora os achados de todos.
local function bestLuckNear(run: RunRegistry.Run, position: Vector3, filter: ((Player) -> boolean)?): number
	local best = 0
	for _, player in membersNear(run, position) do
		if filter == nil or filter(player) then
			best = math.max(best, ProgressionService.getEffectiveAttributes(player).Luck)
		end
	end
	return best
end

-- Dá uma peça da torre a um jogador sem deixar um erro parar quem chamou (run, save, outros jogadores).
local function safeLoot(
	kind: string,
	player: Player,
	roll: (Player, number, number) -> unknown,
	luck: number,
	towerId: number
)
	local ok, err = pcall(roll, player, luck, towerId)
	if not ok then
		warn(`[Loot] falha no drop {kind} de {player.Name}: {err}`)
	end
end

-- Prêmio do boss, uma vez por run, para cada participante com direito (vivo ou espectando): o item garantido e o
-- sorteio da chave da próxima torre (só quem ainda não tem o acesso). A Sorte é a maior entre os que têm direito.
local function grantBossLoot(run: RunRegistry.Run, position: Vector3)
	if bossLootGiven[run] then
		return
	end
	bossLootGiven[run] = true
	local luck = bestLuckNear(run, position, function(player: Player): boolean
		return isBossEligible(run, player)
	end)
	local eligible: { Player } = {}
	for _, player in RunRegistry.members(run) do
		if player.Parent and isBossEligible(run, player) then
			table.insert(eligible, player)
			safeLoot("do boss", player, GearService.rollBossLoot, luck, run.towerId)
		end
	end
	local ok, err = pcall(function(): string?
		TowerService.rollKeys(run.towerId, eligible, luck)
		return nil
	end)
	if not ok then
		warn(`[Torre] falha no sorteio da chave: {err}`)
	end
end

-- Boss derrotado: torre concluída. O HUD mostra "TORRE CONCLUÍDA" e, depois de um tempo, o grupo volta ao lobby.
local function onTowerCompleted(run: RunRegistry.Run, position: Vector3)
	if not run.active or ending[run] then
		return
	end
	ending[run] = true
	RunRegistry.bumpCounter(run, Keys.RunAttr.TowersCompleted)
	-- Antes do save: o item entra no save imediato abaixo. (Erros ficam dentro de safeLoot.)
	local ok, err = pcall(function(): string?
		grantBossLoot(run, position)
		return nil
	end)
	if not ok then
		warn(`[Loot] falha nos itens do boss: {err}`)
	end
	-- Momento crítico: a recompensa do boss acabou de entrar. Salva já, sem esperar o autosave.
	for _, player in run.members do
		DataService.requestSave(player)
	end
	print(`[Run] TORRE CONCLUÍDA (run {run.id}); volta ao lobby em {Run.towerCompleteDelay}s`)
	task.delay(Run.towerCompleteDelay, endRun, run, "torre concluída")
end

local function gameOver(run: RunRegistry.Run)
	print(`[Run] GAME OVER na run {run.id} (XP e Gold ficam)`)
	RunRegistry.bumpCounter(run, Keys.RunAttr.GameOvers) -- o HUD mostra "GAME OVER" quando aumenta
	endRun(run, "game over")
end

-- Todos os participantes da run morreram (LifeService).
local function onWipe(run: RunRegistry.Run)
	if not run.active then
		return
	end
	if ending[run] then
		LifeService.reviveDead(run.members) -- boss já derrotado: só esperam a volta ao lobby
		return
	end
	run.lives -= 1
	if run.lives <= 0 then
		gameOver(run)
		return
	end
	print(
		`[Run] run {run.id}: wipe, {run.lives} vida(s) restante(s), recomeçando o andar {DungeonService.getCurrentFloor(
			run
		)}`
	)
	RunRegistry.setState(run, Keys.RunAttr.Lives, run.lives)
	DungeonService.restartCurrentFloor(run)
	LifeService.reviveDead(run.members) -- renascem na entrada do andar (spawn provider)
end

-- ===== Coração =====

local function spawnHeart(run: RunRegistry.Run, position: Vector3, parent: Instance)
	local heart = Instance.new("Part")
	heart.Name = "Heart"
	heart.Shape = Enum.PartType.Ball
	heart.Size = Vector3.one * HEART_SIZE
	heart.Anchored = true
	heart.CanCollide = false
	heart.Material = Enum.Material.Neon
	heart.Color = HEART_COLOR
	heart.Position = position
	heart.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100
	gui.Parent = heart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "+1 VIDA"
	label.TextColor3 = HEART_COLOR
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui

	local list = hearts[run] or {}
	hearts[run] = list
	table.insert(list, heart)
	print(`[Run] run {run.id}: um Coração caiu!`)
end

local function onMobDied(_: Types.MobDef, position: Vector3, parent: Instance)
	local run = RunRegistry.fromInstance(parent)
	if not run or not run.active then
		return -- mob de treino do lobby
	end
	-- Achados raros: a chance base sobe com a Sorte (Formulas.luckChance). Coração primeiro (não depende do
	-- equipamento); depois a chance de peça de cada participante perto (loot individual).
	local luck = bestLuckNear(run, position)
	local chance = Formulas.luckChance(Run.heartDropChance, luck)
	if rng:NextNumber() < chance then
		spawnHeart(run, position, parent)
	end
	for _, player in membersNear(run, position) do
		safeLoot("de mob", player, GearService.rollMobLoot, luck, run.towerId)
	end
end

local function checkHearts()
	for run, list in hearts do
		for i = #list, 1, -1 do
			local heart = list[i]
			if not heart.Parent then
				table.remove(list, i) -- o andar foi trocado/recomeçado: o coração sumiu junto
			else
				for _, player in run.members do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if
						root
						and root:IsA("BasePart")
						and LifeService.isAlive(player)
						and (root.Position - heart.Position).Magnitude <= Run.heartPickupRadius
					then
						heart:Destroy()
						table.remove(list, i)
						run.lives = math.min(run.lives + 1, Run.maxLives)
						RunRegistry.setState(run, Keys.RunAttr.Lives, run.lives)
						print(`[Run] run {run.id}: {player.Name} pegou um Coração, {run.lives} vida(s)`)
						break
					end
				end
			end
		end
	end
end

-- ===== Saída do jogo =====

-- Alguém saiu do jogo: sai da espera; na run, se ninguém sobrou, a run acaba; se os que sobraram estão todos
-- mortos, conta como wipe (senão eles ficariam espectando para sempre).
local function onPlayerRemoving(player: Player)
	blockedOn[player] = nil
	for _, queue in queues do
		local index = table.find(queue.members, player)
		if index then
			table.remove(queue.members, index)
			publishQueue(queue)
		end
	end
	local run = RunRegistry.runOf(player)
	if not run then
		return
	end
	RunRegistry.removeMember(run, player)
	if #run.members == 0 then
		endRun(run, "todos saíram")
	else
		LifeService.scheduleWipeIfAllDead(run)
	end
end

-- ===== API =====

function RunSessionService.getRunOf(player: Player): RunRegistry.Run?
	return RunRegistry.runOf(player)
end

function RunSessionService.isBossEligible(player: Player): boolean
	local run = RunRegistry.runOf(player)
	return run ~= nil and isBossEligible(run, player)
end

-- SÓ TESTES no Studio (DevService): o jogador sai da run e entra de novo no andar atual (como um amigo que voltou
-- pelo portal). Devolve se ele ficou com direito ao item/XP/Gold do boss.
function RunSessionService.debugRejoin(player: Player): boolean
	local run = RunRegistry.runOf(player)
	if not run or not run.active then
		return false
	end
	RunRegistry.removeMember(run, player)
	joinRun(run, player)
	return isBossEligible(run, player)
end

-- SÓ TESTES: pula a run para o andar `floorNumber`. Sem jogador, usa a única run ativa (se houver só uma).
function RunSessionService.debugGoToFloor(floorNumber: number, player: Player?): boolean
	local run: RunRegistry.Run? = if player then RunRegistry.runOf(player) else nil
	if not run and not player then
		local all = RunRegistry.all()
		run = if #all == 1 then all[1] else nil
	end
	if not run or not run.active then
		return false
	end
	DungeonService.advanceTo(run, floorNumber)
	return true
end

-- SÓ TESTES: todo mundo conta como amigo (os jogadores de teste do Studio não são amigos de verdade).
function RunSessionService.debugSetAllFriends(enabled: boolean)
	debugAllFriends = enabled
end

-- SÓ TESTES: resumo das runs e das esperas.
function RunSessionService.debugSummary(): { [string]: unknown }
	local runs: { unknown } = {}
	for _, run in RunRegistry.all() do
		local names: { string } = {}
		for _, member in run.members do
			table.insert(names, member.Name)
		end
		table.insert(runs, {
			id = run.id,
			tower = run.towerId,
			slot = run.slot,
			origin = tostring(run.origin),
			floor = DungeonService.getCurrentFloor(run),
			lives = run.lives,
			members = names,
		})
	end
	local waiting: { unknown } = {}
	for towerId, queue in queues do
		local names: { string } = {}
		for _, member in queue.members do
			table.insert(names, member.Name)
		end
		table.insert(waiting, {
			tower = towerId,
			members = names,
			secondsLeft = math.max(queue.startsAt - workspace:GetServerTimeNow(), 0),
		})
	end
	return { runs = runs, queues = waiting }
end

function RunSessionService.init()
	EnemyService.setDeathHandler(onMobDied)
	BossService.setDefeatedHandler(onTowerCompleted)
	BossService.setRewardFilter(isBossEligible)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function RunSessionService.start()
	if not Run.startInDungeon then
		return -- modo de treino no lobby (sem torre)
	end
	LifeService.setSpawnProvider(function(player: Player): CFrame?
		local run = RunRegistry.runOf(player)
		if run then
			local entrance = DungeonService.entranceCFrameFor(run, player)
			if entrance then
				return entrance
			end
		end
		return LobbyService.spawnCFrame(player)
	end)
	LifeService.setRunAllDeadHandler(onWipe)
	LobbyService.setPortalHandler(onPortalTick)
	while true do
		task.wait(Run.heartCheckInterval)
		checkHearts()
	end
end

return RunSessionService
