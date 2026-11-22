--!strict
-- Forja do lobby (GDD > Equipamentos > Fortalecimento e Forja). Hoje: fortalecimento de +1 a +10.
-- Itens de bênção (somam % à chance): adiados pelo designer até existirem as torres 2+ e a renda delas.

-- Chance de sucesso da tentativa de chegar a +n (índice = n). A Sorte NÃO afeta (GDD: com itens da conta, todo
-- mundo fortaleceria no personagem mais sortudo).
local SUCCESS_CHANCE: { number } = { 1, 1, 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3 }

-- Base do custo por torre de origem da peça (Types.GearDef.tower). Cada torre nova define a sua, proporcional ao
-- Gold que ela rende: o fortalecimento custa o mesmo esforço na torre de origem do item.
local ENHANCE_BASE_COST: { [number]: number } = {
	[1] = 100, -- Torre 1: +1 = 100, +2 = 200, +5 = 1.600, +10 = 51.200
	[2] = 200, -- Torre 2 (renda ×2): o +7 continua em ~42 runs da torre
}

local MAX_ENHANCE = 10

assert(#SUCCESS_CHANCE == MAX_ENHANCE, "Forge: uma chance de sucesso por nível")
for level, chance in SUCCESS_CHANCE do
	assert(chance > 0 and chance <= 1, `Forge: chance inválida no +{level}`)
end

export type ForgeBalance = {
	maxEnhance: number,
	enhanceStep: number,
	enhanceBaseCost: { [number]: number },
	successChance: { number },
	dropOnFailFrom: number,
	enhanceSellFraction: number,
	forgeRange: number,
}

local FORGE: ForgeBalance = {
	maxEnhance = MAX_ENHANCE,
	-- Cada nível dá +10% dos atributos base da peça (e do Poder, na arma): +10 = o dobro. Pontos quebrados ficam
	-- com decimais (decisão do designer: Calças +1 FOR no +5 = +1,5 FOR).
	enhanceStep = 0.10,
	-- Custo da tentativa de chegar a +n: base da torre × 2^(n − 1).
	enhanceBaseCost = table.freeze(ENHANCE_BASE_COST),
	successChance = table.freeze(SUCCESS_CHANCE),
	-- Falhar a tentativa de +n com n >= isto tira 1 nível (+7 tentando +8 cai para +6). Antes disso só perde o Gold.
	dropOnFailFrom = 8,
	-- Venda da peça fortalecida (decisão do designer): a loja paga o preço base + esta fração da SOMA dos preços das
	-- tentativas até o nível dela (o que gastou quem nunca falhou). Torre 1: +5 = +1.033, +7 = +4.233, +10 = +34.100.
	-- Nunca passa do gasto real: fortalecer para vender sempre dá prejuízo.
	enhanceSellFraction = 1 / 3,
	forgeRange = 14, -- studs: distância máxima do balcão da forja (validado no servidor)
}

return table.freeze(FORGE)
