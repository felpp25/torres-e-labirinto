--!strict
-- Movimento dos chefões vestidos. Os modelos do Tripo não têm esqueleto: o BossService prende cada peça do modelo com
-- um Motor6D (Keys.BossVisual.Joint) na peça "Pai" dela ou no corpo, e aqui o cliente mexe no Transform desses Motor6D
-- a cada quadro. Só aparência e só neste cliente: o Transform não volta para o servidor (colisão e golpes não mudam).
--
-- Golem de Obsidiana e Magma (pedaços de pedra com juntas de lava; decisão do designer):
-- - parado: o peito respira, a cabeça olha em volta, os braços balançam de leve;
-- - andando: as coxas alternam, o joelho dobra na perna que vai para trás, os braços balançam ao contrário das pernas e
--   o corpo quica no passo;
-- - golpe pesado (HeavySlam): no aviso ergue os dois braços acima da cabeça e joga o tronco para trás; no golpe (fim do
--   aviso) desce os braços no chão, inclina para a frente e afunda;
-- - pisão (Stomp): no aviso levanta a perna direita e abre os braços; no golpe pisa e o corpo afunda;
-- - Fissura de Magma (MagmaFissure): no aviso ergue o braço direito lá no alto e torce o tronco; no golpe agacha e
--   soca o chão (a rachadura de lava é do servidor, Telegraph.magmaFissure).
-- Golem com ESQUELETO (rig Mixamo do Tripo, uma malha só com Bones): as mesmas poses, aplicadas nos ossos
-- (BONE_MAP): o corpo dobra sem cortes. O giro de cada pose é no espaço do chefão; no osso ele vira
-- repouso⁻¹ * giro * repouso (o repouso é medido quando o osso aparece, com o Transform ainda zerado).
-- Peça única (ex.: Kokuryū, "Corpo" com a junta nos pés): respira, balança ao andar, recua no aviso e dá um tranco.
--
-- Eixos de cada junta = os do chefão (frente = -z). Angles(+a, 0, 0) leva para a frente o que pende para baixo (braço,
-- perna) e para trás o que aponta para cima (tronco). As peças "D" (direita do Golem) ficam em +x.
-- Streaming: as peças podem chegar depois do corpo; os Motor6D são procurados de novo quando aparecem.

local CollectionService: CollectionService = game:GetService("CollectionService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))

local BREATH_HZ = 0.55 -- respirações por segundo
local BREATH_HEIGHT = 0.12 -- studs
local STEP_HZ = 0.9 -- passos (de cada perna) por segundo, andando
local STEP_BOUNCE = 0.3 -- studs
local WALK_SPEED_FULL = 7 -- studs/s: a partir daqui o andar é o inteiro
-- no impacto antes de voltar (com 0,22 s a batida passava despercebida no vídeo do teste)
local STRIKE_HOLD = 0.4
local STRIKE_TIME = 1.0 -- s até voltar à pose normal
-- rapidez com que cada peça chega na pose (1/s): armar, bater, voltar
local SPEED_WINDUP = 6
local SPEED_STRIKE = 20
local SPEED_RELAX = 4

-- pose -> osso do Mixamo (sem o prefixo "mixamorig:"); a subida e descida do corpo (posição do Tronco) vai no quadril
local BONE_MAP: { [string]: string } = {
	Tronco = "Spine",
	Cabeca = "Head",
	BracoD = "RightArm",
	AntebracoD = "RightForeArm",
	BracoE = "LeftArm",
	AntebracoE = "LeftForeArm",
	CoxaD = "RightUpLeg",
	CanelaD = "RightLeg",
	CoxaE = "LeftUpLeg",
	CanelaE = "LeftLeg",
}

type Pose = { [string]: CFrame }
type Entry = {
	model: Model,
	motors: { [string]: Motor6D },
	current: { [Motor6D]: CFrame },
	bones: { [string]: Bone },
	boneRest: { [Bone]: CFrame }, -- orientação do osso no espaço do chefão, em repouso
	boneCurrent: { [Bone]: CFrame },
	lastPosition: Vector3?,
	speed: number,
	clock: number,
	wasTelegraph: boolean,
	strikeAt: number,
	strikeAttack: string,
}

local BossVisualController = {}

local entries: { [Model]: Entry } = {}

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(x, y, z)
end

local function collect(entry: Entry)
	for _, d in entry.model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == Keys.BossVisual.Joint and d.Part1 then
			entry.motors[d.Part1.Name] = d
		elseif d:IsA("Bone") then
			local short = string.gsub(d.Name, "^mixamorig:", "")
			entry.bones[short] = d
		end
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or entries[instance] or instance:GetAttribute("BossId") == nil then
		return
	end
	local entry: Entry = {
		model = instance,
		motors = {},
		current = {},
		bones = {},
		boneRest = {},
		boneCurrent = {},
		lastPosition = nil,
		speed = 0,
		clock = math.random() * 10,
		wasTelegraph = false,
		strikeAt = -math.huge,
		strikeAttack = "",
	}
	entries[instance] = entry
	collect(entry)
	instance.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") or d:IsA("Bone") then
			collect(entry)
		end
	end)
end

-- Pose do Golem: andar/parado como base; por cima, o golpe armado (no aviso) ou batendo (logo depois do aviso).
local function golemPose(entry: Entry, walk: number, now: number, telegraph: boolean, attack: string): (Pose, number)
	local t = entry.clock
	local phase = t * STEP_HZ * math.pi * 2
	local s = math.sin(phase)
	local breath = math.sin(t * BREATH_HZ * math.pi * 2)
	local bob = breath * BREATH_HEIGHT * (1 - walk) + math.abs(s) * STEP_BOUNCE * walk
	local body = CFrame.new(0, bob, 0)
	local pose: Pose = {
		Tronco = body * rot(0.03 * walk, 0, s * 0.05 * walk),
		Cabeca = rot(math.sin(t * 0.45) * 0.04, math.sin(t * 0.3) * 0.12, 0),
		BracoD = rot(-s * 0.35 * walk + breath * 0.03, 0, breath * 0.02),
		BracoE = rot(s * 0.35 * walk + breath * 0.03, 0, -breath * 0.02),
		AntebracoD = rot(0.15 * walk, 0, 0),
		AntebracoE = rot(0.15 * walk, 0, 0),
		CoxaD = body * rot(s * 0.5 * walk, 0, 0),
		CoxaE = body * rot(-s * 0.5 * walk, 0, 0),
		CanelaD = rot(-math.max(0, -s) * 0.8 * walk, 0, 0),
		CanelaE = rot(-math.max(0, s) * 0.8 * walk, 0, 0),
	}
	local speed = SPEED_RELAX

	local sinceStrike = now - entry.strikeAt
	local striking = sinceStrike >= 0 and sinceStrike < STRIKE_TIME
	local move = if telegraph then attack elseif striking then entry.strikeAttack else ""
	if move == "HeavySlam" then
		if telegraph then -- armar: braços acima da cabeça, tronco para trás
			pose.Tronco = body * rot(0.25, 0, 0)
			pose.Cabeca = rot(0.2, 0, 0)
			pose.BracoD = rot(2.5, 0, 0.15)
			pose.BracoE = rot(2.5, 0, -0.15)
			pose.AntebracoD = rot(0.6, 0, 0)
			pose.AntebracoE = rot(0.6, 0, 0)
			speed = SPEED_WINDUP
		elseif sinceStrike < STRIKE_HOLD then -- bater: braços no chão à frente, tronco para a frente, afunda
			local down = CFrame.new(0, -0.8, 0)
			pose.Tronco = down * rot(-0.5, 0, 0)
			pose.Cabeca = rot(-0.15, 0, 0)
			pose.CoxaD = down * rot(0.15, 0, 0)
			pose.CoxaE = down * rot(0.15, 0, 0)
			pose.CanelaD = rot(-0.3, 0, 0)
			pose.CanelaE = rot(-0.3, 0, 0)
			pose.BracoD = rot(1.1, 0, 0.1)
			pose.BracoE = rot(1.1, 0, -0.1)
			pose.AntebracoD = rot(0.2, 0, 0)
			pose.AntebracoE = rot(0.2, 0, 0)
			speed = SPEED_STRIKE
		end
	elseif move == "Stomp" then
		if telegraph then -- armar: perna direita no alto, braços abertos para equilibrar
			pose.Tronco = body * rot(0.15, 0, 0.1)
			pose.CoxaD = body * rot(1.35, 0, 0)
			pose.CanelaD = rot(-1.35, 0, 0)
			pose.BracoD = rot(0.2, 0, 0.5)
			pose.BracoE = rot(0.2, 0, -0.5)
			speed = SPEED_WINDUP
		elseif sinceStrike < STRIKE_HOLD then -- pisar: perna embaixo, o corpo afunda
			local down = CFrame.new(0, -0.8, 0)
			pose.Tronco = down * rot(-0.2, 0, 0)
			pose.CoxaD = down
			pose.CoxaE = down
			pose.BracoD = rot(-0.2, 0, 0.3)
			pose.BracoE = rot(-0.2, 0, -0.3)
			speed = SPEED_STRIKE
		end
	elseif move == "MagmaFissure" then
		if telegraph then -- armar: braço direito lá no alto, tronco torcido para trás, braço esquerdo para trás
			pose.Tronco = body * rot(0.18, 0.25, -0.05)
			pose.Cabeca = rot(0.1, 0, 0)
			pose.BracoD = rot(2.7, 0, 0.2)
			pose.AntebracoD = rot(0.4, 0, 0)
			pose.BracoE = rot(-0.3, 0, -0.3)
			speed = SPEED_WINDUP
		elseif sinceStrike < STRIKE_HOLD then -- socar o chão: corpo agachado, braço direito no chão à frente
			local down = CFrame.new(0, -1.0, 0)
			pose.Tronco = down * rot(-0.7, -0.15, 0)
			pose.Cabeca = rot(-0.2, 0, 0)
			pose.BracoD = rot(1.0, 0, 0)
			pose.AntebracoD = rot(0.1, 0, 0)
			pose.BracoE = rot(0.4, 0, -0.4)
			pose.CoxaD = down * rot(0.3, 0, 0)
			pose.CoxaE = down * rot(0.3, 0, 0)
			pose.CanelaD = rot(-0.5, 0, 0)
			pose.CanelaE = rot(-0.5, 0, 0)
			speed = SPEED_STRIKE
		end
	elseif move ~= "" then -- outro golpe: recua e dá um tranco com o corpo
		if telegraph then
			pose.Tronco = body * rot(0.2, 0, 0)
			speed = SPEED_WINDUP
		elseif sinceStrike < STRIKE_HOLD then
			pose.Tronco = rot(-0.3, 0, 0)
			speed = SPEED_STRIKE
		end
	end
	return pose, speed
end

-- Peça única com a junta nos pés: o corpo inteiro respira, balança, recua e dá o tranco.
local function singlePose(entry: Entry, walk: number, now: number, telegraph: boolean): (Pose, number)
	local t = entry.clock
	local phase = t * STEP_HZ * 1.2 * math.pi * 2
	local breath = math.sin(t * BREATH_HZ * math.pi * 2) * BREATH_HEIGHT * (1 - walk)
	local bounce = math.abs(math.sin(phase)) * STEP_BOUNCE * walk
	local sway = math.sin(phase) * math.rad(3.5) * walk
	local sinceStrike = now - entry.strikeAt
	local pitch, speed = 0, SPEED_RELAX
	if telegraph then
		pitch, speed = math.rad(7), SPEED_WINDUP
	elseif sinceStrike >= 0 and sinceStrike < STRIKE_HOLD then
		pitch, speed = -math.rad(12), SPEED_STRIKE
	end
	local pose: Pose = {}
	for name in entry.motors do
		pose[name] = CFrame.new(0, breath + bounce, 0) * rot(pitch, 0, sway)
	end
	return pose, speed
end

local function step(dt: number)
	local now = os.clock()
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		local root = model.PrimaryPart
		if not root or next(entry.motors) == nil then
			continue
		end

		-- velocidade no plano (MoveDirection de NPC fica zerada: compara posições)
		local position = root.Position
		if entry.lastPosition and dt > 0 then
			local delta = position - entry.lastPosition
			local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			entry.speed += (flat - entry.speed) * math.min(1, dt * 6)
		end
		entry.lastPosition = position
		local walk = math.clamp(entry.speed / WALK_SPEED_FULL, 0, 1)
		entry.clock += dt

		local telegraph = model:GetAttribute(Keys.BossVisual.Telegraph) == true
		local attack = model:GetAttribute(Keys.BossVisual.Attack)
		local attackId = if type(attack) == "string" then attack else ""
		if entry.wasTelegraph and not telegraph then
			entry.strikeAt = now
			entry.strikeAttack = attackId
		end
		entry.wasTelegraph = telegraph

		local spine: Bone? = entry.bones.Spine
		local hips: Bone? = entry.bones.Hips
		local pose, speed
		if entry.motors.Tronco or (spine and hips) then
			pose, speed = golemPose(entry, walk, now, telegraph, attackId)
		else
			pose, speed = singlePose(entry, walk, now, telegraph)
		end
		local alpha = 1 - math.exp(-speed * dt)

		if spine and hips then
			-- esqueleto: o Motor6D da malha fica parado; as poses vão para os ossos
			local targets: { [Bone]: CFrame } = {}
			for poseName, boneName in BONE_MAP do
				local bone = entry.bones[boneName]
				if bone then
					targets[bone] = (pose[poseName] or CFrame.identity).Rotation
				end
			end
			local trunk = pose.Tronco or CFrame.identity
			targets[hips] = CFrame.new(trunk.Position)
			-- repouso: medido antes de girar qualquer osso (o filho herda o giro do pai)
			for bone in targets do
				if not entry.boneRest[bone] then
					entry.boneRest[bone] = root.CFrame:ToObjectSpace(bone.TransformedWorldCFrame).Rotation
				end
			end
			for bone, wanted in targets do
				local rest = entry.boneRest[bone]
				-- giro no espaço do chefão -> espaço do osso; a posição (quadril) também
				local target = CFrame.new(rest:VectorToObjectSpace(wanted.Position))
					* (rest:Inverse() * wanted.Rotation * rest)
				local current = (entry.boneCurrent[bone] or CFrame.identity):Lerp(target, alpha)
				entry.boneCurrent[bone] = current
				bone.Transform = current
			end
			continue
		end

		for name, motor in entry.motors do
			local target = pose[name] or CFrame.identity
			local current = entry.current[motor] or CFrame.identity
			current = current:Lerp(target, alpha)
			entry.current[motor] = current
			motor.Transform = current
		end
	end
end

function BossVisualController.init() end

function BossVisualController.start()
	for _, instance in CollectionService:GetTagged(Keys.Tags.Enemy) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Keys.Tags.Enemy):Connect(track)
	-- antes da física, como o Animator do Roblox: o Transform escrito aqui vale para este quadro
	RunService.PreSimulation:Connect(step)
end

return BossVisualController
