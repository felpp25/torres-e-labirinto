--!strict
-- TODOS os atalhos de habilidades e poções num lugar só (para trocar tecla, mexa só aqui).
-- Usado pelo InputController e PotionController (entrada) e pelo HudController (texto da tecla nos ícones).
--
-- Teclado (decisão do designer): 1, 2, 3 = habilidades da classe (na ordem de Balance/Classes > abilities);
-- 4 = ultimate; E = Poção de Vida, R = Poção de Mana, T = Poção de Stamina.
-- Fora daqui: clique = ataque, Q = esquiva, C = atributos, F = loja (lobby) / próximo aliado (espectador).
-- Controle: habilidades Y, R1, L2; ultimate L1; poções no direcional (a loja usa o direcional para cima).

export type Slot = {
	key: Enum.KeyCode, -- teclado
	pad: Enum.KeyCode, -- controle
	label: string, -- tecla mostrada no ícone do HUD
	touch: UDim2, -- posição do botão no celular (perto do pulo, canto inferior direito)
}

-- Por POSIÇÃO na lista de habilidades da classe.
local ABILITIES: { Slot } = {
	{ key = Enum.KeyCode.One, pad = Enum.KeyCode.ButtonY, label = "1", touch = UDim2.new(1, -230, 1, -210) },
	{ key = Enum.KeyCode.Two, pad = Enum.KeyCode.ButtonR1, label = "2", touch = UDim2.new(1, -230, 1, -280) },
	{ key = Enum.KeyCode.Three, pad = Enum.KeyCode.ButtonL2, label = "3", touch = UDim2.new(1, -160, 1, -280) },
}

local ULTIMATE: Slot =
	{ key = Enum.KeyCode.Four, pad = Enum.KeyCode.ButtonL1, label = "4", touch = UDim2.new(1, -300, 1, -280) }

-- Por id do item (Balance/Shop).
local POTIONS: { [string]: Slot } = {
	HealthPotion = {
		key = Enum.KeyCode.E,
		pad = Enum.KeyCode.DPadLeft,
		label = "E",
		touch = UDim2.new(1, -300, 1, -200),
	},
	ManaPotion = { key = Enum.KeyCode.R, pad = Enum.KeyCode.DPadDown, label = "R", touch = UDim2.new(1, -370, 1, -80) },
	StaminaPotion = {
		key = Enum.KeyCode.T,
		pad = Enum.KeyCode.DPadRight,
		label = "T",
		touch = UDim2.new(1, -370, 1, -150),
	},
}

return table.freeze({
	abilities = table.freeze(ABILITIES),
	ultimate = table.freeze(ULTIMATE),
	potions = table.freeze(POTIONS),
})
