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

-- Físico escala com Força e gasta stamina; mágico escala com Inteligência e gasta mana.
export type DamageType = "Physical" | "Magical"
export type ResourceType = "Stamina" | "Mana"

-- Um golpe do combo do ataque básico.
export type ComboHitDef = {
	baseDamage: number,
	range: number, -- profundidade da hitbox à frente do personagem (studs)
	width: number, -- largura da hitbox (studs)
	recovery: number, -- tempo mínimo até o próximo golpe (s)
	knockback: number, -- velocidade do empurrão aplicado no alvo (studs/s); 0 = nenhum
	isFinisher: boolean, -- golpe final do combo (tremor de câmera)
}

export type AbilityDef = {
	id: string,
	displayName: string,
	damageType: DamageType,
	baseDamage: number,
	resource: ResourceType,
	cost: number,
	cooldown: number, -- s
	recovery: number, -- s em que o ataque básico fica bloqueado depois de usar a habilidade
	range: number,
	width: number,
	knockback: number,
}

export type ClassDef = {
	id: string,
	displayName: string,
	scalingAttributes: { AttributeName }, -- 2 atributos com M = 1,5
	baseHealth: number,
	baseMana: number,
	baseStamina: number,
	walkSpeed: number,
	combo: { ComboHitDef },
	abilities: { string }, -- ids em Balance/Abilities
}

export type MobDef = {
	id: string,
	displayName: string,
	health: number,
	damage: number,
	defense: number,
	walkSpeed: number,
	aggroRange: number, -- distância para começar a perseguir (studs)
	attackRange: number, -- distância para iniciar o ataque (studs)
	telegraphTime: number, -- aviso visual antes do golpe (s)
	attackCooldown: number, -- s
	xp: number,
	goldMin: number,
	goldMax: number,
	size: Vector3,
	color: Color3,
}

-- Uma sala na grade do labirinto (gerada pelo MazeGenerator).
export type RoomKind = "Entrance" | "Combat" | "Puzzle" | "DeadEnd"

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
