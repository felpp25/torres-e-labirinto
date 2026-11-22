--!strict
-- Forja do lobby (GDD > Equipamentos > Forja): fortalecimento (+1 a +10), transferir o fortalecimento entre duas
-- peças e gemas (incrustar, extrair, fundir). Depois: fabricação e encantamento.
-- O cliente só PEDE (EnhanceGear, TransferEnhance, SocketGem, ExtractGem, FuseGems). Aqui: tipos dos argumentos,
-- anti-spam e
-- distância da bigorna; a regra (peça da conta, nível máximo, Gold, sorteio, baú, Removedor) fica no GearService
-- (fortalecimento) e no GemService (gemas). A resposta volta pelo Remote ForgeResult.
-- O que mudou é salvo alguns segundos depois do último pedido que deu certo (um save por rajada de cliques, não um
-- por clique: o DataStore limita gravações na mesma chave).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GearService = require(script.Parent.GearService)
local GemService = require(script.Parent.GemService)
local LobbyService = require(script.Parent.LobbyService)

local REQUEST_COOLDOWN = 0.3 -- s entre pedidos do mesmo jogador (anti-spam; técnico)
local SAVE_DELAY = 6 -- s depois do último pedido até o save (técnico: limite de gravação do DataStore)

local ForgeService = {}

local lastRequestAt: { [Player]: number } = {}
local saveScheduled: { [Player]: boolean } = {}

local function reply(player: Player, ok: boolean, rolled: boolean, message: string)
	local payload: Remotes.ForgeResultPayload = { ok = ok, rolled = rolled, message = message }
	Remotes.get("ForgeResult"):FireClient(player, payload)
end

local function scheduleSave(player: Player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(SAVE_DELAY, function()
		saveScheduled[player] = nil
		if player.Parent then -- quem saiu já foi salvo pelo DataService ao sair
			DataService.requestSave(player)
		end
	end)
end

-- Anti-spam e distância, comuns a todos os pedidos. Devolve se o pedido segue.
local function allowRequest(player: Player): boolean
	local t = os.clock()
	if t - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = t
	if not LobbyService.isNearForge(player) then
		reply(player, false, false, "Chegue mais perto da forja")
		return false
	end
	return true
end

-- Resposta de uma operação de gema (sem sorteio); salva depois se deu certo.
local function finishGem(player: Player, ok: boolean, message: string)
	reply(player, ok, false, message)
	if ok then
		scheduleSave(player)
	end
end

local function onEnhanceGear(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil or not allowRequest(player) then
		return
	end
	local outcome: GearService.EnhanceOutcome, message = GearService.tryEnhance(player, id)
	reply(player, outcome == "Success", outcome ~= "Refused", message)
	if outcome ~= "Refused" then
		scheduleSave(player)
	end
end

local function onSocketGem(player: Player, rawId: unknown, rawAttribute: unknown, rawLevel: unknown)
	local id = Formulas.parseGearId(rawId)
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(rawAttribute)
	local level = Formulas.parseGemLevel(rawLevel)
	if id == nil or attribute == nil or level == nil or not allowRequest(player) then
		return
	end
	local ok, message = GemService.trySocket(player, id, attribute, level)
	finishGem(player, ok, message)
end

local function onExtractGem(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil or not allowRequest(player) then
		return
	end
	local ok, message = GemService.tryExtract(player, id)
	finishGem(player, ok, message)
end

local function onFuseGems(player: Player, rawAttribute: unknown, rawLevel: unknown)
	local attribute: Types.GemAttribute? = Formulas.parseGemAttribute(rawAttribute)
	local level = Formulas.parseGemLevel(rawLevel)
	if attribute == nil or level == nil or not allowRequest(player) then
		return
	end
	local ok, message = GemService.tryFuse(player, attribute, level)
	finishGem(player, ok, message)
end

-- Troca o fortalecimento de duas peças (sem sorteio: responde e salva como as operações de gema).
local function onTransferEnhance(player: Player, rawFrom: unknown, rawTo: unknown)
	local fromId = Formulas.parseGearId(rawFrom)
	local toId = Formulas.parseGearId(rawTo)
	if fromId == nil or toId == nil or not allowRequest(player) then
		return
	end
	local ok, message = GearService.tryTransfer(player, fromId, toId)
	finishGem(player, ok, message)
end

function ForgeService.init()
	Remotes.get("EnhanceGear").OnServerEvent:Connect(onEnhanceGear)
	Remotes.get("TransferEnhance").OnServerEvent:Connect(onTransferEnhance)
	Remotes.get("SocketGem").OnServerEvent:Connect(onSocketGem)
	Remotes.get("ExtractGem").OnServerEvent:Connect(onExtractGem)
	Remotes.get("FuseGems").OnServerEvent:Connect(onFuseGems)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		saveScheduled[player] = nil
	end)
end

function ForgeService.start() end

return ForgeService
