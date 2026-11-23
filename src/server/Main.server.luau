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

-- Ordem importa: quem é usado por outros vem antes. No start(), o RunSessionService define onde cada jogador
-- nasce (lobby ou torre) antes de o LifeService (último) fazê-los nascer; os outros já ouvem CharacterAdded.
local SERVICES: { [string]: Service } = {
	DataService = require(Services.DataService),
	ProgressionService = require(Services.ProgressionService),
	GearService = require(Services.GearService),
	GemService = require(Services.GemService),
	TowerService = require(Services.TowerService),
	CombatService = require(Services.CombatService),
	EnemyService = require(Services.EnemyService),
	TrainingAreaService = require(Services.TrainingAreaService),
	PuzzleService = require(Services.PuzzleService),
	BossService = require(Services.BossService),
	DungeonService = require(Services.DungeonService),
	LobbyService = require(Services.LobbyService),
	ShopService = require(Services.ShopService),
	ForgeService = require(Services.ForgeService),
	ConsumableService = require(Services.ConsumableService),
	RunSessionService = require(Services.RunSessionService),
	StoryService = require(Services.StoryService),
	MissionService = require(Services.MissionService),
	NpcService = require(Services.NpcService),
	DevService = require(Services.DevService),
	LifeService = require(Services.LifeService),
}
local SERVICE_ORDER: { string } = {
	"DataService",
	"ProgressionService",
	"GearService",
	"GemService",
	"TowerService",
	"CombatService",
	"EnemyService",
	"TrainingAreaService",
	"PuzzleService",
	"BossService",
	"DungeonService",
	"LobbyService",
	"ShopService",
	"ForgeService",
	"ConsumableService",
	"RunSessionService",
	"StoryService", -- antes da missão: na 1ª vitória o capítulo 1 é liberado antes de a missão começar
	"MissionService",
	"NpcService", -- depois do LobbyService (os NPCs ficam em workspace.Lobby)
	"DevService",
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
