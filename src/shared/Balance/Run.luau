--!strict
-- Regras da run (GDD > Morte e checkpoint).

local Run = table.freeze({
	-- true: os jogadores nascem direto no andar 1 (e a onda de treino do lobby é desligada).
	-- false: modo de treino no lobby (bonecos + onda de mobs), útil para testar só o combate.
	startInDungeon = true,

	-- Todos morreram antes de concluir o andar (wipe): espera este tempo, gasta 1 vida do grupo e recomeça o
	-- ANDAR ATUAL (mesmo labirinto; mobs e placas voltam ao estado inicial).
	allDeadRestartDelay = 3,

	-- Boss derrotado: "TORRE CONCLUÍDA" fica na tela por este tempo antes de o grupo voltar ao lobby.
	towerCompleteDelay = 8,

	-- Portal de cada torre (GDD > Torre 2 e escolha de torre): pisar abre uma espera; quem pisar no mesmo portal
	-- nesse tempo entra no grupo. Com o grupo cheio, a run começa na hora.
	queueSeconds = 10,
	maxGroupSize = 4,

	-- Vidas do GRUPO por run. Sem vidas: game over (perde o que ganhou na run; torre recomeça com labirinto novo).
	startingLives = 3,
	maxLives = 3,

	-- Coração (devolve 1 vida): chance BASE por mob morto; a Sorte multiplica (Formulas.luckChance,
	-- usando a maior Sorte entre os jogadores perto do mob).
	heartDropChance = 0.001, -- 0,1%
	heartPickupRadius = 4, -- studs
	heartCheckInterval = 0.15, -- s entre verificações de quem pegou o coração
})

return Run
