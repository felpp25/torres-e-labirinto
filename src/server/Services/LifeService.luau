--!strict
-- Vida e morte dos jogadores (GDD > Morte e checkpoint):
-- - o Roblox NÃO renasce ninguém automaticamente (CharacterAutoLoads = false);
-- - quem morre numa run fica morto (o cliente passa a espectar um aliado vivo da mesma run);
-- - se todos os participantes de UMA run morrem, chama o handler de "run sem ninguém vivo" daquela run depois de um
--   tempo (o RunSessionService gasta uma vida e recomeça o andar, ou dá game over);
-- - quem morre no lobby renasce no lobby depois de um tempo (ou o handler do modo de treino decide);
-- - onde nascer vem do "spawn provider" (o RunSessionService aponta a entrada do andar da run ou o lobby);
-- - reviveDead(jogadores): usado pelo checkpoint para trazer os mortos da run de volta.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Run = require(ReplicatedStorage.Shared.Balance.Run)

local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)
local ProgressionService = require(script.Parent.ProgressionService)

local LifeService = {}

local wipeScheduled: { [RunRegistry.Run]: boolean } = {}
local lobbyRestartScheduled = false
local spawnProvider: (Player) -> CFrame? = function(_: Player): CFrame?
	return nil -- nil = SpawnLocation padrão do lobby
end
local runAllDeadHandler: (run: RunRegistry.Run) -> () = function(_: RunRegistry.Run) end
-- Modo de treino (Balance/Run.startInDungeon = false): todos do lobby mortos -> recomeça a onda. nil = cada um
-- renasce sozinho.
local lobbyAllDeadHandler: (() -> ())? = nil

function LifeService.isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Algum participante da run está vivo? (também usado quando alguém sai do jogo no meio da run)
function LifeService.anyAliveIn(run: RunRegistry.Run): boolean
	for _, player in run.members do
		if LifeService.isAlive(player) then
			return true
		end
	end
	return false
end

-- Cria um personagem novo e, se houver, leva para o ponto indicado (`at` ou o spawn provider).
local function spawnPlayer(player: Player, at: CFrame?)
	player:LoadCharacterAsync()
	local target = at or spawnProvider(player)
	local character = player.Character
	if target and character then
		character:PivotTo(target)
	end
end

function LifeService.setSpawnProvider(provider: (Player) -> CFrame?)
	spawnProvider = provider
end

function LifeService.respawnAll()
	for _, player in Players:GetPlayers() do
		task.spawn(spawnPlayer, player, nil)
	end
end

function LifeService.setRunAllDeadHandler(handler: (run: RunRegistry.Run) -> ())
	runAllDeadHandler = handler
end

function LifeService.setLobbyAllDeadHandler(handler: () -> ())
	lobbyAllDeadHandler = handler
end

-- Traz de volta só quem está morto entre `players` (checkpoint), na posição indicada ou, sem ela, no spawn
-- provider.
function LifeService.reviveDead(players: { Player }, cframe: CFrame?)
	for _, player in players do
		if player.Parent and not LifeService.isAlive(player) then
			task.spawn(spawnPlayer, player, cframe)
		end
	end
end

-- Agenda o handler da run quando ninguém dela está vivo (uma vez por "wipe"). Também chamado pelo
-- RunSessionService quando alguém sai do jogo e sobram só mortos.
function LifeService.scheduleWipeIfAllDead(run: RunRegistry.Run)
	if wipeScheduled[run] or not run.active or LifeService.anyAliveIn(run) then
		return
	end
	wipeScheduled[run] = true
	print(`[Vida] run {run.id}: todos morreram, reiniciando em {Run.allDeadRestartDelay}s`)
	task.delay(Run.allDeadRestartDelay, function()
		wipeScheduled[run] = nil
		if run.active then
			runAllDeadHandler(run)
		end
	end)
end

local function anyAliveInLobby(): boolean
	for _, player in Players:GetPlayers() do
		if RunRegistry.runOf(player) == nil and LifeService.isAlive(player) then
			return true
		end
	end
	return false
end

local function onLobbyDeath(player: Player)
	local handler = lobbyAllDeadHandler
	if handler then
		if lobbyRestartScheduled or anyAliveInLobby() then
			return
		end
		lobbyRestartScheduled = true
		task.delay(Run.allDeadRestartDelay, function()
			lobbyRestartScheduled = false
			handler()
		end)
		return
	end
	task.delay(Run.allDeadRestartDelay, function()
		-- Ainda morto e ainda fora de uma run (o spawn provider aponta o lobby).
		if player.Parent and not LifeService.isAlive(player) and RunRegistry.runOf(player) == nil then
			spawnPlayer(player, nil)
		end
	end)
end

local function onPlayerDied(player: Player)
	print(`[Vida] {player.Name} morreu`)
	local run = RunRegistry.runOf(player)
	if run then
		LifeService.scheduleWipeIfAllDead(run)
	else
		onLobbyDeath(player)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				onPlayerDied(player)
			end)
		end
	end)
	-- Entrou agora: nasce, mas só DEPOIS de os dados salvos carregarem: senão o progresso feito antes do
	-- carregamento seria perdido (sobrescrito pelos dados salvos).
	ProgressionService.waitUntilLoaded(player)
	if not player.Parent then
		return
	end
	spawnPlayer(player, nil)
end

function LifeService.init()
	Players.CharacterAutoLoads = false
end

-- No start (não no init): o RunSessionService já definiu o spawn provider.
function LifeService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LifeService
