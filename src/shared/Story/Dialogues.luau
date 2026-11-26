--!strict
-- Falas dos NPCs fora das Crônicas (as do Observador estão em Story/Chronicles). As etapas da missão apontam para
-- estes ids (Balance/Missions); "Idle_<npc>_..." são as falas de quando o NPC não tem nada novo para o jogador.
-- Falas da missão aprovadas pelo designer (GDD > Missão e história); até ~100 letras cada, para caber no celular.

local Npcs = require(script.Parent.Npcs)

export type Dialogue = {
	npc: Npcs.NpcId,
	lines: { string },
}

local MAX_LINE_LENGTH = 110

local DIALOGUES: { [string]: Dialogue } = {
	-- ===== Missão: O Caminho de Cristal =====
	CrystalPath_Intro = {
		npc = "Ariadne",
		lines = {
			"O Observador falou com você, não falou? Ele sempre aparece para quem volta do labirinto.",
			"Eu sou Ariadne. Já tirei muita gente de labirintos. Mas este é diferente: ele só sobe.",
			"A Torre 2 está selada por cristal de Áuren. Só uma Chave de Cristal abre a passagem.",
			"Eu sei forjar essa chave. Mas antes quero ver do que você é capaz.",
			"Derrote o Golem de Obsidiana e Magma quatro vezes. Depois volte aqui.",
		},
	},
	CrystalPath_Mobs = {
		npc = "Ariadne",
		lines = {
			"Força você tem. O Golem já conhece o seu rosto.",
			"Agora limpe o caminho: as criaturas da Torre 1 estão inquietas. Derrote 200 delas.",
			"Depois, procure Tanu na loja. Você vai precisar de Gold.",
		},
	},
	CrystalPath_Sell = {
		npc = "Tanu",
		lines = {
			"Ossos, pó de cristal, peças velhas... tudo tem valor aqui embaixo!",
			"Ariadne mandou você, é? Então vou te ensinar a fazer Gold.",
			"Venda aqui na loja duas peças que você não usa. Eu pago bem. Quase sempre.",
		},
	},
	CrystalPath_Forge = {
		npc = "Brokk",
		lines = {
			"Hmpf. Tanu disse que agora você tem Gold.",
			"Peça boa se faz no fogo. Escolha uma e fortaleça na bigorna até +3.",
			"Até o +3 a forja nunca falha. Depois disso... aí é com a sorte.",
		},
	},
	CrystalPath_Flawless = {
		npc = "Ariadne",
		lines = {
			"Brokk gostou de você? Ele não gosta de ninguém.",
			"Agora, a prova do cristal. Ele só responde a quem não cai.",
			"Vença a Torre 1 sem que o seu grupo perca nenhuma vida.",
		},
	},
	CrystalPath_Fragments = {
		npc = "Ariadne",
		lines = {
			"Eu senti o cristal vibrar. Você está pronto para a última parte.",
			"O Golem guarda um Fragmento de Cristal a cada derrota. Traga cinco.",
		},
	},
	CrystalPath_Key = {
		npc = "Ariadne",
		lines = {
			"Cinco fragmentos. Segure firme.",
			"(O cristal se funde nas mãos de Ariadne e vira uma chave.)",
			"A Chave de Cristal. A Torre 2 está aberta para você e para todos os seus personagens.",
			"Lá em cima, o Observador vai ter mais para contar. Suba, e não olhe para baixo.",
		},
	},

	-- ===== Quando o NPC não tem nada novo =====
	Idle_Observer_Early = {
		npc = "Observer",
		lines = {
			"Ainda não é a hora, viajante. Volte do labirinto, e eu conto o que vi.",
		},
	},
	Idle_Ariadne_Early = {
		npc = "Ariadne",
		lines = {
			"Volte quando tiver vencido o Golem de Obsidiana e Magma. Aí a gente conversa.",
		},
	},
	Idle_Ariadne_Busy = {
		npc = "Ariadne",
		lines = {
			"Siga o caminho. Eu espero aqui.",
		},
	},
	Idle_Ariadne_Done = {
		npc = "Ariadne",
		lines = {
			"A Torre 2 te espera. Cuidado com Kokuryū.",
		},
	},
	Idle_Tanu = {
		npc = "Tanu",
		lines = {
			"Comprando ou vendendo? O balcão está logo ali.",
		},
	},
	Idle_Brokk = {
		npc = "Brokk",
		lines = {
			"Se não vai forjar nada, não atrapalhe a bigorna.",
		},
	},
}

for id, dialogue in DIALOGUES do
	assert(Npcs.byId[dialogue.npc], `Dialogues: NPC desconhecido em {id}`)
	assert(#dialogue.lines > 0, `Dialogues: {id} não tem falas`)
	for _, line in dialogue.lines do
		assert((utf8.len(line) or 0) <= MAX_LINE_LENGTH, `Dialogues: fala longa demais em {id}`)
	end
	table.freeze(dialogue.lines)
	table.freeze(dialogue)
end

return table.freeze(DIALOGUES)
