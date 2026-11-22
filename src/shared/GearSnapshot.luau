--!strict
-- Formato do Attribute "GearData" do Player (JSON): as peças da conta e os slots do personagem ativo.
-- O servidor monta e codifica (GearService); o cliente decodifica e VALIDA tudo (mesmo vindo do servidor) antes de
-- mostrar. Peça inválida é ignorada; dado ausente vira o snapshot vazio.

local HttpService: HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Gear = require(script.Parent.Balance.Gear)
local Forge = require(script.Parent.Balance.Forge)

local GearSnapshot = {}

function GearSnapshot.empty(): Types.GearSnapshot
	return { gear = {}, equipped = {} }
end

function GearSnapshot.encode(snapshot: Types.GearSnapshot): string
	return HttpService:JSONEncode(snapshot)
end

function GearSnapshot.decode(raw: unknown): Types.GearSnapshot
	local snapshot = GearSnapshot.empty()
	if typeof(raw) ~= "string" then
		return snapshot
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(decoded) ~= "table" then
		return snapshot
	end
	local data = decoded :: { [string]: unknown }
	local known: { [number]: boolean } = {}
	if typeof(data.gear) == "table" then
		local list = data.gear :: { unknown }
		for i = 1, #list do
			local item = list[i]
			if typeof(item) == "table" then
				local entry = item :: { [string]: unknown }
				local id = Formulas.parseGearId(entry.id)
				local rarity: Types.Rarity? = Formulas.parseRarity(entry.rarity)
				local defId = entry.defId
				local inUse = entry.inUse
				local enhance = entry.enhance
				if
					id ~= nil
					and rarity ~= nil
					and typeof(defId) == "string"
					and Gear.byId[defId] ~= nil
					and typeof(inUse) == "boolean"
					and typeof(enhance) == "number"
					and enhance % 1 == 0
					and enhance >= 0
					and enhance <= Forge.maxEnhance
					and not known[id]
				then
					known[id] = true
					table.insert(
						snapshot.gear,
						{ id = id, defId = defId, rarity = rarity, enhance = enhance, inUse = inUse }
					)
				end
			end
		end
	end
	if typeof(data.equipped) == "table" then
		local equipped = data.equipped :: { [string]: unknown }
		for _, slot: Types.EquipSlot in Gear.slots do
			local id = Formulas.parseGearId(equipped[slot])
			if id ~= nil and known[id] then
				snapshot.equipped[slot] = id
			end
		end
	end
	return snapshot
end

function GearSnapshot.find(snapshot: Types.GearSnapshot, id: number): Types.GearEntry?
	for _, entry in snapshot.gear do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- Ordem de exibição nas grades e listas (mochila, venda, forja): por slot, Rara primeiro, mais fortalecida
-- primeiro, nome e id. Ordena a lista recebida (no lugar).
function GearSnapshot.sortEntries(entries: { Types.GearEntry })
	local slotOrder: { [string]: number } = {}
	for index, slot in Gear.slots do
		slotOrder[slot] = index
	end
	table.sort(entries, function(a: Types.GearEntry, b: Types.GearEntry): boolean
		local defA, defB = Gear.byId[a.defId], Gear.byId[b.defId]
		if slotOrder[defA.slot] ~= slotOrder[defB.slot] then
			return slotOrder[defA.slot] < slotOrder[defB.slot]
		end
		if a.rarity ~= b.rarity then
			return a.rarity == "Rare"
		end
		if a.enhance ~= b.enhance then
			return a.enhance > b.enhance
		end
		if defA.displayName ~= defB.displayName then
			return defA.displayName < defB.displayName
		end
		return a.id < b.id
	end)
end

-- Peças no baú (nenhum personagem usa).
function GearSnapshot.chestCount(snapshot: Types.GearSnapshot): number
	local count = 0
	for _, entry in snapshot.gear do
		if not entry.inUse then
			count += 1
		end
	end
	return count
end

return table.freeze(GearSnapshot)
