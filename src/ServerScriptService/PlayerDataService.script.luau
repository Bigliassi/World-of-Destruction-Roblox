--!strict
--[[
	PlayerDataService.script.luau
	World of Destruction (Roblox)
	
	Persists player Cash, High Score (ChaosScore), MaxCombo, Unlocked Vehicles,
	Equipped Vehicle, Selected Paint, and all 5 Garage Upgrade Levels (Engine,
	Armor, Nitro, Plow, Magnet) using Roblox DataStoreService.
	
	Includes an automatic in-memory fallback when running in local Roblox Studio
	without Studio Access to API Services enabled, plus auto-saving, BindToClose
	protection, and clean Bindable/Attribute synchronization across all server scripts.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

--------------------------------------------------------------------------------
-- Constants & Schema
--------------------------------------------------------------------------------
local DATASTORE_NAME = "WorldOfDestruction_PlayerData_v1"
local SCHEMA_VERSION = 1
local AUTOSAVE_INTERVAL = 90 -- seconds
local STARTING_CASH = 500

export type UpgradeTracks = {
	Engine: number,
	Armor: number,
	Nitro: number,
	Plow: number,
	Magnet: number,
}

export type PlayerProfile = {
	SchemaVersion: number,
	Cash: number,
	HighScore: number,
	ChaosScore: number,
	MaxCombo: number,
	TotalDestructions: number,
	CopTakedowns: number,
	MissionsCompleted: number,
	Level: number,
	XP: number,
	TotalXP: number,
	EquippedVehicle: string,
	SelectedPaint: number,
	UnlockedVehicles: { [string]: boolean },
	Upgrades: UpgradeTracks,
	LastSaved: number,
}

local DEFAULT_UPGRADES: UpgradeTracks = {
	Engine = 1,
	Armor = 1,
	Nitro = 1,
	Plow = 1,
	Magnet = 1,
}

local ALL_VEHICLE_IDS = {
	"Compact",
	"Sedan",
	"Muscle",
	"SUV",
	"Pickup",
	"Sports",
	"MonsterTruck",
	"Bulldozer",
	"Tank",
	"sports",
	"sedan",
	"hatchback",
	"suv",
	"pickup",
	"van",
	"boxTruck",
	"motorcycle",
}

local function createDefaultProfile(): PlayerProfile
	return {
		SchemaVersion = SCHEMA_VERSION,
		Cash = STARTING_CASH,
		HighScore = 0,
		ChaosScore = 0,
		MaxCombo = 0,
		TotalDestructions = 0,
		CopTakedowns = 0,
		MissionsCompleted = 0,
		Level = 1,
		XP = 0,
		TotalXP = 0,
		EquippedVehicle = "Compact",
		SelectedPaint = 1,
		UnlockedVehicles = {
			Compact = true,
			Sedan = true,
			sports = true,
			sedan = true,
			hatchback = true,
		},
		Upgrades = {
			Engine = DEFAULT_UPGRADES.Engine,
			Armor = DEFAULT_UPGRADES.Armor,
			Nitro = DEFAULT_UPGRADES.Nitro,
			Plow = DEFAULT_UPGRADES.Plow,
			Magnet = DEFAULT_UPGRADES.Magnet,
		},
		LastSaved = os.time(),
	}
end

--------------------------------------------------------------------------------
-- Shared Infrastructure Helpers (Bindables & Remotes)
--------------------------------------------------------------------------------
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureBindableEvent(parent: Instance, name: string): BindableEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

local function ensureBindableFunction(parent: Instance, name: string): BindableFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BindableFunction") then
		return existing
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = name
	fn.Parent = parent
	return fn
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = parent
	return re
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end

local serverEventsFolder = ensureFolder(ServerStorage, "Events")
local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")

-- Root & Folder Bindables for seamless discovery across server scripts
local PlayerDataLoadedEvent = ensureBindableEvent(ServerStorage, "PlayerDataLoadedEvent")
local PlayerDataUpdatedEvent = ensureBindableEvent(ServerStorage, "PlayerDataUpdatedEvent")
local UpdatePlayerDataEvent = ensureBindableEvent(ServerStorage, "UpdatePlayerDataEvent")
local GetPlayerDataFunction = ensureBindableFunction(ServerStorage, "GetPlayerDataFunction")
local SavePlayerDataEvent = ensureBindableEvent(ServerStorage, "SavePlayerDataEvent")

-- Mirror aliases in ServerStorage.Events
ensureBindableEvent(serverEventsFolder, "PlayerDataLoadedEvent")
ensureBindableEvent(serverEventsFolder, "UpdatePlayerDataEvent")

-- Client Remotes
local ProfileSyncRemote = ensureRemoteEvent(remotesFolder, "ProfileSync")
local WalletUpdatedRemote = ensureRemoteEvent(remotesFolder, "WalletUpdated")
local GetProfileRemote = ensureRemoteFunction(remotesFolder, "GetPlayerProfile")

--------------------------------------------------------------------------------
-- DataStore Initialization with Automatic Studio In-Memory Fallback
--------------------------------------------------------------------------------
local playerStore: GlobalDataStore? = nil
local usingInMemoryFallback = false
local inMemoryStore: { [string]: PlayerProfile } = {}
local activeProfiles: { [number]: PlayerProfile } = {}
local dirtyFlags: { [number]: boolean } = {}
local attributeConnections: { [number]: { RBXScriptConnection } } = {}

local function initDataStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok and result then
		playerStore = result
	else
		usingInMemoryFallback = true
		warn(string.format(
			"[PlayerDataService] DataStoreService unavailable (%s). Using automatic in-memory fallback store.",
			tostring(result)
		))
	end
end

initDataStore()

--------------------------------------------------------------------------------
-- Profile Sanitization & Migration
--------------------------------------------------------------------------------
local function clampUpgrade(level: any): number
	local n = tonumber(level) or 1
	return math.clamp(math.floor(n), 1, 5)
end

local function reconcileProfile(raw: any): PlayerProfile
	local profile = createDefaultProfile()
	if type(raw) ~= "table" then
		return profile
	end

	profile.SchemaVersion = SCHEMA_VERSION
	profile.Cash = math.max(0, math.floor(tonumber(raw.Cash) or STARTING_CASH))
	profile.ChaosScore = math.max(0, math.floor(tonumber(raw.ChaosScore) or 0))
	profile.HighScore = math.max(profile.ChaosScore, math.floor(tonumber(raw.HighScore) or 0))
	profile.MaxCombo = math.max(0, math.floor(tonumber(raw.MaxCombo) or 0))
	profile.TotalDestructions = math.max(0, math.floor(tonumber(raw.TotalDestructions) or 0))
	profile.CopTakedowns = math.max(0, math.floor(tonumber(raw.CopTakedowns) or 0))
	profile.MissionsCompleted = math.max(0, math.floor(tonumber(raw.MissionsCompleted) or 0))
	profile.Level = math.clamp(math.floor(tonumber(raw.Level) or 1), 1, 50)
	profile.XP = math.max(0, math.floor(tonumber(raw.XP) or 0))
	profile.TotalXP = math.max(profile.XP, math.floor(tonumber(raw.TotalXP) or 0))
	profile.SelectedPaint = math.clamp(math.floor(tonumber(raw.SelectedPaint) or 1), 0, 8)

	if type(raw.UnlockedVehicles) == "table" then
		for k, v in pairs(raw.UnlockedVehicles) do
			if type(k) == "string" and v == true then
				profile.UnlockedVehicles[k] = true
			elseif type(k) == "number" and type(v) == "string" then
				profile.UnlockedVehicles[v] = true
			end
		end
	end
	-- Ensure starter vehicles remain unlocked
	profile.UnlockedVehicles["Compact"] = true
	profile.UnlockedVehicles["Sedan"] = true
	profile.UnlockedVehicles["sports"] = true
	profile.UnlockedVehicles["sedan"] = true
	profile.UnlockedVehicles["hatchback"] = true

	local equipped = if type(raw.EquippedVehicle) == "string" and raw.EquippedVehicle ~= ""
		then raw.EquippedVehicle
		else "Compact"
	if not profile.UnlockedVehicles[equipped] then
		equipped = "Compact"
	end
	profile.EquippedVehicle = equipped

	if type(raw.Upgrades) == "table" then
		profile.Upgrades.Engine = clampUpgrade(raw.Upgrades.Engine)
		profile.Upgrades.Armor = clampUpgrade(raw.Upgrades.Armor)
		profile.Upgrades.Nitro = clampUpgrade(raw.Upgrades.Nitro)
		profile.Upgrades.Plow = clampUpgrade(raw.Upgrades.Plow)
		profile.Upgrades.Magnet = clampUpgrade(raw.Upgrades.Magnet or raw.Upgrades.CashMagnet)
	end

	profile.LastSaved = tonumber(raw.LastSaved) or os.time()
	return profile
end

local function deepCopyProfile(src: PlayerProfile): PlayerProfile
	local copy = createDefaultProfile()
	copy.SchemaVersion = src.SchemaVersion
	copy.Cash = src.Cash
	copy.HighScore = src.HighScore
	copy.ChaosScore = src.ChaosScore
	copy.MaxCombo = src.MaxCombo
	copy.TotalDestructions = src.TotalDestructions
	copy.CopTakedowns = src.CopTakedowns
	copy.MissionsCompleted = src.MissionsCompleted
	copy.Level = src.Level
	copy.XP = src.XP
	copy.TotalXP = src.TotalXP
	copy.EquippedVehicle = src.EquippedVehicle
	copy.SelectedPaint = src.SelectedPaint
	copy.LastSaved = src.LastSaved

	copy.UnlockedVehicles = {}
	for k, v in pairs(src.UnlockedVehicles) do
		copy.UnlockedVehicles[k] = v
	end

	copy.Upgrades = {
		Engine = src.Upgrades.Engine,
		Armor = src.Upgrades.Armor,
		Nitro = src.Upgrades.Nitro,
		Plow = src.Upgrades.Plow,
		Magnet = src.Upgrades.Magnet,
	}
	return copy
end

--------------------------------------------------------------------------------
-- Attribute & Leaderstats Synchronization
--------------------------------------------------------------------------------
local function getUnlockedListJson(unlockedMap: { [string]: boolean }): string
	local list = {}
	for _, vehicleId in ipairs(ALL_VEHICLE_IDS) do
		if unlockedMap[vehicleId] and not table.find(list, vehicleId) then
			table.insert(list, vehicleId)
		end
	end
	for k, isUnlocked in pairs(unlockedMap) do
		if isUnlocked and not table.find(list, k) then
			table.insert(list, k)
		end
	end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(list)
	end)
	return if ok then encoded else '["Compact","Sedan","sports","sedan"]'
end

local function decodeUnlockedJson(jsonStr: string): { [string]: boolean }
	local map: { [string]: boolean } = {
		Compact = true,
		Sedan = true,
		sports = true,
		sedan = true,
		hatchback = true,
	}
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(jsonStr)
	end)
	if ok and type(decoded) == "table" then
		for k, v in pairs(decoded) do
			if type(k) == "number" and type(v) == "string" then
				map[v] = true
			elseif type(k) == "string" and v == true then
				map[k] = true
			end
		end
	end
	return map
end

local function ensureLeaderstats(player: Player): Folder
	local ls = player:FindFirstChild("leaderstats")
	if not (ls and ls:IsA("Folder")) then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local function ensureIntValue(name: string, defaultVal: number): IntValue
		local v = ls:FindFirstChild(name)
		if v and v:IsA("IntValue") then
			return v
		end
		local iv = Instance.new("IntValue")
		iv.Name = name
		iv.Value = defaultVal
		iv.Parent = ls
		return iv
	end

	ensureIntValue("Cash", STARTING_CASH)
	ensureIntValue("ChaosScore", 0)
	ensureIntValue("MaxCombo", 0)
	ensureIntValue("HeatLevel", 0)
	return ls
end

local isApplyingProfileToPlayer: { [number]: boolean } = {}

local function applyProfileToPlayer(player: Player, profile: PlayerProfile)
	isApplyingProfileToPlayer[player.UserId] = true

	local ls = ensureLeaderstats(player)
	local cashVal = ls:FindFirstChild("Cash") :: IntValue?
	local chaosVal = ls:FindFirstChild("ChaosScore") :: IntValue?
	local maxComboVal = ls:FindFirstChild("MaxCombo") :: IntValue?

	if cashVal then
		cashVal.Value = profile.Cash
	end
	if chaosVal then
		chaosVal.Value = profile.ChaosScore
	end
	if maxComboVal then
		maxComboVal.Value = profile.MaxCombo
	end

	-- Core Economy & Progression Attributes
	player:SetAttribute("Cash", profile.Cash)
	player:SetAttribute("ChaosScore", profile.ChaosScore)
	player:SetAttribute("HighScore", profile.HighScore)
	player:SetAttribute("MaxCombo", profile.MaxCombo)
	player:SetAttribute("TotalDestructions", profile.TotalDestructions)
	player:SetAttribute("CopTakedowns", profile.CopTakedowns)
	player:SetAttribute("MissionsCompleted", profile.MissionsCompleted)
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("XP", profile.XP)
	player:SetAttribute("TotalXP", profile.TotalXP)

	-- Garage & Vehicle Attributes
	player:SetAttribute("EquippedVehicle", profile.EquippedVehicle)
	player:SetAttribute("SelectedVehicle", profile.EquippedVehicle)
	player:SetAttribute("SelectedPaint", profile.SelectedPaint)
	player:SetAttribute("UnlockedVehicles", getUnlockedListJson(profile.UnlockedVehicles))

	for _, vehicleId in ipairs(ALL_VEHICLE_IDS) do
		player:SetAttribute("Unlocked_" .. vehicleId, profile.UnlockedVehicles[vehicleId] == true)
	end

	-- 5 Upgrade Tracks (supports Upgrade_<Track>, <Track>Level, and CashMagnet aliases)
	player:SetAttribute("Upgrade_Engine", profile.Upgrades.Engine)
	player:SetAttribute("Upgrade_Armor", profile.Upgrades.Armor)
	player:SetAttribute("Upgrade_Nitro", profile.Upgrades.Nitro)
	player:SetAttribute("Upgrade_Plow", profile.Upgrades.Plow)
	player:SetAttribute("Upgrade_Magnet", profile.Upgrades.Magnet)
	player:SetAttribute("Upgrade_CashMagnet", profile.Upgrades.Magnet)

	player:SetAttribute("EngineLevel", profile.Upgrades.Engine)
	player:SetAttribute("ArmorLevel", profile.Upgrades.Armor)
	player:SetAttribute("NitroLevel", profile.Upgrades.Nitro)
	player:SetAttribute("PlowLevel", profile.Upgrades.Plow)
	player:SetAttribute("MagnetLevel", profile.Upgrades.Magnet)
	player:SetAttribute("CashMagnetLevel", profile.Upgrades.Magnet)

	player:SetAttribute("DataLoaded", true)

	isApplyingProfileToPlayer[player.UserId] = false

	-- Notify client UI
	local snapshot = deepCopyProfile(profile)
	ProfileSyncRemote:FireClient(player, snapshot)
	WalletUpdatedRemote:FireClient(player, profile.Cash, 0, "ProfileLoaded")
end

local function captureAttributesIntoProfile(player: Player, profile: PlayerProfile)
	local cashAttr = player:GetAttribute("Cash")
	if type(cashAttr) == "number" then
		profile.Cash = math.max(0, math.floor(cashAttr))
	end

	local chaosAttr = player:GetAttribute("ChaosScore")
	if type(chaosAttr) == "number" then
		profile.ChaosScore = math.max(0, math.floor(chaosAttr))
		if profile.ChaosScore > profile.HighScore then
			profile.HighScore = profile.ChaosScore
			player:SetAttribute("HighScore", profile.HighScore)
		end
	end

	local highScoreAttr = player:GetAttribute("HighScore")
	if type(highScoreAttr) == "number" and highScoreAttr > profile.HighScore then
		profile.HighScore = math.floor(highScoreAttr)
	end

	local maxComboAttr = player:GetAttribute("MaxCombo")
	if type(maxComboAttr) == "number" and maxComboAttr > profile.MaxCombo then
		profile.MaxCombo = math.floor(maxComboAttr)
	end

	local totalDestAttr = player:GetAttribute("TotalDestructions")
	if type(totalDestAttr) == "number" then
		profile.TotalDestructions = math.max(profile.TotalDestructions, math.floor(totalDestAttr))
	end

	local copTakedownsAttr = player:GetAttribute("CopTakedowns")
	if type(copTakedownsAttr) == "number" then
		profile.CopTakedowns = math.max(profile.CopTakedowns, math.floor(copTakedownsAttr))
	end

	local missionsAttr = player:GetAttribute("MissionsCompleted")
	if type(missionsAttr) == "number" then
		profile.MissionsCompleted = math.max(profile.MissionsCompleted, math.floor(missionsAttr))
	end

	local lvlAttr = player:GetAttribute("Level")
	if type(lvlAttr) == "number" then
		profile.Level = math.clamp(math.floor(lvlAttr), 1, 50)
	end

	local xpAttr = player:GetAttribute("XP")
	if type(xpAttr) == "number" then
		profile.XP = math.max(0, math.floor(xpAttr))
	end

	local totalXpAttr = player:GetAttribute("TotalXP")
	if type(totalXpAttr) == "number" then
		profile.TotalXP = math.max(profile.TotalXP, math.floor(totalXpAttr))
	end

	local equippedAttr = player:GetAttribute("EquippedVehicle")
	if type(equippedAttr) == "string" and equippedAttr ~= "" then
		profile.EquippedVehicle = equippedAttr
	end

	local paintAttr = player:GetAttribute("SelectedPaint")
	if type(paintAttr) == "number" then
		profile.SelectedPaint = math.clamp(math.floor(paintAttr), 0, 8)
	end

	local unlockedJson = player:GetAttribute("UnlockedVehicles")
	if type(unlockedJson) == "string" and unlockedJson ~= "" then
		profile.UnlockedVehicles = decodeUnlockedJson(unlockedJson)
	end

	for _, track in ipairs({ "Engine", "Armor", "Nitro", "Plow", "Magnet" }) do
		local lvl = player:GetAttribute("Upgrade_" .. track) or player:GetAttribute(track .. "Level")
		if track == "Magnet" and lvl == nil then
			lvl = player:GetAttribute("Upgrade_CashMagnet") or player:GetAttribute("CashMagnetLevel")
		end
		if type(lvl) == "number" then
			(profile.Upgrades :: any)[track] = clampUpgrade(lvl)
		end
	end
end

--------------------------------------------------------------------------------
-- Load & Save Operations (DataStore + In-Memory Studio Fallback)
--------------------------------------------------------------------------------
local function getStoreKey(userId: number): string
	return "Player_" .. tostring(userId)
end

local function loadPlayerProfile(player: Player): PlayerProfile
	local key = getStoreKey(player.UserId)

	if not usingInMemoryFallback and playerStore then
		local ok, savedData = pcall(function()
			return playerStore:GetAsync(key)
		end)
		if ok then
			if savedData ~= nil then
				local profile = reconcileProfile(savedData)
				inMemoryStore[key] = deepCopyProfile(profile)
				return profile
			else
				local fresh = createDefaultProfile()
				inMemoryStore[key] = deepCopyProfile(fresh)
				return fresh
			end
		else
			warn(string.format(
				"[PlayerDataService] GetAsync failed for %s (%d): %s. Falling back to in-memory store.",
				player.Name,
				player.UserId,
				tostring(savedData)
			))
			usingInMemoryFallback = true
		end
	end

	-- Automatic In-Memory Fallback (for local Roblox Studio without API Services)
	if inMemoryStore[key] then
		return reconcileProfile(inMemoryStore[key])
	end

	local defaultProfile = createDefaultProfile()
	inMemoryStore[key] = deepCopyProfile(defaultProfile)
	return defaultProfile
end

local function savePlayerProfile(player: Player, isLeaving: boolean?): boolean
	local userId = player.UserId
	local profile = activeProfiles[userId]
	if not profile then
		return false
	end

	captureAttributesIntoProfile(player, profile)
	profile.LastSaved = os.time()

	local key = getStoreKey(userId)
	local snapshot = deepCopyProfile(profile)
	inMemoryStore[key] = snapshot
	dirtyFlags[userId] = false

	if not usingInMemoryFallback and playerStore then
		local ok, err = pcall(function()
			playerStore:UpdateAsync(key, function(oldValue: any)
				local reconciledOld = if oldValue then reconcileProfile(oldValue) else nil
				if reconciledOld then
					snapshot.HighScore = math.max(snapshot.HighScore, reconciledOld.HighScore)
					snapshot.MaxCombo = math.max(snapshot.MaxCombo, reconciledOld.MaxCombo)
				end
				return snapshot
			end)
		end)
		if not ok then
			warn(string.format(
				"[PlayerDataService] UpdateAsync failed for %s (%d): %s. Data preserved in memory fallback.",
				player.Name,
				userId,
				tostring(err)
			))
			usingInMemoryFallback = true
		end
	end

	if isLeaving then
		activeProfiles[userId] = nil
		dirtyFlags[userId] = nil
	end

	return true
end

--------------------------------------------------------------------------------
-- Player Attribute Listeners (Keep Profile Live-Synced)
--------------------------------------------------------------------------------
local WATCHED_ATTRIBUTES = {
	"Cash",
	"ChaosScore",
	"HighScore",
	"MaxCombo",
	"TotalDestructions",
	"CopTakedowns",
	"MissionsCompleted",
	"Level",
	"XP",
	"TotalXP",
	"EquippedVehicle",
	"SelectedPaint",
	"UnlockedVehicles",
	"Upgrade_Engine",
	"Upgrade_Armor",
	"Upgrade_Nitro",
	"Upgrade_Plow",
	"Upgrade_Magnet",
	"Upgrade_CashMagnet",
}

local function attachAttributeWatchers(player: Player)
	local conns: { RBXScriptConnection } = {}
	for _, attrName in ipairs(WATCHED_ATTRIBUTES) do
		local conn = player:GetAttributeChangedSignal(attrName):Connect(function()
			if isApplyingProfileToPlayer[player.UserId] then
				return
			end
			local profile = activeProfiles[player.UserId]
			if not profile then
				return
			end
			captureAttributesIntoProfile(player, profile)
			dirtyFlags[player.UserId] = true

			local ls = player:FindFirstChild("leaderstats")
			if ls then
				if attrName == "Cash" then
					local v = ls:FindFirstChild("Cash") :: IntValue?
					if v and v.Value ~= profile.Cash then
						v.Value = profile.Cash
					end
				elseif attrName == "ChaosScore" then
					local v = ls:FindFirstChild("ChaosScore") :: IntValue?
					if v and v.Value ~= profile.ChaosScore then
						v.Value = profile.ChaosScore
					end
				elseif attrName == "MaxCombo" then
					local v = ls:FindFirstChild("MaxCombo") :: IntValue?
					if v and v.Value ~= profile.MaxCombo then
						v.Value = profile.MaxCombo
					end
				end
			end
		end)
		table.insert(conns, conn)
	end
	attributeConnections[player.UserId] = conns
end

--------------------------------------------------------------------------------
-- Bindable & Remote Handlers
--------------------------------------------------------------------------------
GetPlayerDataFunction.OnInvoke = function(player: Player): PlayerProfile?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	local profile = activeProfiles[player.UserId]
	if profile then
		captureAttributesIntoProfile(player, profile)
		return deepCopyProfile(profile)
	end
	return nil
end

GetProfileRemote.OnServerInvoke = function(player: Player): PlayerProfile?
	local profile = activeProfiles[player.UserId]
	if profile then
		captureAttributesIntoProfile(player, profile)
		return deepCopyProfile(profile)
	end
	return nil
end

local function handleExternalProfileUpdate(player: Player, keyOrTable: any, value: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local profile = activeProfiles[player.UserId]
	if not profile then
		return
	end

	if type(keyOrTable) == "table" then
		for k, v in pairs(keyOrTable) do
			if k == "Cash" and type(v) == "number" then
				profile.Cash = math.max(0, math.floor(v))
			elseif k == "ChaosScore" and type(v) == "number" then
				profile.ChaosScore = math.max(0, math.floor(v))
				profile.HighScore = math.max(profile.HighScore, profile.ChaosScore)
			elseif k == "HighScore" and type(v) == "number" then
				profile.HighScore = math.max(profile.HighScore, math.floor(v))
			elseif k == "MaxCombo" and type(v) == "number" then
				profile.MaxCombo = math.max(profile.MaxCombo, math.floor(v))
			elseif k == "EquippedVehicle" and type(v) == "string" then
				profile.EquippedVehicle = v
			elseif k == "SelectedPaint" and type(v) == "number" then
				profile.SelectedPaint = math.clamp(math.floor(v), 0, 8)
			elseif k == "UnlockedVehicles" and type(v) == "table" then
				for vehId, unlocked in pairs(v) do
					if unlocked then
						profile.UnlockedVehicles[tostring(vehId)] = true
					end
				end
			elseif k == "Upgrades" and type(v) == "table" then
				for track, lvl in pairs(v) do
					local canonical = if track == "CashMagnet" then "Magnet" else track
					if (profile.Upgrades :: any)[canonical] ~= nil then
						(profile.Upgrades :: any)[canonical] = clampUpgrade(lvl)
					end
				end
			end
		end
	elseif type(keyOrTable) == "string" then
		if keyOrTable == "UnlockVehicle" and type(value) == "string" then
			profile.UnlockedVehicles[value] = true
		elseif keyOrTable == "EquipVehicle" and type(value) == "string" then
			if profile.UnlockedVehicles[value] then
				profile.EquippedVehicle = value
			end
		elseif keyOrTable == "UpgradeTrack" and type(value) == "table" then
			local rawTrack = tostring(value.Track or "")
			local track = if rawTrack == "CashMagnet" then "Magnet" else rawTrack
			local level = clampUpgrade(value.Level)
			if (profile.Upgrades :: any)[track] ~= nil then
				(profile.Upgrades :: any)[track] = level
			end
		elseif (profile :: any)[keyOrTable] ~= nil then
			(profile :: any)[keyOrTable] = value
		end
	end

	dirtyFlags[player.UserId] = true
	applyProfileToPlayer(player, profile)
	PlayerDataUpdatedEvent:Fire(player, deepCopyProfile(profile))
end

UpdatePlayerDataEvent.Event:Connect(handleExternalProfileUpdate)
local folderUpdateEv = serverEventsFolder:FindFirstChild("UpdatePlayerDataEvent") :: BindableEvent?
if folderUpdateEv then
	folderUpdateEv.Event:Connect(handleExternalProfileUpdate)
end

SavePlayerDataEvent.Event:Connect(function(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		savePlayerProfile(player, false)
	end
end)

--------------------------------------------------------------------------------
-- Player Lifecycle Management
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	ensureLeaderstats(player)
	local profile = loadPlayerProfile(player)
	activeProfiles[player.UserId] = profile
	dirtyFlags[player.UserId] = false

	applyProfileToPlayer(player, profile)
	attachAttributeWatchers(player)

	local snapshot = deepCopyProfile(profile)
	PlayerDataLoadedEvent:Fire(player, snapshot)
	local folderLoadedEv = serverEventsFolder:FindFirstChild("PlayerDataLoadedEvent") :: BindableEvent?
	if folderLoadedEv then
		folderLoadedEv:Fire(player, snapshot)
	end
end

local function onPlayerRemoving(player: Player)
	local conns = attributeConnections[player.UserId]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		attributeConnections[player.UserId] = nil
	end
	savePlayerProfile(player, true)
	isApplyingProfileToPlayer[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Periodic Autosave Loop
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if dirtyFlags[player.UserId] then
				task.spawn(savePlayerProfile, player, false)
			end
		end
	end
end)

-- Save all active profiles on server shutdown
game:BindToClose(function()
	if RunService:IsStudio() and usingInMemoryFallback then
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerProfile(player, true)
		end
		return
	end

	local remaining = 0
	for _, player in ipairs(Players:GetPlayers()) do
		remaining += 1
		task.spawn(function()
			savePlayerProfile(player, true)
			remaining -= 1
		end)
	end

	local deadline = os.clock() + 15
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
