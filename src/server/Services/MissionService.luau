--!strict
-- Missões da conta (GDD > Missão e história; etapas em Balance/Missions; progresso no save, PlayerSchema.missions).
-- - Começa na 1ª vitória da torre `startTower` (só se a conta ainda não tem o acesso à torre da recompensa).
-- - Uma etapa por vez, em ordem; o contador zera a cada etapa. Etapas que já estão cumpridas ao começar concluem na
--   hora (ex.: "Enhance" com uma peça +3 no baú; "Chapter" com o capítulo já ouvido).
-- - Quem conta (decisões do designer): vitórias = quem tem direito ao prêmio do chefão (RunSessionService); mobs =
--   quem recebe o XP do mob (EnemyService), só dentro de uma run da torre da etapa; venda e fortalecimento = a conta.
-- - Fim: a última etapa é uma conversa (ex.: Ariadne forja a Chave de Cristal) e libera a torre (TowerService).
-- O progresso vai para Attributes do jogador (Keys.missionAttr): o HUD e os "!" dos NPCs leem dali.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Missions = require(Shared.Balance.Missions)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local RunRegistry = require(script.Parent.Parent.Runs.RunRegistry)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local GearService = require(script.Parent.GearService)
local TowerService = require(script.Parent.TowerService)
local EnemyService = require(script.Parent.EnemyService)
local RunSessionService = require(script.Parent.RunSessionService)
local StoryService = require(script.Parent.StoryService)

local MissionService = {}

function MissionService.publish(player: Player)
	local profile = ProgressionService.getLoadedProfile(player)
	for _, def in Missions.list do
		local progress = if profile then profile.missions[def.id] else nil
		player:SetAttribute(Keys.missionAttr(def.id, "Step"), if progress then progress.step else nil)
		player:SetAttribute(Keys.missionAttr(def.id, "Count"), if progress then progress.count else nil)
		player:SetAttribute(Keys.missionAttr(def.id, "Done"), if progress then progress.done else nil)
	end
end

local function bestEnhance(profile: PlayerSchema.Profile): number
	local best = 0
	for _, piece in profile.gear do
		if PlayerSchema.defOf(piece) ~= nil then
			best = math.max(best, piece.enhance)
		end
	end
	return best
end

local function currentStep(def: Missions.MissionDef, progress: PlayerSchema.MissionProgress): Missions.MissionStep?
	if progress.done then
		return nil
	end
	return def.steps[progress.step]
end

-- A etapa atual já está cumprida? (Ao começar uma etapa: o que o jogador já tem conta.)
local function alreadyMet(player: Player, profile: PlayerSchema.Profile, step: Missions.MissionStep): boolean
	if step.kind == "Enhance" then
		return bestEnhance(profile) >= step.target
	elseif step.kind == "Chapter" then
		return step.chapter ~= nil and StoryService.hasHeard(player, step.chapter)
	end
	return false
end

-- Conclui a etapa atual e entra na próxima (e nas seguintes, se já estiverem cumpridas). Na última, a recompensa.
local function completeStep(player: Player, profile: PlayerSchema.Profile, def: Missions.MissionDef)
	local progress = profile.missions[def.id]
	if not progress or progress.done then
		return
	end
	while true do
		progress.step += 1
		progress.count = 0
		local step = def.steps[progress.step]
		if not step then
			progress.done = true
			progress.step = #def.steps
			print(`[Missão] {player.Name} concluiu "{def.displayName}"`)
			TowerService.unlock(player, def.rewardTower, "Quest")
			break
		end
		if step.kind == "Enhance" then
			progress.count = math.min(bestEnhance(profile), step.target)
		end
		if not alreadyMet(player, profile, step) then
			print(`[Missão] {player.Name}: "{def.displayName}" etapa {progress.step} ({step.objective})`)
			break
		end
	end
	MissionService.publish(player)
	DataService.requestSave(player)
end

-- Soma `amount` nas etapas atuais do tipo `kind` que aceitam esta torre (nil = qualquer). Conclui ao chegar no alvo.
local function bump(player: Player, kind: Missions.StepKind, towerId: number?, amount: number)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return
	end
	for _, def in Missions.list do
		local progress = profile.missions[def.id]
		local step = if progress then currentStep(def, progress) else nil
		if progress and step and step.kind == kind and (step.towerId == nil or step.towerId == towerId) then
			progress.count = math.min(progress.count + amount, step.target)
			if progress.count >= step.target then
				completeStep(player, profile, def)
			else
				MissionService.publish(player)
			end
		end
	end
end

-- Começa as missões desta torre (1ª vitória), se a conta ainda não tem o acesso que elas dão.
local function startMissions(player: Player, profile: PlayerSchema.Profile, towerId: number)
	for _, def in Missions.list do
		if def.startTower == towerId and profile.missions[def.id] == nil then
			if not TowerService.hasAccess(player, def.rewardTower) then
				profile.missions[def.id] = { step = 1, count = 0, done = false }
				print(`[Missão] {player.Name} começou "{def.displayName}"`)
				local first = def.steps[1]
				if alreadyMet(player, profile, first) then
					completeStep(player, profile, def)
				else
					MissionService.publish(player)
					DataService.requestSave(player)
				end
			end
		end
	end
end

local function onVictory(player: Player, towerId: number, flawless: boolean)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return
	end
	bump(player, "BossWins", towerId, 1)
	bump(player, "Fragments", towerId, 1)
	if flawless then
		bump(player, "FlawlessWins", towerId, 1)
	end
	-- Depois de contar: a vitória que começa a missão não vale para as etapas dela (a 1ª é ouvir o Observador).
	startMissions(player, profile, towerId)
end

local function onMobKilled(player: Player, _: Types.MobDef, parent: Instance)
	local run = RunRegistry.fromInstance(parent)
	if run and RunRegistry.isMember(run, player) then
		bump(player, "MobKills", run.towerId, 1)
	end
end

local function onChapterHeard(player: Player, chapterId: number)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return
	end
	for _, def in Missions.list do
		local progress = profile.missions[def.id]
		local step = if progress then currentStep(def, progress) else nil
		if step and step.kind == "Chapter" and step.chapter == chapterId then
			completeStep(player, profile, def)
		end
	end
end

-- Equipamento mudou: a etapa "Enhance" acompanha a peça mais fortalecida da conta.
local function onGearChanged(player: Player)
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile then
		return
	end
	for _, def in Missions.list do
		local progress = profile.missions[def.id]
		local step = if progress then currentStep(def, progress) else nil
		if progress and step and step.kind == "Enhance" then
			local best = math.min(bestEnhance(profile), step.target)
			if best >= step.target then
				completeStep(player, profile, def)
			elseif best ~= progress.count then
				progress.count = best
				MissionService.publish(player)
			end
		end
	end
end

-- Fala de quando o NPC não tem etapa para o jogador.
local function idleDialogue(profile: PlayerSchema.Profile?, npcId: string): string?
	if npcId == "Ariadne" then
		local progress = if profile then profile.missions.CrystalPath else nil
		if not progress then
			return "Idle_Ariadne_Early"
		end
		return if progress.done then "Idle_Ariadne_Done" else "Idle_Ariadne_Busy"
	elseif npcId == "Tanu" then
		return "Idle_Tanu"
	elseif npcId == "Brokk" then
		return "Idle_Brokk"
	end
	return nil
end

-- Conversa com um NPC da missão (não o Observador): se a etapa atual é falar com ele, conclui e mostra a fala dela;
-- senão, a fala de "nada novo".
function MissionService.talk(player: Player, npcId: string): Remotes.NpcDialoguePayload?
	local profile = ProgressionService.getLoadedProfile(player)
	if profile then
		for _, def in Missions.list do
			local progress = profile.missions[def.id]
			local step = if progress then currentStep(def, progress) else nil
			if step and step.kind == "Talk" and step.npc == npcId and step.dialogue then
				local dialogue = step.dialogue
				-- Depois de quem chamou mandar a conversa: o aviso da recompensa (ex.: "TORRE 2 LIBERADA!") chega ao
				-- cliente com a conversa já aberta, e o HUD espera ela fechar (medido: chegava antes e cobria o NPC).
				task.defer(completeStep, player, profile, def)
				return { npc = npcId, dialogue = dialogue, canSkip = false, menu = false }
			end
		end
	end
	local idle = idleDialogue(profile, npcId)
	if not idle then
		return nil
	end
	return { npc = npcId, dialogue = idle, canSkip = true, menu = false }
end

-- SÓ TESTES (DevService): põe a missão numa etapa (0 = apaga o progresso; acima do total = concluída, sem recompensa).
function MissionService.debugSetStep(player: Player, missionId: string, step: number, count: number?): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	local def = Missions.byId[missionId]
	if not profile or not def then
		return false
	end
	if step <= 0 then
		profile.missions[missionId] = nil
	elseif step > #def.steps then
		profile.missions[missionId] = { step = #def.steps, count = 0, done = true }
	else
		profile.missions[missionId] = { step = step, count = count or 0, done = false }
	end
	MissionService.publish(player)
	return true
end

function MissionService.init()
	ProgressionService.setLoadedHandler(MissionService.publish)
	RunSessionService.addVictoryListener(onVictory)
	EnemyService.addKillListener(onMobKilled)
	StoryService.addHeardListener(onChapterHeard)
	GearService.addSoldListener(function(player: Player)
		bump(player, "SellGear", nil, 1)
	end)
	GearService.addChangedListener(onGearChanged)
end

function MissionService.start() end

return MissionService
