--!strict
-- Equipamentos (GDD > Equipamentos > Catálogo da Torre 1; Torre 2 em "Torre 2 e escolha de torre"). Valores da
-- raridade COMUM; a Rara vale `rarityMultiplier.Rare` vezes isso (o dobro dos pontos e do Poder).
-- Os ids vão para o save (DataStore): NUNCA renomear nem apagar um id já usado. Para aposentar uma peça, tire-a de
-- `dropPool` (quem já tem continua com ela).
-- Cada peça é declarada com o tipo exato e só depois entra na tabela geral (mesmo padrão de Balance/Abilities).
-- NOMES (decisão do designer, GDD > Mundo e temas): peça base + marca da torre. Nas declarações abaixo `displayName` é
-- o nome BASE ("Faixa do Combatente", "Luvas"); a tabela geral acrescenta a marca da torre (Balance/Towers):
-- "Faixa do Combatente de Osso" na Torre 1, "... de Cristal" na Torre 2. A raridade é a cor, não entra no nome.

local Types = require(script.Parent.Parent.Types)
local Forge = require(script.Parent.Forge)
local Towers = require(script.Parent.Towers)

-- Atributos parciais: os que faltam valem 0 (Types.Attributes exige os 7 campos).
type PartialAttributes = {
	Strength: number?,
	Vitality: number?,
	Intelligence: number?,
	Wisdom: number?,
	Dexterity: number?,
	Defense: number?,
	Luck: number?,
}

local function points(p: PartialAttributes): Types.Attributes
	return table.freeze({
		Strength = p.Strength or 0,
		Vitality = p.Vitality or 0,
		Intelligence = p.Intelligence or 0,
		Wisdom = p.Wisdom or 0,
		Dexterity = p.Dexterity or 0,
		Defense = p.Defense or 0,
		Luck = p.Luck or 0,
	})
end

-- Linha Combatente: Força ++, Vitalidade + (corpo a corpo). Acessórios: metade da linha, metade Sorte.
local COMBATANT_HEADBAND: Types.GearDef = {
	id = "CombatantHeadband",
	displayName = "Faixa do Combatente",
	slot = "Helmet",
	line = "Combatant",
	power = 0,
	attributes = points({ Strength = 2 }),
	minLevel = 1,
	tower = 1,
}
local COMBATANT_JERKIN: Types.GearDef = {
	id = "CombatantJerkin",
	displayName = "Gibão do Combatente",
	slot = "Armor",
	line = "Combatant",
	power = 0,
	attributes = points({ Strength = 2, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local COMBATANT_PANTS: Types.GearDef = {
	id = "CombatantPants",
	displayName = "Calças do Combatente",
	slot = "Pants",
	line = "Combatant",
	power = 0,
	attributes = points({ Strength = 1, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local COMBATANT_BOOTS: Types.GearDef = {
	id = "CombatantBoots",
	displayName = "Botas do Combatente",
	slot = "Boots",
	line = "Combatant",
	power = 0,
	attributes = points({ Strength = 1, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local COMBATANT_BRACELET: Types.GearDef = {
	id = "CombatantBracelet",
	displayName = "Pulseira do Combatente",
	slot = "Bracelet",
	line = "Combatant",
	power = 0,
	attributes = points({ Strength = 1, Luck = 1 }),
	minLevel = 1,
	tower = 1,
}
local COMBATANT_NECKLACE: Types.GearDef = {
	id = "CombatantNecklace",
	displayName = "Colar do Combatente",
	slot = "Necklace",
	line = "Combatant",
	power = 0,
	attributes = points({ Vitality = 1, Luck = 1 }),
	minLevel = 1,
	tower = 1,
}

-- Linha Guardião: Defesa ++, Vitalidade + (tank).
local GUARDIAN_HELM: Types.GearDef = {
	id = "GuardianHelm",
	displayName = "Elmo do Guardião",
	slot = "Helmet",
	line = "Guardian",
	power = 0,
	attributes = points({ Defense = 2 }),
	minLevel = 1,
	tower = 1,
}
local GUARDIAN_CUIRASS: Types.GearDef = {
	id = "GuardianCuirass",
	displayName = "Couraça do Guardião",
	slot = "Armor",
	line = "Guardian",
	power = 0,
	attributes = points({ Defense = 2, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local GUARDIAN_GREAVES: Types.GearDef = {
	id = "GuardianGreaves",
	displayName = "Perneiras do Guardião",
	slot = "Pants",
	line = "Guardian",
	power = 0,
	attributes = points({ Defense = 1, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local GUARDIAN_BOOTS: Types.GearDef = {
	id = "GuardianBoots",
	displayName = "Botas do Guardião",
	slot = "Boots",
	line = "Guardian",
	power = 0,
	attributes = points({ Defense = 1, Vitality = 1 }),
	minLevel = 1,
	tower = 1,
}
local GUARDIAN_BRACELET: Types.GearDef = {
	id = "GuardianBracelet",
	displayName = "Pulseira do Guardião",
	slot = "Bracelet",
	line = "Guardian",
	power = 0,
	attributes = points({ Defense = 1, Luck = 1 }),
	minLevel = 1,
	tower = 1,
}
local GUARDIAN_NECKLACE: Types.GearDef = {
	id = "GuardianNecklace",
	displayName = "Colar do Guardião",
	slot = "Necklace",
	line = "Guardian",
	power = 0,
	attributes = points({ Vitality = 1, Luck = 1 }),
	minLevel = 1,
	tower = 1,
}

-- Armas do Lutador (GDD > Armas): Luvas = inicial (todo Lutador começa com elas), Soco Inglês = intermediária
-- (cai na Torre 1 enquanto ela for a única torre). O Poder multiplica o dano do tipo da arma.
-- Os ids vêm dos nomes antigos (Luvas de Couro, Soco Inglês de Ferro) e ficam: estão no save.
local LEATHER_GLOVES: Types.GearDef = {
	id = "LeatherGloves",
	displayName = "Luvas",
	slot = "Weapon",
	classId = "Fighter",
	damageType = "Physical",
	power = 0.05,
	attributes = points({ Strength = 1, Dexterity = 2 }),
	minLevel = 1,
	tower = 1,
}
local IRON_KNUCKLES: Types.GearDef = {
	id = "IronKnuckles",
	displayName = "Soco Inglês",
	slot = "Weapon",
	classId = "Fighter",
	damageType = "Physical",
	power = 0.10,
	attributes = points({ Strength = 1 }),
	minLevel = 1,
	tower = 1,
}

local TOWER_1: { Types.GearDef } = {
	COMBATANT_HEADBAND,
	COMBATANT_JERKIN,
	COMBATANT_PANTS,
	COMBATANT_BOOTS,
	COMBATANT_BRACELET,
	COMBATANT_NECKLACE,
	GUARDIAN_HELM,
	GUARDIAN_CUIRASS,
	GUARDIAN_GREAVES,
	GUARDIAN_BOOTS,
	GUARDIAN_BRACELET,
	GUARDIAN_NECKLACE,
	LEATHER_GLOVES,
	IRON_KNUCKLES,
}

-- Torre 2 (GDD > Torre 2 e escolha de torre; decisões do designer): as mesmas peças e linhas com o DOBRO dos pontos e
-- do Poder (o Comum da Torre 2 = o Raro da Torre 1), nível mínimo 10. As duas armas do Lutador também.
local TOWER_2_MULTIPLIER = 2
local TOWER_2_MIN_LEVEL = 10

local function towerVersion(base: Types.GearDef, id: string): Types.GearDef
	local m = TOWER_2_MULTIPLIER
	local a = base.attributes
	return {
		id = id,
		displayName = base.displayName, -- mesmo nome base; a marca da Torre 2 entra na tabela geral
		slot = base.slot,
		line = base.line,
		classId = base.classId,
		damageType = base.damageType,
		power = base.power * m,
		attributes = points({
			Strength = a.Strength * m,
			Vitality = a.Vitality * m,
			Intelligence = a.Intelligence * m,
			Wisdom = a.Wisdom * m,
			Dexterity = a.Dexterity * m,
			Defense = a.Defense * m,
			Luck = a.Luck * m,
		}),
		minLevel = TOWER_2_MIN_LEVEL,
		tower = 2,
	}
end

local TOWER_2: { Types.GearDef } = {
	towerVersion(COMBATANT_HEADBAND, "CombatantHeadband2"),
	towerVersion(COMBATANT_JERKIN, "CombatantJerkin2"),
	towerVersion(COMBATANT_PANTS, "CombatantPants2"),
	towerVersion(COMBATANT_BOOTS, "CombatantBoots2"),
	towerVersion(COMBATANT_BRACELET, "CombatantBracelet2"),
	towerVersion(COMBATANT_NECKLACE, "CombatantNecklace2"),
	towerVersion(GUARDIAN_HELM, "GuardianHelm2"),
	towerVersion(GUARDIAN_CUIRASS, "GuardianCuirass2"),
	towerVersion(GUARDIAN_GREAVES, "GuardianGreaves2"),
	towerVersion(GUARDIAN_BOOTS, "GuardianBoots2"),
	towerVersion(GUARDIAN_BRACELET, "GuardianBracelet2"),
	towerVersion(GUARDIAN_NECKLACE, "GuardianNecklace2"),
	towerVersion(LEATHER_GLOVES, "LeatherGloves2"),
	towerVersion(IRON_KNUCKLES, "IronKnuckles2"),
}

local BY_TOWER: { [number]: { Types.GearDef } } = { [1] = TOWER_1, [2] = TOWER_2 }

local LIST: { Types.GearDef } = {}
for _, defs in BY_TOWER do
	for _, def in defs do
		table.insert(LIST, def)
	end
end

local BY_ID: { [string]: Types.GearDef } = {}
for _, def in LIST do
	assert(BY_ID[def.id] == nil, `Gear: id repetido {def.id}`)
	local tower = Towers.byId[def.tower]
	assert(tower ~= nil, `Gear: {def.id} é de uma torre que não existe ({def.tower})`)
	def.displayName = `{def.displayName} {tower.gearMark}`
	table.freeze(def)
	BY_ID[def.id] = def
end

-- Ordem dos slots no painel e no sorteio do drop.
local SLOTS: { Types.EquipSlot } = { "Weapon", "Helmet", "Armor", "Pants", "Boots", "Bracelet", "Necklace" }

-- Peças que podem cair em cada torre (as da própria torre).
local DROP_POOL: { [number]: { string } } = {}
for tower, defs in BY_TOWER do
	local pool: { string } = {}
	for _, def in defs do
		assert(def.tower == tower, `Gear: {def.id} está na lista da torre {tower}, mas é da torre {def.tower}`)
		table.insert(pool, def.id)
	end
	DROP_POOL[tower] = table.freeze(pool)
end

-- Arma que todo personagem da classe recebe ao ser criado (e na migração do save v3 -> v4).
local STARTING_WEAPON: { [string]: string } = {
	Fighter = "LeatherGloves",
}

-- Indexados por Types.Rarity (string), como Shop.items: evita atrito do verificador com chaves literais.
local RARITY_MULTIPLIER: { [string]: number } = {
	Common = 1,
	Rare = 2,
}
local SELL_PRICE: { [string]: number } = {
	Common = 10,
	Rare = 50,
}

-- Conferências ao carregar (erro de digitação no catálogo falha logo, não no meio de uma run).
for _, def in LIST do
	local isWeapon = def.slot == "Weapon"
	if isWeapon then
		assert(def.classId ~= nil and def.damageType ~= nil, `Gear: a arma {def.id} precisa de classId e damageType`)
		assert(def.line == nil and def.power > 0, `Gear: a arma {def.id} não tem linha e precisa de Poder`)
	else
		assert(def.line ~= nil and def.classId == nil and def.damageType == nil, `Gear: {def.id} precisa de linha`)
		assert(def.power == 0, `Gear: só armas têm Poder ({def.id})`)
	end
	-- GDD: "Sorte só nos acessórios".
	if def.attributes.Luck > 0 then
		assert(def.slot == "Bracelet" or def.slot == "Necklace", `Gear: Sorte só em acessórios ({def.id})`)
	end
	assert(table.find(SLOTS, def.slot) ~= nil, `Gear: slot desconhecido em {def.id}`)
	assert(Forge.enhanceBaseCost[def.tower] ~= nil, `Gear: a torre {def.tower} de {def.id} não tem custo na Forja`)
end
for classId, defId in STARTING_WEAPON do
	local def = BY_ID[defId]
	assert(def ~= nil and def.slot == "Weapon" and def.classId == classId, `Gear: arma inicial inválida ({classId})`)
end
for tower, pool in DROP_POOL do
	for _, defId in pool do
		assert(BY_ID[defId] ~= nil, `Gear: {defId} no dropPool da torre {tower} não existe`)
	end
end
for rarity in RARITY_MULTIPLIER do
	assert(SELL_PRICE[rarity] ~= nil, `Gear: falta o preço de venda de {rarity}`)
end

-- Tipo declarado: sem ele, o verificador alarga `slots` para { string } (perde os nomes exatos dos slots).
export type GearBalance = {
	byId: { [string]: Types.GearDef },
	slots: { Types.EquipSlot },
	dropPool: { [number]: { string } }, -- torre -> peças que caem nela
	startingWeapon: { [string]: string },
	rarityMultiplier: { [string]: number },
	sellPrice: { [string]: number },
	resonanceFromTower: number,
	resonanceDamagePerPiece: number,
	resonanceReductionPerPiece: number,
	chestCapacity: number,
	bossRareChance: number,
	mobDropChance: number,
}

local GEAR: GearBalance = {
	byId = table.freeze(BY_ID),
	slots = table.freeze(SLOTS),
	dropPool = table.freeze(DROP_POOL),
	startingWeapon = table.freeze(STARTING_WEAPON),
	rarityMultiplier = table.freeze(RARITY_MULTIPLIER),
	-- Gold pago pela loja ao vender uma peça da Torre 1 (e quando o baú está cheio no drop). Nas outras torres, vezes
	-- a recompensa da torre (Balance/Towers; Torre 2: o dobro, 20 / 100).
	sellPrice = table.freeze(SELL_PRICE),
	-- Ressonância (GDD > Torre 2 e escolha de torre; decisão do designer): numa run da Torre 2 em diante, cada peça
	-- equipada da torre em que se está (ou de uma acima) dá +dano e -dano recebido; o conjunto completo (7 peças) dá
	-- +50% / -25%. A peça de torre mais baixa vale inteira, só não ressoa: dá para jogar os primeiros andares com o
	-- equipamento velho, mas o chefão pede o da torre atual. A Torre 1 fica como foi validada (sem ressonância).
	resonanceFromTower = 2,
	resonanceDamagePerPiece = 0.5 / 7,
	resonanceReductionPerPiece = 0.25 / 7,
	chestCapacity = 50, -- peças no baú da conta (as equipadas não contam)
	bossRareChance = 0.35, -- item garantido do chefão: chance de ser Raro (com a Sorte do grupo)
	mobDropChance = 0.005, -- chance de cada mob dar uma peça Comum (com a Sorte do grupo)
}

return table.freeze(GEAR)
