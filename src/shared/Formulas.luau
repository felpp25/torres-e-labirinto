--!strict
-- Fórmulas de jogo, como funções puras (sem estado, sem Instances).
-- O servidor usa para DECIDIR; o cliente só pode usar para MOSTRAR prévias.

local Types = require(script.Parent.Types)
local Combat = require(script.Parent.Balance.Combat)
local Progression = require(script.Parent.Balance.Progression)
local Luck = require(script.Parent.Balance.Luck)
local Gear = require(script.Parent.Balance.Gear)
local Forge = require(script.Parent.Balance.Forge)
local Gems = require(script.Parent.Balance.Gems)
local Towers = require(script.Parent.Balance.Towers)

local Formulas = {}

local ATTRIBUTE_ORDER: { Types.AttributeName } =
	{ "Strength", "Vitality", "Intelligence", "Wisdom", "Dexterity", "Defense", "Luck" }

function Formulas.attributeNames(): { Types.AttributeName }
	return table.clone(ATTRIBUTE_ORDER)
end

-- Tabela de consulta (e não um laço): o verificador de tipos alargaria o nome do laço para `string`.
local ATTRIBUTE_BY_NAME: { [string]: Types.AttributeName } = {
	Strength = "Strength",
	Vitality = "Vitality",
	Intelligence = "Intelligence",
	Wisdom = "Wisdom",
	Dexterity = "Dexterity",
	Defense = "Defense",
	Luck = "Luck",
}

-- Valida um valor vindo de fora (ex.: Remote do cliente): devolve o nome do atributo se for um dos 7, senão nil.
function Formulas.parseAttributeName(value: unknown): Types.AttributeName?
	if typeof(value) ~= "string" then
		return nil
	end
	return ATTRIBUTE_BY_NAME[value]
end

local SLOT_BY_NAME: { [string]: Types.EquipSlot } = {
	Weapon = "Weapon",
	Helmet = "Helmet",
	Armor = "Armor",
	Pants = "Pants",
	Boots = "Boots",
	Bracelet = "Bracelet",
	Necklace = "Necklace",
}

-- Valida um slot de equipamento vindo de fora (Remote, save). Nil se não for um dos 7.
function Formulas.parseEquipSlot(value: unknown): Types.EquipSlot?
	if typeof(value) ~= "string" then
		return nil
	end
	return SLOT_BY_NAME[value]
end

local RARITY_BY_NAME: { [string]: Types.Rarity } = {
	Common = "Common",
	Rare = "Rare",
}

function Formulas.parseRarity(value: unknown): Types.Rarity?
	if typeof(value) ~= "string" then
		return nil
	end
	return RARITY_BY_NAME[value]
end

-- Maior id de peça aceito: limite técnico (inteiro exato em JSON e em Remotes), não de balanceamento.
local MAX_GEAR_ID = 2 ^ 31 - 1

-- Valida o id de uma peça vindo de fora: inteiro de 1 a MAX_GEAR_ID (rejeita NaN, infinito e frações).
function Formulas.parseGearId(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	if value ~= value or value % 1 ~= 0 or value < 1 or value > MAX_GEAR_ID then
		return nil
	end
	return value
end

function Formulas.emptyAttributes(): Types.Attributes
	return {
		Strength = 0,
		Vitality = 0,
		Intelligence = 0,
		Wisdom = 0,
		Dexterity = 0,
		Defense = 0,
		Luck = 0,
	}
end

-- Soma atributo por atributo (ex.: pontos distribuídos + equipamento = atributos efetivos). Devolve uma tabela nova.
function Formulas.addAttributes(a: Types.Attributes, b: Types.Attributes): Types.Attributes
	local result = Formulas.emptyAttributes()
	for _, name in ATTRIBUTE_ORDER do
		result[name] = a[name] + b[name]
	end
	return result
end

-- Multiplicador do fortalecimento: +10% por nível (+10 = o dobro). Nível fora de 0..máximo é limitado.
function Formulas.enhanceFactor(enhance: number?): number
	return 1 + Forge.enhanceStep * math.clamp(enhance or 0, 0, Forge.maxEnhance)
end

-- Tira o resíduo de ponto flutuante (1 × 1,3 = 1,3000000000000003): os valores do equipamento são décimos de
-- ponto (e décimos de % no Poder), então 4 casas sobram.
local function tidy(value: number): number
	return math.round(value * 10000) / 10000
end

-- Pontos que uma peça dá na raridade e no fortalecimento dela (a Rara multiplica os valores da Comum; cada + soma
-- 10% dos pontos base). Pode ter decimais (decisão do designer). Tabela nova.
function Formulas.gearAttributes(def: Types.GearDef, rarity: Types.Rarity, enhance: number?): Types.Attributes
	local multiplier = (Gear.rarityMultiplier[rarity] or 1) * Formulas.enhanceFactor(enhance)
	local result = Formulas.emptyAttributes()
	for _, name in ATTRIBUTE_ORDER do
		result[name] = tidy(def.attributes[name] * multiplier)
	end
	return result
end

-- Poder de uma arma na raridade e no fortalecimento dela (0 nas peças que não são arma).
function Formulas.gearPower(def: Types.GearDef, rarity: Types.Rarity, enhance: number?): number
	return tidy(def.power * (Gear.rarityMultiplier[rarity] or 1) * Formulas.enhanceFactor(enhance))
end

-- ===== Gemas (GDD > Gemas; números em Balance/Gems) =====

local GEM_ATTRIBUTE_BY_NAME: { [string]: Types.GemAttribute } = {
	Strength = "Strength",
	Vitality = "Vitality",
	Intelligence = "Intelligence",
	Wisdom = "Wisdom",
	Dexterity = "Dexterity",
	Defense = "Defense",
}

-- Atributo de gema vindo de fora (Remote, save): um dos 6 (não existe gema de Sorte). Nil se inválido.
function Formulas.parseGemAttribute(value: unknown): Types.GemAttribute?
	if typeof(value) ~= "string" then
		return nil
	end
	return GEM_ATTRIBUTE_BY_NAME[value]
end

-- Nível de gema vindo de fora: inteiro de 1 a Gems.maxLevel. Nil se inválido.
function Formulas.parseGemLevel(value: unknown): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	if value < 1 or value > Gems.maxLevel then
		return nil
	end
	return value
end

-- Gema vinda de fora ({ attribute, level }). Nil se inválida. Tabela nova.
function Formulas.parseGem(value: unknown): Types.Gem?
	if typeof(value) ~= "table" then
		return nil
	end
	local data = value :: { [string]: unknown }
	-- Tipos anotados: sem eles o verificador alarga o atributo para `string`.
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(data.attribute)
	local level = Formulas.parseGemLevel(data.level)
	if attribute == nil or level == nil then
		return nil
	end
	local gem: Types.Gem = { attribute = attribute, level = level }
	return gem
end

-- Pontos que a gema dá (nível × pontos por nível, só no atributo dela). Sem gema: tudo 0. Tabela nova.
-- O fortalecimento NÃO multiplica a gema (GDD: cada + dá 10% dos atributos BASE da peça).
function Formulas.gemAttributes(gem: Types.Gem?): Types.Attributes
	local result = Formulas.emptyAttributes()
	if gem then
		result[gem.attribute] = gem.level * Gems.pointsPerLevel
	end
	return result
end

-- Gold que a loja paga por 1 gema / 1 Removedor deste nível (venda de sobras: Balance/Gems).
function Formulas.gemSellPrice(level: number): number
	return Gems.gemSellPerLevel * level
end

function Formulas.removerSellPrice(level: number): number
	return math.round((Gems.removerPrice[level] or 0) * Gems.removerSellFraction)
end

-- Gold para fundir 3 gemas deste nível; nil = este nível não funde (Nv1 da loja, Nv3 e o máximo).
function Formulas.fuseCost(level: number): number?
	return Gems.fuseCost[level]
end

-- ===== Fortalecimento (GDD > Fortalecimento). `target` = nível que a tentativa quer alcançar (1 a 10). =====

function Formulas.enhanceChance(target: number): number
	return Forge.successChance[target] or 0
end

-- Gold de UMA tentativa: base da torre da peça × 2^(target − 1).
function Formulas.enhanceCost(def: Types.GearDef, target: number): number
	local base = Forge.enhanceBaseCost[def.tower] or 0
	return base * 2 ^ (math.max(target, 1) - 1)
end

-- Nível depois da tentativa. Sucesso sobe 1; falha nas tentativas de +8 a +10 tira 1 nível; antes disso, fica.
function Formulas.enhanceResult(current: number, success: boolean): number
	local target = current + 1
	if success then
		return math.min(target, Forge.maxEnhance)
	elseif target >= Forge.dropOnFailFrom then
		return math.max(current - 1, 0)
	end
	return current
end

-- Gold que o fortalecimento soma na venda: fração (Balance/Forge) da soma dos preços das tentativas de +1 até
-- `enhance`, na base da torre da peça. Arredonda para baixo: nunca passa do que o jogador mais sortudo gastou.
function Formulas.enhanceSellBonus(def: Types.GearDef, enhance: number): number
	local total = 0
	for target = 1, math.min(enhance, Forge.maxEnhance) do
		total += Formulas.enhanceCost(def, target)
	end
	-- +1e-6: 300 × (1/3) em ponto flutuante pode dar 99,999... e o floor viraria 99.
	return math.floor(total * Forge.enhanceSellFraction + 1e-6)
end

-- Gold que a loja paga pela peça: preço base da raridade (vezes a recompensa da torre da peça: Torre 2 = o dobro) +
-- o que o fortalecimento soma.
function Formulas.gearSellPrice(def: Types.GearDef, rarity: Types.Rarity, enhance: number): number
	local tower = Towers.byId[def.tower]
	local base = (Gear.sellPrice[rarity] or 0) * (if tower then tower.rewardMultiplier else 1)
	return math.round(base) + Formulas.enhanceSellBonus(def, enhance)
end

-- Quanto a peça vale numa run da torre `runTower` (nil = fora de run): numa torre ACIMA da dela, a fração de
-- Balance/Gear (pontos, Poder e fortalecimento; a gema não entra aqui: vale inteira).
function Formulas.gearEfficiency(def: Types.GearDef, runTower: number?): number
	if runTower ~= nil and runTower > def.tower then
		return Gear.lowerTowerEfficiency
	end
	return 1
end

-- ===== Transferir o fortalecimento (decisões do designer): as duas peças TROCAM os níveis =====

export type TransferCheck = "Ok" | "WrongSlot" | "NothingToMove" | "SameLevel" | "HigherTower"

-- Pode trocar o fortalecimento da peça A (+enhanceA) com o da peça B (+enhanceB)? Só peças do mesmo tipo (slot), e
-- um nível só vai para peça da MESMA torre ou de uma mais baixa: subir seria um atalho (fortalecer uma peça barata
-- da Torre 1 com o Gold de uma torre alta e passar o + para a peça cara).
function Formulas.transferCheck(
	defA: Types.GearDef,
	enhanceA: number,
	defB: Types.GearDef,
	enhanceB: number
): TransferCheck
	if defA.slot ~= defB.slot then
		return "WrongSlot"
	end
	if enhanceA == 0 and enhanceB == 0 then
		return "NothingToMove"
	end
	if enhanceA == enhanceB then
		return "SameLevel"
	end
	if (enhanceA > 0 and defB.tower > defA.tower) or (enhanceB > 0 and defA.tower > defB.tower) then
		return "HigherTower"
	end
	return "Ok"
end

-- Gold da troca: 1 tentativa do MAIOR nível trocado, na base da torre da peça que tem esse nível.
function Formulas.transferCost(defA: Types.GearDef, enhanceA: number, defB: Types.GearDef, enhanceB: number): number
	if enhanceA >= enhanceB then
		return Formulas.enhanceCost(defA, enhanceA)
	end
	return Formulas.enhanceCost(defB, enhanceB)
end

function Formulas.isScaling(classDef: Types.ClassDef, attribute: Types.AttributeName): boolean
	return table.find(classDef.scalingAttributes, attribute) ~= nil
end

-- Dano do GDD: Base × (1 + 0,02 × Atributo × M) × (1 + Poder). Físico usa Força; mágico usa Inteligência.
-- `power` = Poder da arma equipada, só quando ela é do mesmo tipo de dano do golpe (nil ou 0 = sem bônus).
-- M vale para o atributo inteiro (distribuído + equipamento): pontos de equipamento num atributo ★ rendem 1,5×.
function Formulas.damage(
	baseDamage: number,
	damageType: Types.DamageType,
	attributes: Types.Attributes,
	classDef: Types.ClassDef,
	power: number?
): number
	local attribute: Types.AttributeName = if damageType == "Physical" then "Strength" else "Intelligence"
	local m = if Formulas.isScaling(classDef, attribute) then Combat.scalingMultiplier else Combat.commonMultiplier
	local fromAttribute = 1 + Combat.damagePerAttributePoint * attributes[attribute] * m
	return baseDamage * fromAttribute * (1 + math.max(power or 0, 0))
end

-- Fração do dano bloqueada pela Defesa (0 a <1). Vale igual para dano físico e mágico.
function Formulas.defenseReduction(defense: number): number
	local d = math.max(defense, 0)
	return d / (d + Combat.defenseConstant)
end

function Formulas.applyDefense(rawDamage: number, defense: number): number
	return rawDamage * (1 - Formulas.defenseReduction(defense))
end

function Formulas.critChance(luck: number): number
	return math.clamp(Combat.critBaseChance + Combat.critChancePerLuck * math.max(luck, 0), 0, 1)
end

-- Quanto a Sorte multiplica a chance de "achados" raros (1 = sem bônus; 50 pts = ×2; 100 pts = ×3).
function Formulas.luckFindMultiplier(luck: number): number
	return 1 + math.max(luck, 0) / Luck.findDivisor
end

-- Chance de um "achado" raro (Coração; no futuro drops, baús, salas secretas) com a Sorte aplicada.
-- Ex.: base 0,1% com Sorte 27 -> 0,154%; com Sorte 100 -> 0,3%.
function Formulas.luckChance(baseChance: number, luck: number): number
	return math.clamp(baseChance * Formulas.luckFindMultiplier(luck), 0, 1)
end

-- `roll` é um número em [0, 1) sorteado pelo servidor; separado para a função continuar pura e testável.
function Formulas.rollCrit(luck: number, roll: number): boolean
	return roll < Formulas.critChance(luck)
end

function Formulas.maxHealth(classDef: Types.ClassDef, attributes: Types.Attributes): number
	return classDef.baseHealth + Progression.healthPerVitality * attributes.Vitality
end

function Formulas.maxMana(classDef: Types.ClassDef, attributes: Types.Attributes): number
	return classDef.baseMana + Progression.manaPerWisdom * attributes.Wisdom
end

function Formulas.maxStamina(classDef: Types.ClassDef, attributes: Types.Attributes): number
	return classDef.baseStamina + Progression.staminaPerDexterity * attributes.Dexterity
end

-- XP necessário para ir do nível `level` para `level + 1`. No nível máximo, devolve math.huge.
function Formulas.xpToNextLevel(level: number): number
	if level >= Progression.maxLevel then
		return math.huge
	end
	return math.floor(Progression.xpBase * Progression.xpGrowth ^ (level - 1))
end

-- Soma XP e sobe quantos níveis couberem. Devolve o novo nível, o XP que sobrou e os níveis ganhos.
function Formulas.addXp(level: number, xp: number, gained: number): (number, number, number)
	local newLevel = level
	local newXp = xp + math.max(gained, 0)
	while newLevel < Progression.maxLevel and newXp >= Formulas.xpToNextLevel(newLevel) do
		newXp -= Formulas.xpToNextLevel(newLevel)
		newLevel += 1
	end
	if newLevel >= Progression.maxLevel then
		newXp = 0
	end
	return newLevel, newXp, newLevel - level
end

-- "Distribuir recomendado": cada ponto vai para o atributo de scaling com MENOS pontos (empate: o primeiro da lista).
-- Assim os dois atributos de scaling crescem equilibrados, sem precisar guardar estado extra.
function Formulas.distributeRecommended(
	attributes: Types.Attributes,
	points: number,
	classDef: Types.ClassDef
): Types.Attributes
	local result = table.clone(attributes)
	local scaling = classDef.scalingAttributes
	if #scaling == 0 then
		return result
	end
	for _ = 1, math.max(math.floor(points), 0) do
		local best = scaling[1]
		for _, name in scaling do
			if result[name] < result[best] then
				best = name
			end
		end
		result[best] += 1
	end
	return result
end

-- Assistência de mira: direção (horizontal, unitária) para o alvo mais próximo que esteja dentro do alcance
-- e a no máximo `maxAngleDeg` graus da frente. Sem alvo válido, devolve a própria frente.
function Formulas.chooseAimDirection(
	origin: Vector3,
	facing: Vector3,
	targets: { Vector3 },
	range: number,
	maxAngleDeg: number
): Vector3
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 1e-3 then
		flatFacing = Vector3.new(0, 0, -1)
	end
	flatFacing = flatFacing.Unit

	local cosLimit = math.cos(math.rad(maxAngleDeg))
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, position in targets do
		local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
		local distance = offset.Magnitude
		if distance > 1e-3 and distance <= range and distance < bestDistance then
			local direction = offset.Unit
			if direction:Dot(flatFacing) >= cosLimit then
				best = direction
				bestDistance = distance
			end
		end
	end
	return best or flatFacing
end

-- Mobs por sala de combate no andar N: base + extra a cada `floorsPerStep` andares
-- (base 2, extra 1, a cada 2: andares 1-2 = 2, 3-4 = 3, 5-6 = 4...).
function Formulas.mobsPerRoom(floorNumber: number, base: number, extraPerStep: number, floorsPerStep: number): number
	local steps = math.floor((math.max(floorNumber, 1) - 1) / math.max(floorsPerStep, 1))
	return base + extraPerStep * steps
end

-- Quantos mobs em cada uma das `roomCount` salas: `perRoom` em todas, sem passar de `maxTotal` no andar (se houver).
-- Com teto, ele é dividido igualmente e as primeiras salas recebem o resto.
-- Ex.: 9 salas, 4 por sala, teto 30 -> 4,4,4,3,3,3,3,3,3 (= 30). 7 salas × 4 = 28 fica 28 (abaixo do teto).
function Formulas.mobDistribution(roomCount: number, perRoom: number, maxTotal: number?): { number }
	local counts: { number } = {}
	if roomCount <= 0 then
		return counts
	end
	if maxTotal == nil or roomCount * perRoom <= maxTotal then
		for i = 1, roomCount do
			counts[i] = perRoom
		end
		return counts
	end
	local base = math.floor(maxTotal / roomCount)
	local extra = maxTotal - base * roomCount
	for i = 1, roomCount do
		counts[i] = base + (if i <= extra then 1 else 0)
	end
	return counts
end

-- Multiplicador de vida e dano dos mobs no andar N (andar 1 = 1,0).
function Formulas.floorStatMultiplier(floorNumber: number, growthPerFloor: number): number
	return 1 + growthPerFloor * (math.max(floorNumber, 1) - 1)
end

return table.freeze(Formulas)
