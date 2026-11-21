--!strict
-- Ponto de entrada do servidor (único Script do servidor).
-- Carrega os serviços em ordem: primeiro todos os init() (preparar estado, conectar Remotes),
-- depois todos os start() (começar a rodar). Assim um serviço pode usar outro já inicializado.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Todo serviço exporta init() e start() (mesmo que vazios).
type Service = {
	init: () -> (),
	start: () -> (),
}

local Services = script.Parent.Services

-- Ordem importa: quem é usado por outros vem antes. No start(), DungeonService gera o andar 1 antes de o
-- LifeService (último) fazer os jogadores nascerem; os outros já estão ouvindo CharacterAdded.
local SERVICES: { [string]: Service } = {
	ProgressionService = require(Services.ProgressionService),
	CombatService = require(Services.CombatService),
	EnemyService = require(Services.EnemyService),
	TrainingAreaService = require(Services.TrainingAreaService),
	PuzzleService = require(Services.PuzzleService),
	BossService = require(Services.BossService),
	DungeonService = require(Services.DungeonService),
	RunSessionService = require(Services.RunSessionService),
	LifeService = require(Services.LifeService),
}
local SERVICE_ORDER: { string } = {
	"ProgressionService",
	"CombatService",
	"EnemyService",
	"TrainingAreaService",
	"PuzzleService",
	"BossService",
	"DungeonService",
	"RunSessionService",
	"LifeService",
}

Remotes.setupServer()

for _, name in SERVICE_ORDER do
	SERVICES[name].init()
end

for _, name in SERVICE_ORDER do
	task.spawn(SERVICES[name].start)
end

print(`[Servidor] {Config.GAME_NAME} v{Config.VERSION} iniciado ({#SERVICE_ORDER} serviços)`)
