--!strict
-- Formato do Attribute "GearData" do Player (JSON): as peças da conta, os slots do personagem ativo e as pilhas
-- de gemas e Removedores do baú.
-- O servidor monta e codifica (GearService); o cliente decodifica e VALIDA tudo (mesmo vindo do servidor) antes de
-- mostrar. Peça ou pilha inválida é ignorada; dado ausente vira o snapshot vazio.

local HttpService: HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Gear = require(script.Parent.Balance.Gear)
local Forge = require(script.Parent.Balance.Forge)
local Gems = require(script.Parent.Balance.Gems)

local GearSnapshot = {}

function GearSnapshot.empty(): Types.GearSnapshot
	return { gear = {}, equipped = {}, gems = {}, removers = {} }
end

-- Quantidade de uma pilha vinda de fora: inteiro de 1 ao máximo da pilha. Nil se inválida.
local function parseCount(value: unknown): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		return nil
	end
	return if value >= 1 and value <= Gems.stackMax then value else nil
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
				local gem = Formulas.parseGem(entry.gem)
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
					and (entry.gem == nil or gem ~= nil)
					and not known[id]
				then
					known[id] = true
					table.insert(
						snapshot.gear,
						{ id = id, defId = defId, rarity = rarity, enhance = enhance, gem = gem, inUse = inUse }
					)
				end
			end
		end
	end
	-- Pilhas do baú: cada tipo (atributo + nível) uma vez só.
	if typeof(data.gems) == "table" then
		local seen: { [string]: boolean } = {}
		local list = data.gems :: { unknown }
		for i = 1, #list do
			local item = list[i]
			local gem = Formulas.parseGem(item)
			local count = if typeof(item) == "table" then parseCount((item :: { [string]: unknown }).count) else nil
			if gem and count then
				local key = `{gem.attribute}:{gem.level}`
				if not seen[key] then
					seen[key] = true
					table.insert(snapshot.gems, { attribute = gem.attribute, level = gem.level, count = count })
				end
			end
		end
	end
	if typeof(data.removers) == "table" then
		local seen: { [number]: boolean } = {}
		local list = data.removers :: { unknown }
		for i = 1, #list do
			local item = list[i]
			if typeof(item) == "table" then
				local stack = item :: { [string]: unknown }
				local level = Formulas.parseGemLevel(stack.level)
				local count = parseCount(stack.count)
				if level and count and not seen[level] then
					seen[level] = true
					table.insert(snapshot.removers, { level = level, count = count })
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

-- Espaços ocupados no baú: peças que nenhum personagem usa + 1 por pilha de gema ou de Removedor.
function GearSnapshot.chestCount(snapshot: Types.GearSnapshot): number
	local count = #snapshot.gems + #snapshot.removers
	for _, entry in snapshot.gear do
		if not entry.inUse then
			count += 1
		end
	end
	return count
end

function GearSnapshot.gemCount(snapshot: Types.GearSnapshot, attribute: Types.GemAttribute, level: number): number
	for _, stack in snapshot.gems do
		if stack.attribute == attribute and stack.level == level then
			return stack.count
		end
	end
	return 0
end

function GearSnapshot.removerCount(snapshot: Types.GearSnapshot, level: number): number
	for _, stack in snapshot.removers do
		if stack.level == level then
			return stack.count
		end
	end
	return 0
end

-- Cabe mais 1 nesta pilha (que hoje tem `current`)? Mesma regra do servidor (PlayerSchema): pilha nova ocupa 1
-- espaço do baú. Só para deixar o botão cinza; quem decide é o servidor.
function GearSnapshot.canStoreOne(snapshot: Types.GearSnapshot, current: number): boolean
	if current + 1 > Gems.stackMax then
		return false
	end
	return current > 0 or GearSnapshot.chestCount(snapshot) < Gear.chestCapacity
end

return table.freeze(GearSnapshot)
