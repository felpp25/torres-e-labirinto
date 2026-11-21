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
	Luck: number, -- Sorte: crítico (drops e baús depois do protótipo)
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

export type MobDef = {
	id: string,
	displayName: string,
	health: number,
	damage: number,
	defense: number,
	walkSpeed: number,
	aggroRange: number, -- distância para começar a perseguir (studs)
	attackRange: number, -- distância (centro a centro) para iniciar o ataque (studs)
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
-- "Front": área retangular à frente do boss. "Circle": área circular ao redor dele.
export type BossAttackShape = "Front" | "Circle"

export type BossAttackDef = {
	id: string,
	shape: BossAttackShape,
	telegraphTime: number, -- aviso no chão antes do golpe (s)
	damage: number,
	range: number, -- Front: profundidade da área; Circle: raio (studs)
	width: number, -- Front: largura da área (Circle ignora)
	triggerRange: number, -- o boss escolhe este ataque se o alvo estiver até esta distância
	recovery: number, -- s parado depois do golpe (janela para o jogador revidar)
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
