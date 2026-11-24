--!strict
-- Troca a iluminação conforme o lugar (presets em client/LightingPresets): Lobby 1 fora da run, Torre dentro dela
-- (Attribute InRun do jogador, decidido pelo servidor). Só no cliente: o Lighting vale para o mundo inteiro e jogadores
-- do mesmo servidor podem estar em lugares diferentes. Os efeitos que faltarem no Lighting são criados aqui.

local Lighting: Lighting = game:GetService("Lighting")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Keys = require(Shared:WaitForChild("Keys"))
local LightingPresets = require(script.Parent.Parent:WaitForChild("LightingPresets"))

local localPlayer = Players.LocalPlayer

local LightingController = {}

local function atmosphere(): Atmosphere
	local found = Lighting:FindFirstChildOfClass("Atmosphere")
	if found then
		return found
	end
	local created = Instance.new("Atmosphere")
	created.Parent = Lighting
	return created
end

local function bloom(): BloomEffect
	local found = Lighting:FindFirstChildOfClass("BloomEffect")
	if found then
		return found
	end
	local created = Instance.new("BloomEffect")
	created.Parent = Lighting
	return created
end

local function colorCorrection(): ColorCorrectionEffect
	local found = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if found then
		return found
	end
	local created = Instance.new("ColorCorrectionEffect")
	created.Parent = Lighting
	return created
end

local function sunRays(): SunRaysEffect
	local found = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if found then
		return found
	end
	local created = Instance.new("SunRaysEffect")
	created.Parent = Lighting
	return created
end

local function sky(): Sky
	local found = Lighting:FindFirstChildOfClass("Sky")
	if found then
		return found
	end
	local created = Instance.new("Sky")
	created.Parent = Lighting
	return created
end

local function apply(preset: LightingPresets.Preset)
	Lighting.ClockTime = preset.clockTime
	Lighting.Brightness = preset.brightness
	Lighting.Ambient = preset.ambient
	Lighting.OutdoorAmbient = preset.outdoorAmbient
	Lighting.EnvironmentDiffuseScale = preset.environmentDiffuseScale
	Lighting.EnvironmentSpecularScale = preset.environmentSpecularScale
	Lighting.ExposureCompensation = preset.exposureCompensation

	local a = atmosphere()
	a.Density = preset.atmosphere.density
	a.Offset = preset.atmosphere.offset
	a.Color = preset.atmosphere.color
	a.Decay = preset.atmosphere.decay
	a.Glare = preset.atmosphere.glare
	a.Haze = preset.atmosphere.haze

	local b = bloom()
	b.Intensity = preset.bloom.intensity
	b.Size = preset.bloom.size
	b.Threshold = preset.bloom.threshold

	local cc = colorCorrection()
	cc.Brightness = preset.colorCorrection.brightness
	cc.Contrast = preset.colorCorrection.contrast
	cc.Saturation = preset.colorCorrection.saturation
	cc.TintColor = preset.colorCorrection.tintColor

	local rays = sunRays()
	rays.Enabled = preset.sunRays.enabled
	rays.Intensity = preset.sunRays.intensity
	rays.Spread = preset.sunRays.spread

	local s = sky()
	s.StarCount = preset.sky.starCount
	s.CelestialBodiesShown = preset.sky.celestialBodiesShown
end

local function refresh()
	local inRun = localPlayer:GetAttribute(Keys.InRunAttr) == true
	apply(if inRun then LightingPresets.Tower else LightingPresets.Lobby1)
end

function LightingController.init() end

function LightingController.start()
	refresh()
	localPlayer:GetAttributeChangedSignal(Keys.InRunAttr):Connect(refresh)
end

return LightingController
