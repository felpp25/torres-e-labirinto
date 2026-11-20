--!strict
-- Ponto de entrada do cliente (único LocalScript, em StarterPlayerScripts).
-- Mesmo padrão do servidor: todos os init() e depois todos os start() dos controllers.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No cliente, a replicação pode ainda não ter terminado: WaitForChild evita erro de "nil".
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

type Controller = {
	init: (() -> ())?,
	start: (() -> ())?,
}

-- Os controllers entram aqui a partir do M2.
local CONTROLLERS: { [string]: Controller } = {}
local CONTROLLER_ORDER: { string } = {}

for _, name in CONTROLLER_ORDER do
	local controller = CONTROLLERS[name]
	if controller.init then
		controller.init()
	end
end

for _, name in CONTROLLER_ORDER do
	local controller = CONTROLLERS[name]
	if controller.start then
		task.spawn(controller.start)
	end
end

print(`[Cliente] {Players.LocalPlayer.Name} conectado ({Config.GAME_NAME} v{Config.VERSION})`)
