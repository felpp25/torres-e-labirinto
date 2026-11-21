--!strict
-- Ponto de entrada do cliente (único LocalScript, em StarterPlayerScripts).
-- Mesmo padrão do servidor: todos os init() e depois todos os start() dos controllers.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No cliente, a replicação pode ainda não ter terminado: WaitForChild evita erro de "nil".
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- Todo controller exporta init() e start() (mesmo que vazios).
type Controller = {
	init: () -> (),
	start: () -> (),
}

local Controllers = script.Parent:WaitForChild("Controllers")

local CONTROLLERS: { [string]: Controller } = {
	CombatFeedbackController = require(Controllers:WaitForChild("CombatFeedbackController")),
	InputController = require(Controllers:WaitForChild("InputController")),
	SpectateController = require(Controllers:WaitForChild("SpectateController")),
	HudController = require(Controllers:WaitForChild("HudController")),
	AttributesController = require(Controllers:WaitForChild("AttributesController")),
	ShopController = require(Controllers:WaitForChild("ShopController")),
	PotionController = require(Controllers:WaitForChild("PotionController")),
}
local CONTROLLER_ORDER: { string } = {
	"HudController",
	"AttributesController",
	"ShopController",
	"PotionController",
	"CombatFeedbackController",
	"InputController",
	"SpectateController",
}

for _, name in CONTROLLER_ORDER do
	CONTROLLERS[name].init()
end

for _, name in CONTROLLER_ORDER do
	task.spawn(CONTROLLERS[name].start)
end

print(`[Cliente] {Players.LocalPlayer.Name} conectado ({Config.GAME_NAME} v{Config.VERSION})`)
