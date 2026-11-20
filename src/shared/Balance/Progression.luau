--!strict
-- Progressão: níveis, XP e quanto cada atributo vale em recursos.

local Progression = table.freeze({
	maxLevel = 10, -- teto do protótipo
	pointsPerLevel = 3,

	-- XP para passar do nível N para o N+1 = floor(xpBase × xpGrowth^(N-1))
	xpBase = 50,
	xpGrowth = 1.35,

	-- Raio em que um aliado recebe o XP inteiro quando um mob morre (GDD > Recompensas)
	xpShareRadius = 80,

	-- Recursos por ponto de atributo
	healthPerVitality = 10,
	manaPerWisdom = 5,
	staminaPerDexterity = 5,
})

return Progression
