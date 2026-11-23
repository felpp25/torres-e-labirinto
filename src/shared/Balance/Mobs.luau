--!strict
-- Inimigos: Brutamontes (corpo a corpo, segura o jogador), Arremessador (à distância, Torre 2+) e o boneco de treino
-- (só para testes). Quais mobs cada torre usa: Balance/Towers. Os números aqui são na escala da Torre 1; a torre e o
-- andar multiplicam vida e dano (Balance/Towers e Balance/Dungeon).

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

	-- Arremessador (GDD > Torre 2 > Conteúdo; decisões do designer): marca um círculo no chão onde o jogador está e a
	-- pedra cai 0,8 s depois (dá para sair). Fica parado arremessando, mesmo de perto (o Lutador alcança e derruba);
	-- só anda para chegar ao alcance ou à linha de visão. 1 pedra a cada 2,3 s (aviso 0,8 + recarga 1,5). Recompensa
	-- igual à do Brutamontes (mantém o XP da run da Torre 2).
	Thrower = table.freeze({
		id = "Thrower",
		displayName = "Arremessador",
		health = 40,
		damage = 10,
		defense = 0,
		walkSpeed = 10,
		aggroRange = 60,
		attackRange = 30,
		attack = "Lob",
		areaRadius = 4,
		hitRange = 0,
		hitWidth = 0,
		telegraphTime = 0.8,
		attackCooldown = 1.5,
		xp = 8,
		goldMin = 1,
		goldMax = 3,
		size = Vector3.new(3, 4, 3),
		color = Color3.fromRGB(125, 118, 105), -- pedra
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
