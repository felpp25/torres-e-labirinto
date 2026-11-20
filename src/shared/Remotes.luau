--!strict
-- Definição central dos RemoteEvents (canais de rede cliente <-> servidor).
-- O servidor cria os Remotes em ReplicatedStorage.Remotes no início; o cliente espera por eles.
-- Usar sempre Remotes.get("Nome"): um nome errado vira erro de tipo, não um bug silencioso.
--
-- Direção e payload de cada Remote (o servidor VALIDA tudo que vem do cliente):
--   AttackRequest   cliente -> servidor  ()                       quero dar o próximo golpe do combo
--   DodgeRequest    cliente -> servidor  ()                       quero esquivar (servidor cobra stamina/recarga)
--   AbilityRequest  cliente -> servidor  (abilityId: string)      quero usar uma habilidade
--   CombatFeedback  servidor -> clientes (CombatFeedbackPayload)  algo foi atingido: mostrar número/flash/tremor
--   RewardGranted   servidor -> 1 cliente (RewardPayload)         você ganhou XP/Gold: mostrar texto flutuante

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

export type RemoteName = "AttackRequest" | "DodgeRequest" | "AbilityRequest" | "CombatFeedback" | "RewardGranted"

export type CombatFeedbackPayload = {
	target: Model, -- quem foi atingido (inimigo ou personagem de jogador)
	attacker: Player?, -- quem bateu (nil = mob)
	damage: number,
	isCrit: boolean,
	isFinisher: boolean, -- golpe final do combo: o atacante treme a câmera
}

export type RewardPayload = {
	xp: number,
	gold: number,
	position: Vector3, -- onde o mob morreu
}

local REMOTE_NAMES: { RemoteName } =
	{ "AttackRequest", "DodgeRequest", "AbilityRequest", "CombatFeedback", "RewardGranted" }
local FOLDER_NAME = "Remotes"
local CLIENT_WAIT_TIMEOUT = 30

local Remotes = {}

-- Só o servidor chama: cria a pasta e todos os Remotes. Idempotente.
function Remotes.setupServer()
	assert(RunService:IsServer(), "Remotes.setupServer só pode rodar no servidor")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = FOLDER_NAME
		newFolder.Parent = ReplicatedStorage
		folder = newFolder
	end
	assert(folder, "pasta de Remotes não criada")
	for _, name in REMOTE_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: RemoteName): RemoteEvent
	local folder: Instance
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Instance
		assert(folder, "Remotes.setupServer() ainda não foi chamado")
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_TIMEOUT) :: Instance
		assert(folder, "pasta de Remotes não apareceu no cliente")
	end
	local remote = if RunService:IsServer()
		then folder:FindFirstChild(name)
		else folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	assert(remote and remote:IsA("RemoteEvent"), `Remote '{name}' não encontrado`)
	return remote
end

return table.freeze(Remotes)
