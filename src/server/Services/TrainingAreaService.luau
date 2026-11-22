--!strict
-- Área de treino perto do spawn, para testar o combate durante o desenvolvimento (ligar/desligar em Balance/Training).
-- - Bonecos: não andam, não atacam e voltam à vida cheia depois de alguns segundos sem apanhar.
-- - Onda de mobs: mobs de verdade (com IA); quando todos morrem, a onda reaparece.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Mobs = require(Shared.Balance.Mobs)
local Training = require(Shared.Balance.Training)
local Run = require(Shared.Balance.Run)

local EnemyFactory = require(script.Parent.Parent.Enemies.EnemyFactory)
local EnemyService = require(script.Parent.EnemyService)
local LifeService = require(script.Parent.LifeService)

local REGEN_CHECK_INTERVAL = 0.5

local TrainingAreaService = {}

local function spawnDummy(position: Vector3, parent: Instance)
	local dummy = EnemyFactory.create(Mobs.TrainingDummy, CFrame.new(position), 1)
	dummy.Parent = parent
	EnemyFactory.setServerOwned(dummy)

	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "boneco sem Humanoid")
	local lastHitAt = 0
	humanoid.HealthChanged:Connect(function(health: number)
		if health < humanoid.MaxHealth then
			lastHitAt = os.clock()
		end
	end)

	task.spawn(function()
		while dummy.Parent do
			task.wait(REGEN_CHECK_INTERVAL)
			if humanoid.Health < humanoid.MaxHealth and os.clock() - lastHitAt >= Training.regenDelay then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end)
end

-- Cada onda tem um número; ao reiniciar, ondas antigas param de agendar o próprio retorno.
local waveGeneration = 0

local function spawnWave(parent: Instance)
	waveGeneration += 1
	local generation = waveGeneration
	local def = Mobs[Training.waveMobId]
	assert(def, `mob desconhecido na onda de treino: {Training.waveMobId}`)
	local alive = #Training.wavePositions
	for _, position in Training.wavePositions do
		local mob = EnemyService.spawn(def, CFrame.new(position), 1, parent)
		local humanoid = mob:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			alive -= 1
			if alive == 0 then
				task.delay(Training.waveRespawnDelay, function()
					if generation == waveGeneration then
						spawnWave(parent)
					end
				end)
			end
		end)
	end
end

-- "Todos morreram" na área de treino: recomeça tudo (onda nova + todos renascem), como o andar 1 fará no M6.
local function restartTraining(wave: Instance)
	wave:ClearAllChildren()
	spawnWave(wave)
	LifeService.respawnAll()
end

function TrainingAreaService.init() end

function TrainingAreaService.start()
	if not Training.enabled then
		return
	end
	local dummies = Instance.new("Folder")
	dummies.Name = "TrainingDummies"
	dummies.Parent = workspace
	for _, position in Training.dummyPositions do
		spawnDummy(position, dummies)
	end

	-- Com a torre ligada, a onda de treino fica desligada (quem cuida de "todos morreram" é a run).
	if Run.startInDungeon then
		return
	end
	local wave = Instance.new("Folder")
	wave.Name = "TrainingWave"
	wave.Parent = workspace
	spawnWave(wave)
	LifeService.setLobbyAllDeadHandler(function()
		restartTraining(wave)
	end)
end

return TrainingAreaService
