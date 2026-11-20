--!strict
-- Área de treino perto do spawn (só para testar o combate durante o desenvolvimento).

local Training = table.freeze({
	enabled = true,
	regenDelay = 2.5, -- s sem apanhar até o boneco voltar à vida cheia
	dummyPositions = table.freeze({
		Vector3.new(-6, 4, -18),
		Vector3.new(6, 4, -18),
	}),
})

return Training
