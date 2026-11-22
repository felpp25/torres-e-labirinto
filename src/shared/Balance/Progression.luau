--!strict
-- Progressão: níveis, XP e quanto cada atributo vale em recursos.

local Progression = table.freeze({
	-- Teto de nível: +10 por torre (decisão do designer; Torre 2 = 20). A curva de XP abaixo precisa mudar antes da
	-- Torre 3 (o nível 30 custaria 223 mil XP só ele).
	maxLevel = 20,
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
