--!strict
-- Monta o modelo greybox de um inimigo a partir da definição em Balance/Mobs.
-- Estrutura: HumanoidRootPart (corpo) + Head + "nariz" (mostra para onde ele está virado) + Humanoid.

local CollectionService: CollectionService = game:GetService("CollectionService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Keys = require(Shared.Keys)

local HOVER_HEIGHT = 0.5 -- studs entre a base do corpo e o chão

local EnemyFactory = {}

local function weld(root: BasePart, part: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = part
	constraint.Parent = part
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- `statMultiplier` escala a vida (dificuldade do andar). O chamador define o Parent e depois chama setServerOwned.
function EnemyFactory.create(def: Types.MobDef, cframe: CFrame, statMultiplier: number): Model
	local model = Instance.new("Model")
	model.Name = def.displayName

	local root = makePart("HumanoidRootPart", def.size, cframe, def.color)
	root.Parent = model

	local headSize = math.min(def.size.X, def.size.Z) * 0.6
	local headCFrame = cframe * CFrame.new(0, def.size.Y / 2 + headSize / 2, 0)
	local head = makePart("Head", Vector3.one * headSize, headCFrame, def.color)
	head.Massless = true
	head.CanCollide = false
	head.Parent = model
	weld(root, head)

	local noseSize = headSize * 0.35
	local noseCFrame = headCFrame * CFrame.new(0, 0, -(headSize / 2 + noseSize / 2))
	local nose = makePart("Nose", Vector3.one * noseSize, noseCFrame, Color3.fromRGB(30, 30, 30))
	nose.Massless = true
	nose.CanCollide = false
	nose.Parent = model
	weld(root, nose)

	local humanoid = Instance.new("Humanoid")
	-- R15 sem pernas: o Humanoid sustenta o HumanoidRootPart HOVER_HEIGHT acima do chão.
	-- NÃO usar 0: com o corpo encostado no chão o Humanoid fica preso em Freefall e desliza sem parar
	-- (medido no playtest: ~21 studs/s até cair do mapa).
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HOVER_HEIGHT
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = def.health * statMultiplier
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = def.walkSpeed
	humanoid.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("MobId", def.id)
	model:SetAttribute("Defense", def.defense)
	CollectionService:AddTag(model, Keys.Tags.Enemy)
	return model
end

-- A física do inimigo fica com o servidor. Sem isso, o Roblox pode entregá-la ao cliente mais próximo,
-- que poderia manipular a posição do mob. Só funciona depois que o modelo está no workspace.
function EnemyFactory.setServerOwned(model: Model)
	local root = model.PrimaryPart
	if root then
		root:SetNetworkOwner(nil)
	end
end

return table.freeze(EnemyFactory)
