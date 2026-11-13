--!strict
-- Ponto de entrada do servidor (Script em ServerScriptService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[Servidor] {Config.GAME_NAME} v{Config.VERSION} iniciado`)
