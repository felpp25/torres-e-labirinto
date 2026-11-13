--!strict
-- Ponto de entrada do cliente (LocalScript em StarterPlayerScripts).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

-- No cliente, a replicação pode ainda não ter terminado: WaitForChild evita erro de "nil".
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local localPlayer = Players.LocalPlayer

print(`[Cliente] {localPlayer.Name} conectado ({Config.GAME_NAME} v{Config.VERSION})`)
