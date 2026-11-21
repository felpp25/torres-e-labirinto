--!strict
-- Loja do lobby (GDD > Lobby e loja). Preços e efeitos iniciais: ajustar depois de jogar.
-- Referência: uma torre completa rende ~400 a 450 Gold (mobs 1-3, boss 300).

local Types = require(script.Parent.Parent.Types)

local HEALTH_POTION: Types.ConsumableDef = {
	id = "HealthPotion",
	displayName = "Poção de Vida",
	description = "Recupera 40% da vida máxima",
	price = 30,
	maxOwned = 5,
	effect = "Heal",
	amount = 0.4, -- fração da vida máxima
	cooldown = 8, -- s entre usos (deste tipo)
}

local STAMINA_POTION: Types.ConsumableDef = {
	id = "StaminaPotion",
	displayName = "Poção de Stamina",
	description = "Enche a stamina",
	price = 20,
	maxOwned = 5,
	effect = "Stamina",
	amount = 1, -- fração da stamina máxima
	cooldown = 8,
}

local MANA_POTION: Types.ConsumableDef = {
	id = "ManaPotion",
	displayName = "Poção de Mana",
	description = "Enche a mana",
	price = 20,
	maxOwned = 5,
	effect = "Mana",
	amount = 1, -- fração da mana máxima
	cooldown = 8,
}

local ITEMS: { [string]: Types.ConsumableDef } = {
	HealthPotion = HEALTH_POTION,
	StaminaPotion = STAMINA_POTION,
	ManaPotion = MANA_POTION,
}

-- Ordem de exibição na loja e na barra de ações (segue as teclas E, R, T; atalhos em client/Hotkeys).
local ORDER: { string } = { "HealthPotion", "ManaPotion", "StaminaPotion" }

return table.freeze({
	items = table.freeze(ITEMS),
	order = table.freeze(ORDER),
	resetPricePerLevel = 25, -- reset de atributos custa isto × nível do personagem (nível 10 = 250)
	shopRange = 14, -- studs: distância máxima do balcão para comprar (validado no servidor)
})
