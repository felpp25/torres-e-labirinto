--!strict
-- Configuração global compartilhada entre servidor e cliente.

export type Config = {
	GAME_NAME: string,
	VERSION: string,
}

local Config: Config = table.freeze({
	GAME_NAME = "Ascending Labyrinths",
	VERSION = "0.0.1",
})

return Config
