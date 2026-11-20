--!strict
-- Empurrão horizontal seguro (esquiva do jogador no cliente; empurrão de mobs no servidor).
--
-- Por que existe: um LinearVelocity com força infinita empurrando contra uma parede gera forças enormes na
-- colisão e ARREMESSA o personagem (medido: esquiva contra a parede chegou a 112 studs/s e jogou o jogador
-- 38 studs para trás). Aqui:
-- 1. um Spherecast mede o espaço livre à frente e o movimento é encurtado para parar antes do obstáculo;
-- 2. a força máxima é limitada (massa × aceleração máxima), então nada "explode" mesmo num caso não previsto.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Balance"):WaitForChild("Combat"))

local ATTACHMENT_NAME = "MotionAttachment"

local Motion = {}

-- Distância livre (horizontal) à frente de `root`, descontando a margem; nunca negativa.
function Motion.freeDistance(root: BasePart, direction: Vector3, maxDistance: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local radius = Combat.motionProbeRadius
	local hit = workspace:Spherecast(root.Position, radius, direction * (maxDistance + radius), params)
	if not hit then
		return maxDistance
	end
	return math.max(hit.Distance - Combat.motionWallMargin, 0)
end

-- Move `root` na direção (horizontal, unitária) a `speed` studs/s por até `duration` s, parando antes de paredes.
-- `ignore`: o que não conta como obstáculo (o próprio modelo, e por exemplo outros personagens/mobs).
-- Devolve a duração efetiva (0 = não havia espaço para se mover).
function Motion.push(root: BasePart, direction: Vector3, speed: number, duration: number, ignore: { Instance }): number
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 or speed <= 0 or duration <= 0 then
		return 0
	end
	flat = flat.Unit

	local free = Motion.freeDistance(root, flat, speed * duration, ignore)
	local effectiveDuration = free / speed
	if effectiveDuration < Combat.motionMinDuration then
		return 0
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root

	-- Modo Plano: controla só o movimento horizontal; a gravidade continua agindo.
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(flat.X, flat.Z) * speed
	velocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	velocity.MaxForce = root.AssemblyMass * Combat.motionMaxAcceleration
	velocity.Parent = root

	task.delay(effectiveDuration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
	return effectiveDuration
end

return table.freeze(Motion)
