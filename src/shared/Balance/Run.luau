--!strict
-- Regras da run (GDD > Morte e checkpoint).

local Run = table.freeze({
	-- true: os jogadores nascem direto no andar 1 (e a onda de treino do lobby é desligada).
	-- false: modo de treino no lobby (bonecos + onda de mobs), útil para testar só o combate.
	startInDungeon = true,

	-- Todos morreram antes de concluir o andar: espera este tempo e reinicia a run no andar 1.
	allDeadRestartDelay = 3,
})

return Run
