--!strict
-- Bosses. Cada torre tem o seu, com tema e moveset próprios (GDD). Os números são na escala da Torre 1: a torre
-- multiplica vida e dano (Balance/Towers, statMultiplier) e o XP e o Gold (rewardMultiplier).
-- A IA (BossService) é genérica: executa a lista de ataques de cada boss.

local Types = require(script.Parent.Parent.Types)

-- Guardião da Torre: grande e lento; dois ataques com aviso no chão.
local GUARDIAN_ATTACKS: { Types.BossAttackDef } = {
	{
		id = "HeavySlam", -- golpe pesado à frente
		shape = "Front",
		telegraphTime = 1.0,
		damage = 30,
		range = 14,
		width = 10,
		triggerRange = 12,
		recovery = 0.8,
	},
	{
		id = "Stomp", -- pisão: área circular ao redor dele (pune quem fica colado)
		shape = "Circle",
		telegraphTime = 1.2,
		damage = 22,
		range = 14,
		width = 0,
		triggerRange = 9,
		recovery = 1.0,
	},
}

local GUARDIAN_BODY: Types.MobDef = {
	id = "TowerGuardian",
	displayName = "Guardião da Torre",
	health = 1200, -- vida base com 1 jogador
	damage = 0, -- (os danos estão nos ataques)
	defense = 10,
	walkSpeed = 9,
	aggroRange = 0, -- (não usado: o boss ataca quem entra na arena)
	attackRange = 0,
	hitRange = 0,
	hitWidth = 0,
	telegraphTime = 0,
	attackCooldown = 0,
	xp = 0, -- (a recompensa do boss está em BossDef)
	goldMin = 0,
	goldMax = 0,
	size = Vector3.new(8, 10, 8),
	color = Color3.fromRGB(90, 70, 130),
}

-- Geomante das Rochas (chefão da Torre 2; GDD > Torre 2 > Conteúdo, decisões do designer): mago de pedra. Danos na
-- escala da Torre 1 (com o ×2,25 da Torre 2: 51,75 / 49,5 / 58,5). Pausas escolhidas para a MESMA pressão do Guardião (8,7 de
-- dano/s base se acertar tudo), o que mantém o índice de dificuldade do GDD; parado 35% do tempo (janelas para bater).
local GEOMANCER_ATTACKS: { Types.BossAttackDef } = {
	{
		id = "RockRain", -- Chuva de Rochas: um círculo embaixo de cada jogador, 3 ondas; cada onda mira de novo
		shape = "AtPlayers",
		telegraphTime = 1.2,
		damage = 23,
		range = 6,
		width = 0,
		waves = 3,
		triggerRange = math.huge, -- a qualquer distância (dentro da arena)
		recovery = 2.0,
	},
	{
		id = "SeismicWave", -- Onda Sísmica: área circular em volta dele (pune quem cola)
		shape = "Circle",
		telegraphTime = 1.2,
		damage = 22,
		range = 12,
		width = 0,
		triggerRange = 9,
		recovery = 1.4,
	},
	{
		id = "StoneBlast", -- Rajada de Pedra: faixa longa à frente
		shape = "Front",
		telegraphTime = 1.0,
		damage = 26,
		range = 24,
		width = 6,
		triggerRange = 20,
		recovery = 1.3,
	},
}

local GEOMANCER_BODY: Types.MobDef = {
	id = "Geomancer",
	displayName = "Geomante das Rochas",
	health = 1200, -- vida base com 1 jogador (igual ao Guardião; a Torre 2 multiplica: 2.700)
	damage = 0, -- (os danos estão nos ataques)
	defense = 10,
	walkSpeed = 8,
	aggroRange = 0, -- (não usado: o boss ataca quem entra na arena)
	attackRange = 0,
	hitRange = 0,
	hitWidth = 0,
	telegraphTime = 0,
	attackCooldown = 0,
	xp = 0, -- (a recompensa do boss está em BossDef)
	goldMin = 0,
	goldMax = 0,
	size = Vector3.new(7, 11, 7),
	color = Color3.fromRGB(115, 90, 65), -- terra e pedra
}

local Bosses: { [string]: Types.BossDef } = {
	TowerGuardian = {
		id = "TowerGuardian",
		displayName = "Guardião da Torre",
		body = GUARDIAN_BODY,
		healthPerExtraPlayer = 0.5, -- 2 jogadores: 1800 de vida; 4 jogadores: 3000
		attacks = GUARDIAN_ATTACKS,
		attackCooldown = 1.0,
		-- O boss dá o grosso da recompensa da torre (~70%; mobs ~30%): GDD > Progressão global e torres.
		xp = 1500,
		gold = 300,
	},
	Geomancer = {
		id = "Geomancer",
		displayName = "Geomante das Rochas",
		body = GEOMANCER_BODY,
		healthPerExtraPlayer = 0.5,
		attacks = GEOMANCER_ATTACKS,
		attackCooldown = 1.0,
		xp = 1500, -- ×2 na Torre 2: 3.000 XP e 600 Gold
		gold = 300,
	},
}

-- O chefão de cada torre fica em Balance/Towers (bossId).
return table.freeze({
	byId = table.freeze(Bosses),
})
