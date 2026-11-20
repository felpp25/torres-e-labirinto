--!strict
-- Fórmulas de jogo, como funções puras (sem estado, sem Instances).
-- O servidor usa para DECIDIR; o cliente só pode usar para MOSTRAR prévias.

local Types = require(script.Parent.Types)
local Combat = require(script.Parent.Balance.Combat)
local Progression = require(script.Parent.Balance.Progression)

local Formulas = {}

local ATTRIBUTE_ORDER: { Types.AttributeName } =
	{ "Strength", "Vitality", "Intelligence", "Wisdom", "Dexterity", "Defense", "Luck" }

function Formulas.attributeNames(): { Types.AttributeName }
	return table.clone(ATTRIBUTE_ORDER)
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

function Formulas.isScaling(classDef: Types.ClassDef, attribute: Types.AttributeName): boolean
	return table.find(classDef.scalingAttributes, attribute) ~= nil
end

-- Dano do GDD: Base × (1 + 0,02 × Atributo × M). Físico usa Força; mágico usa Inteligência.
function Formulas.damage(
	baseDamage: number,
	damageType: Types.DamageType,
	attributes: Types.Attributes,
	classDef: Types.ClassDef
): number
	local attribute: Types.AttributeName = if damageType == "Physical" then "Strength" else "Intelligence"
	local m = if Formulas.isScaling(classDef, attribute) then Combat.scalingMultiplier else Combat.commonMultiplier
	return baseDamage * (1 + Combat.damagePerAttributePoint * attributes[attribute] * m)
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

-- Multiplicador de vida e dano dos mobs no andar N (andar 1 = 1,0).
function Formulas.floorStatMultiplier(floorNumber: number, growthPerFloor: number): number
	return 1 + growthPerFloor * (math.max(floorNumber, 1) - 1)
end

return table.freeze(Formulas)
