--!strict
-- Fórmulas de jogo, como funções puras (sem estado, sem Instances).
-- O servidor usa para DECIDIR; o cliente só pode usar para MOSTRAR prévias.

local Types = require(script.Parent.Types)
local Combat = require(script.Parent.Balance.Combat)
local Progression = require(script.Parent.Balance.Progression)
local Luck = require(script.Parent.Balance.Luck)

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
