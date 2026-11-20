--!strict
-- Regras da run (GDD > Morte e checkpoint).

local Run = table.freeze({
	-- Todos morreram antes de concluir o andar: espera este tempo e reinicia (M6: volta ao andar 1).
	allDeadRestartDelay = 3,
})

return Run
