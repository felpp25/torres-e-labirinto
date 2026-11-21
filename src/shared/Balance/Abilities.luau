--!strict
-- Habilidades. Cada uma declara o próprio recurso pela NATUREZA dela (GDD > Atributos > Recursos):
-- golpes, armas e movimento gastam stamina; Chi, sagrado, elemental e cura gastam mana.
-- Cada habilidade é declarada com o tipo exato (Strike/SelfBuff) e só depois entra na tabela geral: o verificador
-- de tipos não aceita o table.freeze direto de uma tabela com tipos diferentes da união.

local Types = require(script.Parent.Parent.Types)

local IRON_PALM: Types.StrikeAbilityDef = {
	kind = "Strike",
	id = "IronPalm",
	displayName = "Palma de Ferro",
	shortName = "Palma",
	resource = "Stamina",
	cost = 30,
	cooldown = 6,
	recovery = 0.45,
	damageType = "Physical",
	baseDamage = 30,
	shape = "Front",
	range = 8,
	width = 6,
	knockback = 60,
}

-- Para quando o Lutador está cercado: acerta todos em volta e abre espaço.
local SPIN_KICK: Types.StrikeAbilityDef = {
	kind = "Strike",
	id = "SpinKick",
	displayName = "Chute Giratório",
	shortName = "Chute",
	resource = "Stamina",
	cost = 35,
	cooldown = 8,
	recovery = 0.4,
	damageType = "Physical",
	baseDamage = 22,
	shape = "Circle",
	range = 7, -- raio
	width = 0,
	knockback = 30,
}

-- Ultimate do Lutador: dano alto num alvo à frente (ex.: o boss). Gasta a barra de ultimate inteira.
-- Total: 7 × 10 + 20 = 90 de dano base (3× a Palma), em 1,6 s com o Lutador parado (risco em troca do dano).
local HUNDRED_FISTS: Types.BarrageAbilityDef = {
	kind = "Barrage",
	id = "HundredFists",
	displayName = "Rajada de Cem Punhos",
	shortName = "Rajada",
	resource = "Ultimate",
	cost = 100, -- barra cheia
	cooldown = 2,
	recovery = 0.2,
	damageType = "Physical",
	hits = 8,
	hitInterval = 0.2,
	baseDamage = 10,
	finalDamage = 20,
	range = 7,
	width = 6,
	finalKnockback = 50,
}

-- Habilidade de mana do Lutador: dá uso à Sabedoria desde a classe inicial.
-- A MANA é o limite, não a recarga: no ritmo máximo (1 uso a cada 10 s) a regeneração (3/s) repõe 30 dos 50,
-- então cada uso consome 20 da reserva. Com 100 de mana são 3 usos seguidos no ritmo máximo; cada +20 de mana
-- (4 pontos de Sabedoria) dá mais 1.
local INNER_FOCUS: Types.SelfBuffAbilityDef = {
	kind = "SelfBuff",
	id = "InnerFocus",
	displayName = "Foco Interior",
	shortName = "Foco",
	resource = "Mana",
	cost = 50,
	cooldown = 10,
	recovery = 0.3,
	healFraction = 0.12,
	damageBonus = 0.12,
	duration = 6,
}

table.freeze(IRON_PALM)
table.freeze(INNER_FOCUS)
table.freeze(SPIN_KICK)
table.freeze(HUNDRED_FISTS)

local Abilities: { [string]: Types.AbilityDef } = {
	IronPalm = IRON_PALM,
	InnerFocus = INNER_FOCUS,
	SpinKick = SPIN_KICK,
	HundredFists = HUNDRED_FISTS,
}

return table.freeze(Abilities)
