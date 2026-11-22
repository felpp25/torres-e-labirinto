--!strict
-- Torres (GDD > Torre 2 e escolha de torre). Cada torre tem um portal no lobby.
-- Acesso (decisões do designer): nível mínimo + ACESSO da conta (vitalício, vale para todos os personagens). O acesso
-- vem da CHAVE (cai do chefão da torre anterior, por jogador, com a Sorte) ou da MISSÃO (a definir com o designer).
-- No portal, cada um do grupo precisa ter os dois.

export type TowerDef = {
	id: number,
	displayName: string,
	minLevel: number,
	requiresAccess: boolean, -- precisa do acesso da conta (chave ou missão); a Torre 1 é livre
	keyName: string?, -- nome da chave que libera ESTA torre (provisório até o designer escolher)
	keyChance: number, -- chance base (por jogador com direito) de a chave cair do chefão da torre anterior
}

local TOWER_1: TowerDef = {
	id = 1,
	displayName = "Torre 1",
	minLevel = 1,
	requiresAccess = false,
	keyName = nil,
	keyChance = 0,
}

local TOWER_2: TowerDef = {
	id = 2,
	displayName = "Torre 2",
	minLevel = 10,
	requiresAccess = true,
	keyName = "Chave da Torre 2", -- nome provisório
	-- 5%: em média 20 vitórias na Torre 1; 10% dos jogadores passariam de 45 (por isso existe a missão).
	keyChance = 0.05,
}

local LIST: { TowerDef } = { TOWER_1, TOWER_2 }

local BY_ID: { [number]: TowerDef } = {}
for index, def in LIST do
	assert(def.id == index, `Towers: a torre {def.id} está fora de ordem`)
	assert(def.keyChance >= 0 and def.keyChance <= 1, `Towers: chance de chave inválida na torre {def.id}`)
	assert(not def.requiresAccess or def.keyName ~= nil, `Towers: a torre {def.id} precisa do nome da chave`)
	table.freeze(def)
	BY_ID[def.id] = def
end

export type TowersBalance = {
	byId: { [number]: TowerDef },
	list: { TowerDef },
}

local TOWERS: TowersBalance = {
	byId = table.freeze(BY_ID),
	list = table.freeze(LIST),
}

return table.freeze(TOWERS)
