--!strict
-- As Crônicas do Observador (GDD > Missão e história; textos em Shared/Story/Chronicles):
-- - o capítulo N é liberado na 1ª vitória da Torre N, para quem tem direito ao prêmio do chefão;
-- - falar com o Observador: o capítulo liberado mais antigo ainda não ouvido (sem "Pular" na 1ª vez); sem nada novo,
--   o menu para rever os já liberados (o cliente toca sozinho, com "Pular");
-- - liberados e ouvidos ficam no save da conta e vão para Attributes do jogador ("1,2"): o "!" e o menu leem dali.
-- O capítulo conta como ouvido quando começa (o servidor não espera o cliente terminar de ler).

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Remotes = require(Shared.Remotes)
local Chronicles = require(Shared.Story.Chronicles)

local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local RunSessionService = require(script.Parent.RunSessionService)

local StoryService = {}

-- Ouvintes de "capítulo ouvido" (ex.: MissionService, etapa "Chapter").
local heardListeners: { (player: Player, chapterId: number) -> () } = {}

function StoryService.publish(player: Player)
	local profile = ProgressionService.getLoadedProfile(player)
	player:SetAttribute(Keys.ChaptersUnlockedAttr, if profile then table.concat(profile.chapters, ",") else "")
	player:SetAttribute(Keys.ChaptersSeenAttr, if profile then table.concat(profile.chaptersSeen, ",") else "")
end

-- Libera o capítulo da torre vencida. Devolve false se não há capítulo para ela ou ele já estava liberado.
function StoryService.unlockForTower(player: Player, towerId: number): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile or not Chronicles.byId[towerId] then
		return false
	end
	if not PlayerSchema.unlockChapter(profile, towerId) then
		return false
	end
	StoryService.publish(player)
	DataService.requestSave(player)
	print(`[História] {player.Name}: capítulo {towerId} liberado ("{Chronicles.byId[towerId].title}")`)
	return true
end

-- O capítulo já foi ouvido pela conta?
function StoryService.hasHeard(player: Player, chapterId: number): boolean
	local profile = ProgressionService.getLoadedProfile(player)
	return profile ~= nil and table.find(profile.chaptersSeen, chapterId) ~= nil
end

-- Conversa com o Observador: o que mostrar (já marca o capítulo novo como ouvido).
function StoryService.talk(player: Player): Remotes.NpcDialoguePayload
	local profile = ProgressionService.getLoadedProfile(player)
	if not profile or #profile.chapters == 0 then
		return { npc = "Observer", dialogue = "Idle_Observer_Early", canSkip = true, menu = false }
	end
	for _, chapterId in profile.chapters do
		if Chronicles.byId[chapterId] and PlayerSchema.markChapterSeen(profile, chapterId) then
			StoryService.publish(player)
			DataService.requestSave(player)
			print(`[História] {player.Name} ouviu o capítulo {chapterId}`)
			for _, listener in heardListeners do
				task.spawn(listener, player, chapterId)
			end
			return { npc = "Observer", chapter = chapterId, canSkip = false, menu = false }
		end
	end
	return { npc = "Observer", canSkip = true, menu = true }
end

function StoryService.addHeardListener(listener: (player: Player, chapterId: number) -> ())
	table.insert(heardListeners, listener)
end

-- SÓ TESTES (DevService): libera um capítulo sem vencer a torre.
function StoryService.debugUnlock(player: Player, chapterId: number): boolean
	return StoryService.unlockForTower(player, chapterId)
end

function StoryService.init()
	ProgressionService.setLoadedHandler(StoryService.publish)
	RunSessionService.addVictoryListener(function(player: Player, towerId: number, _: boolean)
		StoryService.unlockForTower(player, towerId)
	end)
end

function StoryService.start() end

return StoryService
