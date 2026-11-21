--!strict
-- Formato dos dados salvos de um jogador (DataStore). Funções puras: criar padrão, validar/migrar e copiar.
--
-- Uma chave por jogador (User_<UserId>) com o PERFIL da conta:
--   schemaVersion  versão do formato (para migrações)
--   gold           Gold da CONTA, compartilhado por todos os personagens
--   activeSlot     personagem em uso
--   characters     lista de personagens; cada um com classe, nível, XP, atributos e pontos livres
--   session        trava de sessão (qual servidor está com os dados e desde quando); nil = livre
-- Decisões do designer: vários personagens por conta; Gold GLOBAL da conta (trocar de personagem no lobby para
-- atender o grupo sem recomeçar a economia); run em andamento NÃO é salva.
--
-- Versões:
--   1  Gold dentro de cada personagem.
--   2  Gold na conta. Migração: soma o Gold de todos os personagens da v1.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Classes = require(Shared.Balance.Classes)
local Progression = require(Shared.Balance.Progression)

export type Character = {
	classId: string,
	level: number,
	xp: number, -- XP dentro do nível atual
	unspentPoints: number,
	attributes: Types.Attributes,
}

export type Session = {
	id: string, -- identificador do servidor que está com os dados
	time: number, -- os.time() da última renovação da trava
}

export type Profile = {
	schemaVersion: number,
	gold: number,
	activeSlot: number,
	characters: { Character },
	session: Session?,
}

local PlayerSchema = {}

PlayerSchema.VERSION = 2

function PlayerSchema.newCharacter(classId: string): Character
	return {
		classId = classId,
		level = 1,
		xp = 0,
		unspentPoints = 0,
		attributes = Formulas.emptyAttributes(),
	}
end

function PlayerSchema.newProfile(): Profile
	return {
		schemaVersion = PlayerSchema.VERSION,
		gold = 0,
		activeSlot = 1,
		characters = { PlayerSchema.newCharacter(Classes.defaultClassId) },
		session = nil,
	}
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

-- Valida e MIGRA o que veio do DataStore para a versão atual. Nunca falha: campos ausentes ou inválidos recebem o
-- valor padrão. `raw` nil = jogador novo.
function PlayerSchema.reconcile(raw: unknown): Profile
	if typeof(raw) ~= "table" then
		return PlayerSchema.newProfile()
	end
	local data = raw :: { [string]: unknown }
	local profile = PlayerSchema.newProfile()

	local rawCharacters: { unknown } = {}
	if typeof(data.characters) == "table" then
		rawCharacters = data.characters :: { unknown }
	end
	local list: { Character } = {}
	for _, rawCharacter in rawCharacters do
		table.insert(list, reconcileCharacter(rawCharacter))
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
