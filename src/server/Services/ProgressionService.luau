--!strict
-- Progressão do jogador: classe, atributos, nível, XP e Gold.
-- - XP sobe de nível (curva em Formulas.xpToNextLevel, teto em Balance/Progression.maxLevel);
-- - cada nível dá 3 pontos LIVRES; o jogador escolhe onde colocar (GDD > Atributos):
--   AllocateAttribute (1 ponto num atributo) ou AllocateRecommended (todos nos atributos de scaling da classe);
--   o ponto colocado é definitivo (sem reset, por enquanto);
-- - aplica no personagem o que vem da classe e dos atributos (vida máxima, velocidade).
-- Tudo só muda aqui; o cliente só PEDE (validado abaixo) e recebe por Attributes (HUD) e pelo Remote LevelUp.
-- Persistência: os dados de cada jogador SÃO o personagem ativo carregado pelo DataService (mesma tabela);
-- o que muda aqui é o que o DataService grava. O jogador só nasce depois do carregamento (LifeService espera).

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Formulas = require(Shared.Formulas)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Classes = require(Shared.Balance.Classes)
local Combat = require(Shared.Balance.Combat)
local Progression = require(Shared.Balance.Progression)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local DataService = require(script.Parent.DataService)

type PlayerData = PlayerSchema.Character

local LOAD_WAIT_TIMEOUT = 60 -- s: o DataService pode esperar uma trava de outro servidor (~30 s) antes de desistir

local ProgressionService = {}

local profiles: { [Player]: PlayerSchema.Profile } = {} -- conta inteira (Gold global + personagens)
local playerData: { [Player]: PlayerData } = {} -- personagem ativo (dentro do perfil)
local loaded: { [Player]: boolean } = {}

-- Ainda não carregou (não deveria acontecer: o jogador só nasce depois): valores temporários, nunca salvos;
-- quando o carregamento terminar, são substituídos pelo perfil salvo.
local function getProfile(player: Player): PlayerSchema.Profile
	local profile = profiles[player]
	if not profile then
		profile = PlayerSchema.newProfile()
		profiles[player] = profile
	end
	return profile
end

local function getData(player: Player): PlayerData
	local data = playerData[player]
	if not data then
		local profile = getProfile(player)
		data = profile.characters[profile.activeSlot]
		playerData[player] = data
	end
	return data
end

-- Espera os dados do jogador carregarem (o LifeService chama antes de fazê-lo nascer).
function ProgressionService.waitUntilLoaded(player: Player): boolean
	local deadline = os.clock() + LOAD_WAIT_TIMEOUT
	while not loaded[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return loaded[player] == true
end

local function replicate(player: Player, data: PlayerData)
	player:SetAttribute(Keys.PlayerAttr.Level, data.level)
	player:SetAttribute(Keys.PlayerAttr.XP, data.xp)
	local toNext = Formulas.xpToNextLevel(data.level)
	player:SetAttribute(Keys.PlayerAttr.XPToNext, if toNext == math.huge then 0 else toNext)
	player:SetAttribute(Keys.PlayerAttr.Gold, getProfile(player).gold) -- Gold da CONTA
	player:SetAttribute(Keys.PlayerAttr.UnspentPoints, data.unspentPoints)
	for _, name in Formulas.attributeNames() do
		player:SetAttribute(Keys.statAttr(name), data.attributes[name])
	end
end

function ProgressionService.getClass(player: Player): Types.ClassDef
	local classDef = Classes.byId[getData(player).classId]
	assert(classDef, "classe desconhecida")
	return classDef
end

-- Devolve uma cópia: quem chama não pode alterar os atributos por fora.
function ProgressionService.getAttributes(player: Player): Types.Attributes
	return table.clone(getData(player).attributes)
end

function ProgressionService.getLevel(player: Player): number
	return getData(player).level
end

-- Vida máxima pela classe + Vitalidade. Quando ela aumenta (subiu de nível), a diferença entra na vida atual:
-- não é cura total (vida cheia só no checkpoint), mas o ponto novo não fica "vazio".
local function applyHealth(player: Player, fillToMax: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local data = getData(player)
	local newMax = Formulas.maxHealth(ProgressionService.getClass(player), data.attributes)
	local gained = math.max(newMax - humanoid.MaxHealth, 0)
	humanoid.MaxHealth = newMax
	humanoid.Health = if fillToMax then newMax else math.min(humanoid.Health + gained, newMax)
end

function ProgressionService.addXp(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = getData(player)
	local newLevel, newXp, levelsGained = Formulas.addXp(data.level, data.xp, amount)
	data.level = newLevel
	data.xp = newXp

	if levelsGained > 0 then
		local points = levelsGained * Progression.pointsPerLevel
		data.unspentPoints += points
		local payload: Remotes.LevelUpPayload = { level = newLevel, points = points }
		Remotes.get("LevelUp"):FireClient(player, payload)
	end
	replicate(player, data)
end

-- Depois de mudar atributos: replica e ajusta a vida máxima (o ganho de Vitalidade entra na vida atual).
-- Mana e stamina máximas são recalculadas pelo CombatService a cada atualização de recursos.
local function afterAttributesChanged(player: Player, data: PlayerData)
	applyHealth(player, false)
	replicate(player, data)
end

-- SÓ PARA TESTES no Studio (chamado pelo DevService, que não existe fora do Studio): define atributos direto.
-- `values` = { Defense = 100, ... }; nomes inválidos são ignorados; atributos não citados ficam como estão.
function ProgressionService.debugSetAttributes(player: Player, values: { [string]: number })
	local data = getData(player)
	for key, value in values do
		local name = Formulas.parseAttributeName(key)
		if name and typeof(value) == "number" then
			data.attributes[name] = math.max(math.floor(value), 0)
		end
	end
	afterAttributesChanged(player, data)
end

-- Pedido do cliente: 1 ponto livre no atributo `attributeName`. VALIDADO: tipo, nome e se há ponto livre.
local function onAllocateAttribute(player: Player, attributeName: unknown)
	local name = Formulas.parseAttributeName(attributeName)
	if not name then
		return
	end
	local data = getData(player)
	if data.unspentPoints <= 0 then
		return
	end
	data.unspentPoints -= 1
	data.attributes[name] += 1
	afterAttributesChanged(player, data)
end

-- Pedido do cliente: todos os pontos livres no "recomendado" (atributos de scaling da classe, equilibrados).
local function onAllocateRecommended(player: Player)
	local data = getData(player)
	if data.unspentPoints <= 0 then
		return
	end
	data.attributes =
		Formulas.distributeRecommended(data.attributes, data.unspentPoints, ProgressionService.getClass(player))
	data.unspentPoints = 0
	afterAttributesChanged(player, data)
end

-- Gold é da CONTA (compartilhado por todos os personagens).
function ProgressionService.addGold(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	getProfile(player).gold += math.floor(amount)
	replicate(player, getData(player))
end

function ProgressionService.getGold(player: Player): number
	return getProfile(player).gold
end

-- Vida cheia (checkpoint, M6).
function ProgressionService.restoreHealth(player: Player)
	applyHealth(player, true)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.WalkSpeed = ProgressionService.getClass(player).walkSpeed
	applyHealth(player, true)

	if Combat.disableNaturalHealthRegen then
		-- O Roblox coloca um Script "Health" em todo personagem que regenera vida aos poucos.
		local healthScript = character:WaitForChild("Health", 5)
		if healthScript then
			healthScript:Destroy()
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	-- Carrega o perfil salvo (espera o DataStore e a trava de sessão).
	local profile = DataService.loadAsync(player)
	if not player.Parent then
		return -- saiu durante o carregamento
	end
	local data = profile.characters[profile.activeSlot]
	profiles[player] = profile
	playerData[player] = data
	loaded[player] = true
	replicate(player, data)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function ProgressionService.init()
	Remotes.get("AllocateAttribute").OnServerEvent:Connect(onAllocateAttribute)
	Remotes.get("AllocateRecommended").OnServerEvent:Connect(onAllocateRecommended)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		-- (O DataService guarda a sua própria referência e salva na saída; aqui só limpa o mapa.)
		profiles[player] = nil
		playerData[player] = nil
		loaded[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function ProgressionService.start() end

return ProgressionService
