--!strict
-- Formato dos dados salvos de um jogador (DataStore). Funções puras: criar padrão, validar/migrar e copiar.
--
-- Uma chave por jogador (User_<UserId>) com o PERFIL da conta:
--   schemaVersion  versão do formato (para migrações futuras)
--   activeSlot     personagem em uso
--   characters     lista de personagens; cada um com classe, nível, XP, Gold PRÓPRIO, atributos e pontos livres
--   session        trava de sessão (qual servidor está com os dados e desde quando); nil = livre
-- Decisões do designer: vários personagens por conta; Gold por personagem; run em andamento NÃO é salva.

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
	gold: number,
	unspentPoints: number,
	attributes: Types.Attributes,
}

export type Session = {
	id: string, -- identificador do servidor que está com os dados
	time: number, -- os.time() da última renovação da trava
}

export type Profile = {
	schemaVersion: number,
	activeSlot: number,
	characters: { Character },
	session: Session?,
}

local PlayerSchema = {}

PlayerSchema.VERSION = 1

function PlayerSchema.newCharacter(classId: string): Character
	return {
		classId = classId,
		level = 1,
		xp = 0,
		gold = 0,
		unspentPoints = 0,
		attributes = Formulas.emptyAttributes(),
	}
end

function PlayerSchema.newProfile(): Profile
	return {
		schemaVersion = PlayerSchema.VERSION,
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
	character.gold = wholeNumber(data.gold, 0, math.huge, 0)
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

-- Valida (e migra, quando houver versões novas) o que veio do DataStore. Nunca falha: campos ausentes ou
-- inválidos recebem o valor padrão. `raw` nil = jogador novo.
function PlayerSchema.reconcile(raw: unknown): Profile
	if typeof(raw) ~= "table" then
		return PlayerSchema.newProfile()
	end
	local data = raw :: { [string]: unknown }
	-- (Migrações futuras: `if data.schemaVersion == 1 then ... end` antes de validar.)
	local profile = PlayerSchema.newProfile()
	local characters = data.characters
	if typeof(characters) == "table" then
		local list: { Character } = {}
		for _, rawCharacter in characters :: { unknown } do
			table.insert(list, reconcileCharacter(rawCharacter))
		end
		if #list > 0 then
			profile.characters = list
		end
	end
	profile.activeSlot = wholeNumber(data.activeSlot, 1, #profile.characters, 1)
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
