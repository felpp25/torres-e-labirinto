--!strict
-- Salvamento do progresso (DataStore). Uma chave por jogador: User_<UserId> (formato em Data/PlayerSchema).
--
-- - Carrega ao entrar, com TRAVA DE SESSÃO: o servidor marca os dados como "em uso". Se outro servidor ainda
--   estiver com eles (o jogador pulou de servidor antes do anterior salvar), espera a trava ser liberada em vez
--   de carregar dados velhos. Trava abandonada (servidor caiu) expira depois de LOCK_EXPIRE segundos.
-- - Salva: ao sair, ao fechar o servidor (BindToClose), no autosave e quando pedido (ex.: torre concluída).
--   Saves do mesmo jogador rodam em fila, um por vez, na ordem (a doc pede ordem por chave).
-- - Toda leitura/gravação usa UpdateAsync dentro de pcall, com novas tentativas e espera crescente + jitter.
-- - Se não der para carregar (erro ou trava presa), o jogador joga SEM salvar (aviso no HUD) e nunca
--   sobrescreve os dados reais.
-- - No Studio usa outro DataStore ("..._Studio"): testes não tocam no progresso dos jogadores de verdade.
--   (No Studio é preciso ligar: Configurações do jogo > Segurança > "Enable Studio Access to API Services".)

local DataStoreService: DataStoreService = game:GetService("DataStoreService")
local HttpService: HttpService = game:GetService("HttpService")
local Players: Players = game:GetService("Players")
local RunService: RunService = game:GetService("RunService")

local Keys = require(game:GetService("ReplicatedStorage").Shared.Keys)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)

local STORE_NAME = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local AUTOSAVE_INTERVAL = 120 -- s (cada jogador começa num ponto aleatório do ciclo, para espalhar as gravações)
local LOCK_EXPIRE = 360 -- s: trava mais velha que isto é considerada abandonada (o autosave a renova)
local MAX_ATTEMPTS = 5 -- tentativas por leitura/gravação
local LOCKED_RETRIES = 6 -- quantas vezes esperar uma trava ativa de outro servidor ao entrar
local LOCKED_RETRY_DELAY = 5 -- s entre essas esperas
local CLOSE_TIMEOUT = 25 -- s: BindToClose tem 30 s no total

-- Identifica ESTE servidor na trava (no Studio o JobId é vazio, então geramos um próprio).
local SESSION_ID = HttpService:GenerateGUID(false)

export type LoadStatus = "ok" | "locked" | "error"

type Entry = {
	key: string,
	profile: PlayerSchema.Profile,
	canSave: boolean, -- false = jogando sem salvar
	saving: boolean,
	pendingSave: boolean,
	pendingRelease: boolean,
	released: boolean,
	nextAutosaveAt: number,
}

local DataService = {}

local entries: { [Player]: Entry } = {}
local rng = Random.new()
local cachedStore: DataStore? = nil

local function getStore(): DataStore
	if not cachedStore then
		cachedStore = DataStoreService:GetDataStore(STORE_NAME)
	end
	return cachedStore :: DataStore
end

local function keyFor(userId: number): string
	return `User_{userId}`
end

-- Erros que não adianta repetir (ex.: 403 = acesso do Studio à API desligado).
local function isPermanentError(err: unknown): boolean
	local message = tostring(err)
	return string.find(message, "403", 1, true) ~= nil or string.find(message, "not allowed", 1, true) ~= nil
end

-- Roda `request` com até MAX_ATTEMPTS tentativas, espera crescente (1, 2, 4, 8 s) + jitter.
local function withRetries(request: () -> unknown): (boolean, string?)
	local delay = 1
	local lastError = "?"
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(request)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		if isPermanentError(err) or attempt == MAX_ATTEMPTS then
			break
		end
		task.wait(delay + rng:NextNumber() * 0.5)
		delay = math.min(delay * 2, 8)
	end
	return false, lastError
end

-- Tenta pegar os dados da chave com a trava de sessão.
-- "ok" = carregado (e travado para este servidor); "locked" = outro servidor está com a trava; "error" = falhou.
function DataService.loadKey(key: string): (LoadStatus, PlayerSchema.Profile?, string?)
	local now = os.time()
	local status: LoadStatus = "error"
	local loaded: PlayerSchema.Profile? = nil
	local ok, err = withRetries(function(): unknown
		return getStore():UpdateAsync(key, function(current: unknown): unknown
			-- (O callback não pode esperar/yield e pode rodar mais de uma vez: só calcula e devolve.)
			local profile = PlayerSchema.reconcile(current)
			local session = profile.session
			if session and session.id ~= SESSION_ID and now - session.time < LOCK_EXPIRE then
				status = "locked"
				loaded = nil
				return nil -- nil cancela a gravação: não mexe nos dados do outro servidor
			end
			profile.session = { id = SESSION_ID, time = now }
			status = "ok"
			loaded = profile
			return PlayerSchema.deepCopy(profile)
		end)
	end)
	if not ok then
		return "error", nil, err
	end
	return status, loaded, nil
end

-- Grava o perfil. `release` = liberar a trava (saída do jogador / servidor fechando).
-- Se outro servidor tiver tomado a trava (a nossa expirou), NÃO sobrescreve: devolve false.
function DataService.saveKey(key: string, profile: PlayerSchema.Profile, release: boolean): (boolean, string?)
	local now = os.time()
	local snapshot = PlayerSchema.deepCopy(profile)
	local lostLock = false
	local ok, err = withRetries(function(): unknown
		return getStore():UpdateAsync(key, function(current: unknown): unknown
			if typeof(current) == "table" then
				local session = (current :: { [string]: any }).session
				if typeof(session) == "table" and session.id ~= SESSION_ID then
					lostLock = true
					return nil
				end
			end
			lostLock = false
			local data = PlayerSchema.deepCopy(snapshot)
			data.session = if release then nil else { id = SESSION_ID, time = now }
			return data
		end)
	end)
	if lostLock then
		return false, "outro servidor tomou a trava de sessão"
	end
	return ok, err
end

-- Fila de saves por jogador: nunca dois ao mesmo tempo para a mesma chave.
local function savePlayer(player: Player, release: boolean)
	local entry = entries[player]
	if not entry or not entry.canSave or entry.released then
		return
	end
	if entry.saving then
		entry.pendingSave = true
		entry.pendingRelease = entry.pendingRelease or release
		return
	end
	entry.saving = true
	local releaseNow = release
	while true do
		entry.pendingSave = false
		local ok, err = DataService.saveKey(entry.key, entry.profile, releaseNow)
		if ok then
			print(`[Save] {player.Name} salvo{if releaseNow then " (trava liberada)" else ""}`)
		else
			warn(`[Save] falha ao salvar {player.Name}: {err}`)
		end
		if releaseNow then
			entry.released = true
		end
		if entry.released or not entry.pendingSave then
			break
		end
		releaseNow = entry.pendingRelease
		entry.pendingRelease = false
	end
	entry.saving = false
end

-- Carrega o perfil do jogador (conta + personagens; espera, chame antes de ele nascer). Nunca falha: em último
-- caso devolve um perfil novo e marca o jogador como "jogando sem salvar".
-- Quem altera o perfil devolvido (ProgressionService) altera o que será salvo: é a mesma tabela.
function DataService.loadAsync(player: Player): PlayerSchema.Profile
	local key = keyFor(player.UserId)
	local reason = "?"
	for attempt = 1, LOCKED_RETRIES do
		local status, profile, err = DataService.loadKey(key)
		if status == "ok" and profile then
			entries[player] = {
				key = key,
				profile = profile,
				canSave = true,
				saving = false,
				pendingSave = false,
				pendingRelease = false,
				released = false,
				nextAutosaveAt = os.clock() + rng:NextNumber() * AUTOSAVE_INTERVAL,
			}
			player:SetAttribute(Keys.PlayerAttr.SaveStatus, "ok")
			local character = profile.characters[profile.activeSlot]
			print(`[Save] {player.Name} carregado: nível {character.level}, {profile.gold} Gold na conta`)
			if not player.Parent then
				task.spawn(savePlayer, player, true) -- saiu durante o carregamento: libera a trava
			end
			return profile
		elseif status == "locked" then
			reason = "dados em uso por outro servidor"
			print(`[Save] {player.Name}: {reason}; tentativa {attempt}/{LOCKED_RETRIES}`)
			task.wait(LOCKED_RETRY_DELAY)
		else
			reason = err or "?"
			break
		end
	end

	warn(`[Save] {player.Name} vai jogar SEM salvar ({reason})`)
	local profile = PlayerSchema.newProfile()
	entries[player] = {
		key = key,
		profile = profile,
		canSave = false,
		saving = false,
		pendingSave = false,
		pendingRelease = false,
		released = false,
		nextAutosaveAt = math.huge,
	}
	player:SetAttribute(Keys.PlayerAttr.SaveStatus, "offline")
	return profile
end

-- Pede um save agora (sem esperar). Ex.: torre concluída.
function DataService.requestSave(player: Player)
	task.spawn(savePlayer, player, false)
end

-- Salva agora e espera terminar (usado pelas ferramentas de teste).
function DataService.saveNow(player: Player): boolean
	savePlayer(player, false)
	local entry = entries[player]
	return entry ~= nil and entry.canSave
end

function DataService.getSessionId(): string
	return SESSION_ID
end

function DataService.getStoreName(): string
	return STORE_NAME
end

local function onPlayerRemoving(player: Player)
	-- Salva e libera a trava sem esperar mais nada antes (a doc avisa: esperar aqui deixa o jogador entrar em
	-- outro servidor antes do save).
	savePlayer(player, true)
	-- Se havia um save em andamento, o de liberação entrou na fila dele: espera terminar antes de apagar
	-- o registro (o BindToClose usa esta tabela para saber se ainda há save pendente).
	local entry = entries[player]
	local deadline = os.clock() + CLOSE_TIMEOUT
	while entry and entry.saving and os.clock() < deadline do
		task.wait(0.1)
	end
	entries[player] = nil
end

local function onClose()
	for _, player in Players:GetPlayers() do
		task.spawn(savePlayer, player, true)
	end
	local deadline = os.clock() + CLOSE_TIMEOUT
	while os.clock() < deadline do
		local busy = false
		for _, entry in entries do
			if entry.canSave and (entry.saving or not entry.released) then
				busy = true
			end
		end
		if not busy then
			break
		end
		task.wait(0.2)
	end
end

function DataService.init()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onClose)
	print(`[Save] DataStore "{STORE_NAME}" (sessão {string.sub(SESSION_ID, 1, 8)})`)
end

-- Autosave: cada jogador no seu próprio ritmo (espalhado), renovando a trava de sessão.
function DataService.start()
	while true do
		task.wait(5)
		local now = os.clock()
		for player, entry in entries do
			if entry.canSave and not entry.released and now >= entry.nextAutosaveAt then
				entry.nextAutosaveAt = now + AUTOSAVE_INTERVAL
				task.spawn(savePlayer, player, false)
			end
		end
	end
end

return DataService
