--!strict
-- Sorte como atributo GLOBAL (GDD > Atributos > Sorte): multiplica a chance de tudo de bom que é raro.
-- Fórmula única para "achados": chance final = chance base × (1 + Sorte / findDivisor), limitada a 100%.
-- Usos: Coração (hoje). Futuro: drops de itens, baús, salas secretas, e o que mais for "sorte de encontrar".
-- O crítico tem fórmula própria (Balance/Combat: critBaseChance + critChancePerLuck), por ser frequente.

local Luck = table.freeze({
	-- A cada `findDivisor` pontos de Sorte, as chances de achados dobram (50 pts = ×2, 100 pts = ×3).
	findDivisor = 50,
})

return Luck
