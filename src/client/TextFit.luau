--!strict
-- Texto de uma linha que ENCOLHE para caber, em vez de cortar com "...". Feito para os nomes das peças, que são
-- "peça base + marca da torre" (GDD > Mundo e temas) e passam da caixa com o "+N" (medido: "Pulseira do Combatente de
-- Cristal +10" tem 245 px a 14 e a caixa do painel Personagem, 230; cabe a 13). O tamanho atual vira o máximo:
-- texto curto não muda. Abaixo do mínimo o Roblox corta o texto (TextFits = false).

local TextFit = {}

function TextFit.shrinkToFit(label: TextLabel, minSize: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = label.TextSize
	constraint.MinTextSize = minSize
	constraint.Parent = label
	label.TextScaled = true
end

return TextFit
