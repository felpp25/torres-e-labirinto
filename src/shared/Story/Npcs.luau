--!strict
-- NPCs do lobby (GDD > Missão e história; decisões do designer). O NpcService monta os modelos e os prompts; a
-- caixa de conversa (DialogueController) usa o nome e a cor; o HUD da missão usa o lugar ("Fale com Tanu, na loja").

export type NpcId = "Observer" | "Ariadne" | "Brokk" | "Tanu"

export type NpcDef = {
	id: NpcId,
	displayName: string,
	title: string, -- aparece embaixo do nome, em cima do NPC
	place: string, -- onde encontrá-lo (texto do HUD da missão)
	color: Color3, -- nome na caixa de conversa
}

local LIST: { NpcDef } = {
	{
		-- Narrador das Crônicas; sem nome, só o título (decisão do designer).
		id = "Observer",
		displayName = "O Observador",
		title = "testemunha da Ruptura",
		place = "no lobby",
		color = Color3.fromRGB(90, 220, 255), -- ciano da Mana
	},
	{
		-- Grega: deu a Teseu o fio para sair do Labirinto.
		id = "Ariadne",
		displayName = "Ariadne",
		title = "a Guia",
		place = "perto dos portais",
		color = Color3.fromRGB(255, 200, 120),
	},
	{
		-- Nórdica: o anão que forjou o martelo de Thor.
		id = "Brokk",
		displayName = "Brokk",
		title = "o Ferreiro",
		place = "na Forja",
		color = Color3.fromRGB(255, 140, 70),
	},
	{
		-- Folclore japonês: um tanuki, o bicho da sorte nos negócios (não é uma divindade).
		id = "Tanu",
		displayName = "Tanu",
		title = "o Mercador",
		place = "na loja",
		color = Color3.fromRGB(170, 220, 110),
	},
}

local BY_ID: { [string]: NpcDef } = {}
for _, def in LIST do
	table.freeze(def)
	BY_ID[def.id] = def
end

export type NpcsData = {
	list: { NpcDef },
	byId: { [string]: NpcDef },
}

local NPCS: NpcsData = {
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
}

return table.freeze(NPCS)
