--!strict
-- Torres (GDD > Torre 2 e escolha de torre). Cada torre tem um portal no lobby.
-- Acesso (decisões do designer): nível mínimo + ACESSO da conta (vitalício, vale para todos os personagens). O acesso
-- vem da CHAVE (cai do chefão da torre anterior, por jogador, com a Sorte) ou da MISSÃO (a definir com o designer).
-- No portal, cada um do grupo precisa ter os dois.
-- Nomes (decisão do designer, GDD > Mundo e temas): cada torre tem uma MARCA, o subtema dela dentro do tema do lobby.
-- A marca fecha o nome das peças da torre ("Faixa do Combatente de Osso", Balance/Gear) e o da chave que a libera
-- ("Chave de Cristal" abre a Torre 2). Formato "de X": não muda com gênero nem plural, então serve a qualquer peça.

export type TowerDef = {
	id: number,
	displayName: string,
	gearMark: string, -- marca da torre (ver acima)
	minLevel: number,
	requiresAccess: boolean, -- precisa do acesso da conta (chave ou missão); a Torre 1 é livre
	keyName: string?, -- nome da chave que libera ESTA torre: preenchido abaixo, "Chave " + a marca dela
	keyChance: number, -- chance base (por jogador com direito) de a chave cair do chefão da torre anterior
	-- Força dos mobs e do chefão (vida e dano), por cima da rampa de +15% por andar (Balance/Dungeon).
	statMultiplier: number,
	-- XP e Gold dos mobs e do chefão; também o preço base de venda das peças desta torre (Balance/Gear).
	rewardMultiplier: number,
	bossId: string, -- Balance/Bosses
	mobPool: { string }, -- Balance/Mobs: linha de frente, sorteados nas salas de combate
	-- Mob de apoio (ex.: o Arremessador): `supportShare` dos mobs do andar, no máximo 1 por sala e só em sala com mais
	-- de um mob (sempre sobra alguém da linha de frente para segurar o jogador). Sem apoio: nil e 0.
	supportMob: string?,
	supportShare: number,
}

local TOWER_1: TowerDef = {
	id = 1,
	displayName = "Torre 1",
	gearMark = "de Osso", -- fundo do abismo: ossos, obsidiana, escuridão
	minLevel = 1,
	requiresAccess = false,
	keyChance = 0,
	statMultiplier = 1,
	rewardMultiplier = 1,
	bossId = "TowerGuardian",
	mobPool = { "Brute" },
	supportMob = nil,
	supportShare = 0,
}

local TOWER_2: TowerDef = {
	id = 2,
	displayName = "Torre 2",
	gearMark = "de Cristal", -- ruínas de cristal, subindo para a superfície
	minLevel = 10,
	requiresAccess = true,
	-- 5%: em média 20 vitórias na Torre 1; 10% dos jogadores passariam de 45 (por isso existe a missão).
	keyChance = 0.05,
	-- ×2,25 (decisão do designer, com a Ressonância de Balance/Gear): com o equipamento da Torre 1 dá para jogar os
	-- primeiros andares, mas o chefão não; com o conjunto Comum da Torre 2 ressoando, sim. ×2: ~4.760 XP e ~900 Gold
	-- por run solo.
	statMultiplier = 2.25,
	rewardMultiplier = 2,
	bossId = "TowerGuardian", -- provisório: o Geomante das Rochas entra na etapa 5
	mobPool = { "Brute" },
	-- 1 a cada 3 mobs (decisão do designer): andares 1-2 (2 por sala) ~2 em cada 3 salas; andares 3-4, 1 por sala.
	supportMob = "Thrower",
	supportShare = 1 / 3,
}

local LIST: { TowerDef } = { TOWER_1, TOWER_2 }

local BY_ID: { [number]: TowerDef } = {}
for index, def in LIST do
	assert(def.id == index, `Towers: a torre {def.id} está fora de ordem`)
	assert(def.keyChance >= 0 and def.keyChance <= 1, `Towers: chance de chave inválida na torre {def.id}`)
	assert(def.gearMark ~= "", `Towers: a torre {def.id} precisa da marca`)
	if def.requiresAccess then
		def.keyName = `Chave {def.gearMark}`
	end
	assert(def.statMultiplier > 0 and def.rewardMultiplier > 0, `Towers: multiplicadores inválidos na torre {def.id}`)
	assert(#def.mobPool > 0, `Towers: a torre {def.id} não tem mobs`)
	assert(def.supportShare >= 0 and def.supportShare < 1, `Towers: supportShare inválido na torre {def.id}`)
	assert(
		(def.supportMob ~= nil) == (def.supportShare > 0),
		`Towers: supportMob e supportShare juntos (torre {def.id})`
	)
	table.freeze(def.mobPool)
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
