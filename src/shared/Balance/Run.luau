--!strict
-- Regras da run (GDD > Morte e checkpoint).

local Run = table.freeze({
	-- true: os jogadores nascem direto no andar 1 (e a onda de treino do lobby é desligada).
	-- false: modo de treino no lobby (bonecos + onda de mobs), útil para testar só o combate.
	startInDungeon = true,

	-- Todos morreram antes de concluir o andar: espera este tempo e recomeça o ANDAR ATUAL
	-- (mesmo labirinto; mobs e placas voltam ao estado inicial; XP e Gold ganhos ficam).
	allDeadRestartDelay = 3,
})

return Run
