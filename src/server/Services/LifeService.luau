--!strict
-- Vida e morte dos jogadores (GDD > Morte e checkpoint):
-- - o Roblox NÃO renasce ninguém automaticamente (CharacterAutoLoads = false);
-- - quem morre fica morto (o cliente passa a espectar um aliado vivo);
-- - se todos morrem, chama o handler de "todos mortos" depois de um tempo
--   (padrão: renasce todo mundo; o DungeonService troca por "reiniciar a run no andar 1");
-- - onde nascer vem do "spawn provider" (o DungeonService aponta para a entrada do andar atual);
-- - reviveDead(): usado pelo checkpoint para trazer os mortos de volta.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Run = require(ReplicatedStorage.Shared.Balance.Run)

local ProgressionService = require(script.Parent.ProgressionService)

local LifeService = {}

local restartScheduled = false
local spawnProvider: (Player) -> CFrame? = function(_: Player): CFrame?
	return nil -- nil = SpawnLocation padrão do lobby
end

function LifeService.isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function anyAlive(): boolean
	for _, player in Players:GetPlayers() do
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

local allDeadHandler: () -> () = LifeService.respawnAll

function LifeService.setAllDeadHandler(handler: () -> ())
	allDeadHandler = handler
end

-- Traz de volta só quem está morto (checkpoint), na posição indicada ou, sem ela, no spawn provider.
function LifeService.reviveDead(cframe: CFrame?)
	for _, player in Players:GetPlayers() do
		if not LifeService.isAlive(player) then
			task.spawn(spawnPlayer, player, cframe)
		end
	end
end

local function onPlayerDied(player: Player)
	print(`[Vida] {player.Name} morreu`)
	if restartScheduled or anyAlive() then
		return
	end
	restartScheduled = true
	print(`[Vida] todos morreram: reiniciando em {Run.allDeadRestartDelay}s`)
	task.delay(Run.allDeadRestartDelay, function()
		restartScheduled = false
		allDeadHandler()
	end)
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
	-- Entrou agora: nasce (mesmo com a run em andamento), mas só DEPOIS de os dados salvos carregarem:
	-- senão o progresso feito antes do carregamento seria perdido (sobrescrito pelos dados salvos).
	ProgressionService.waitUntilLoaded(player)
	if not player.Parent then
		return
	end
	spawnPlayer(player, nil)
end

function LifeService.init()
	Players.CharacterAutoLoads = false
end

-- No start (não no init): o DungeonService já gerou o andar e definiu o spawn provider.
function LifeService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LifeService
