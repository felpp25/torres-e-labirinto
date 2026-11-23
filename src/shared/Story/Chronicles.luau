--!strict
-- As Crônicas do Observador: a história do jogo, escrita pelo designer em
-- docs/Ascending Labyrinths — Lore As Crônicas do Observador.md (as falas abaixo são copiadas de lá; mude lá e aqui).
-- 10 capítulos, 1 por torre concluída: o capítulo N é liberado na 1ª vitória da Torre N (StoryService). Por enquanto
-- só as falas; as cutscenes (cenas, câmera e cenários) entram depois, por cima do mesmo sistema (GDD > Missão e
-- história).

export type Chapter = {
	id: number, -- = a torre que libera o capítulo
	title: string,
	lines: { string }, -- uma fala por caixa de diálogo (até ~100 letras, para caber no celular)
}

local MAX_LINE_LENGTH = 110

local LIST: { Chapter } = {
	{
		id = 1,
		title = "A Cidade de Luz",
		lines = {
			"Ah... você voltou do labirinto. Poucos voltam. Chegue mais perto, viajante.",
			"Eu sou o Observador. Eu vi coisas que o tempo esqueceu.",
			"Muito antes deste lugar existir, havia uma cidade chamada Áuren.",
			"Suas torres eram de cristal e brilhavam à noite como estrelas.",
			"Mas tudo em Áuren precisava de energia: as luzes, as máquinas, os hospitais.",
			"E, para ter energia, eles queimavam madeira e pedras escuras.",
			"A fumaça subia... e o céu azul foi ficando cinza.",
			"Os sábios sabiam: se continuassem assim, Áuren se apagaria.",
			"Eles precisavam de uma energia limpa. Uma que não sujasse o céu.",
			"E a resposta estava brilhando bem em cima da cabeça deles. Suba mais, e eu conto.",
		},
	},
	{
		id = 2,
		title = "O Segredo do Sol",
		lines = {
			"Você subiu mais. Ótimo. Hoje vou te contar o segredo do Sol.",
			"Tudo o que existe é feito de peças minúsculas chamadas átomos.",
			"São como blocos de Lego tão pequenos que ninguém consegue ver.",
			"O átomo mais simples de todos se chama hidrogênio.",
			"Dois átomos de hidrogênio se empurram, como dois ímãs virados do mesmo lado.",
			"Mas no centro do Sol é quente demais: cerca de 15 milhões de graus!",
			"Lá é tão apertado que os átomos não conseguem fugir. Eles batem... e viram um só.",
			"Isso se chama fusão. E, quando acontece, um pedacinho da matéria vira luz e calor.",
			"Sem fumaça. Sem sujeira. Só luz.",
			'Os sábios de Áuren pensaram: "E se a gente fizer um pequeno Sol aqui embaixo?"',
			"Mas havia um problema... ninguém consegue segurar 15 milhões de graus nas mãos.",
		},
	},
	{
		id = 3,
		title = "O Sonho Impossível",
		lines = {
			"Os sábios de Áuren tinham um sonho: fazer a fusão do Sol... sem o calor do Sol.",
			"Fusão na temperatura de uma sala. Fria como a água de um copo.",
			"Eles chamaram esse sonho de Fusão a Frio.",
			"Imagine: energia limpa saindo de uma caixinha do tamanho de uma mochila.",
			"Por anos, os maiores sábios tentaram. E, por anos, falharam.",
			"Sem o calor, os átomos continuavam se empurrando. Nunca se encontravam.",
			"Muitos desistiram. Diziam que era impossível.",
			"Mas um jovem cientista não desistiu. O nome dele era Nexos.",
			'Nexos dizia: "Se o universo sabe fazer, existe um jeito. Só não o encontramos ainda."',
			"Ele passava noites inteiras no laboratório, medindo tudo e anotando tudo.",
			"Foi assim que ele percebeu algo estranho. Algo que não deveria acontecer.",
		},
	},
	{
		id = 4,
		title = "A Caixa que Mentia",
		lines = {
			"Existe uma regra que todos os cientistas conhecem.",
			"Muito tempo depois, um cientista do seu mundo chamado Lavoisier escreveria a mesma regra:",
			'"Na natureza nada se cria, nada se perde, tudo se transforma."',
			"Quer dizer: se você fecha uma caixa muito bem, nada entra e nada sai.",
			"Você pode misturar, queimar, transformar o que está dentro... mas o peso total continua igual.",
			"Os átomos não somem nem aparecem. Só trocam de lugar, como peças de Lego montando outra forma.",
			"Nexos tinha uma caixa assim. Perfeitamente fechada.",
			"Ele pesou tudo antes do experimento. E pesou de novo depois.",
			"A caixa estava mais pesada.",
			"Um pouquinho só. Mas estava.",
			"Se nada podia entrar... de onde veio aquilo?",
			"Nexos entendeu: a caixa não estava fechada. Algo invisível estava entrando nela.",
		},
	},
	{
		id = 5,
		title = "As Cordas do Universo",
		lines = {
			"Nexos procurou por meses o que estava entrando na caixa.",
			"Ele olhou para dentro dos átomos. E depois, mais para dentro ainda.",
			"Lá no fundo de cada pedacinho do universo, ele encontrou... cordas.",
			"Cordas minúsculas, vibrando sem parar, como as cordas de um violão.",
			'Cada corda toca uma "nota" diferente. E cada nota vira uma coisa diferente.',
			"Uma nota vira um elétron. Outra vira um quark. Outra vira um fóton, que é a luz.",
			"O universo inteiro é uma música, viajante. E nós somos feitos dela.",
			"Mas quem afinava essas cordas?",
			"Nexos descobriu uma energia escura, invisível, que envolvia todas as cordas e as moldava.",
			"Ninguém podia vê-la nem tocá-la. Ele a chamou de Matéria Escura.",
			"E a Matéria Escura tinha uma pequena rachadura... por onde algo estava vazando.",
		},
	},
	{
		id = 6,
		title = "O Nascimento da Mana",
		lines = {
			"O que vazava da Matéria Escura era um elemento que ninguém conhecia.",
			"Brilhava em azul, flutuava como fumaça e parecia quente e frio ao mesmo tempo.",
			"Nexos o chamou de Mana.",
			"E a Mana tinha um poder que nada no universo tinha: em certas condições, ela conseguia criar.",
			"Lembra da caixa que ficou mais pesada? Era a Mana, criando um pouquinho de matéria.",
			"Nexos teve uma ideia: e se a Mana criasse um lugar especial para os átomos?",
			"Ele prendeu a Mana numa esfera de cristal. Lá dentro, ela formou uma bolha calma.",
			"Uma bolha com a temperatura controlada, igual à de uma sala...",
			"...mas onde os átomos paravam de se empurrar.",
			"Dois átomos se aproximaram. Se tocaram. E viraram um só.",
			"Uma luz suave encheu o laboratório. Sem fogo. Sem fumaça.",
			"Naquela noite, Nexos fez o impossível: a primeira Fusão a Frio.",
		},
	},
	{
		id = 7,
		title = "A Era de Ouro",
		lines = {
			"A notícia correu Áuren inteira. A Fusão a Frio era real.",
			"Logo, cada casa tinha sua própria esfera de luz. Energia limpa, para todos.",
			"As fornalhas se apagaram. A fumaça sumiu. E o céu voltou a ser azul.",
			"Com tanta energia, Áuren construiu naves que voavam até outras estrelas.",
			"Viagens que levariam mil anos passaram a levar alguns dias.",
			"Nos hospitais, a luz da fusão curava feridas e doenças que antes não tinham cura.",
			"Máquinas transformavam água suja em água limpa. Ninguém mais passava sede.",
			"As escolas viraram bibliotecas de cristal, onde qualquer criança podia estudar as estrelas.",
			"Nexos virou um herói. Seu rosto estava em todas as praças.",
			"Foi a época mais feliz de Áuren. A Era de Ouro.",
			"Mas Nexos não estava feliz. Ele olhava para a rachadura e pensava:",
			'"Se um vazamento pequeno faz tudo isso... o que um vazamento grande faria?"',
		},
	},
	{
		id = 8,
		title = "A Ambição de Nexos",
		lines = {
			"Nexos queria saber mais. Queria entender tudo o que a Mana podia fazer.",
			"Ele descobriu que, quanto maior o vazamento, mais forte a Mana ficava.",
			"Com um pouco de Mana, ele fazia luz. Com mais, fazia flores de cristal brotarem do chão.",
			"Ele sonhava em criar estrelas. Mundos inteiros. Talvez até vida.",
			"Nexos levou seu plano ao Conselho de Áuren.",
			'Os sábios disseram não: "A Matéria Escura segura as cordas do universo."',
			'"Se você mexer nela, tudo pode desmoronar."',
			"Nexos ficou em silêncio. Mas não desistiu.",
			"Em segredo, debaixo da cidade, ele construiu uma máquina gigante: o Ressonador.",
			"O Ressonador fazia as cordas vibrarem na mesma nota da Matéria Escura, para alargar a rachadura.",
			'"Só um pouco mais", ele pensava. Alguns tentaram avisá-lo. Eu tentei.',
			"Mas Nexos já não escutava ninguém. Na noite da grande festa de Áuren, ele ligou o Ressonador.",
		},
	},
	{
		id = 9,
		title = "A Ruptura",
		lines = {
			"Agora preciso te contar sobre o tecido do espaço-tempo.",
			"Imagine um lençol enorme, bem esticado. O universo inteiro está apoiado nele.",
			"O Ressonador vibrou tão forte que o lençol começou a esticar... esticar...",
			"E rasgou.",
			"Pela rachadura, a Mana não vazou mais em gotas. Ela jorrou como um rio.",
			"Onde a Mana tocava, a realidade se dobrava. Ruas viravam escadas. Salas viravam corredores sem fim.",
			"Pedaços de lugares diferentes se misturaram, formando labirintos.",
			"A Mana tocou animais, pedras e sombras... e deles nasceram monstros.",
			"Algumas pessoas também foram tocadas. Ganharam fogo nas mãos, gelo no olhar, luz no corpo.",
			"Chamamos isso de afinidades mágicas.",
			"E Nexos? Ele estava no centro de tudo. A Fenda o engoliu, junto com o Ressonador.",
			"Em uma só noite, Áuren deixou de existir.",
		},
	},
	{
		id = 10,
		title = "O Que Restou",
		lines = {
			"Você chegou longe, viajante. Agora já sabe quase tudo.",
			"Os labirintos que você atravessa são o que sobrou de Áuren.",
			"Ruas, casas e laboratórios, dobrados pela Mana e empilhados uns sobre os outros.",
			"Por isso a torre só sobe. Cada andar é um pedaço do nosso mundo tentando voltar ao lugar.",
			"E os monstros que você enfrenta? Nasceram naquela noite. Ainda estão cheios de Mana.",
			"O poder que corre nas suas mãos também veio de lá. A Mana tocou você também.",
			"Quanto a mim... eu estava perto do Ressonador quando a Fenda se abriu.",
			"O tempo parou para mim. Eu não envelheço. Não pertenço a nenhum lugar.",
			"Por isso estou em todos os lobbys ao mesmo tempo. Eu só consigo observar.",
			"No topo da torre, a Fenda continua aberta. E a Mana ainda vaza, todos os dias.",
			"Às vezes, no silêncio, ouço uma voz vindo de lá. Uma voz que eu conheço.",
			"A história de Áuren acabou. A sua está só começando. Suba, viajante.",
		},
	},
}

local BY_ID: { [number]: Chapter } = {}
for index, chapter in LIST do
	assert(chapter.id == index, `Chronicles: o capítulo {chapter.id} está fora de ordem`)
	assert(#chapter.lines > 0, `Chronicles: o capítulo {chapter.id} não tem falas`)
	for _, line in chapter.lines do
		assert((utf8.len(line) or 0) <= MAX_LINE_LENGTH, `Chronicles: fala longa demais no capítulo {chapter.id}`)
	end
	table.freeze(chapter.lines)
	table.freeze(chapter)
	BY_ID[chapter.id] = chapter
end

export type ChroniclesData = {
	list: { Chapter },
	byId: { [number]: Chapter },
}

local CHRONICLES: ChroniclesData = {
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
}

return table.freeze(CHRONICLES)
