--!strict
-- Missões da conta (GDD > Missão e história; decisões do designer). O MissionService segue as etapas em ordem; o
-- progresso fica no save (PlayerSchema.missions) e vale para todos os personagens da conta.
--
-- Tipos de etapa (o contador zera a cada etapa):
--   "Chapter"      ouvir o capítulo `chapter` das Crônicas com o Observador
--   "Talk"         falar com `npc` (a fala `dialogue`, em Story/Dialogues)
--   "BossWins"     vencer a torre `towerId` (contam os que estavam na run antes do andar do chefão: a regra do item)
--   "MobKills"     derrotar mobs na torre `towerId` (conta para quem recebe o XP do mob)
--   "SellGear"     vender peças na loja
--   "Enhance"      ter uma peça fortalecida até `target` (conta a maior da conta; se já tiver, conclui na hora)
--   "FlawlessWins" vencer a torre `towerId` sem o grupo perder vida (nenhum wipe na run)
--   "Fragments"    juntar Fragmentos de Cristal: 1 por vitória na torre `towerId` (mesma regra de "BossWins")

local Npcs = require(script.Parent.Parent.Story.Npcs)
local Dialogues = require(script.Parent.Parent.Story.Dialogues)
local Chronicles = require(script.Parent.Parent.Story.Chronicles)

export type StepKind =
	"Chapter"
	| "Talk"
	| "BossWins"
	| "MobKills"
	| "SellGear"
	| "Enhance"
	| "FlawlessWins"
	| "Fragments"

export type MissionStep = {
	kind: StepKind,
	target: number, -- quantas vezes (Talk e Chapter: 1; Enhance: o nível do fortalecimento)
	npc: Npcs.NpcId?, -- Talk e Chapter: com quem falar
	dialogue: string?, -- Talk: id em Story/Dialogues
	chapter: number?, -- Chapter: id em Story/Chronicles
	towerId: number?, -- BossWins, MobKills, FlawlessWins e Fragments
	objective: string, -- texto do HUD; as etapas com contador mostram "(2/4)" depois
}

export type MissionDef = {
	id: string, -- vai para o save (chave texto): NUNCA renomear
	displayName: string,
	startTower: number, -- a missão começa na 1ª vitória nesta torre
	rewardTower: number, -- concluir libera o acesso da conta a esta torre (TowerService)
	steps: { MissionStep },
}

-- O Caminho de Cristal (acesso à Torre 2): ~15 runs (~4,5 h) contando a 1ª vitória. A Chave de Cristal só sai daqui.
local CRYSTAL_PATH: MissionDef = {
	id = "CrystalPath",
	displayName = "O Caminho de Cristal",
	startTower = 1,
	rewardTower = 2,
	steps = {
		{ kind = "Chapter", target = 1, npc = "Observer", chapter = 1, objective = "Fale com o Observador" },
		{ kind = "Talk", target = 1, npc = "Ariadne", dialogue = "CrystalPath_Intro", objective = "Fale com Ariadne" },
		{ kind = "BossWins", target = 4, towerId = 1, objective = "Derrote o Guardião da Torre" },
		{ kind = "Talk", target = 1, npc = "Ariadne", dialogue = "CrystalPath_Mobs", objective = "Fale com Ariadne" },
		{ kind = "MobKills", target = 200, towerId = 1, objective = "Derrote mobs na Torre 1" },
		{ kind = "Talk", target = 1, npc = "Tanu", dialogue = "CrystalPath_Sell", objective = "Fale com Tanu" },
		{ kind = "SellGear", target = 2, objective = "Venda peças na loja" },
		{ kind = "Talk", target = 1, npc = "Brokk", dialogue = "CrystalPath_Forge", objective = "Fale com Brokk" },
		{ kind = "Enhance", target = 3, objective = "Fortaleça uma peça até +3" },
		{
			kind = "Talk",
			target = 1,
			npc = "Ariadne",
			dialogue = "CrystalPath_Flawless",
			objective = "Fale com Ariadne",
		},
		{ kind = "FlawlessWins", target = 1, towerId = 1, objective = "Vença a Torre 1 sem perder vida" },
		{
			kind = "Talk",
			target = 1,
			npc = "Ariadne",
			dialogue = "CrystalPath_Fragments",
			objective = "Fale com Ariadne",
		},
		{ kind = "Fragments", target = 5, towerId = 1, objective = "Fragmentos de Cristal" },
		{ kind = "Talk", target = 1, npc = "Ariadne", dialogue = "CrystalPath_Key", objective = "Fale com Ariadne" },
	},
}

local LIST: { MissionDef } = { CRYSTAL_PATH }

local BY_ID: { [string]: MissionDef } = {}
for _, def in LIST do
	assert(BY_ID[def.id] == nil, `Missions: id repetido {def.id}`)
	assert(#def.steps > 0, `Missions: {def.id} sem etapas`)
	for index, step in def.steps do
		assert(step.target >= 1, `Missions: alvo inválido na etapa {index} de {def.id}`)
		local needsNpc = step.kind == "Talk" or step.kind == "Chapter"
		assert(not needsNpc or step.npc ~= nil, `Missions: etapa {index} de {def.id} sem NPC`)
		if step.kind == "Talk" then
			local dialogue = if step.dialogue then Dialogues[step.dialogue] else nil
			assert(dialogue, `Missions: etapa {index} de {def.id} com fala desconhecida`)
			assert(dialogue.npc == step.npc, `Missions: a fala da etapa {index} de {def.id} é de outro NPC`)
		elseif step.kind == "Chapter" then
			local chapter = if step.chapter then Chronicles.byId[step.chapter] else nil
			assert(chapter, `Missions: etapa {index} de {def.id} com capítulo desconhecido`)
			assert(step.npc == "Observer", `Missions: quem conta o capítulo é o Observador (etapa {index})`)
		end
		table.freeze(step)
	end
	-- A recompensa sai ao falar com o NPC na última etapa (ex.: Ariadne forja a chave).
	assert(def.steps[#def.steps].kind == "Talk", `Missions: a última etapa de {def.id} precisa ser uma conversa`)
	table.freeze(def.steps)
	table.freeze(def)
	BY_ID[def.id] = def
end

export type MissionsBalance = {
	list: { MissionDef },
	byId: { [string]: MissionDef },
}

local MISSIONS: MissionsBalance = {
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
}

return table.freeze(MISSIONS)
