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

local function formatNumber(value: number): string
	if value % 1 == 0 then
		return string.format("%d", value)
	end
	return string.format("%.1f", value)
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

-- Ex.: "Faixa do Combatente (Raro)".
function GearInfo.fullName(def: Types.GearDef, rarity: Types.Rarity): string
	return `{def.displayName} ({GearInfo.rarityLabel(rarity)})`
end

-- Ex.: "+2 FOR, +1 VIT" ou "+1 FOR, +2 DES  ·  Poder +5%" (valores já com a raridade).
function GearInfo.describe(def: Types.GearDef, rarity: Types.Rarity): string
	local attributes = Formulas.gearAttributes(def, rarity)
	local parts: { string } = {}
	for _, info in AttributeInfo do
		local value = attributes[info.key]
		if value ~= 0 then
			table.insert(parts, `+{formatNumber(value)} {info.short}`)
		end
	end
	local text = table.concat(parts, ", ")
	local power = Formulas.gearPower(def, rarity)
	if power > 0 then
		local powerText = `Poder +{formatNumber(math.round(power * 1000) / 10)}%`
		text = if text == "" then powerText else `{text}  ·  {powerText}`
	end
	return text
end

return table.freeze(GearInfo)
