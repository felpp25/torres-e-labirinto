--!strict
-- Acesso às torres (GDD > Torre 2 e escolha de torre > Acesso às torres; números em Balance/Towers):
-- - para entrar: nível mínimo da torre + o ACESSO da conta (vitalício, vale para todos os personagens);
-- - o acesso vem da CHAVE, sorteada no chefão da torre anterior (por jogador com direito, com a Sorte; quem já tem o
--   acesso não sorteia), ou da MISSÃO (a definir com o designer);
-- - liberar salva logo e avisa o jogador (Remote TowerUnlocked).
-- O acesso de cada torre também vai para um Attribute do jogador (Keys.towerAccessAttr), para a tela e os testes.

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Formulas = require(Shared.Formulas)
local Towers = require(Shared.Balance.Towers)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

export type UnlockSource = "Key" | "Quest" | "Dev"

local TowerService = {}

local rng = Random.new()
local forcedKey: { [Player]: boolean } = {} -- SÓ TESTES: a próxima chave sorteada para o jogador cai com certeza

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
	local previous = Towers.byId[towerId - 1]
	local keySource = if previous then `cai do chefão da {previous.displayName}` else "cai do chefão"
	if needsLevel and needsAccess then
		return false, `Precisa do nível {def.minLevel} e da {keyName} ({keySource}) ou da missão`
	elseif needsLevel then
		return false, `Precisa do nível {def.minLevel} (você está no {level})`
	elseif needsAccess then
		return false, `Precisa da {keyName} ({keySource}) ou da missão`
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

-- Chefão da torre `towerId` derrotado: cada jogador com direito, sem o acesso à próxima torre, sorteia a chave dela.
-- `luck` = maior Sorte entre os que têm direito, perto do chefão (regra dos achados raros).
function TowerService.rollKeys(towerId: number, players: { Player }, luck: number)
	local nextDef = Towers.byId[towerId + 1]
	if not nextDef or not nextDef.requiresAccess then
		return
	end
	local chance = Formulas.luckChance(nextDef.keyChance, luck)
	for _, player in players do
		if player.Parent and not TowerService.hasAccess(player, nextDef.id) then
			local forced = forcedKey[player] == true
			forcedKey[player] = nil
			if forced or rng:NextNumber() < chance then
				TowerService.unlock(player, nextDef.id, "Key")
			end
		end
	end
end

-- SÓ TESTES (DevService): a próxima chave sorteada para o jogador cai com certeza.
function TowerService.debugForceNextKey(player: Player)
	forcedKey[player] = true
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
	Players.PlayerRemoving:Connect(function(player: Player)
		forcedKey[player] = nil
	end)
end

function TowerService.start() end

return TowerService
