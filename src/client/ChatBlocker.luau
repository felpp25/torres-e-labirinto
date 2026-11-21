--!strict
-- A janela de chat do Roblox (CoreGui) fica por cima da nossa interface no canto inferior esquerdo (o HUD a move
-- para lá) e "engole" os cliques naquela área (medido: o botão "Distribuir pontos" não recebia clique).
-- Janelas grandes (Personagem, Loja) escondem o chat enquanto estão abertas; ele volta quando todas fecham.

local TextChatService: TextChatService = game:GetService("TextChatService")

local ChatBlocker = {}

local owners: { [string]: boolean? } = {}

local function apply()
	local visible = next(owners) == nil
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if window then
		window.Enabled = visible
	end
	local input = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if input then
		input.Enabled = visible
	end
end

-- `owner` = nome de quem está escondendo (ex.: "Character"); o chat só volta quando nenhum esconde mais.
function ChatBlocker.setHidden(owner: string, hidden: boolean)
	owners[owner] = if hidden then true else nil
	apply()
end

return table.freeze(ChatBlocker)
