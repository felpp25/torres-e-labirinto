--!strict
-- Habilidades. Físicas gastam stamina; mágicas gastam mana (GDD > Atributos > Recursos).

local Types = require(script.Parent.Parent.Types)

local Abilities: { [string]: Types.AbilityDef } = table.freeze({
	IronPalm = table.freeze({
		id = "IronPalm",
		displayName = "Palma de Ferro",
		damageType = "Physical",
		baseDamage = 30,
		resource = "Stamina",
		cost = 30,
		cooldown = 6,
		recovery = 0.45,
		range = 8,
		width = 6,
		knockback = 60,
	} :: Types.AbilityDef),
})

return Abilities
