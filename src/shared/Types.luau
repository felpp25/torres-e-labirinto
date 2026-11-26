--!strict
-- Tipos compartilhados entre servidor e cliente.
-- Identificadores em inglês (código); textos de interface em português (displayName).

-- Os 7 atributos do GDD (docs/GDD-resumo.md > Atributos).
export type AttributeName = "Strength" | "Vitality" | "Intelligence" | "Wisdom" | "Dexterity" | "Defense" | "Luck"

export type Attributes = {
	Strength: number, -- Força: dano físico
	Vitality: number, -- Vitalidade: vida máxima
	Intelligence: number, -- Inteligência: dano mágico
	Wisdom: number, -- Sabedoria: mana máxima
	Dexterity: number, -- Destreza: stamina
	Defense: number, -- Defesa: reduz dano físico e mágico
	Luck: number, -- Sorte: crítico e achados raros (Coração, equipamentos; baús no futuro)
}

-- Físico escala com Força; mágico escala com Inteligência. O recurso gasto é de cada habilidade (AbilityDef).
export type DamageType = "Physical" | "Magical"
export type ResourceType = "Stamina" | "Mana"
-- Recurso que uma habilidade gasta. "Ultimate" = a barra de ultimate (enche lutando; `cost` 100 = barra cheia).
export type AbilityResource = ResourceType | "Ultimate"

-- Um golpe do combo do ataque básico.
export type ComboHitDef = {
	baseDamage: number,
	range: number, -- profundidade da hitbox à frente do personagem (studs)
	width: number, -- largura da hitbox (studs)
	recovery: number, -- tempo mínimo até o próximo golpe (s)
	knockback: number, -- velocidade do empurrão aplicado no alvo (studs/s); 0 = nenhum
	isFinisher: boolean, -- golpe final do combo (tremor de câmera)
}

-- Habilidades. Cada uma declara o próprio recurso pela NATUREZA dela (GDD > Atributos > Recursos): golpes, armas
-- e movimento gastam stamina; Chi, sagrado, elemental e cura gastam mana. `kind` diz o que a habilidade faz.

-- Área de um golpe: "Front" = retângulo à frente do personagem; "Circle" = círculo em volta dele.
export type StrikeShape = "Front" | "Circle"

-- "Strike": golpe único com dano numa área.
export type StrikeAbilityDef = {
	kind: "Strike",
	id: string,
	displayName: string,
	shortName: string, -- texto curto para botões e ícones
	resource: AbilityResource,
	cost: number,
	cooldown: number, -- s
	recovery: number, -- s em que o ataque básico fica bloqueado depois de usar a habilidade
	damageType: DamageType,
	baseDamage: number,
	shape: StrikeShape,
	range: number, -- Front: profundidade da área; Circle: raio (studs)
	width: number, -- Front: largura da área (Circle ignora)
	knockback: number, -- Front: empurra para a frente; Circle: empurra para longe do personagem
}

-- "Barrage": sequência de golpes à frente com o personagem PARADO (não anda, não ataca, não esquiva) até acabar.
-- Os primeiros golpes dão `baseDamage`; o último dá `finalDamage` e empurra.
export type BarrageAbilityDef = {
	kind: "Barrage",
	id: string,
	displayName: string,
	shortName: string,
	resource: AbilityResource,
	cost: number,
	cooldown: number,
	recovery: number, -- s extras de bloqueio do ataque básico depois do último golpe
	damageType: DamageType,
	hits: number,
	hitInterval: number, -- s entre golpes (duração total = hits × hitInterval)
	baseDamage: number,
	finalDamage: number,
	range: number,
	width: number,
	finalKnockback: number,
}

-- "SelfBuff": efeito no próprio jogador: cura na hora e bônus de dano por um tempo.
export type SelfBuffAbilityDef = {
	kind: "SelfBuff",
	id: string,
	displayName: string,
	shortName: string,
	resource: AbilityResource,
	cost: number,
	cooldown: number,
	recovery: number,
	healFraction: number, -- cura na hora: fração da vida máxima (0,12 = 12%)
	damageBonus: number, -- dano extra enquanto durar (0,12 = +12%), em todo golpe e habilidade
	duration: number, -- s do bônus de dano
}

export type AbilityDef = StrikeAbilityDef | BarrageAbilityDef | SelfBuffAbilityDef

export type ClassDef = {
	id: string,
	displayName: string,
	scalingAttributes: { AttributeName }, -- 2 atributos com M = 1,5
	baseHealth: number,
	baseMana: number,
	baseStamina: number,
	walkSpeed: number,
	combo: { ComboHitDef },
	abilities: { string }, -- ids em Balance/Abilities (as 3 habilidades, na ordem dos atalhos)
	ultimate: string, -- id em Balance/Abilities (gasta a barra de ultimate)
}

-- Ataque do mob. "Melee": golpe à frente (caixa hitRange × hitWidth). "Lob": pedra que cai onde o alvo estava ao
-- começar o aviso (círculo de raio `areaRadius`); precisa de linha de visão até o alvo.
export type MobAttack = "Melee" | "Lob"

export type MobDef = {
	id: string,
	displayName: string,
	health: number,
	damage: number,
	defense: number,
	walkSpeed: number,
	aggroRange: number, -- distância para começar a perseguir (studs)
	attackRange: number, -- distância (centro a centro) para iniciar o ataque (studs)
	attack: MobAttack?, -- nil = "Melee"
	areaRadius: number?, -- só "Lob": raio do círculo onde a pedra cai (studs)
	hitRange: number, -- profundidade da área do golpe à frente do mob (studs)
	hitWidth: number, -- largura da área do golpe (studs)
	telegraphTime: number, -- aviso visual antes do golpe (s)
	attackCooldown: number, -- s
	xp: number,
	goldMin: number,
	goldMax: number,
	size: Vector3,
	color: Color3,
}

-- Um ataque de boss. Cada boss tem a própria lista (tema e moveset únicos); a IA só executa o que está descrito.
-- "Front": área retangular à frente do boss. "Circle": área circular ao redor dele. "AtPlayers": um círculo embaixo de
-- CADA jogador vivo na arena (raio `range`), em `waves` ondas seguidas; cada onda mira de novo.
export type BossAttackShape = "Front" | "Circle" | "AtPlayers"

export type BossAttackDef = {
	id: string,
	shape: BossAttackShape,
	telegraphTime: number, -- aviso no chão antes do golpe (s)
	damage: number,
	range: number, -- Front: profundidade da área; Circle e AtPlayers: raio (studs)
	width: number, -- Front: largura da área (os outros ignoram)
	waves: number?, -- AtPlayers: quantas ondas seguidas (padrão 1); a pausa `recovery` vem depois da última
	triggerRange: number, -- o boss escolhe este ataque se o alvo estiver até esta distância
	minRange: number?, -- ... e a pelo menos esta (golpe de longe: de perto ficam os outros); padrão 0
	recovery: number, -- s parado depois do golpe (janela para o jogador revidar)
	effect: string?, -- efeito visual no golpe (Telegraph), ex.: "MagmaFissure" (rachadura de lava pela faixa)
}

export type BossDef = {
	id: string,
	displayName: string,
	body: MobDef, -- corpo (tamanho, cor, vida base, velocidade); os campos de ataque de mob são ignorados
	healthPerExtraPlayer: number, -- +X da vida base por jogador além do primeiro (coop)
	attacks: { BossAttackDef },
	attackCooldown: number, -- s entre o fim da recuperação de um ataque e o próximo
	xp: number, -- para CADA jogador da run, ao derrotar
	gold: number,
}

-- Item consumível da loja (poções). Guardado na conta; usado por atalho na run.
export type ConsumableEffect = "Heal" | "Stamina" | "Mana"

export type ConsumableDef = {
	id: string,
	displayName: string,
	description: string,
	price: number, -- Gold
	maxOwned: number, -- quantos a conta pode guardar
	effect: ConsumableEffect,
	amount: number, -- Heal: fração da vida máxima; Stamina/Mana: fração do máximo do recurso
	cooldown: number, -- s entre usos deste item (o atalho fica no cliente: client/Hotkeys)
}

-- Equipamento (GDD > Equipamentos). O catálogo fica em Balance/Gear; o save guarda só referências (OwnedGear).
export type EquipSlot = "Weapon" | "Helmet" | "Armor" | "Pants" | "Boots" | "Bracelet" | "Necklace"
export type Rarity = "Common" | "Rare"
-- Linha da peça (o "scaling" dela: quais atributos dá). Armas não têm linha.
export type GearLine = "Combatant" | "Guardian"

-- Peça do catálogo, com os valores da raridade COMUM (a Rara multiplica por Gear.rarityMultiplier).
export type GearDef = {
	id: string, -- vai para o save: NUNCA renomear nem apagar um id já usado
	displayName: string,
	slot: EquipSlot,
	line: GearLine?, -- nil nas armas
	classId: string?, -- só armas: a classe que pode usar
	damageType: DamageType?, -- só armas: o tipo de dano que o Poder multiplica
	power: number, -- Poder da arma Comum (0,05 = +5% de dano); 0 nas outras peças
	attributes: Attributes, -- pontos da peça Comum
	minLevel: number, -- nível mínimo do personagem para equipar
	tower: number, -- torre em que a peça cai: define a base do custo do fortalecimento (Balance/Forge)
}

-- Gemas (GDD > Equipamentos > Gemas; números em Balance/Gems). O atributo é um dos 7, menos a Sorte.
export type GemAttribute = "Strength" | "Vitality" | "Intelligence" | "Wisdom" | "Dexterity" | "Defense"

export type Gem = {
	attribute: GemAttribute,
	level: number, -- 1 a 5 = 1 a 5 pontos no atributo
}

-- Pilha no baú da conta (gemas e Removedores empilham por tipo; cada pilha ocupa 1 espaço do baú).
export type GemStack = { attribute: GemAttribute, level: number, count: number }
export type RemoverStack = { level: number, count: number }

-- Peça que a conta possui (o que vai para o save). Pontos, Poder, nome e preço vêm do catálogo.
export type OwnedGear = {
	id: number, -- único na conta e nunca reutilizado
	defId: string,
	rarity: Rarity,
	enhance: number, -- fortalecimento: 0 (sem) a 10 (save v5)
	gem: Gem?, -- gema encaixada (save v6); nil = sem gema
}

-- Visão do cliente (atributo GearData; formato em Shared/GearSnapshot).
export type GearEntry = {
	id: number,
	defId: string,
	rarity: Rarity,
	enhance: number, -- fortalecimento (0 a 10)
	gem: Gem?,
	inUse: boolean, -- equipada por algum personagem da conta: não conta no baú e não pode ser vendida
}

export type GearSnapshot = {
	gear: { GearEntry },
	equipped: { [EquipSlot]: number }, -- slots do personagem ativo (slot -> id da peça)
	gems: { GemStack }, -- gemas soltas no baú (na ordem de Balance/Gems: atributo, depois nível)
	removers: { RemoverStack }, -- Removedores no baú (por nível)
}

-- Uma sala na grade do labirinto (gerada pelo MazeGenerator).
-- "Puzzle" = sala final dos andares normais; "Boss" = sala final do último andar da torre (vira a arena).
export type RoomKind = "Entrance" | "Combat" | "Puzzle" | "DeadEnd" | "Boss"

export type Room = {
	x: number,
	y: number,
	kind: RoomKind,
	doors: { North: boolean, South: boolean, East: boolean, West: boolean },
}

export type FloorLayout = {
	seed: number,
	floorNumber: number,
	width: number,
	height: number,
	rooms: { Room },
}

-- ModuleScript precisa devolver um valor não-nil; os tipos são usados como Types.Attributes etc.
return {}
