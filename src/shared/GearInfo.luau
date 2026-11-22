--!strict
-- Textos e cores dos equipamentos para a interface (mesmo papel do AttributeInfo). Os números vêm de Formulas.
-- Usado pelas mensagens do servidor e pelos painéis do cliente, para nomes e cores baterem em todo lugar.

local Types = require(script.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local AttributeInfo = require(script.Parent.AttributeInfo)
local Gems = require(script.Parent.Balance.Gems)

local GearInfo = {}

local SLOT_LABELS: { [string]: string } = {
	Weapon = "Arma",
	Helmet = "Capacete",
	Armor = "Armadura",
	Pants = "Calças",
	Boots = "Botas",
	Bracelet = "Pulseira",
	Necklace = "Colar",
}

-- GDD > Equipamentos > Raridades: Comum cinza, Raro azul.
local RARITY_LABELS: { [string]: string } = {
	Common = "Comum",
	Rare = "Raro",
}
local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(200, 200, 210),
	Rare = Color3.fromRGB(80, 150, 255),
}

-- Número para a tela: no máximo 1 casa decimal, com vírgula (12 -> "12"; 9,1 -> "9,1"; 281,25 -> "281,3").
-- Atributos do equipamento fortalecido têm décimos (Calças +1 FOR no +5 = +1,5).
function GearInfo.formatNumber(value: number): string
	local rounded = math.round(value * 10) / 10
	if rounded % 1 == 0 then
		return string.format("%d", rounded)
	end
	local text = string.gsub(string.format("%.1f", rounded), "%.", ",") -- gsub devolve (texto, nº): fica o texto
	return text
end

local formatNumber = GearInfo.formatNumber

-- "+5" (ou "" sem fortalecimento).
function GearInfo.enhanceLabel(enhance: number?): string
	return if enhance and enhance > 0 then `+{enhance}` else ""
end

function GearInfo.slotLabel(slot: Types.EquipSlot): string
	return SLOT_LABELS[slot] or slot
end

function GearInfo.rarityLabel(rarity: Types.Rarity): string
	return RARITY_LABELS[rarity] or rarity
end

function GearInfo.rarityColor(rarity: Types.Rarity): Color3
	return RARITY_COLORS[rarity] or Color3.new(1, 1, 1)
end

-- Nome com o fortalecimento: "Gibão do Combatente +5" (sem a raridade).
function GearInfo.displayName(def: Types.GearDef, enhance: number?): string
	local label = GearInfo.enhanceLabel(enhance)
	return if label == "" then def.displayName else `{def.displayName} {label}`
end

-- Ex.: "Faixa do Combatente (Raro)" ou "Gibão do Combatente +5 (Comum)".
function GearInfo.fullName(def: Types.GearDef, rarity: Types.Rarity, enhance: number?): string
	return `{GearInfo.displayName(def, enhance)} ({GearInfo.rarityLabel(rarity)})`
end

-- ===== Gemas =====

-- Cor de cada tipo de gema (para a célula e o nome). Provisório, até a arte.
local GEM_COLORS: { [string]: Color3 } = {
	Strength = Color3.fromRGB(235, 90, 80),
	Vitality = Color3.fromRGB(110, 210, 110),
	Intelligence = Color3.fromRGB(100, 150, 255),
	Wisdom = Color3.fromRGB(180, 120, 240),
	Dexterity = Color3.fromRGB(240, 210, 80),
	Defense = Color3.fromRGB(140, 200, 210),
}

local function attributeInfo(attribute: Types.AttributeName): AttributeInfo.Info?
	for _, info in AttributeInfo do
		if info.key == attribute then
			return info
		end
	end
	return nil
end

-- Sigla do atributo da gema ("FOR").
function GearInfo.gemShort(attribute: Types.GemAttribute): string
	local info = attributeInfo(attribute)
	return if info then info.short else attribute
end

function GearInfo.gemColor(attribute: Types.GemAttribute): Color3
	return GEM_COLORS[attribute] or Color3.new(1, 1, 1)
end

-- "Gema de Força Nv1".
function GearInfo.gemName(attribute: Types.GemAttribute, level: number): string
	local info = attributeInfo(attribute)
	return `Gema de {if info then info.long else attribute} Nv{level}`
end

-- "+1 FOR".
function GearInfo.gemEffect(attribute: Types.GemAttribute, level: number): string
	local points = Formulas.gemAttributes({ attribute = attribute, level = level })[attribute]
	return `+{formatNumber(points)} {GearInfo.gemShort(attribute)}`
end

-- "Removedor Nv1".
function GearInfo.removerName(level: number): string
	return `Removedor Nv{level}`
end

-- Por que a troca de fortalecimento entre duas peças não pode (Formulas.transferCheck). Nil = pode.
function GearInfo.transferBlockedReason(check: Formulas.TransferCheck): string?
	if check == "WrongSlot" then
		return "Só entre peças do mesmo tipo"
	elseif check == "NothingToMove" then
		return "Nenhuma das duas peças está fortalecida"
	elseif check == "SameLevel" then
		return "As duas peças têm o mesmo fortalecimento"
	elseif check == "HigherTower" then
		return "O fortalecimento não passa para peça de torre mais alta"
	end
	return nil
end

-- Por que gemas deste nível não fundem (só para os níveis sem fusão em Balance/Gems).
function GearInfo.fuseBlockedReason(level: number): string
	if level == Gems.shopLevel then
		return `A gema Nv{level} (da loja) não funde`
	elseif level >= Gems.maxLevel then
		return `Nv{Gems.maxLevel} é o nível máximo`
	end
	return `Não existe a fusão de Nv{level} para Nv{level + 1}`
end

-- Ex.: "+2 FOR, +1 VIT" ou "+1 FOR, +2 DES  ·  Poder +5%" (valores já com a raridade e o fortalecimento).
function GearInfo.describe(def: Types.GearDef, rarity: Types.Rarity, enhance: number?): string
	local attributes = Formulas.gearAttributes(def, rarity, enhance)
	local parts: { string } = {}
	for _, info in AttributeInfo do
		local value = attributes[info.key]
		if value ~= 0 then
			table.insert(parts, `+{formatNumber(value)} {info.short}`)
		end
	end
	local text = table.concat(parts, ", ")
	local power = Formulas.gearPower(def, rarity, enhance)
	if power > 0 then
		local powerText = `Poder +{formatNumber(power * 100)}%`
		text = if text == "" then powerText else `{text}  ·  {powerText}`
	end
	return text
end

return table.freeze(GearInfo)
