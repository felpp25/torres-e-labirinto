--!strict
-- Inimigos. Protótipo: 1 mob corpo a corpo + o boneco de treino (só para testes).

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
		hitRange = 7,
		hitWidth = 6,
		telegraphTime = 0.6,
		attackCooldown = 1.5,
		-- Mobs dão pouco; o grosso fica com o boss (GDD > Progressão global e torres).
		xp = 8,
		goldMin = 1,
		goldMax = 3,
		size = Vector3.new(4, 5, 4),
		color = Color3.fromRGB(150, 70, 60),
	} :: Types.MobDef),

	-- Não anda, não ataca e não dá recompensa. Vida alta: recupera tudo depois de alguns segundos sem apanhar.
	TrainingDummy = table.freeze({
		id = "TrainingDummy",
		displayName = "Boneco de treino",
		health = 5000,
		damage = 0,
		defense = 0,
		walkSpeed = 0,
		aggroRange = 0,
		attackRange = 0,
		hitRange = 0,
		hitWidth = 0,
		telegraphTime = 0,
		attackCooldown = 0,
		xp = 0,
		goldMin = 0,
		goldMax = 0,
		size = Vector3.new(3, 5, 3),
		color = Color3.fromRGB(190, 160, 110),
	} :: Types.MobDef),
})

return Mobs
