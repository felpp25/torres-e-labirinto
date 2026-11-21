--!strict
-- Bosses. Cada torre terá o seu, com tema e moveset próprios (GDD). O protótipo tem um só.
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
}

return table.freeze({
	byId = table.freeze(Bosses),
	towerBossId = "TowerGuardian", -- boss da única torre do protótipo
})
