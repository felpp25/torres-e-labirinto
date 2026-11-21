--!strict
-- Ferramentas de desenvolvedor para TESTES. Só existem dentro do Roblox Studio (RunService:IsStudio()):
-- no jogo publicado este serviço não faz nada, então não abre brecha para trapaça.
--
-- Por que existe: testes pelo MCP (`execute_luau`) rodam numa cópia dos módulos, sem acesso ao estado real do
-- jogo. Este serviço expõe um BindableFunction em ServerStorage (que os clientes nunca enxergam) para o teste
-- chamar os sistemas REAIS. Uso no datamodel Server:
--   local dev = game.ServerStorage.DevTools.Invoke
--   dev:Invoke("SetAttributes", player, { Defense = 100 })
--   local dano = dev:Invoke("DamagePlayer", player, 13.8) -- dano efetivamente aplicado (0 se invencível)

--   dev:Invoke("SaveNow", player)               -- salva agora (espera terminar)
--   dev:Invoke("ReadStored", "User_123")        -- valor cru no DataStore (JSON) para conferir o que foi salvo
--   Testes de trava (só chaves "Test_..."): "WriteStored"(key, valor), "LoadKey"(key), "SaveKey"(key), "SessionId"

local DataStoreService: DataStoreService = game:GetService("DataStoreService")
local HttpService: HttpService = game:GetService("HttpService")
local RunService: RunService = game:GetService("RunService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local function store(): DataStore
	return DataStoreService:GetDataStore(DataService.getStoreName())
end

local function assertTestKey(key: string)
	assert(string.sub(key, 1, 5) == "Test_", "DevTools: escrita só em chaves de teste (Test_...)")
end

local DevService = {}

type Command = (...any) -> any

local COMMANDS: { [string]: Command } = {
	SetAttributes = function(player: Player, values: { [string]: number }): boolean
		ProgressionService.debugSetAttributes(player, values)
		return true
	end,

	-- Passa pelo MESMO caminho de dano que os mobs e o boss usam (Defesa, invencibilidade da esquiva).
	DamagePlayer = function(player: Player, rawDamage: number): number
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return -1
		end
		local before = humanoid.Health
		CombatService.damagePlayer(player, rawDamage)
		return before - humanoid.Health
	end,

	SaveNow = function(player: Player): boolean
		return DataService.saveNow(player)
	end,

	ReadStored = function(key: string): string
		local value = store():GetAsync(key)
		return if value == nil then "nil" else HttpService:JSONEncode(value)
	end,

	WriteStored = function(key: string, value: any): boolean
		assertTestKey(key)
		store():SetAsync(key, value)
		return true
	end,

	LoadKey = function(key: string): string
		assertTestKey(key)
		local status = DataService.loadKey(key)
		return status
	end,

	SaveKey = function(key: string): string
		assertTestKey(key)
		local ok, err = DataService.saveKey(key, PlayerSchema.newProfile(), false)
		return if ok then "ok" else `falhou: {err}`
	end,

	SessionId = function(): string
		return DataService.getSessionId()
	end,
}

function DevService.init()
	if not RunService:IsStudio() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevTools"
	local invoke = Instance.new("BindableFunction")
	invoke.Name = "Invoke"
	invoke.OnInvoke = function(command: string, ...: any): any
		local handler = COMMANDS[command]
		assert(handler, `DevTools: comando desconhecido '{command}'`)
		return handler(...)
	end
	invoke.Parent = folder
	folder.Parent = ServerStorage
	print("[Dev] ferramentas de teste ativas (só no Studio)")
end

function DevService.start() end

return DevService
