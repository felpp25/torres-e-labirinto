--!strict
-- Vida e morte dos jogadores (GDD > Morte e checkpoint):
-- - o Roblox NÃO renasce ninguém automaticamente (CharacterAutoLoads = false);
-- - quem morre fica morto (o cliente passa a espectar um aliado vivo);
-- - se todos morrem, chama o handler de "todos mortos" depois de um tempo
--   (padrão: renasce todo mundo; no M6 o DungeonService troca por "reiniciar a run no andar 1");
-- - reviveDeadAt(cframe): usado pelo checkpoint para trazer os mortos de volta.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Run = require(ReplicatedStorage.Shared.Balance.Run)

local LifeService = {}

local restartScheduled = false

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

function LifeService.respawnAll()
	for _, player in Players:GetPlayers() do
		task.spawn(player.LoadCharacterAsync, player)
	end
end

local allDeadHandler: () -> () = LifeService.respawnAll

function LifeService.setAllDeadHandler(handler: () -> ())
	allDeadHandler = handler
end

-- Traz de volta só quem está morto, na posição indicada (checkpoint).
function LifeService.reviveDeadAt(cframe: CFrame)
	for _, player in Players:GetPlayers() do
		if not LifeService.isAlive(player) then
			task.spawn(function()
				player:LoadCharacterAsync()
				local character = player.Character
				if character then
					character:PivotTo(cframe)
				end
			end)
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
	-- Entrou agora: nasce (mesmo com a run em andamento).
	player:LoadCharacterAsync()
end

function LifeService.init()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function LifeService.start() end

return LifeService
