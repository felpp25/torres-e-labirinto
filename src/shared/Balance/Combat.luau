--!strict
-- Balanceamento geral de combate (vale para todas as classes).
-- Números iniciais do protótipo: ajuste aqui, nunca espalhado pelo código.

local Combat = table.freeze({
	-- Combo do ataque básico
	comboWindow = 0.8, -- s depois de um golpe para encadear o próximo; passou disso, o combo volta ao 1º golpe

	-- Esquiva (dash)
	dodge = table.freeze({
		staminaCost = 20,
		cooldown = 0.6, -- s
		invulnerableTime = 0.3, -- s de invencibilidade a partir do início do dash
		speed = 70, -- studs/s (aplicado no cliente)
		duration = 0.18, -- s
	}),

	-- Recursos
	staminaRegenDelay = 1.2, -- s sem gastar stamina até começar a regenerar
	staminaRegenPerSecond = 35,
	manaRegenPerSecond = 3,

	-- Crítico (Sorte)
	critBaseChance = 0.05,
	critChancePerLuck = 0.005,
	critMultiplier = 1.5,

	-- Defesa: redução = Defesa / (Defesa + defenseConstant)
	defenseConstant = 100,

	-- Fórmula de dano do GDD: Base × (1 + damagePerAttributePoint × Atributo × M)
	damagePerAttributePoint = 0.02,
	scalingMultiplier = 1.5, -- M dos atributos de scaling da classe
	commonMultiplier = 1, -- M dos demais atributos

	-- Hitbox (servidor): caixa à frente do personagem com esta altura
	hitboxHeight = 7,
	-- Tolerância de rede: studs extras de alcance e segundos de folga nas recargas
	rangeTolerance = 2,
	serverTimingTolerance = 0.08,
	-- Assistência de mira: o golpe vira para o inimigo mais próximo DENTRO DO ALCANCE do golpe e até este ângulo
	-- (graus) da frente. 180 = qualquer direção (celular: inimigo atrás de você é comum; com 70 o golpe saía no vazio).
	aimAssistAngle = 180,
	-- Empurrão: o alvo é levado a `knockback` studs/s (valor de cada golpe/habilidade) durante este tempo.
	-- Distância aproximada = knockback × knockbackDuration (ex.: Palma 60 × 0,18 ≈ 11 studs).
	knockbackDuration = 0.18,

	-- IA dos inimigos
	enemyThinkInterval = 0.1, -- s entre decisões (perseguir/atacar)
	enemyRepathInterval = 0.5, -- s entre recálculos de caminho (PathfindingService) sem linha de visão
	corpseLifetime = 1.5, -- s até o corpo do mob sumir

	-- Sem regeneração natural de vida: no protótipo, vida só volta no checkpoint (GDD > Morte e checkpoint)
	disableNaturalHealthRegen = true,

	-- Feedback (cliente)
	cameraShakeIntensity = 0.35,
	cameraShakeDuration = 0.15,
	hitFlashDuration = 0.1,
	damageNumberDuration = 0.8,
})

return Combat
