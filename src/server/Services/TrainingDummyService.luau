--!strict
-- Bonecos de treino perto do spawn, para testar o combate sem mobs (ligar/desligar em Balance/Training).
-- Não andam, não atacam e voltam à vida cheia depois de alguns segundos sem apanhar.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Mobs = require(Shared.Balance.Mobs)
local Training = require(Shared.Balance.Training)

local EnemyFactory = require(script.Parent.Parent.Enemies.EnemyFactory)

local REGEN_CHECK_INTERVAL = 0.5

local TrainingDummyService = {}

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

function TrainingDummyService.init() end

function TrainingDummyService.start()
	if not Training.enabled then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrainingDummies"
	folder.Parent = workspace
	for _, position in Training.dummyPositions do
		spawnDummy(position, folder)
	end
end

return TrainingDummyService
