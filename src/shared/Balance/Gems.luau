--!strict
-- Gemas (GDD > Equipamentos > Gemas). 1 gema por peça; nível 1 a 5 = 1 a 5 pontos no atributo da gema.
-- Etapa 3: gema Nv1 e Removedor Nv1 na loja; incrustar, fundir e extrair na Forja. As gemas Nv2 a Nv5 caem do
-- chefão nas torres 5+ (ainda não existem: a fusão é testada com o DevService).
-- Gemas e Removedores ficam no BAÚ da conta (decisão do designer): cada tipo (atributo + nível) empilha e a pilha
-- ocupa 1 espaço dos 50.

local Types = require(script.Parent.Parent.Types)

-- Os 6 tipos, na ordem de exibição. Não existe gema de Sorte (GDD: "Sorte só nos acessórios").
local ATTRIBUTES: { Types.GemAttribute } = { "Strength", "Vitality", "Intelligence", "Wisdom", "Dexterity", "Defense" }

local MAX_LEVEL = 5

-- Fusão: 3 gemas iguais (mesmo nível e atributo) viram 1 do nível seguinte, com o mesmo atributo. Índice = nível
-- das gemas fundidas. Só existem 2→3 e 4→5: a Nv1 da loja não funde e não existe 3→4 (o Gold compra só o Nv1; o
-- Nv4 só vem do chefão no Avançado/Pesadelo).
local FUSE_COST: { [number]: number } = {
	[2] = 200,
	[4] = 2000,
}

-- Removedor (extração): gasta um do MESMO nível da gema. Vendido só na loja. Índice = nível.
local REMOVER_PRICE: { number } = { 100, 200, 400, 800, 2000 }

assert(#REMOVER_PRICE == MAX_LEVEL, "Gems: um preço de Removedor por nível")
for level in FUSE_COST do
	assert(level >= 1 and level < MAX_LEVEL, `Gems: fusão de nível inválido ({level})`)
end

-- Tipo declarado: sem ele, o verificador alarga `attributes` para { string }.
export type GemBalance = {
	attributes: { Types.GemAttribute },
	maxLevel: number,
	pointsPerLevel: number,
	shopLevel: number,
	shopPrice: number,
	socketCost: number,
	fuseCount: number,
	fuseCost: { [number]: number },
	removerPrice: { number },
	removerShopMaxLevel: number,
	stackMax: number,
}

local GEMS: GemBalance = {
	attributes = table.freeze(ATTRIBUTES),
	maxLevel = MAX_LEVEL,
	pointsPerLevel = 1, -- gema nível n = n pontos no atributo
	shopLevel = 1, -- a loja vende só a gema deste nível (as outras só caem do chefão)
	shopPrice = 1000, -- Gold; todos os tipos custam o mesmo
	socketCost = 500, -- Gold para incrustar (GDD: ~500 por gema)
	fuseCount = 3, -- gemas iguais por fusão
	fuseCost = table.freeze(FUSE_COST),
	removerPrice = table.freeze(REMOVER_PRICE),
	-- A loja vende Removedores só até este nível (decisão do designer): os Nv2 a Nv5 entram junto com as gemas Nv2+
	-- (torres 5+). Antes disso o jogador gastaria Gold num item sem uso.
	removerShopMaxLevel = 1,
	stackMax = 99, -- máximo por pilha no baú (trava técnica: 99 gemas Nv1 = 99.000 Gold)
}

return table.freeze(GEMS)
