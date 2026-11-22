--!strict
-- Forja do lobby (GDD > Equipamentos > Forja). Hoje: fortalecimento (+1 a +10). Depois: gemas (incrustar, fundir,
-- extrair), fabricação e encantamento.
-- O cliente só PEDE (EnhanceGear). Aqui: tipo do id, anti-spam e distância da bigorna; a regra (peça da conta,
-- nível máximo, Gold, sorteio no servidor) fica no GearService. A resposta volta pelo Remote ForgeResult.
-- O Gold gasto e o novo nível são salvos alguns segundos depois da última tentativa (um save por rajada de cliques,
-- não um por clique: o DataStore limita gravações na mesma chave).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GearService = require(script.Parent.GearService)
local LobbyService = require(script.Parent.LobbyService)

local REQUEST_COOLDOWN = 0.3 -- s entre tentativas do mesmo jogador (anti-spam; técnico)
local SAVE_DELAY = 6 -- s depois da última tentativa até o save (técnico: limite de gravação do DataStore)

local ForgeService = {}

local lastRequestAt: { [Player]: number } = {}
local saveScheduled: { [Player]: boolean } = {}

local function reply(player: Player, outcome: GearService.EnhanceOutcome, message: string)
	local payload: Remotes.ForgeResultPayload =
		{ ok = outcome == "Success", rolled = outcome ~= "Refused", message = message }
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

local function onEnhanceGear(player: Player, rawId: unknown)
	local id = Formulas.parseGearId(rawId)
	if id == nil then
		return
	end
	local t = os.clock()
	if t - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[player] = t
	if not LobbyService.isNearForge(player) then
		reply(player, "Refused", "Chegue mais perto da forja")
		return
	end
	local outcome: GearService.EnhanceOutcome, message = GearService.tryEnhance(player, id)
	reply(player, outcome, message)
	if outcome ~= "Refused" then
		scheduleSave(player)
	end
end

function ForgeService.init()
	Remotes.get("EnhanceGear").OnServerEvent:Connect(onEnhanceGear)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		saveScheduled[player] = nil
	end)
end

function ForgeService.start() end

return ForgeService
