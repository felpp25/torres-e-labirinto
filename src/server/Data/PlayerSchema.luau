--!strict
-- Formato dos dados salvos de um jogador (DataStore). Funções puras: criar padrão, validar/migrar e copiar.
--
-- Uma chave por jogador (User_<UserId>) com o PERFIL da conta:
--   schemaVersion  versão do formato (para migrações)
--   gold           Gold da CONTA, compartilhado por todos os personagens
--   inventory      itens da CONTA (ex.: poções): { [itemId] = quantidade }
--   activeSlot     personagem em uso
--   characters     lista de personagens; cada um com classe, nível, XP, atributos, pontos livres e equipamento
--   gear           TODAS as peças de equipamento da conta (baú + equipadas): { id, defId, rarity }
--   nextGearId     próximo id de peça (só cresce; um id nunca é reutilizado)
--   session        trava de sessão (qual servidor está com os dados e desde quando); nil = livre
-- Decisões do designer: vários personagens por conta; Gold GLOBAL da conta (trocar de personagem no lobby para
-- atender o grupo sem recomeçar a economia); run em andamento NÃO é salva.
--
-- Equipamento (GDD > Equipamentos > Dono): as peças são da CONTA; cada personagem tem 7 slots que apontam para ids
-- de `gear` (character.equipped). O baú = peças que nenhum personagem equipa (50 espaços; equipadas não contam).
-- O save guarda só referências: pontos, Poder, nome e preço vêm do catálogo (Shared/Balance/Gear).
-- character.attributes guarda SÓ os pontos distribuídos; o equipamento nunca entra ali (o reset devolveria pontos).
-- Peça com defId fora do catálogo (ex.: id renomeado por engano) fica guardada, mas "inerte": não aparece, não dá
-- pontos e não conta no baú. Se o id voltar ao catálogo, ela volta. Nada é apagado em silêncio.
-- O slot de arma nunca fica vazio (decisão do designer: a arma só é trocada); se ficar (dados velhos ou
-- corrompidos), a arma inicial da classe é dada de novo.
--
-- Versões:
--   1  Gold dentro de cada personagem.
--   2  Gold na conta. Migração: soma o Gold de todos os personagens da v1.
--   3  Inventário da conta (poções). Migração: inventário vazio.
--   4  Equipamento: peças da conta (gear) e 7 slots por personagem (equipped). Migração: todo personagem cuja
--      classe tem arma inicial ganha a arma Comum equipada (Lutador: Luvas de Couro).
--
-- REGRA: todo campo NOVO salvo (mesmo opcional, ex.: fortalecimento ou gema da peça) aumenta VERSION. O servidor
-- que encontra dados de uma versão MAIOR que a dele recusa carregar (DataService) em vez de apagar o que não conhece.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Classes = require(Shared.Balance.Classes)
local Progression = require(Shared.Balance.Progression)
local Shop = require(Shared.Balance.Shop)
local Gear = require(Shared.Balance.Gear)

export type Character = {
	classId: string,
	level: number,
	xp: number, -- XP dentro do nível atual
	unspentPoints: number,
	attributes: Types.Attributes, -- pontos DISTRIBUÍDOS (o equipamento soma por fora)
	equipped: { [Types.EquipSlot]: number }, -- slot -> id da peça em Profile.gear
}

export type Session = {
	id: string, -- identificador do servidor que está com os dados
	time: number, -- os.time() da última renovação da trava
}

export type Profile = {
	schemaVersion: number,
	gold: number,
	inventory: { [string]: number },
	activeSlot: number,
	characters: { Character },
	gear: { Types.OwnedGear }, -- lista densa, na ordem em que as peças chegaram
	nextGearId: number,
	session: Session?,
}

-- Resultados das regras de equipamento (funções puras abaixo). O GearService transforma em mensagens.
export type EquipOutcome =
	"Equipped"
	| "AlreadyEquipped"
	| "NotFound"
	| "WrongClass"
	| "LowLevel"
	| "ChestFull"
	| "OtherCharacterWeapon"
export type UnequipOutcome = "Unequipped" | "Empty" | "WeaponLocked" | "ChestFull"
export type SellOutcome = "Sold" | "NotFound" | "InUse"

local PlayerSchema = {}

PlayerSchema.VERSION = 4

local WEAPON_SLOT: Types.EquipSlot = "Weapon"
local MAX_DEF_ID_LENGTH = 64 -- defId salvo maior que isto é lixo (os ids do catálogo são curtos)

function PlayerSchema.newCharacter(classId: string): Character
	return {
		classId = classId,
		level = 1,
		xp = 0,
		unspentPoints = 0,
		attributes = Formulas.emptyAttributes(),
		equipped = {},
	}
end

-- Perfil padrão SEM a arma inicial (base do reconcile: dar a arma é decisão do próprio reconcile).
local function baseProfile(): Profile
	return {
		schemaVersion = PlayerSchema.VERSION,
		gold = 0,
		inventory = {},
		activeSlot = 1,
		characters = { PlayerSchema.newCharacter(Classes.defaultClassId) },
		gear = {},
		nextGearId = 1,
		session = nil,
	}
end

-- ===== Equipamento: consultas e alterações (puras, sem yield e sem Random: valem dentro do UpdateAsync) =====

local function indexOfGear(profile: Profile, id: number): number?
	for index, piece in profile.gear do
		if piece.id == id then
			return index
		end
	end
	return nil
end

function PlayerSchema.findGear(profile: Profile, id: number): Types.OwnedGear?
	local index = indexOfGear(profile, id)
	return if index then profile.gear[index] else nil
end

-- Def do catálogo de uma peça; nil se a peça for inerte (defId fora do catálogo).
function PlayerSchema.defOf(piece: Types.OwnedGear): Types.GearDef?
	return Gear.byId[piece.defId]
end

-- Qual personagem (índice) equipa a peça, e em que slot. Nil = está no baú (ou é inerte).
function PlayerSchema.ownerOf(profile: Profile, id: number): (number?, Types.EquipSlot?)
	for index, character in profile.characters do
		-- Pela lista fixa de slots, com o tipo anotado (sem anotação o verificador alarga o slot para `string`).
		for _, slot: Types.EquipSlot in Gear.slots do
			if character.equipped[slot] == id then
				return index, slot
			end
		end
	end
	return nil, nil
end

function PlayerSchema.equippedIds(profile: Profile): { [number]: boolean }
	local used: { [number]: boolean } = {}
	for _, character in profile.characters do
		for _, equippedId in character.equipped do
			used[equippedId] = true
		end
	end
	return used
end

-- Peças no baú: as que existem no catálogo e que nenhum personagem equipa.
function PlayerSchema.chestCount(profile: Profile): number
	local used = PlayerSchema.equippedIds(profile)
	local count = 0
	for _, piece in profile.gear do
		if not used[piece.id] and Gear.byId[piece.defId] ~= nil then
			count += 1
		end
	end
	return count
end

-- Cria uma peça nova na conta (vai para o baú). Quem chama decide o que fazer com o baú cheio (GearService).
function PlayerSchema.addGear(profile: Profile, defId: string, rarity: Types.Rarity): Types.OwnedGear
	assert(Gear.byId[defId] ~= nil, `PlayerSchema.addGear: peça desconhecida {defId}`)
	local id = profile.nextGearId
	assert(Formulas.parseGearId(id) ~= nil, `PlayerSchema.addGear: nextGearId inválido ({id})`)
	local piece: Types.OwnedGear = { id = id, defId = defId, rarity = rarity }
	table.insert(profile.gear, piece)
	profile.nextGearId = id + 1
	return piece
end

-- Dá e equipa a arma inicial da classe, se o slot de arma estiver vazio. Devolve se deu.
function PlayerSchema.grantStartingGear(profile: Profile, character: Character): boolean
	local defId = Gear.startingWeapon[character.classId]
	if defId == nil or character.equipped[WEAPON_SLOT] ~= nil then
		return false
	end
	local piece = PlayerSchema.addGear(profile, defId, "Common")
	character.equipped[WEAPON_SLOT] = piece.id
	return true
end

-- Equipa a peça `id` no personagem `charIndex`. Valida tudo antes de alterar qualquer coisa.
-- A peça que estava no slot volta para o baú; a que vem de outro personagem sai dele (GDD > Dono).
function PlayerSchema.equip(profile: Profile, charIndex: number, id: number): EquipOutcome
	local character = profile.characters[charIndex]
	local piece = PlayerSchema.findGear(profile, id)
	local def = if piece then Gear.byId[piece.defId] else nil
	if character == nil or def == nil then
		return "NotFound"
	end
	if def.classId ~= nil and def.classId ~= character.classId then
		return "WrongClass"
	end
	if character.level < def.minLevel then
		return "LowLevel"
	end
	local slot: Types.EquipSlot = def.slot
	if character.equipped[slot] == id then
		return "AlreadyEquipped"
	end
	local ownerIndex: number?, ownerSlot: Types.EquipSlot? = PlayerSchema.ownerOf(profile, id)
	-- O slot de arma nunca fica vazio: não dá para tirar a arma que OUTRO personagem está usando.
	if ownerIndex ~= nil and ownerIndex ~= charIndex and ownerSlot == WEAPON_SLOT then
		return "OtherCharacterWeapon"
	end
	-- Baú: entra a peça que sai deste slot; sai a peça, se ela estava no baú. Troca simples não muda a contagem.
	local delta = (if character.equipped[slot] ~= nil then 1 else 0) - (if ownerIndex == nil then 1 else 0)
	if delta > 0 and PlayerSchema.chestCount(profile) + delta > Gear.chestCapacity then
		return "ChestFull"
	end
	if ownerIndex ~= nil and ownerSlot ~= nil then
		profile.characters[ownerIndex].equipped[ownerSlot] = nil
	end
	character.equipped[slot] = id
	return "Equipped"
end

-- Tira a peça do slot (vai para o baú). A arma não pode ser tirada, só trocada (decisão do designer).
function PlayerSchema.unequip(profile: Profile, charIndex: number, slot: Types.EquipSlot): UnequipOutcome
	local character = profile.characters[charIndex]
	if character == nil or character.equipped[slot] == nil then
		return "Empty"
	end
	if slot == WEAPON_SLOT then
		return "WeaponLocked"
	end
	if PlayerSchema.chestCount(profile) >= Gear.chestCapacity then
		return "ChestFull"
	end
	character.equipped[slot] = nil
	return "Unequipped"
end

-- Tira uma peça do BAÚ da conta (venda). Peça equipada ou inerte não sai. Devolve a peça removida.
function PlayerSchema.sell(profile: Profile, id: number): (SellOutcome, Types.OwnedGear?)
	local index = indexOfGear(profile, id)
	if index == nil then
		return "NotFound", nil
	end
	local piece = profile.gear[index]
	if Gear.byId[piece.defId] == nil then
		return "NotFound", nil
	end
	if PlayerSchema.ownerOf(profile, id) ~= nil then
		return "InUse", nil
	end
	table.remove(profile.gear, index)
	return "Sold", piece
end

function PlayerSchema.newProfile(): Profile
	local profile = baseProfile()
	for _, character in profile.characters do
		PlayerSchema.grantStartingGear(profile, character)
	end
	return profile
end

local function wholeNumber(value: unknown, minimum: number, maximum: number, default: number): number
	if typeof(value) ~= "number" or value ~= value then -- value ~= value: NaN
		return default
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

local function reconcileCharacter(raw: unknown): Character
	local character = PlayerSchema.newCharacter(Classes.defaultClassId)
	if typeof(raw) ~= "table" then
		return character
	end
	local data = raw :: { [string]: unknown }
	local classId = data.classId
	if typeof(classId) == "string" and Classes.byId[classId] then
		character.classId = classId
	end
	character.level = wholeNumber(data.level, 1, Progression.maxLevel, 1)
	character.xp = wholeNumber(data.xp, 0, math.huge, 0)
	character.unspentPoints = wholeNumber(data.unspentPoints, 0, math.huge, 0)
	local attributes = data.attributes
	if typeof(attributes) == "table" then
		local values = attributes :: { [string]: unknown }
		for _, name in Formulas.attributeNames() do
			character.attributes[name] = wholeNumber(values[name], 0, math.huge, 0)
		end
	end
	return character
end

-- Equipamento salvo (v4+). Lê na ordem da lista (determinístico: o UpdateAsync pode rodar o callback mais de uma
-- vez). Descarta só o que é lixo (id inválido ou repetido, raridade inválida); peça fora do catálogo fica inerte.
local function reconcileGear(data: { [string]: unknown }, profile: Profile, rawCharacters: { unknown })
	local byId: { [number]: Types.OwnedGear } = {}
	local maxId = 0
	local dropped = 0
	if typeof(data.gear) == "table" then
		local rawGear = data.gear :: { unknown }
		for i = 1, #rawGear do
			local rawPiece = rawGear[i]
			local id: number? = nil
			local rarity: Types.Rarity? = nil
			local defId: string? = nil
			if typeof(rawPiece) == "table" then
				local p = rawPiece :: { [string]: unknown }
				id = Formulas.parseGearId(p.id)
				rarity = Formulas.parseRarity(p.rarity)
				local rawDefId = p.defId
				if typeof(rawDefId) == "string" and #rawDefId > 0 and #rawDefId <= MAX_DEF_ID_LENGTH then
					defId = rawDefId
				end
			end
			if id ~= nil and rarity ~= nil and defId ~= nil and byId[id] == nil then
				local piece: Types.OwnedGear = { id = id, defId = defId, rarity = rarity }
				table.insert(profile.gear, piece)
				byId[id] = piece
				maxId = math.max(maxId, id)
			else
				dropped += 1
			end
		end
	end
	if dropped > 0 then
		warn(`[Save] {dropped} peça(s) de equipamento inválida(s) descartada(s) ao carregar`)
	end
	profile.nextGearId = math.max(Formulas.parseGearId(data.nextGearId) or 1, maxId + 1)

	-- Slots de cada personagem, na ordem fixa dos slots. Só fica a referência válida: peça existente e do catálogo,
	-- do slot certo, da classe certa (armas) e ainda não usada por outro personagem (o primeiro fica com ela).
	local claimed: { [number]: boolean } = {}
	for index, character in profile.characters do
		local rawCharacter = rawCharacters[index]
		local rawEquipped: { [string]: unknown } = {}
		if typeof(rawCharacter) == "table" then
			local equippedValue = (rawCharacter :: { [string]: unknown }).equipped
			if typeof(equippedValue) == "table" then
				rawEquipped = equippedValue :: { [string]: unknown }
			end
		end
		for _, slot: Types.EquipSlot in Gear.slots do
			local id = Formulas.parseGearId(rawEquipped[slot])
			local piece = if id ~= nil then byId[id] else nil
			local def = if piece then Gear.byId[piece.defId] else nil
			if
				id ~= nil
				and def ~= nil
				and not claimed[id]
				and def.slot == slot
				and (def.classId == nil or def.classId == character.classId)
			then
				character.equipped[slot] = id
				claimed[id] = true
			end
		end
	end

	-- Arma nunca vazia. Dados corrompidos: equipa a primeira arma da classe que estiver no baú. Sem nenhuma (ou na
	-- migração da v3, sem peças), dá a arma inicial da classe.
	for _, character in profile.characters do
		if character.equipped[WEAPON_SLOT] == nil then
			for _, piece in profile.gear do
				local def = Gear.byId[piece.defId]
				if
					def ~= nil
					and not claimed[piece.id]
					and def.slot == WEAPON_SLOT
					and def.classId == character.classId
				then
					character.equipped[WEAPON_SLOT] = piece.id
					claimed[piece.id] = true
					break
				end
			end
		end
		if PlayerSchema.grantStartingGear(profile, character) then
			-- A arma recém-dada é deste personagem: o próximo não pode "achá-la" no baú.
			claimed[character.equipped[WEAPON_SLOT] :: number] = true
		end
	end
end

-- Valida e MIGRA o que veio do DataStore para a versão atual. Nunca falha: campos ausentes ou inválidos recebem o
-- valor padrão. `raw` nil = jogador novo.
function PlayerSchema.reconcile(raw: unknown): Profile
	if typeof(raw) ~= "table" then
		return PlayerSchema.newProfile()
	end
	local data = raw :: { [string]: unknown }
	local profile = baseProfile()

	local rawCharacters: { unknown } = {}
	if typeof(data.characters) == "table" then
		rawCharacters = data.characters :: { unknown }
	end
	local list: { Character } = {}
	local listRaw: { unknown } = {} -- personagem cru de cada item de `list` (mesmo índice), para ler o equipamento
	for _, rawCharacter in rawCharacters do
		table.insert(list, reconcileCharacter(rawCharacter))
		table.insert(listRaw, rawCharacter)
	end
	if #list > 0 then
		profile.characters = list
	end
	profile.activeSlot = wholeNumber(data.activeSlot, 1, #profile.characters, 1)

	-- Gold da conta. Migração v1 -> v2: o Gold estava em cada personagem; soma tudo no cofre da conta.
	local version = wholeNumber(data.schemaVersion, 0, math.huge, 1)
	if version < 2 then
		local total = 0
		for _, rawCharacter in rawCharacters do
			if typeof(rawCharacter) == "table" then
				total += wholeNumber((rawCharacter :: { [string]: unknown }).gold, 0, math.huge, 0)
			end
		end
		profile.gold = total
	else
		profile.gold = wholeNumber(data.gold, 0, math.huge, 0)
	end

	-- Inventário (v3+). Só itens que existem na loja, com a quantidade limitada ao máximo permitido.
	if typeof(data.inventory) == "table" then
		local rawInventory = data.inventory :: { [string]: unknown }
		for itemId, def in Shop.items do
			local count = wholeNumber(rawInventory[itemId], 0, def.maxOwned, 0)
			if count > 0 then
				profile.inventory[itemId] = count
			end
		end
	end

	-- Equipamento (v4+). Na migração da v3 (sem `gear`), cada personagem só recebe a arma inicial.
	reconcileGear(data, profile, listRaw)

	local session = data.session
	if typeof(session) == "table" then
		local s = session :: { [string]: unknown }
		if typeof(s.id) == "string" and typeof(s.time) == "number" then
			profile.session = { id = s.id, time = s.time }
		end
	end
	return profile
end

-- Cópia profunda (o que vai para o DataStore não pode ser alterado depois por quem continua jogando).
function PlayerSchema.deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = PlayerSchema.deepCopy(item)
	end
	return copy :: any
end

return table.freeze(PlayerSchema)
