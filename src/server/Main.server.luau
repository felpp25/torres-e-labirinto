--!strict
-- Ponto de entrada do servidor (único Script do servidor).
-- Carrega os serviços em ordem: primeiro todos os init() (preparar estado, conectar Remotes),
-- depois todos os start() (começar a rodar). Assim um serviço pode usar outro já inicializado.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Service = {
	init: (() -> ())?,
	start: (() -> ())?,
}

-- Ordem importa: quem é usado por outros vem antes. Os serviços entram aqui a partir do M2.
local SERVICES: { [string]: Service } = {}
local SERVICE_ORDER: { string } = {}

Remotes.setupServer()

for _, name in SERVICE_ORDER do
	local service = SERVICES[name]
	if service.init then
		service.init()
	end
end

for _, name in SERVICE_ORDER do
	local service = SERVICES[name]
	if service.start then
		task.spawn(service.start)
	end
end

print(`[Servidor] {Config.GAME_NAME} v{Config.VERSION} iniciado ({#SERVICE_ORDER} serviços)`)
