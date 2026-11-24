--!strict
-- Área de treino (só para testar o combate durante o desenvolvimento). No Lobby 1, no vão entre a entrada da Caverna
-- das Profundezas (Torre 1) e o Acampamento dos Exploradores: fora da avenida e da vista do spawn.

local Training = table.freeze({
	enabled = true,

	-- Bonecos: não atacam; voltam à vida cheia depois de `regenDelay` s sem apanhar
	regenDelay = 2.5,
	dummyPositions = table.freeze({
		Vector3.new(-85, 4, 60),
		Vector3.new(-100, 4, 60),
	}),

	-- Onda de mobs de teste (só no modo de treino, Run.startInDungeon = false): quando todos morrem, reaparece depois
	-- de `waveRespawnDelay` s
	waveMobId = "Brute",
	waveRespawnDelay = 5,
	wavePositions = table.freeze({
		Vector3.new(-130, 4, 52),
		Vector3.new(-145, 4, 62),
		Vector3.new(-130, 4, 72),
	}),
})

return Training
