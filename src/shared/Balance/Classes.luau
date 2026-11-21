--!strict
-- Classes jogáveis. Protótipo: só o Lutador (evolui para Monge depois).

local Types = require(script.Parent.Parent.Types)

-- Declarados com tipo explícito: literais como "Strength" precisam virar AttributeName, não string.
local FIGHTER_SCALING: { Types.AttributeName } = { "Strength", "Vitality" }

local FIGHTER_COMBO: { Types.ComboHitDef } = {
	{ baseDamage = 10, range = 6, width = 5, recovery = 0.3, knockback = 0, isFinisher = false },
	{ baseDamage = 10, range = 6, width = 5, recovery = 0.3, knockback = 0, isFinisher = false },
	{ baseDamage = 16, range = 7, width = 6, recovery = 0.55, knockback = 25, isFinisher = true },
}

local FIGHTER: Types.ClassDef = {
	id = "Fighter",
	displayName = "Lutador",
	scalingAttributes = FIGHTER_SCALING,
	baseHealth = 100,
	baseMana = 100, -- igual à stamina (decisão do designer); a Sabedoria soma a partir daqui
	baseStamina = 100,
	walkSpeed = 18,
	combo = FIGHTER_COMBO,
	-- 3 habilidades + 1 ultimate (GDD > Classes). Atalhos na mesma ordem: 1 / Y, 2 / R1, 3 / L2; ultimate 4 / L1
	-- (client/Hotkeys).
	abilities = { "IronPalm", "InnerFocus", "SpinKick" },
	ultimate = "HundredFists",
}

local Classes: { [string]: Types.ClassDef } = {
	Fighter = FIGHTER,
}

return table.freeze({
	byId = table.freeze(Classes),
	-- Classe usada por todos os jogadores no protótipo.
	defaultClassId = "Fighter",
})
