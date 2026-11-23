--!strict
-- Definição central dos RemoteEvents (canais de rede cliente <-> servidor).
-- O servidor cria os Remotes em ReplicatedStorage.Remotes no início; o cliente espera por eles.
-- Usar sempre Remotes.get("Nome"): um nome errado vira erro de tipo, não um bug silencioso.
--
-- Direção e payload de cada Remote (o servidor VALIDA tudo que vem do cliente):
--   AttackRequest   cliente -> servidor  ()                       quero dar o próximo golpe do combo
--   DodgeRequest    cliente -> servidor  ()                       quero esquivar (servidor cobra stamina/recarga)
--   AbilityRequest  cliente -> servidor  (abilityId: string)      quero usar uma habilidade
--   CombatFeedback  servidor -> clientes (CombatFeedbackPayload)  algo foi atingido (ou curado): número/flash/tremor
--   RewardGranted   servidor -> 1 cliente (RewardPayload)         você ganhou XP/Gold: mostrar texto flutuante
--   LevelUp         servidor -> 1 cliente (LevelUpPayload)        você subiu de nível: mostrar aviso
--   AllocateAttribute   cliente -> servidor (attributeName: string)  quero pôr 1 ponto livre neste atributo
--   AllocateRecommended cliente -> servidor ()                       quero distribuir os pontos livres no recomendado
--   BuyItem         cliente -> servidor  (itemId: string)          quero comprar 1 unidade (perto da loja)
--   ResetAttributes cliente -> servidor  ()                        quero resetar meus atributos (perto da loja)
--   UsePotion       cliente -> servidor  (itemId: string)          quero usar 1 poção
--   ShopResult      servidor -> 1 cliente (ShopResultPayload)      resultado de compra/reset (mensagem na loja)
--   EquipGear       cliente -> servidor  (gearId: number)          quero equipar esta peça da conta (só no lobby)
--   UnequipGear     cliente -> servidor  (slot: string)            quero tirar a peça deste slot (vai para o baú)
--   GearResult      servidor -> 1 cliente (GearResultPayload)      resultado de equipar/tirar (painel Personagem)
--   GearNotice      servidor -> 1 cliente (GearNoticePayload)      ganhou uma peça (ou Gold, com o baú cheio)
--   SellGear        cliente -> servidor  (gearId: number)          quero vender esta peça do baú (perto da loja;
--                                                                  resposta em ShopResult)
--   EnhanceGear     cliente -> servidor  (gearId: number)          quero tentar fortalecer esta peça (perto da forja)
--   ForgeResult     servidor -> 1 cliente (ForgeResultPayload)     resultado da forja (sucesso, falha ou recusa)
--   TransferEnhance cliente -> servidor  (fromId, toId: number)    quero trocar o fortalecimento destas duas peças
--                                                                  (perto da forja; resposta em ForgeResult)
--   BuyGem          cliente -> servidor  (attribute: string)       quero comprar 1 gema Nv1 deste atributo (perto da
--                                                                  loja; resposta em ShopResult)
--   BuyRemover      cliente -> servidor  (level: number)           quero comprar 1 Removedor deste nível (idem)
--   SocketGem       cliente -> servidor  (gearId, attribute, level) quero encaixar esta gema do baú nesta peça (perto
--                                                                  da forja; resposta em ForgeResult)
--   ExtractGem      cliente -> servidor  (gearId: number)          quero tirar a gema desta peça (gasta Removedor)
--   FuseGems        cliente -> servidor  (attribute, level)        quero fundir 3 gemas iguais em 1 do nível seguinte
--   SellGem         cliente -> servidor  (attribute, level)        quero vender 1 gema do baú (perto da loja; ShopResult)
--   SellRemover     cliente -> servidor  (level: number)           quero vender 1 Removedor do baú (idem)
--   DestroyGear     cliente -> servidor  (gearId: number)          quero destruir esta peça do baú (arrastei para fora
--                                                                  da mochila e confirmei; resposta em GearResult)
--   DestroyGems     cliente -> servidor  (attribute, level)        quero destruir a pilha inteira dessas gemas (idem)
--   DestroyRemovers cliente -> servidor  (level: number)           quero destruir a pilha inteira de Removedores (idem)
--   TowerUnlocked   servidor -> 1 cliente (TowerUnlockedPayload)   sua conta liberou uma torre (fim da missão)
--   NpcDialogue     servidor -> 1 cliente (NpcDialoguePayload)     você falou com um NPC do lobby: mostrar a conversa
--                                                                  (o servidor já contou o progresso da missão)
-- O equipamento em si (peças da conta, slots, gemas e Removedores do baú) chega pelo Attribute "GearData" do Player
-- (Shared/GearSnapshot).

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

export type RemoteName =
	"AttackRequest"
	| "DodgeRequest"
	| "AbilityRequest"
	| "CombatFeedback"
	| "RewardGranted"
	| "LevelUp"
	| "AllocateAttribute"
	| "AllocateRecommended"
	| "BuyItem"
	| "ResetAttributes"
	| "UsePotion"
	| "ShopResult"
	| "EquipGear"
	| "UnequipGear"
	| "GearResult"
	| "GearNotice"
	| "SellGear"
	| "EnhanceGear"
	| "ForgeResult"
	| "BuyGem"
	| "BuyRemover"
	| "SocketGem"
	| "ExtractGem"
	| "FuseGems"
	| "SellGem"
	| "SellRemover"
	| "DestroyGear"
	| "DestroyGems"
	| "DestroyRemovers"
	| "TransferEnhance"
	| "TowerUnlocked"
	| "NpcDialogue"

export type CombatFeedbackPayload = {
	target: Model, -- quem foi atingido (inimigo ou personagem de jogador)
	attacker: Player?, -- quem bateu (nil = mob)
	damage: number,
	isCrit: boolean,
	isFinisher: boolean, -- golpe final do combo: o atacante treme a câmera
	isHeal: boolean?, -- true = cura: `damage` é quanto curou (número verde, sem flash nem tremor)
}

export type RewardPayload = {
	xp: number,
	gold: number,
	position: Vector3, -- onde o mob morreu
}

export type LevelUpPayload = {
	level: number, -- novo nível
	points: number, -- pontos de atributo ganhos (ficam livres para o jogador distribuir)
}

local REMOTE_NAMES: { RemoteName } = {
	"AttackRequest",
	"DodgeRequest",
	"AbilityRequest",
	"CombatFeedback",
	"RewardGranted",
	"LevelUp",
	"AllocateAttribute",
	"AllocateRecommended",
	"BuyItem",
	"ResetAttributes",
	"UsePotion",
	"ShopResult",
	"EquipGear",
	"UnequipGear",
	"GearResult",
	"GearNotice",
	"SellGear",
	"EnhanceGear",
	"ForgeResult",
	"BuyGem",
	"BuyRemover",
	"SocketGem",
	"ExtractGem",
	"FuseGems",
	"SellGem",
	"SellRemover",
	"DestroyGear",
	"DestroyGems",
	"DestroyRemovers",
	"TransferEnhance",
	"TowerUnlocked",
	"NpcDialogue",
}

-- Conversa com um NPC (os textos ficam em Shared/Story; o cliente só mostra). Um destes: `dialogue`, `chapter` ou
-- `menu`.
export type NpcDialoguePayload = {
	npc: string, -- Story/Npcs (quem fala; a câmera vai nele)
	dialogue: string?, -- id em Story/Dialogues
	chapter: number?, -- id em Story/Chronicles (o Observador contando)
	canSkip: boolean, -- false na 1ª vez (capítulo novo ou etapa da missão)
	menu: boolean, -- true: abre o menu para rever os capítulos (o Observador sem nada novo)
}

export type TowerUnlockedPayload = {
	towerId: number,
	source: string, -- "Quest" (fim da missão) | "Dev"
}

export type GearResultPayload = {
	ok: boolean,
	message: string, -- ex.: "Equipou Faixa do Combatente de Osso (Raro)" / "Troca de equipamento só no lobby"
}

-- Campos simples (strings): o cliente valida e consulta o catálogo.
export type GearNoticePayload = {
	defId: string,
	rarity: string, -- "Common" | "Rare"
	source: string, -- "Boss" | "Mob" | "Dev"
	goldInstead: number, -- 0 = a peça foi para o baú; > 0 = baú cheio, virou este Gold
}

export type ShopResultPayload = {
	ok: boolean,
	message: string, -- ex.: "Comprou Poção de Vida" / "Gold insuficiente"
}

export type ForgeResultPayload = {
	ok: boolean, -- true = deu certo (fortalecimento, incrustar, extrair, fundir); false = falhou ou foi recusado
	rolled: boolean, -- true = houve sorteio do fortalecimento (Gold gasto: sucesso ou falha); gemas: sempre false
	message: string, -- ex.: "Sucesso! Gibão do Combatente de Osso +5" / "Falhou: caiu para +6" / "Gold insuficiente"
}
local FOLDER_NAME = "Remotes"
local CLIENT_WAIT_TIMEOUT = 30

local Remotes = {}

-- Só o servidor chama: cria a pasta e todos os Remotes. Idempotente.
function Remotes.setupServer()
	assert(RunService:IsServer(), "Remotes.setupServer só pode rodar no servidor")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = FOLDER_NAME
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	assert(folder, "pasta de Remotes não criada")
	for _, name in REMOTE_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: RemoteName): RemoteEvent
	local folder: Instance
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Instance
		assert(folder, "Remotes.setupServer() ainda não foi chamado")
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_TIMEOUT) :: Instance
		assert(folder, "pasta de Remotes não apareceu no cliente")
	end
	local remote = if RunService:IsServer()
		then folder:FindFirstChild(name)
		else folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteEvent"), `Remote '{name}' não encontrado`)
	return remote
end

return table.freeze(Remotes)
