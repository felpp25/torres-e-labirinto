--!strict
-- Inimigos. Protótipo: 1 mob corpo a corpo.

local Types = require(script.Parent.Parent.Types)

local Mobs: { [string]: Types.MobDef } = table.freeze({
	Brute = table.freeze({
		id = "Brute",
		displayName = "Brutamontes",
		health = 60,
		damage = 12,
		defense = 0,
		walkSpeed = 12,
		aggroRange = 60,
		attackRange = 5,
		telegraphTime = 0.6,
		attackCooldown = 1.5,
		xp = 20,
		goldMin = 3,
		goldMax = 6,
		size = Vector3.new(4, 5, 4),
	} :: Types.MobDef),
})

return Mobs
