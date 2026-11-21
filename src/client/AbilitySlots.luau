--!strict
-- Atalhos das habilidades, por POSIÇÃO na lista da classe (Balance/Classes > abilities): a 1ª habilidade usa o
-- slot 1, a 2ª o slot 2... Compartilhado pelo InputController (entrada) e pelo HudController (ícones).
-- Teclas livres conferidas: F (loja/espectador), C (atributos), Q (esquiva), 1-3 (poções); no controle,
-- R1 só é usado pelo espectador, que só existe com o personagem morto.

export type Slot = {
	key: Enum.KeyCode, -- teclado
	pad: Enum.KeyCode, -- controle
	label: string, -- tecla mostrada no ícone do HUD
	touch: UDim2, -- posição do botão no celular (perto do pulo, canto inferior direito)
}

local SLOTS: { Slot } = {
	{ key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonY, label = "E", touch = UDim2.new(1, -230, 1, -210) },
	{ key = Enum.KeyCode.R, pad = Enum.KeyCode.ButtonR1, label = "R", touch = UDim2.new(1, -230, 1, -280) },
}

return table.freeze(SLOTS)
