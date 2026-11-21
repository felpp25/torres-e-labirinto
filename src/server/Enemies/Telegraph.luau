--!strict
-- Avisos de ataque inimigo ("telegraph") e quem é atingido. Usado por mobs (EnemyService) e bosses (BossService).
-- Regra de design: o golpe acerta EXATAMENTE a área mostrada no chão (justo e legível).

local Players: Players = game:GetService("Players")

local Telegraph = {}

Telegraph.COLOR = Color3.fromRGB(255, 40, 40)
local INDICATOR_TRANSPARENCY = 0.55
local INDICATOR_NAME = "TelegraphIndicator"
local CIRCLE_HEIGHT = 8 -- altura da área do golpe circular (studs, a partir do chão)

local function baseIndicator(): Part
	local indicator = Instance.new("Part")
	indicator.Name = INDICATOR_NAME
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CanQuery = false
	indicator.CanTouch = false
	indicator.CastShadow = false
	indicator.Material = Enum.Material.Neon
	indicator.Color = Telegraph.COLOR
	indicator.Transparency = INDICATOR_TRANSPARENCY
	return indicator
end

-- Faixa no chão para uma área retangular (`hitCFrame`/`size` = a caixa do golpe).
function Telegraph.rect(hitCFrame: CFrame, size: Vector3, groundY: number): Part
	local indicator = baseIndicator()
	indicator.Size = Vector3.new(size.X, 0.2, size.Z)
	local position = hitCFrame.Position
	indicator.CFrame = CFrame.new(position.X, groundY + 0.1, position.Z) * hitCFrame.Rotation
	indicator.Parent = workspace
	return indicator
end

-- Disco no chão para uma área circular. (O cilindro do Roblox tem o eixo em X: gira 90° para deitar.)
function Telegraph.circle(center: Vector3, radius: number, groundY: number): Part
	local indicator = baseIndicator()
	indicator.Shape = Enum.PartType.Cylinder
	indicator.Size = Vector3.new(0.2, radius * 2, radius * 2)
	indicator.CFrame = CFrame.new(center.X, groundY + 0.1, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	indicator.Parent = workspace
	return indicator
end

local function aliveCharacters(): { Model }
	local result: { Model } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 then
			table.insert(result, character)
		end
	end
	return result
end

-- Jogadores vivos com alguma parte do corpo dentro da caixa.
function Telegraph.playersInBox(hitCFrame: CFrame, size: Vector3): { Player }
	local filter: { Instance } = {}
	for _, character in aliveCharacters() do
		table.insert(filter, character)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = filter

	local result: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(hitCFrame, size, params) do
		local character = part:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and not seen[player] then
			seen[player] = true
			table.insert(result, player)
		end
	end
	return result
end

-- Jogadores vivos com o centro do corpo a até `radius` studs (no plano) de `center`, e perto do chão da área.
function Telegraph.playersInRadius(center: Vector3, radius: number, groundY: number): { Player }
	local result: { Player } = {}
	for _, character in aliveCharacters() do
		local root = character:FindFirstChild("HumanoidRootPart")
		local player = Players:GetPlayerFromCharacter(character)
		if root and root:IsA("BasePart") and player then
			local offset = root.Position - center
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			local height = root.Position.Y - groundY
			if flat <= radius and height >= -1 and height <= CIRCLE_HEIGHT then
				table.insert(result, player)
			end
		end
	end
	return result
end

return table.freeze(Telegraph)
