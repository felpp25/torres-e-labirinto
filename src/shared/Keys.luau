--!strict
-- Nomes usados em mais de um lugar (tags do CollectionService e Attributes replicados).
-- Centralizados aqui para um erro de digitação virar erro de tipo, não um bug silencioso.

local Keys = {}

-- Tags do CollectionService (o Roblox replica tags para os clientes).
Keys.Tags = table.freeze({
	Enemy = "Enemy",
})

-- Attributes do Player, definidos SÓ pelo servidor; o cliente lê para o HUD e para prever recargas.
-- Os horários de recarga usam workspace:GetServerTimeNow(), que é sincronizado entre servidor e clientes.
Keys.PlayerAttr = table.freeze({
	Stamina = "Stamina",
	MaxStamina = "MaxStamina",
	Mana = "Mana",
	MaxMana = "MaxMana",
	DodgeReadyAt = "DodgeReadyAt",
	DamageBonus = "DamageBonus", -- bônus de dano ativo (0,12 = +12%), ex.: Foco Interior
	DamageBonusUntil = "DamageBonusUntil", -- até quando (relógio do servidor) o bônus vale
	UltimateCharge = "UltimateCharge", -- barra de ultimate, 0 a 100
	WeaponPower = "WeaponPower", -- Poder da arma equipada (0,05 = +5% de dano do tipo dela); 0 = sem arma
	Resonance = "Resonance", -- peças equipadas que ressoam na run atual (Balance/Gear); 0 no lobby e na Torre 1
	GearData = "GearData", -- JSON com as peças da conta e os slots do personagem ativo (Shared/GearSnapshot)
	Level = "Level",
	XP = "XP", -- XP dentro do nível atual
	XPToNext = "XPToNext", -- XP necessário para o próximo nível (0 no nível máximo)
	Gold = "Gold",
	UnspentPoints = "UnspentPoints", -- pontos de atributo ganhos e ainda não distribuídos
	SaveStatus = "SaveStatus", -- "ok" = progresso sendo salvo; "offline" = jogando sem salvar (falha no DataStore)
})

-- Attributes do Player com o estado da RUN dele (várias runs por servidor: cada participante recebe o estado da
-- sua; definidos SÓ pelo servidor, server/Runs/RunRegistry; o HUD lê). Fora de uma run ficam nil.
Keys.RunAttr = table.freeze({
	RunId = "RunId", -- id da run (nil = no lobby); o espectador só segue quem tem o mesmo
	TowerId = "TowerId", -- torre da run
	FloorNumber = "FloorNumber",
	PlatesActive = "PlatesActive",
	PlatesTotal = "PlatesTotal",
	ExitOpen = "ExitOpen",
	Lives = "Lives", -- vidas do grupo
	IsBossFloor = "IsBossFloor", -- o andar atual é o do boss
	BossName = "BossName",
	BossHealth = "BossHealth",
	BossMaxHealth = "BossMaxHealth", -- 0 = nenhum boss ativo (o HUD esconde a barra)
	-- Contadores do jogador (sobrevivem ao fim da run): o HUD avisa quando o número sobe.
	TowersCompleted = "TowersCompleted", -- torre concluída ("TORRE CONCLUÍDA")
	GameOvers = "GameOvers", -- game over
	-- Espera no portal (GDD: um portal por torre, ~10 s para o grupo se formar). nil = não está esperando.
	QueueTower = "QueueTower", -- torre do portal
	QueueStartsAt = "QueueStartsAt", -- quando a run começa (workspace:GetServerTimeNow())
	QueueSize = "QueueSize", -- quantos estão no grupo
	PortalBlocked = "PortalBlocked", -- em cima de um portal trancado: o motivo (texto); nil = não está
	PortalBlockedTower = "PortalBlockedTower", -- torre desse portal
})

-- Capítulos das Crônicas do Observador da conta (StoryService): ids separados por vírgula, ex.: "1,2".
Keys.ChaptersUnlockedAttr = "ChaptersUnlocked"
Keys.ChaptersSeenAttr = "ChaptersSeen"

-- Progresso de uma missão da conta (MissionService): etapa atual, contador da etapa e se terminou. Sem a missão
-- começada: nil.
function Keys.missionAttr(missionId: string, field: "Step" | "Count" | "Done"): string
	return `Mission_{missionId}_{field}`
end

-- O acesso da conta à torre (true = liberada: a chave, que sai da missão). Só torres que exigem acesso.
function Keys.towerAccessAttr(towerId: number): string
	return `TowerAccess_{towerId}`
end

-- Quantidade de um item da conta (ex.: "Item_HealthPotion"), replicada no Player para a loja e os atalhos.
function Keys.itemAttr(itemId: string): string
	return `Item_{itemId}`
end

-- Horário (relógio do servidor) em que o item pode ser usado de novo (recarga da poção).
function Keys.itemReadyAttr(itemId: string): string
	return `ItemReadyAt_{itemId}`
end

-- O jogador está dentro da torre (participando da run), e não no lobby.
Keys.InRunAttr = "InRun"

-- SÓ NO CLIENTE (não replica): uma conversa com NPC está aberta (DialogueController). O HUD segura avisos que
-- cobririam o rosto do NPC (ex.: "TORRE 2 LIBERADA!" no fim da missão) até ela fechar.
Keys.DialogueOpenAttr = "DialogueOpen"

function Keys.abilityReadyAttr(abilityId: string): string
	return `AbilityReadyAt_{abilityId}`
end

-- Attribute do Player com o valor atual do recurso que uma habilidade gasta (stamina, mana ou barra de ultimate).
function Keys.resourceAttr(resource: "Stamina" | "Mana" | "Ultimate"): string
	if resource == "Stamina" then
		return Keys.PlayerAttr.Stamina
	elseif resource == "Mana" then
		return Keys.PlayerAttr.Mana
	end
	return Keys.PlayerAttr.UltimateCharge
end

-- Pontos DISTRIBUÍDOS de cada atributo (Força, Vitalidade...) replicados para o HUD.
function Keys.statAttr(attributeName: string): string
	return `Stat_{attributeName}`
end

-- Pontos que o EQUIPAMENTO dá em cada atributo (efetivo = Stat_ + GearStat_).
function Keys.gearStatAttr(attributeName: string): string
	return `GearStat_{attributeName}`
end

function Keys.isGearStatAttr(name: string): boolean
	return string.sub(name, 1, 9) == "GearStat_"
end

return table.freeze(Keys)
