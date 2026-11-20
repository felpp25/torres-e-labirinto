--!strict
-- Nomes usados em mais de um lugar (tags do CollectionService e Attributes replicados).
-- Centralizados aqui para um erro de digitação virar erro de tipo, não um bug silencioso.

local Keys = {}

-- Tags do CollectionService (o Roblox replica tags para os clientes).
Keys.Tags = table.freeze({
	Enemy = "Enemy",
})

-- Attributes do Player, definidos SÓ pelo servidor; o cliente lê para o HUD e para prever recargas.
-- Os horários de recarga usam workspace:GetServerTimeNow(), que é sincronizado entre servidor e clientes.
Keys.PlayerAttr = table.freeze({
	Stamina = "Stamina",
	MaxStamina = "MaxStamina",
	Mana = "Mana",
	MaxMana = "MaxMana",
	DodgeReadyAt = "DodgeReadyAt",
	XP = "XP",
	Gold = "Gold",
})

function Keys.abilityReadyAttr(abilityId: string): string
	return `AbilityReadyAt_{abilityId}`
end

return table.freeze(Keys)
