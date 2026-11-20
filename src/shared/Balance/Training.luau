--!strict
-- Área de treino perto do spawn (só para testar o combate durante o desenvolvimento).

local Training = table.freeze({
	enabled = true,

	-- Bonecos: não atacam; voltam à vida cheia depois de `regenDelay` s sem apanhar
	regenDelay = 2.5,
	dummyPositions = table.freeze({
		Vector3.new(-6, 4, -18),
		Vector3.new(6, 4, -18),
	}),

	-- Onda de mobs de teste: quando todos morrem, reaparece depois de `waveRespawnDelay` s
	waveMobId = "Brute",
	waveRespawnDelay = 5,
	wavePositions = table.freeze({
		Vector3.new(-12, 4, 40),
		Vector3.new(0, 4, 45),
		Vector3.new(12, 4, 40),
	}),
})

return Training
