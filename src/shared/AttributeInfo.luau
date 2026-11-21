--!strict
-- Nomes e descrições dos 7 atributos para a interface (ordem de exibição). Só texto: os efeitos estão em Formulas.

local Types = require(script.Parent.Types)

export type Info = {
	key: Types.AttributeName,
	short: string, -- sigla no HUD
	long: string, -- nome completo
	description: string, -- o que o atributo faz (GDD > Atributos)
}

local LIST: { Info } = {
	{ key = "Strength", short = "FOR", long = "Força", description = "Aumenta o dano físico" },
	{ key = "Vitality", short = "VIT", long = "Vitalidade", description = "Aumenta a vida máxima" },
	{ key = "Intelligence", short = "INT", long = "Inteligência", description = "Aumenta o dano mágico" },
	{ key = "Wisdom", short = "SAB", long = "Sabedoria", description = "Aumenta a mana máxima" },
	{ key = "Dexterity", short = "DES", long = "Destreza", description = "Aumenta a stamina máxima" },
	{ key = "Defense", short = "DEF", long = "Defesa", description = "Reduz o dano recebido" },
	{ key = "Luck", short = "SOR", long = "Sorte", description = "Aumenta a chance de crítico" },
}

return table.freeze(LIST)
