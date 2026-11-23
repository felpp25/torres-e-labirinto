--!strict
-- Acesso às torres (GDD > Torre 2 e escolha de torre > Acesso às torres; números em Balance/Towers):
-- - para entrar: nível mínimo da torre + o ACESSO da conta (vitalício, vale para todos os personagens);
-- - o acesso é a chave da torre, que sai só da MISSÃO (MissionService; decisão do designer: nunca cai do chefão);
-- - liberar salva logo e avisa o jogador (Remote TowerUnlocked).
-- O acesso de cada torre também vai para um Attribute do jogador (Keys.towerAccessAttr), para a tela e os testes.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Towers = require(Shared.Balance.Towers)
local Missions = require(Shared.Balance.Missions)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

export type UnlockSource = "Quest" | "Dev"

local TowerService = {}

-- Nome da missão que dá o acesso à torre (para a mensagem do portal trancado).
local function missionFor(towerId: number): Missions.MissionDef?
	for _, def in Missions.list do
		if def.rewardTower == towerId then
			return def
		end
	end
	return nil
end

function TowerService.publish(player: Player)
	local profile = ProgressionService.getLoadedProfile(player)
	for _, def in Towers.list do
		if def.requiresAccess then
			local unlocked = profile ~= nil and PlayerSchema.hasTowerAccess(profile, def.id)
			player:SetAttribute(Keys.towerAccessAttr(def.id), unlocked)
		end
	end
end

-- A conta tem o acesso à torre? (Torre sem exigência de acesso: sempre.)
function TowerService.hasAccess(player: Player, towerId: number): boolean
	local def = Towers.byId[towerId]
	if not def then
		return false
	end
	if not def.requiresAccess then
		return true
	end
	local profile = ProgressionService.getLoadedProfile(player)
	return profile ~= nil and PlayerSchema.hasTowerAccess(profile, towerId)
end

-- Pode entrar na torre? Quando não pode, devolve o motivo (texto para a tela).
function TowerService.canEnter(player: Player, towerId: number): (boolean, string?)
	local def = Towers.byId[towerId]
	if not def then
		return false, "Torre desconhecida"
	end
	if not ProgressionService.getLoadedProfile(player) then
		return false, "Aguarde, carregando seus dados"
	end
	local level = ProgressionService.getLevel(player)
	local needsLevel = level < def.minLevel
	local needsAccess = not TowerService.hasAccess(player, towerId)
	local keyName = def.keyName or "chave"
	local mission = missionFor(towerId)
	local keySource = if mission then `missão {mission.displayName}` else "missão"
	if needsLevel and needsAccess then
		return false, `Precisa do nível {def.minLevel} e da {keyName} ({keySource})`
	elseif needsLevel then
		return false, `Precisa do nível {def.minLevel} (você está no {level})`
	elseif needsAccess then
		return false, `Precisa da {keyName} ({keySource})`
	end
	return true, nil
end

-- Libera a torre para a conta do jogador. Devolve false se ela já estava liberada (ou o perfil não carregou).
function TowerService.unlock(player: Player, towerId: number, source: UnlockSource): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	local def = Towers.byId[towerId]
	if not profile or not def or not def.requiresAccess then
		return false
	end
	if not PlayerSchema.unlockTower(profile, towerId) then
		return false
	end
	TowerService.publish(player)
	DataService.requestSave(player) -- acesso vitalício: não espera o autosave
	local payload: Remotes.TowerUnlockedPayload = { towerId = towerId, source = source }
	Remotes.get("TowerUnlocked"):FireClient(player, payload)
	print(`[Torre] {player.Name}: {def.displayName} liberada para a conta ({source})`)
	return true
end

-- SÓ TESTES: tira o acesso da conta (para testar o portal trancado de novo).
function TowerService.debugLock(player: Player, towerId: number): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile or not PlayerSchema.lockTower(profile, towerId) then
		return false
	end
	TowerService.publish(player)
	return true
end

function TowerService.init()
	ProgressionService.setLoadedHandler(TowerService.publish)
end

function TowerService.start() end

return TowerService
