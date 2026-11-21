--!strict
-- Barra de ações embaixo, no centro da tela, CENTRALIZADA, nesta ordem: esquiva, habilidades da classe, ultimate e
-- poções. O HudController (esquiva, habilidades e ultimate) e o PotionController (poções) usam as posições daqui.

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Balance")
local Classes = require(Balance:WaitForChild("Classes"))
local Shop = require(Balance:WaitForChild("Shop"))

local ICON_SIZE = 64
local STEP = 80 -- distância entre o início de um ícone e o do próximo (64 + 16 de espaço)
local BOTTOM_OFFSET = -80

local ActionBar = {}

ActionBar.iconSize = ICON_SIZE

local function abilityCount(): number
	return #Classes.byId[Classes.defaultClassId].abilities
end

-- Posição (canto superior esquerdo) do ícone número `slot` (1 = esquiva; ver as funções abaixo).
function ActionBar.position(slot: number): UDim2
	local count = 1 + abilityCount() + 1 + #Shop.order
	local totalWidth = count * STEP - (STEP - ICON_SIZE)
	return UDim2.new(0.5, -totalWidth / 2 + (slot - 1) * STEP, 1, BOTTOM_OFFSET)
end

-- Slot da habilidade número `index` da classe (1 = primeira).
function ActionBar.abilitySlot(index: number): number
	return 1 + index
end

function ActionBar.ultimateSlot(): number
	return 2 + abilityCount()
end

-- Slot da poção número `index` (ordem de Shop.order).
function ActionBar.potionSlot(index: number): number
	return 2 + abilityCount() + index
end

return table.freeze(ActionBar)
