--!strict
-- Textos e cores dos equipamentos para a interface (mesmo papel do AttributeInfo). Os números vêm de Formulas.
-- Usado pelas mensagens do servidor e pelos painéis do cliente, para nomes e cores baterem em todo lugar.

local Types = require(script.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local AttributeInfo = require(script.Parent.AttributeInfo)

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
