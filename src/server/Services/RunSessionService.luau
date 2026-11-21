--!strict
-- A run (torre) e quem está nela (GDD > Lobby e loja, > Vidas, > Progressão global e torres):
-- - O jogador nasce no LOBBY. Pisar no portal entra na torre: sem run ativa, começa uma (andar 1, 3 vidas);
--   com run ativa, o jogador entra no andar atual.
-- - 3 vidas do GRUPO. Wipe (todos os PARTICIPANTES mortos) gasta 1 vida e recomeça o andar atual.
-- - Sem vidas: GAME OVER -> todos voltam ao lobby. XP, níveis e Gold ganhos FICAM.
-- - Boss derrotado: TORRE CONCLUÍDA -> depois de um tempo, todos voltam ao lobby.
-- - Coração: drop raro dos mobs que devolve 1 vida (até o máximo).
-- - Equipamento (GDD > Equipamentos > Obtenção), loot individual:
--   - boss: 1 peça garantida para cada participante COM DIREITO (entrou na run antes do andar do boss;
--     decisão do designer: quem entra ou volta só no andar do boss não ganha a peça, nem o XP e o Gold do boss,
--     e a Sorte dele não conta no sorteio do Raro);
--   - mobs: cada participante perto do mob tem a sua chance de uma peça Comum.
--   Um erro no drop nunca impede o save e a volta ao lobby (cada peça é dada dentro de pcall).
-- Vidas, nº da run e "run ativa" vão para Attributes do workspace; "está na torre" vai no Player (InRun).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Formulas = require(Shared.Formulas)
local Run = require(Shared.Balance.Run)
local Progression = require(Shared.Balance.Progression)
local Dungeon = require(Shared.Balance.Dungeon)

local BossService = require(script.Parent.BossService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local DungeonService = require(script.Parent.DungeonService)
local EnemyService = require(script.Parent.EnemyService)
local GearService = require(script.Parent.GearService)
local LifeService = require(script.Parent.LifeService)
local LobbyService = require(script.Parent.LobbyService)
local ProgressionService = require(script.Parent.ProgressionService)

local HEART_COLOR = Color3.fromRGB(255, 60, 90)
local HEART_SIZE = 2

local RunSessionService = {}

local rng = Random.new()
local runActive = false
local lives = Run.startingLives
local runNumber = 0
local towersCompleted = 0
local gameOvers = 0
local participants: { [Player]: boolean? } = {}
local bossEligible: { [Player]: boolean? } = {} -- entrou na run antes do andar do boss
local bossLootRun = 0 -- nº da run que já deu o item do boss (o boss pode renascer num wipe durante o aviso)
local hearts: { Part } = {}

local function publish()
	workspace:SetAttribute(Keys.WorldAttr.RunActive, runActive)
	workspace:SetAttribute(Keys.WorldAttr.Lives, lives)
	workspace:SetAttribute(Keys.WorldAttr.RunNumber, runNumber)
end

local function isParticipant(player: Player): boolean
	return participants[player] == true
end

local function setInRun(player: Player, inRun: boolean)
	participants[player] = if inRun then true else nil
	if not inRun then
		bossEligible[player] = nil
	end
	player:SetAttribute(Keys.InRunAttr, inRun)
end

-- Participante que entrou na run antes do andar do boss: recebe XP, Gold e o item do boss.
local function isBossEligible(player: Player): boolean
	return participants[player] == true and bossEligible[player] == true
end

local function startRun()
	runActive = true
	runNumber += 1
	lives = Run.startingLives
	publish()
	DungeonService.startFloor(1)
	print(`[Run] run {runNumber} começou`)
end

-- Portal do lobby: entra na torre (começa a run se não houver uma).
local function enterRun(player: Player)
	if participants[player] then
		return
	end
	-- Marca como participante ANTES de criar o andar: o HUD só avisa "ANDAR N" para quem está na torre.
	setInRun(player, true)
	-- Run nova começa no andar 1; entrando numa run em andamento, vale o andar atual.
	bossEligible[player] = not runActive or DungeonService.getCurrentFloor() < Dungeon.floorsPerTower
	if not runActive then
		startRun() -- já leva os participantes para a entrada
	else
		local character = player.Character
		if character then
			character:PivotTo(DungeonService.entranceCFrameFor(player))
		end
	end
	ProgressionService.restoreHealth(player)
	CombatService.restoreResources(player)
	CombatService.resetUltimate(player) -- a barra carregada nos bonecos de treino do lobby não entra na torre
	print(`[Run] {player.Name} entrou na torre (andar {DungeonService.getCurrentFloor()})`)
end

-- Fim da run (torre concluída, game over ou todos saíram): todos voltam ao lobby; mortos renascem lá.
local function endRun(reason: string)
	if not runActive then
		return
	end
	print(`[Run] run {runNumber} terminou ({reason}): todos de volta ao lobby`)
	local wasInRun: { Player } = {}
	for player in participants do
		table.insert(wasInRun, player)
	end
	for _, player in wasInRun do
		setInRun(player, false)
	end
	runActive = false
	publish()
	DungeonService.clear()
	for _, player in wasInRun do
		if player.Parent and LifeService.isAlive(player) and player.Character then
			player.Character:PivotTo(LobbyService.spawnCFrame(player))
			ProgressionService.restoreHealth(player)
			CombatService.restoreResources(player)
		end
	end
	LifeService.reviveDead(nil) -- o spawn provider agora aponta o lobby
end

-- Jogadores vivos perto de `position` (os mesmos que recebem o XP do mob).
local function playersNear(position: Vector3): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
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

-- Maior Sorte (efetiva) entre os jogadores vivos perto de `position` que passam no filtro.
-- No coop, ter alguém "sortudo" no grupo melhora os achados de todos.
local function bestLuckNear(position: Vector3, filter: ((Player) -> boolean)?): number
	local best = 0
	for _, player in playersNear(position) do
		if filter == nil or filter(player) then
			best = math.max(best, ProgressionService.getEffectiveAttributes(player).Luck)
		end
	end
	return best
end

-- Dá uma peça a um jogador sem deixar um erro parar quem chamou (run, save, outros jogadores).
local function safeLoot(kind: string, player: Player, roll: (Player, number) -> unknown, luck: number)
	local ok, err = pcall(roll, player, luck)
	if not ok then
		warn(`[Loot] falha no drop {kind} de {player.Name}: {err}`)
	end
end

-- Item garantido do boss: 1 por participante com direito (vivo ou espectando), uma vez por run.
local function grantBossLoot(position: Vector3)
	if bossLootRun == runNumber then
		return
	end
	bossLootRun = runNumber
	local luck = bestLuckNear(position, isBossEligible)
	for player in participants do
		if player.Parent and isBossEligible(player) then
			safeLoot("do boss", player, GearService.rollBossLoot, luck)
		end
	end
end

-- Boss derrotado: torre concluída. O HUD mostra "TORRE CONCLUÍDA" e, depois de um tempo, todos voltam ao lobby.
local function onTowerCompleted(position: Vector3)
	towersCompleted += 1
	workspace:SetAttribute(Keys.WorldAttr.TowersCompleted, towersCompleted)
	-- Antes do save: o item entra no save imediato abaixo. (Erros ficam dentro de safeLoot.)
	local ok, err = pcall(function(): string?
		grantBossLoot(position)
		return nil
	end)
	if not ok then
		warn(`[Loot] falha nos itens do boss: {err}`)
	end
	-- Momento crítico: a recompensa do boss acabou de entrar. Salva já, sem esperar o autosave.
	for _, player in Players:GetPlayers() do
		DataService.requestSave(player)
	end
	print(`[Run] TORRE CONCLUÍDA (run {runNumber}); volta ao lobby em {Run.towerCompleteDelay}s`)
	task.delay(Run.towerCompleteDelay, endRun, "torre concluída")
end

local function gameOver()
	print(`[Run] GAME OVER na run {runNumber} (XP e Gold ficam)`)
	gameOvers += 1
	workspace:SetAttribute(Keys.WorldAttr.GameOvers, gameOvers) -- o HUD mostra "GAME OVER" quando aumenta
	endRun("game over")
end

local function onWipe()
	if not runActive then
		return
	end
	lives -= 1
	if lives <= 0 then
		gameOver()
		return
	end
	print(`[Run] wipe: {lives} vida(s) restante(s), recomeçando o andar {DungeonService.getCurrentFloor()}`)
	publish()
	DungeonService.restartCurrentFloor()
	LifeService.reviveDead(nil) -- renascem na entrada do andar (spawn provider)
end

local function spawnHeart(position: Vector3, parent: Instance)
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

	table.insert(hearts, heart)
	print("[Run] um Coração caiu!")
end

local function onMobDied(_: Types.MobDef, position: Vector3, parent: Instance)
	-- Achados raros: a chance base sobe com a Sorte (Formulas.luckChance). Coração primeiro (não depende do
	-- equipamento); depois a chance de peça de cada participante perto (loot individual).
	local luck = bestLuckNear(position)
	local chance = Formulas.luckChance(Run.heartDropChance, luck)
	if rng:NextNumber() < chance then
		spawnHeart(position, parent)
	end
	for _, player in playersNear(position) do
		if isParticipant(player) then
			safeLoot("de mob", player, GearService.rollMobLoot, luck)
		end
	end
end

local function checkHearts()
	for i = #hearts, 1, -1 do
		local heart = hearts[i]
		if not heart.Parent then
			table.remove(hearts, i) -- o andar foi trocado/recomeçado: o coração sumiu junto
		else
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					root
					and root:IsA("BasePart")
					and LifeService.isAlive(player)
					and (root.Position - heart.Position).Magnitude <= Run.heartPickupRadius
				then
					heart:Destroy()
					table.remove(hearts, i)
					lives = math.min(lives + 1, Run.maxLives)
					publish()
					print(`[Run] {player.Name} pegou um Coração: {lives} vida(s)`)
					break
				end
			end
		end
	end
end

-- Alguém saiu do jogo no meio da run: se ninguém sobrou, a run acaba; se os que sobraram estão todos mortos,
-- conta como wipe (senão eles ficariam espectando para sempre).
local function onPlayerRemoving(player: Player)
	if not participants[player] then
		return
	end
	participants[player] = nil
	bossEligible[player] = nil
	if not runActive then
		return
	end
	if next(participants) == nil then
		endRun("todos saíram")
	elseif LifeService.allParticipantsDead() then
		task.delay(Run.allDeadRestartDelay, onWipe)
	end
end

function RunSessionService.getLives(): number
	return lives
end

-- SÓ TESTES no Studio (DevService): o jogador sai da run e entra de novo no andar atual (como quem voltou pelo
-- portal). Devolve se ele ficou com direito ao item/XP/Gold do boss.
function RunSessionService.debugRejoin(player: Player): boolean
	if not runActive or not participants[player] then
		return false
	end
	setInRun(player, false)
	enterRun(player)
	return isBossEligible(player)
end

function RunSessionService.isBossEligible(player: Player): boolean
	return isBossEligible(player)
end

function RunSessionService.init()
	EnemyService.setDeathHandler(onMobDied)
	BossService.setDefeatedHandler(onTowerCompleted)
	BossService.setRewardFilter(isBossEligible)
	workspace:SetAttribute(Keys.WorldAttr.TowersCompleted, towersCompleted)
	workspace:SetAttribute(Keys.WorldAttr.GameOvers, gameOvers)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function RunSessionService.start()
	if not Run.startInDungeon then
		return -- modo de treino no lobby (sem torre)
	end
	publish()
	LifeService.setParticipantFilter(isParticipant)
	DungeonService.setParticipantFilter(isParticipant)
	LifeService.setSpawnProvider(function(player: Player): CFrame?
		if runActive and participants[player] then
			return DungeonService.entranceCFrameFor(player)
		end
		return LobbyService.spawnCFrame(player)
	end)
	LifeService.setAllDeadHandler(onWipe)
	LobbyService.setPortalHandler(enterRun)
	while true do
		task.wait(Run.heartCheckInterval)
		checkHearts()
	end
end

return RunSessionService
