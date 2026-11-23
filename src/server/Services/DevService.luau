--!strict
-- Ferramentas de desenvolvedor para TESTES. Só existem dentro do Roblox Studio (RunService:IsStudio()):
-- no jogo publicado este serviço não faz nada, então não abre brecha para trapaça.
--
-- Por que existe: testes pelo MCP (`execute_luau`) rodam numa cópia dos módulos, sem acesso ao estado real do
-- jogo. Este serviço expõe um BindableFunction em ServerStorage (que os clientes nunca enxergam) para o teste
-- chamar os sistemas REAIS. Uso no datamodel Server:
--   local dev = game.ServerStorage.DevTools.Invoke
--   dev:Invoke("SetAttributes", player, { Defense = 100 })
--   local dano = dev:Invoke("DamagePlayer", player, 13.8) -- dano efetivamente aplicado (0 se invencível)

--   dev:Invoke("SaveNow", player)               -- salva agora (espera terminar)
--   dev:Invoke("ReadStored", "User_123")        -- valor cru no DataStore (JSON) para conferir o que foi salvo
--   Testes de trava (só chaves "Test_..."): "WriteStored"(key, valor), "LoadKey"(key), "SaveKey"(key), "SessionId"
--   dev:Invoke("GetStats", player)              -- JSON: atributos distribuídos, do equipamento, efetivos, Poder, máximos
--   dev:Invoke("DamagePreview", player, 100)    -- dano de um golpe base 100 (sem crítico e sem a Defesa do alvo)
--   dev:Invoke("SnapshotProfile", player)       -- guarda o perfil (conta inteira) antes de um teste
--   dev:Invoke("RestoreProfile", player)        -- devolve o perfil guardado (no lugar: Gold, itens, equipamento...)
--   dev:Invoke("RestoreFromJson", player, json) -- idem, a partir do JSON de um ReadStored (teste que reinicia o Play)
--   Equipamento (passa pelas regras REAIS do GearService):
--   dev:Invoke("ListGear", player)                          -- JSON: peças da conta, dono de cada uma, baú
--   dev:Invoke("GiveGear", player, "GuardianHelm", "Rare")  -- dá uma peça (aviso na tela; baú cheio = Gold)
--   dev:Invoke("FillChest", player, n, defId?, raridade?)   -- dá n peças sem aviso (testar o baú cheio)
--   dev:Invoke("Equip", player, id) / ("Unequip", player, "Helmet") -- mensagem do resultado (ignora o anti-spam)
--   Drops: "SampleDrops"(classId, n) (contagem por peça, sem dar nada), "SampleLoot"("BossRare"|"Mob", sorte, n)
--   (fração sorteada), "RollBossLoot"(player, sorte) (dá de verdade), "ForceMobDrop"(player) (o próximo mob perto
--   dá peça), "GoToFloor"(n, player?) (pula a run do jogador, ou a única run ativa, para o andar n), "RejoinRun"(player)
--   (sai e volta à run: devolve se ficou com direito ao boss), "BossEligible"(player)
--   Runs (várias por servidor): "Runs"() (JSON: runs ativas, andar, vidas, participantes e esperas nos portais) e
--   "SetAllFriends"(true/false) (todos contam como amigos: os jogadores de teste do Studio não são amigos).
--   Mobs: "SpawnMob"(player, mobId, distância?, força?) (mob REAL com IA, a `distância` studs à frente do jogador,
--   padrão 20; força = multiplicador de vida e dano, padrão 1; fica em workspace.DevMobs: apague com
--   ClearAllChildren). Os mobs do andar têm os Attributes MobId e Room (índice da sala): conte-os pelo workspace.
--   Torres: "UnlockTower"(player, torre) (acesso real: salva e avisa), "LockTower"(player, torre) (tira o acesso),
--   "ForceKeyDrop"(player) (a próxima chave sorteada cai), "SetLevel"(player, nível) (só o nível; XP zerado).
--   Forja: "Enhance"(player, id, forçar?) (uma tentativa REAL, cobra Gold; forçar = true/false fixa o sorteio;
--   ignora a distância e o anti-spam), "SetEnhance"(player, id, nível) (define direto, sem custo),
--   "TransferEnhance"(player, deId, paraId) (troca real dos níveis, cobra Gold; ignora a distância)
--   Gemas (regras REAIS do GemService; ignoram distância e anti-spam; devolvem "ok: ..." / "recusado: ..."):
--   "BuyGem"(player, "Strength") e "BuyRemover"(player, nível) (cobram Gold), "SocketGem"(player, id, atributo,
--   nível), "ExtractGem"(player, id), "FuseGems"(player, atributo, nível). Sem custo: "GiveGems"(player, atributo,
--   nível, n) (qualquer nível: as Nv2+ ainda não caem) e "GiveRemovers"(player, nível, n).
--   Venda (regras reais, sem distância): "SellGear"(player, id) (peça do baú; a fortalecida vale a base + parte
--   das tentativas), "SellGem"(player, atributo, nível) e "SellRemover"(player, nível) (vende 1).
--   Destruir (o que o arrastar para fora da mochila pede): "DestroyGear"(player, id), "DestroyGems"(player,
--   atributo, nível) e "DestroyRemovers"(player, nível) (pilha inteira).

local DataStoreService: DataStoreService = game:GetService("DataStoreService")
local HttpService: HttpService = game:GetService("HttpService")
local RunService: RunService = game:GetService("RunService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Formulas = require(game:GetService("ReplicatedStorage").Shared.Formulas)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local GearService = require(script.Parent.GearService)
local GemService = require(script.Parent.GemService)
local EnemyService = require(script.Parent.EnemyService)
local Mobs = require(game:GetService("ReplicatedStorage").Shared.Balance.Mobs)
local ProgressionService = require(script.Parent.ProgressionService)
local RunSessionService = require(script.Parent.RunSessionService)
local TowerService = require(script.Parent.TowerService)

local function store(): DataStore
	return DataStoreService:GetDataStore(DataService.getStoreName())
end

local function assertTestKey(key: string)
	assert(string.sub(key, 1, 5) == "Test_", "DevTools: escrita só em chaves de teste (Test_...)")
end

local DevService = {}

type Command = (...any) -> any

-- Perfis guardados por SnapshotProfile (só nesta sessão do Studio).
local snapshots: { [Player]: PlayerSchema.Profile } = {}

-- Devolve o perfil guardado NO LUGAR: DataService e ProgressionService seguram a mesma tabela (e o personagem ativo).
local function restoreInPlace(player: Player, saved: PlayerSchema.Profile): boolean
	local profile, _ = ProgressionService.getLoadedProfile(player)
	if not profile then
		return false
	end
	local copy = PlayerSchema.deepCopy(saved)
	profile.gold = copy.gold
	profile.inventory = copy.inventory
	profile.gear = copy.gear
	profile.gems = copy.gems
	profile.removers = copy.removers
	profile.towers = copy.towers
	-- O contador nunca volta: os ids dados durante o teste não são reutilizados depois.
	profile.nextGearId = math.max(profile.nextGearId, copy.nextGearId)
	for index, savedCharacter in copy.characters do
		local character = profile.characters[index]
		if character then
			character.level = savedCharacter.level
			character.xp = savedCharacter.xp
			character.unspentPoints = savedCharacter.unspentPoints
			character.attributes = savedCharacter.attributes
			character.equipped = savedCharacter.equipped
		end
	end
	ProgressionService.refreshEquipment(player)
	GearService.publish(player)
	TowerService.publish(player)
	return true
end

local function parseRarityOrCommon(value: unknown): Types.Rarity
	return Formulas.parseRarity(value) or "Common"
end

local function gemArgs(attribute: unknown, level: unknown): (Types.GemAttribute, number)
	local parsedAttribute: Types.GemAttribute? = Formulas.parseGemAttribute(attribute)
	local parsedLevel = Formulas.parseGemLevel(level)
	assert(parsedAttribute and parsedLevel, `DevTools: gema inválida ({attribute}, {level})`)
	return parsedAttribute, parsedLevel
end

local function outcomeText(ok: boolean, message: string): string
	return `{if ok then "ok" else "recusado"}: {message}`
end

-- Pasta dos mobs criados pelo "SpawnMob".
local function devMobsFolder(): Folder
	local existing = workspace:FindFirstChild("DevMobs")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevMobs"
	folder.Parent = workspace
	return folder
end

local COMMANDS: { [string]: Command } = {
	SetAttributes = function(player: Player, values: { [string]: number }): boolean
		ProgressionService.debugSetAttributes(player, values)
		return true
	end,

	-- Passa pelo MESMO caminho de dano que os mobs e o boss usam (Defesa, invencibilidade da esquiva).
	DamagePlayer = function(player: Player, rawDamage: number): number
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return -1
		end
		local before = humanoid.Health
		CombatService.damagePlayer(player, rawDamage)
		return before - humanoid.Health
	end,

	-- resource = "Stamina" ou "Mana"
	SetResource = function(player: Player, resource: string, value: number): boolean
		if resource ~= "Stamina" and resource ~= "Mana" then
			return false
		end
		CombatService.debugSetResource(player, resource, value)
		return true
	end,

	-- Carga da barra de ultimate (0 a 100).
	SetUltimate = function(player: Player, value: number): boolean
		CombatService.debugSetUltimate(player, value)
		return true
	end,

	GiveGold = function(player: Player, amount: number): number
		ProgressionService.addGold(player, amount)
		return ProgressionService.getGold(player)
	end,

	SaveNow = function(player: Player): boolean
		return DataService.saveNow(player)
	end,

	ReadStored = function(key: string): string
		local value = store():GetAsync(key)
		return if value == nil then "nil" else HttpService:JSONEncode(value)
	end,

	WriteStored = function(key: string, value: any): boolean
		assertTestKey(key)
		store():SetAsync(key, value)
		return true
	end,

	LoadKey = function(key: string): string
		assertTestKey(key)
		local status = DataService.loadKey(key)
		return status
	end,

	SaveKey = function(key: string): string
		assertTestKey(key)
		local ok, err = DataService.saveKey(key, PlayerSchema.newProfile(), false)
		return if ok then "ok" else `falhou: {err}`
	end,

	SessionId = function(): string
		return DataService.getSessionId()
	end,

	GetStats = function(player: Player): string
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return HttpService:JSONEncode({
			distributed = ProgressionService.getDistributedAttributes(player),
			gear = ProgressionService.getGearAttributes(player),
			effective = ProgressionService.getEffectiveAttributes(player),
			weaponPowerPhysical = ProgressionService.getWeaponPower(player, "Physical"),
			weaponPowerMagical = ProgressionService.getWeaponPower(player, "Magical"),
			maxHealth = if humanoid then humanoid.MaxHealth else -1,
			maxStamina = player:GetAttribute("MaxStamina"),
			maxMana = player:GetAttribute("MaxMana"),
			resonance = ProgressionService.getResonance(player),
		})
	end,

	-- damageType = "Physical" (padrão) ou "Magical".
	DamagePreview = function(player: Player, baseDamage: number, damageType: string?): number
		local kind: Types.DamageType = if damageType == "Magical" then "Magical" else "Physical"
		return CombatService.debugRawDamage(player, baseDamage, kind)
	end,

	SnapshotProfile = function(player: Player): string
		local profile, _ = ProgressionService.getLoadedProfile(player)
		assert(profile, "DevTools: perfil ainda não carregado")
		snapshots[player] = PlayerSchema.deepCopy(profile)
		return HttpService:JSONEncode(snapshots[player])
	end,

	RestoreProfile = function(player: Player): boolean
		local saved = snapshots[player]
		assert(saved, "DevTools: nenhum SnapshotProfile deste jogador")
		return restoreInPlace(player, saved)
	end,

	-- Devolve um perfil a partir do JSON de um backup (ex.: o "ReadStored" feito antes do teste). Para testes que
	-- reiniciam o Play: o SnapshotProfile vive só na sessão de Play em que foi feito. Passa pelo reconcile (migra
	-- versões antigas). Depois, "SaveNow" para gravar.
	RestoreFromJson = function(player: Player, json: string): boolean
		local saved = PlayerSchema.reconcile(HttpService:JSONDecode(json))
		return restoreInPlace(player, saved)
	end,

	ListGear = function(player: Player): string
		local profile, _ = ProgressionService.getLoadedProfile(player)
		assert(profile, "DevTools: perfil ainda não carregado")
		local list = {}
		for _, piece in profile.gear do
			local owner, slot = PlayerSchema.ownerOf(profile, piece.id)
			table.insert(list, {
				id = piece.id,
				defId = piece.defId,
				rarity = piece.rarity,
				enhance = piece.enhance,
				gem = piece.gem,
				owner = owner,
				slot = slot,
				known = PlayerSchema.defOf(piece) ~= nil,
			})
		end
		return HttpService:JSONEncode({
			chest = PlayerSchema.chestCount(profile),
			nextGearId = profile.nextGearId,
			gear = list,
			equipped = profile.characters[profile.activeSlot].equipped,
			gems = profile.gems,
			removers = profile.removers,
		})
	end,

	GiveGear = function(player: Player, defId: string, rarity: string?): string
		local result = GearService.grant(player, defId, parseRarityOrCommon(rarity), "Dev")
		return HttpService:JSONEncode(result or { error = "perfil não carregado" })
	end,

	FillChest = function(player: Player, count: number, defId: string?, rarity: string?): string
		local stored, converted = 0, 0
		for _ = 1, count do
			local result =
				GearService.grant(player, defId or "CombatantHeadband", parseRarityOrCommon(rarity), "Dev", true)
			if result and result.stored then
				stored += 1
			elseif result then
				converted += 1
			end
		end
		GearService.publish(player)
		return HttpService:JSONEncode({ stored = stored, converted = converted })
	end,

	Equip = function(player: Player, id: number): string
		local ok, message = GearService.tryEquip(player, id)
		return `{if ok then "ok" else "recusado"}: {message or "(sem mensagem)"}`
	end,

	SampleDrops = function(classId: string, count: number, towerId: number?): string
		local counts: { [string]: number } = {}
		for _ = 1, count do
			local defId = GearService.rollDefId(classId, towerId or 1)
			counts[defId] = (counts[defId] or 0) + 1
		end
		return HttpService:JSONEncode(counts)
	end,

	SampleLoot = function(kind: string, luck: number, count: number): number
		local hits = 0
		for _ = 1, count do
			local hit = if kind == "BossRare"
				then GearService.rollBossRarity(luck) == "Rare"
				else GearService.rollsMobDrop(luck)
			if hit then
				hits += 1
			end
		end
		return hits / count
	end,

	RollBossLoot = function(player: Player, luck: number?, towerId: number?): string
		return HttpService:JSONEncode(
			GearService.rollBossLoot(player, luck or 0, towerId or 1) or { error = "perfil não carregado" }
		)
	end,

	ForceMobDrop = function(player: Player): boolean
		GearService.debugForceNextMobDrop(player)
		return true
	end,

	GoToFloor = function(floorNumber: number, player: Player?): boolean
		return RunSessionService.debugGoToFloor(floorNumber, player)
	end,

	SetAllFriends = function(enabled: boolean): boolean
		RunSessionService.debugSetAllFriends(enabled == true)
		return enabled == true
	end,

	Runs = function(): string
		return HttpService:JSONEncode(RunSessionService.debugSummary())
	end,

	SpawnMob = function(player: Player, mobId: string, distance: number?, strength: number?): string
		local def = Mobs[mobId]
		assert(def, `mob desconhecido: {mobId}`)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		assert(root and root:IsA("BasePart"), "jogador sem personagem")
		local folder = devMobsFolder()
		local position = root.Position + root.CFrame.LookVector * (distance or 20)
		local model = EnemyService.spawn(def, CFrame.lookAt(position, root.Position), strength or 1, folder)
		return model:GetFullName()
	end,

	UnlockTower = function(player: Player, towerId: number): boolean
		return TowerService.unlock(player, towerId, "Dev")
	end,

	LockTower = function(player: Player, towerId: number): boolean
		return TowerService.debugLock(player, towerId)
	end,

	ForceKeyDrop = function(player: Player): boolean
		TowerService.debugForceNextKey(player)
		return true
	end,

	SetLevel = function(player: Player, level: number): number
		return ProgressionService.debugSetLevel(player, level)
	end,

	RejoinRun = function(player: Player): boolean
		return RunSessionService.debugRejoin(player)
	end,

	BossEligible = function(player: Player): boolean
		return RunSessionService.isBossEligible(player)
	end,

	Unequip = function(player: Player, slot: string): string
		local parsed: Types.EquipSlot? = Formulas.parseEquipSlot(slot)
		assert(parsed, `DevTools: slot inválido {slot}`)
		local ok, message = GearService.tryUnequip(player, parsed)
		return `{if ok then "ok" else "recusado"}: {message or "(sem mensagem)"}`
	end,

	Enhance = function(player: Player, id: number, forced: boolean?): string
		local outcome, message = GearService.tryEnhance(player, id, forced)
		return `{outcome}: {message}`
	end,

	SetEnhance = function(player: Player, id: number, enhance: number): boolean
		return GearService.debugSetEnhance(player, id, enhance)
	end,

	TransferEnhance = function(player: Player, fromId: number, toId: number): string
		return outcomeText(GearService.tryTransfer(player, fromId, toId))
	end,

	BuyGem = function(player: Player, attribute: string): string
		local parsed: Types.GemAttribute, _ = gemArgs(attribute, 1)
		return outcomeText(GemService.tryBuyGem(player, parsed))
	end,

	BuyRemover = function(player: Player, level: number): string
		local _, parsed = gemArgs("Strength", level)
		return outcomeText(GemService.tryBuyRemover(player, parsed))
	end,

	SocketGem = function(player: Player, id: number, attribute: string, level: number): string
		local parsedAttribute: Types.GemAttribute, parsedLevel = gemArgs(attribute, level)
		return outcomeText(GemService.trySocket(player, id, parsedAttribute, parsedLevel))
	end,

	ExtractGem = function(player: Player, id: number): string
		return outcomeText(GemService.tryExtract(player, id))
	end,

	FuseGems = function(player: Player, attribute: string, level: number): string
		local parsedAttribute: Types.GemAttribute, parsedLevel = gemArgs(attribute, level)
		return outcomeText(GemService.tryFuse(player, parsedAttribute, parsedLevel))
	end,

	GiveGems = function(player: Player, attribute: string, level: number, amount: number?): string
		local parsedAttribute: Types.GemAttribute, parsedLevel = gemArgs(attribute, level)
		return GemService.debugGiveGems(player, parsedAttribute, parsedLevel, amount or 1) or "perfil não carregado"
	end,

	GiveRemovers = function(player: Player, level: number, amount: number?): string
		local _, parsedLevel = gemArgs("Strength", level)
		return GemService.debugGiveRemovers(player, parsedLevel, amount or 1) or "perfil não carregado"
	end,

	SellGem = function(player: Player, attribute: string, level: number): string
		local parsedAttribute: Types.GemAttribute, parsedLevel = gemArgs(attribute, level)
		return outcomeText(GemService.trySellGem(player, parsedAttribute, parsedLevel))
	end,

	SellRemover = function(player: Player, level: number): string
		local _, parsedLevel = gemArgs("Strength", level)
		return outcomeText(GemService.trySellRemover(player, parsedLevel))
	end,

	SellGear = function(player: Player, id: number): string
		return outcomeText(GearService.trySell(player, id))
	end,

	DestroyGear = function(player: Player, id: number): string
		return outcomeText(GearService.tryDestroy(player, id))
	end,

	DestroyGems = function(player: Player, attribute: string, level: number): string
		local parsedAttribute: Types.GemAttribute, parsedLevel = gemArgs(attribute, level)
		return outcomeText(GemService.tryDestroyGems(player, parsedAttribute, parsedLevel))
	end,

	DestroyRemovers = function(player: Player, level: number): string
		local _, parsedLevel = gemArgs("Strength", level)
		return outcomeText(GemService.tryDestroyRemovers(player, parsedLevel))
	end,
}

function DevService.init()
	if not RunService:IsStudio() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevTools"
	local invoke = Instance.new("BindableFunction")
	invoke.Name = "Invoke"
	invoke.OnInvoke = function(command: string, ...: any): any
		local handler = COMMANDS[command]
		assert(handler, `DevTools: comando desconhecido '{command}'`)
		return handler(...)
	end
	invoke.Parent = folder
	folder.Parent = ServerStorage
	print("[Dev] ferramentas de teste ativas (só no Studio)")
end

function DevService.start() end

return DevService
