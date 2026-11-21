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
	Level = "Level",
	XP = "XP", -- XP dentro do nível atual
	XPToNext = "XPToNext", -- XP necessário para o próximo nível (0 no nível máximo)
	Gold = "Gold",
	UnspentPoints = "UnspentPoints", -- pontos de atributo ganhos e ainda não distribuídos
	SaveStatus = "SaveStatus", -- "ok" = progresso sendo salvo; "offline" = jogando sem salvar (falha no DataStore)
})

-- Attributes do workspace (estado do andar, definidos SÓ pelo servidor; o HUD lê).
Keys.WorldAttr = table.freeze({
	FloorNumber = "FloorNumber",
	PlatesActive = "PlatesActive",
	PlatesTotal = "PlatesTotal",
	ExitOpen = "ExitOpen",
	Lives = "Lives", -- vidas do grupo na run atual
	RunNumber = "RunNumber", -- aumenta a cada game over (o HUD mostra o aviso)
	IsBossFloor = "IsBossFloor", -- o andar atual é o do boss
	BossName = "BossName",
	BossHealth = "BossHealth",
	BossMaxHealth = "BossMaxHealth", -- 0 = nenhum boss ativo (o HUD esconde a barra)
	TowersCompleted = "TowersCompleted", -- aumenta ao derrotar o boss (o HUD mostra "TORRE CONCLUÍDA")
	RunActive = "RunActive", -- há uma torre em andamento (false = todos no lobby)
	GameOvers = "GameOvers", -- aumenta a cada game over (o HUD mostra o aviso)
})

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

function Keys.abilityReadyAttr(abilityId: string): string
	return `AbilityReadyAt_{abilityId}`
end

-- Valor de cada atributo (Força, Vitalidade...) replicado para o HUD.
function Keys.statAttr(attributeName: string): string
	return `Stat_{attributeName}`
end

return table.freeze(Keys)
