--!strict
-- Registro das runs do servidor (GDD > Torre 2 e escolha de torre: várias runs no mesmo servidor).
-- Cada run tem um id, a torre, um ponto próprio no mapa (as runs ficam a `Dungeon.runSpacing` studs umas das outras:
-- mobs, avisos de ataque e XP de uma não alcançam a outra), uma pasta no workspace e os participantes.
-- O estado que o HUD mostra (andar, vidas, placas, chefão) vira Attributes de CADA participante (Keys.RunAttr):
-- quem entra no meio recebe o estado atual; quem sai tem esses Attributes limpos.
-- Só dados: não depende de nenhum serviço (todos podem usar sem dependência circular).

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Keys = require(Shared.Keys)
local Dungeon = require(Shared.Balance.Dungeon)

export type StateValue = number | string | boolean

export type Run = {
	id: number,
	towerId: number,
	slot: number, -- posição no mapa (reaproveitada quando a run acaba)
	origin: Vector3, -- onde os andares desta run são construídos
	folder: Folder, -- workspace.Runs.Run_<id> (Attribute "RunId"): o andar fica aqui dentro
	members: { Player }, -- ordem de entrada (espaçamento no spawn)
	bossEligible: { [Player]: boolean }, -- entrou antes do andar do chefão (prêmio do chefão)
	lives: number,
	active: boolean, -- false depois que a run terminou (torre concluída, game over, todos saíram)
	state: { [string]: StateValue }, -- o que o HUD lê (copiado para os Attributes de cada participante)
}

local RUN_ID_ATTR = "RunId"
local FOLDER_NAME = "Runs"

local RunRegistry = {}

local runs: { Run } = {}
local runByPlayer: { [Player]: Run } = {}
local usedSlots: { [number]: boolean } = {}
local nextId = 0

local function runsFolder(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function freeSlot(): number
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	return slot
end

-- Cria uma run vazia (sem andar e sem participantes) para a torre `towerId`.
function RunRegistry.create(towerId: number): Run
	nextId += 1
	local slot = freeSlot()
	usedSlots[slot] = true
	local folder = Instance.new("Folder")
	folder.Name = `Run_{nextId}`
	folder:SetAttribute(RUN_ID_ATTR, nextId)
	folder.Parent = runsFolder()
	local run: Run = {
		id = nextId,
		towerId = towerId,
		slot = slot,
		origin = Dungeon.floorOrigin + Vector3.new(0, 0, (slot - 1) * Dungeon.runSpacing),
		folder = folder,
		members = {},
		bossEligible = {},
		lives = 0,
		active = true,
		state = {},
	}
	table.insert(runs, run)
	return run
end

-- Tira a run do registro: libera o lugar no mapa e destrói a pasta (andar, mobs e chefão junto).
-- Os participantes já devem ter saído (removeMember).
function RunRegistry.destroy(run: Run)
	run.active = false
	local index = table.find(runs, run)
	if index then
		table.remove(runs, index)
	end
	usedSlots[run.slot] = nil
	run.folder:Destroy()
end

function RunRegistry.all(): { Run }
	return table.clone(runs)
end

function RunRegistry.runOf(player: Player): Run?
	return runByPlayer[player]
end

function RunRegistry.isMember(run: Run, player: Player): boolean
	return runByPlayer[player] == run
end

-- Participantes na ordem de entrada (cópia: pode ser percorrida enquanto alguém sai).
function RunRegistry.members(run: Run): { Player }
	return table.clone(run.members)
end

-- Run dona de uma instância (mob, coração, peça do andar): sobe até a pasta da run.
function RunRegistry.fromInstance(instance: Instance): Run?
	local current: Instance? = instance
	while current do
		local id = current:GetAttribute(RUN_ID_ATTR)
		if typeof(id) == "number" then
			for _, run in runs do
				if run.id == id then
					return run
				end
			end
			return nil
		end
		current = current.Parent
	end
	return nil
end

-- Põe o jogador na run: Attributes de participante e o estado atual da run (para quem entra no meio).
function RunRegistry.addMember(run: Run, player: Player)
	local previous = runByPlayer[player]
	assert(previous == nil or previous == run, "jogador já está em outra run")
	if previous == run then
		return
	end
	runByPlayer[player] = run
	table.insert(run.members, player)
	player:SetAttribute(Keys.RunAttr.RunId, run.id)
	player:SetAttribute(Keys.RunAttr.TowerId, run.towerId)
	for key, value in run.state do
		player:SetAttribute(key, value)
	end
	-- Por último: o HUD trata "entrou na torre" quando InRun muda e já encontra o estado da run.
	player:SetAttribute(Keys.InRunAttr, true)
end

-- Tira o jogador da run e limpa os Attributes de participante (os contadores de avisos ficam).
function RunRegistry.removeMember(run: Run, player: Player)
	if runByPlayer[player] ~= run then
		return
	end
	runByPlayer[player] = nil
	run.bossEligible[player] = nil
	local index = table.find(run.members, player)
	if index then
		table.remove(run.members, index)
	end
	player:SetAttribute(Keys.InRunAttr, false)
	for key in run.state do
		player:SetAttribute(key, nil)
	end
	player:SetAttribute(Keys.RunAttr.RunId, nil)
	player:SetAttribute(Keys.RunAttr.TowerId, nil)
end

-- Muda um valor do estado da run (andar, vidas, placas, chefão) para todos os participantes. nil = apaga.
function RunRegistry.setState(run: Run, key: string, value: StateValue?)
	if value == nil then
		run.state[key] = nil
	else
		run.state[key] = value
	end
	for _, player in run.members do
		player:SetAttribute(key, value)
	end
end

-- Contador de avisos do jogador (ex.: torre concluída, game over): +1 para cada participante. O HUD avisa quando
-- o número sobe. Fica no jogador (não é estado da run): sobrevive ao fim da run.
function RunRegistry.bumpCounter(run: Run, key: string)
	for _, player in run.members do
		local current = player:GetAttribute(key)
		player:SetAttribute(key, (if typeof(current) == "number" then current else 0) + 1)
	end
end

return RunRegistry
