--!strict
-- Iluminação de cada lugar. O Lighting do Roblox vale para o mundo inteiro (lobby e andares da torre), então o
-- LightingController troca o preset no cliente conforme o jogador está no lobby ou numa run.
-- - Lobby 1 (Abismo de Áuren): valores do BRIEFING-LOBBY1 > Fase 3 (meia-noite, ambiente violeta escuro; a luz vem
--   do feixe, dos cristais roxos e das lanternas de Áuren montados no mundo), com o ambiente ajustado no Studio: com
--   os valores iniciais (24, 20, 34) / (18, 15, 28) e exposição 0, a pedra da caverna ficava preta (só as luzes
--   apareciam). Com (75, 62, 105) / (55, 46, 82) e exposição +0,8, a rocha aparece num violeta escuro.
-- - Torre: o visual de antes do Lobby 1 (luz de dia do template), até as torres ganharem iluminação própria. Sem
--   isso, os andares (greybox, sem luzes) ficariam escuros demais para jogar.

export type Preset = {
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	environmentDiffuseScale: number,
	environmentSpecularScale: number,
	exposureCompensation: number,
	atmosphere: {
		density: number,
		offset: number,
		color: Color3,
		decay: Color3,
		glare: number,
		haze: number,
	},
	bloom: { intensity: number, size: number, threshold: number },
	colorCorrection: { brightness: number, contrast: number, saturation: number, tintColor: Color3 },
	sunRays: { enabled: boolean, intensity: number, spread: number },
	sky: { starCount: number, celestialBodiesShown: boolean },
}

local Lobby1: Preset = {
	clockTime = 0,
	brightness = 3,
	ambient = Color3.fromRGB(75, 62, 105),
	outdoorAmbient = Color3.fromRGB(55, 46, 82),
	environmentDiffuseScale = 1,
	environmentSpecularScale = 1, -- reflexo do chão molhado (Piso de Áuren)
	exposureCompensation = 0.8,
	atmosphere = {
		density = 0.4,
		offset = 0.25,
		color = Color3.fromRGB(40, 30, 60),
		decay = Color3.fromRGB(60, 30, 90),
		glare = 0,
		haze = 0,
	},
	bloom = { intensity = 0.8, size = 24, threshold = 1.5 },
	colorCorrection = { brightness = 0, contrast = 0.1, saturation = 0.1, tintColor = Color3.new(1, 1, 1) },
	sunRays = { enabled = false, intensity = 0.01, spread = 0.1 }, -- caverna fechada, sem sol
	-- Sem estrelas nem lua: medido em Play, o céu da meia-noite vazava por trás do teto escuro (pontinhos brancos)
	sky = { starCount = 0, celestialBodiesShown = false },
}

local Tower: Preset = {
	clockTime = 14.5,
	brightness = 3,
	ambient = Color3.fromRGB(70, 70, 70),
	outdoorAmbient = Color3.fromRGB(70, 70, 70),
	environmentDiffuseScale = 1,
	environmentSpecularScale = 1,
	exposureCompensation = 0,
	atmosphere = {
		density = 0.3,
		offset = 0.25,
		color = Color3.fromRGB(199, 199, 199),
		decay = Color3.fromRGB(106, 112, 125),
		glare = 0,
		haze = 0,
	},
	bloom = { intensity = 1, size = 24, threshold = 2 },
	colorCorrection = { brightness = 0, contrast = 0, saturation = 0, tintColor = Color3.new(1, 1, 1) },
	sunRays = { enabled = true, intensity = 0.01, spread = 0.1 },
	sky = { starCount = 3000, celestialBodiesShown = true },
}

return table.freeze({
	Lobby1 = Lobby1,
	Tower = Tower,
})
