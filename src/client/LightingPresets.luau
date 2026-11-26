--!strict
-- Iluminação de cada lugar. O Lighting do Roblox vale para o mundo inteiro (lobby e andares da torre), então o
-- LightingController troca o preset no cliente conforme o jogador está no lobby ou numa run.
-- - Lobby 1 (Abismo de Áuren): meia-noite; a luz vem do feixe, dos cristais roxos e das lanternas de Áuren montados no
--   mundo. Teste de visual (o designer achou a primeira versão "apagada, fosca, antiga"): ambiente mais baixo e violeta
--   (contraste: escuro onde é escuro, vivo onde há luz), névoa clara e roxa que acende com a distância e em volta das
--   luzes (Haze/Glare) em vez de escurecer, Bloom forte e mais saturação e contraste. Junto com LightingStyle =
--   Realistic e ShadowSoftness 0,12, que ficam no Lighting do place (valem para lobby e torre).
--   Versões anteriores: a do briefing (24, 20, 34; névoa escura 0,4) deixava a rocha preta; a primeira correção
--   (75, 62, 105; exposição +0,8) achatava tudo num violeta morno.
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

-- Caverna fechada: a luz do "céu" (OutdoorAmbient e EnvironmentDiffuse) é bloqueada pelo teto. O Roblox calcula esse
-- bloqueio aos poucos e só perto da câmera: nos primeiros segundos tudo recebia a luz do céu e depois escurecia em
-- volta do personagem, enquanto o longe continuava claro (bug do vídeo em lobby1-claude-code/bugs). Por isso a luz de
-- fundo vai TODA no Ambient (que não é bloqueado). Medido no Acampamento: 108, 96, 142 (a soma do Ambient e do
-- OutdoorAmbient de antes) ficou estável mas mais escuro que o começo do vídeo; 140, 126, 182 chega perto dele.
local Lobby1: Preset = {
	clockTime = 0,
	brightness = 3,
	ambient = Color3.fromRGB(140, 126, 182),
	outdoorAmbient = Color3.fromRGB(0, 0, 0),
	environmentDiffuseScale = 0,
	environmentSpecularScale = 1, -- reflexo do chão molhado (Piso de Áuren)
	exposureCompensation = 0.35,
	-- Cores de névoa e de correção pouco saturadas (vídeo "Environmental Art": a Atmosphere mistura as cores da cena
	-- sem supersaturar). O designer achou as luzes fortes demais com Bloom 1,2, saturação 0,35 e Haze 1,3.
	atmosphere = {
		density = 0.3,
		offset = 0.15,
		color = Color3.fromRGB(135, 120, 160),
		decay = Color3.fromRGB(95, 80, 120),
		glare = 0.1,
		haze = 0.6,
	},
	bloom = { intensity = 0.6, size = 24, threshold = 1.4 },
	colorCorrection = {
		brightness = 0,
		contrast = 0.12,
		saturation = 0.05,
		tintColor = Color3.fromRGB(255, 250, 255),
	},
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
