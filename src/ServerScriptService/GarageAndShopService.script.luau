--!strict
--[[
	GarageAndShopService.script.luau
	World of Destruction (Roblox)
	
	Handles Vehicle Roster Unlocking, Vehicle Selection, Paint Customization,
	the 5 Upgrade Tracks (Levels 1 to 5), Drive-Through Mechanic Spot Repairs,
	and Speed Shop Interactions:
	  1. Engine (Top Speed & Acceleration)
	  2. Armor  (Vehicle Health & Impact Resistance)
	  3. Nitro  (Boost Power & Recharge Rate)
	  4. Plow   (Ramming Force & Destruction Threshold Reduction)
	  5. Magnet (Cash & Chaos Point Multiplier)
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- Vehicle Catalog & Pricing
--------------------------------------------------------------------------------
export type VehicleSpec = {
	Id: string,
	DisplayName: string,
	Tagline: string,
	Price: number,
	BaseHealth: number,
	BaseTopSpeed: number,
	BaseAccel: number,
	BaseSteer: number,
	BaseWreckPower: number,
	BaseArmorFactor: number,
}

local VEHICLE_CATALOG: { [string]: VehicleSpec } = {
	Compact = {
		Id = "Compact",
		DisplayName = "TURBO POCKET",
		Tagline = "Nimble cornering + drift pro",
		Price = 0,
		BaseHealth = 100,
		BaseTopSpeed = 0.98,
		BaseAccel = 1.10,
		BaseSteer = 1.16,
		BaseWreckPower = 0.95,
		BaseArmorFactor = 0.95,
	},
	Sedan = {
		Id = "Sedan",
		DisplayName = "CRUISER V8",
		Tagline = "Balanced street bruiser with reinforced bumpers",
		Price = 1500,
		BaseHealth = 125,
		BaseTopSpeed = 1.00,
		BaseAccel = 1.02,
		BaseSteer = 1.00,
		BaseWreckPower = 1.05,
		BaseArmorFactor = 0.92,
	},
	Muscle = {
		Id = "Muscle",
		DisplayName = "HELLFIRE GT",
		Tagline = "Supercharged torque monster made for smoky burnouts",
		Price = 4500,
		BaseHealth = 140,
		BaseTopSpeed = 1.05,
		BaseAccel = 1.12,
		BaseSteer = 1.04,
		BaseWreckPower = 1.25,
		BaseArmorFactor = 0.88,
	},
	SUV = {
		Id = "SUV",
		DisplayName = "TITAN 4x4",
		Tagline = "Heavy armor + strong impact",
		Price = 9000,
		BaseHealth = 175,
		BaseTopSpeed = 0.96,
		BaseAccel = 0.98,
		BaseSteer = 0.96,
		BaseWreckPower = 1.40,
		BaseArmorFactor = 0.78,
	},
	Pickup = {
		Id = "Pickup",
		DisplayName = "RANCH RAMMER",
		Tagline = "High-torque ramming truck",
		Price = 15000,
		BaseHealth = 185,
		BaseTopSpeed = 0.97,
		BaseAccel = 1.00,
		BaseSteer = 0.95,
		BaseWreckPower = 1.50,
		BaseArmorFactor = 0.80,
	},
	Sports = {
		Id = "Sports",
		DisplayName = "APEX GT",
		Tagline = "Top speed + sharp handling",
		Price = 28000,
		BaseHealth = 130,
		BaseTopSpeed = 1.12,
		BaseAccel = 1.15,
		BaseSteer = 1.10,
		BaseWreckPower = 1.15,
		BaseArmorFactor = 0.92,
	},
	MonsterTruck = {
		Id = "MonsterTruck",
		DisplayName = "CRUSHER XL",
		Tagline = "Oversized tires flatten traffic and street props",
		Price = 50000,
		BaseHealth = 250,
		BaseTopSpeed = 1.02,
		BaseAccel = 1.05,
		BaseSteer = 0.92,
		BaseWreckPower = 2.10,
		BaseArmorFactor = 0.68,
	},
	Bulldozer = {
		Id = "Bulldozer",
		DisplayName = "GOLIATH DOZER",
		Tagline = "Colossal demolition siege rig",
		Price = 95000,
		BaseHealth = 380,
		BaseTopSpeed = 0.90,
		BaseAccel = 0.94,
		BaseSteer = 0.88,
		BaseWreckPower = 3.00,
		BaseArmorFactor = 0.55,
	},
}
VEHICLE_CATALOG.sports = VEHICLE_CATALOG.Sports
VEHICLE_CATALOG.sedan = VEHICLE_CATALOG.Sedan
VEHICLE_CATALOG.hatchback = VEHICLE_CATALOG.Compact
VEHICLE_CATALOG.suv = VEHICLE_CATALOG.SUV
VEHICLE_CATALOG.pickup = VEHICLE_CATALOG.Pickup
VEHICLE_CATALOG.van = VEHICLE_CATALOG.SUV
VEHICLE_CATALOG.boxTruck = VEHICLE_CATALOG.Bulldozer
VEHICLE_CATALOG.motorcycle = VEHICLE_CATALOG.Sports

-- Flexible alias lookup so UI can pass "Compact", "Sports", "Muscle", "MonsterTruck", "Bulldozer", etc.
local VEHICLE_ALIASES: { [string]: string } = {
	["compact"] = "Compact",
	["hatchback"] = "Compact",
	["turbo pocket"] = "Compact",
	["turbopocket"] = "Compact",
	["sedan"] = "Sedan",
	["cruiser v8"] = "Sedan",
	["cruiserv8"] = "Sedan",
	["muscle"] = "Muscle",
	["hellfire gt"] = "Muscle",
	["hellfiregt"] = "Muscle",
	["suv"] = "SUV",
	["titan 4x4"] = "SUV",
	["titan 4×4"] = "SUV",
	["titan4x4"] = "SUV",
	["pickup"] = "Pickup",
	["ranch rammer"] = "Pickup",
	["ranchrammer"] = "Pickup",
	["sports"] = "Sports",
	["apex gt"] = "Sports",
	["apexgt"] = "Sports",
	["van"] = "SUV",
	["iron van"] = "SUV",
	["ironvan"] = "SUV",
	["monstertruck"] = "MonsterTruck",
	["monster truck"] = "MonsterTruck",
	["crusher xl"] = "MonsterTruck",
	["bulldozer"] = "Bulldozer",
	["tank"] = "Bulldozer",
	["boxtruck"] = "Bulldozer",
	["box truck"] = "Bulldozer",
	["goliath rig"] = "Bulldozer",
	["goliathrig"] = "Bulldozer",
	["motorcycle"] = "Sports",
	["street bolt"] = "Sports",
	["streetbolt"] = "Sports",
}

local PAINT_PALETTE = {
	[0] = { Name = "Stealth Obsidian", Color = Color3.fromRGB(26, 31, 41) },
	[1] = { Name = "Midnight Navy", Color = Color3.fromRGB(26, 46, 82) },
	[2] = { Name = "Shadow Gunmetal", Color = Color3.fromRGB(51, 56, 66) },
	[3] = { Name = "Dark Crimson", Color = Color3.fromRGB(122, 26, 31) },
	[4] = { Name = "Antique Bronze", Color = Color3.fromRGB(117, 87, 41) },
	[5] = { Name = "Forest Slate", Color = Color3.fromRGB(31, 61, 46) },
	[6] = { Name = "Deep Violet", Color = Color3.fromRGB(61, 31, 87) },
	[7] = { Name = "Moonlit Silver", Color = Color3.fromRGB(143, 153, 168) },
}

--------------------------------------------------------------------------------
-- 5 Upgrade Tracks (Levels 1 to 5)
--------------------------------------------------------------------------------
export type TrackName = "Engine" | "Armor" | "Nitro" | "Plow" | "Magnet"

local MAX_UPGRADE_LEVEL = 5

-- Cost to upgrade from current Level L -> L+1 (index 1 = L1->L2, ..., index 4 = L4->L5)
local UPGRADE_COSTS: { [number]: number } = {
	[1] = 400,  -- Level 1 -> 2
	[2] = 900,  -- Level 2 -> 3
	[3] = 1800, -- Level 3 -> 4
	[4] = 3200, -- Level 4 -> 5
}

local TRACK_METADATA: { [string]: { Name: TrackName, DisplayName: string, Description: string } } = {
	Engine = {
		Name = "Engine",
		DisplayName = "V8 TWIN-TURBO ENGINE",
		Description = "Boosts Top Speed & Acceleration (+8% speed, +10% acceleration per level)",
	},
	Armor = {
		Name = "Armor",
		DisplayName = "REINFORCED CHASSIS ARMOR",
		Description = "Increases Vehicle Max Health & Impact Resistance (+25% HP, -10% damage taken per level)",
	},
	Nitro = {
		Name = "Nitro",
		DisplayName = "HYPER NITRO INJECTOR",
		Description = "Increases Boost Power & Nitro Recharge Rate (+12% power, +18% recharge per level)",
	},
	Plow = {
		Name = "Plow",
		DisplayName = "HEAVY DEMOLITION PLOW",
		Description = "Amplifies Ramming Force & lowers Destruction Speed Threshold (+20% ramming force per level)",
	},
	Magnet = {
		Name = "Magnet",
		DisplayName = "CASH & CHAOS MAGNET",
		Description = "Multiplies all Cash & Chaos Points earned up to 2.0x at Level 5",
	},
}

local TRACK_ALIASES: { [string]: TrackName } = {
	["engine"] = "Engine",
	["turbo"] = "Engine",
	["speed"] = "Engine",
	["armor"] = "Armor",
	["health"] = "Armor",
	["hull"] = "Armor",
	["nitro"] = "Nitro",
	["boost"] = "Nitro",
	["plow"] = "Plow",
	["wreckingball"] = "Plow",
	["wrecking"] = "Plow",
	["ram"] = "Plow",
	["magnet"] = "Magnet",
	["cashmagnet"] = "Magnet",
	["multiplier"] = "Magnet",
}

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

-- ServerStorage Bindables
local SpendCashFunction = ensureBindableFunction(ServerStorage, "SpendCashFunction")
local UpdatePlayerDataEvent = ensureBindableEvent(ServerStorage, "UpdatePlayerDataEvent")
local PlayerDataLoadedEvent = ensureBindableEvent(ServerStorage, "PlayerDataLoadedEvent")
local VehicleRepairedEvent = ensureBindableEvent(ServerStorage, "VehicleRepairedEvent")
local VehicleUpgradedEvent = ensureBindableEvent(ServerStorage, "VehicleUpgradedEvent")
local VehicleSpawnRequestEvent = ensureBindableEvent(ServerStorage, "VehicleSpawnRequestEvent")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")

-- Mirror in ServerStorage.Events
ensureBindableEvent(serverEventsFolder, "VehicleRepairedEvent")
ensureBindableEvent(serverEventsFolder, "VehicleUpgradedEvent")
ensureBindableEvent(serverEventsFolder, "VehicleSpawnRequestEvent")

-- ReplicatedStorage Remotes for Garage, Speed Shop, and Mechanic Spot
local GarageActionRemote = ensureRemoteEvent(remotesFolder, "GarageAction")
local SpeedShopActionRemote = ensureRemoteEvent(remotesFolder, "SpeedShopAction")
local BuyUpgradeRemote = ensureRemoteEvent(remotesFolder, "BuyUpgrade")
local PurchaseUpgradeFunction = ensureRemoteFunction(remotesFolder, "PurchaseUpgrade")
local UnlockVehicleRemote = ensureRemoteEvent(remotesFolder, "UnlockVehicle")
local SelectVehicleRemote = ensureRemoteEvent(remotesFolder, "SelectVehicle")
local RepairVehicleRemote = ensureRemoteEvent(remotesFolder, "RepairVehicle")
local GarageNotificationRemote = ensureRemoteEvent(remotesFolder, "GarageNotification")
local SpeedShopToggleRemote = ensureRemoteEvent(remotesFolder, "SpeedShopToggle")
local GetGarageDataFunction = ensureRemoteFunction(remotesFolder, "GetGarageData")

-- Root aliases for broad script compatibility
local RootGarageRemote = ensureRemoteEvent(ReplicatedStorage, "GarageEvent")
local RootSpeedShopRemote = ensureRemoteEvent(ReplicatedStorage, "SpeedShopEvent")
local RootMechanicRemote = ensureRemoteEvent(ReplicatedStorage, "MechanicRepairEvent")

--------------------------------------------------------------------------------
-- Upgrade & Vehicle Multiplier Calculations
--------------------------------------------------------------------------------
local MAGNET_MULTIPLIERS = { 1.0, 1.15, 1.35, 1.60, 2.00 }

local function resolveVehicleId(rawId: any): string?
	if type(rawId) ~= "string" then
		return nil
	end
	local key = string.lower(string.gsub(rawId, "^%s*(.-)%s*$", "%1"))
	return VEHICLE_ALIASES[key] or (if VEHICLE_CATALOG[rawId] then rawId else nil)
end

local function resolveTrackName(rawTrack: any): TrackName?
	if type(rawTrack) ~= "string" then
		return nil
	end
	local key = string.lower(string.gsub(rawTrack, "%s+", ""))
	return TRACK_ALIASES[key]
end

local function getUnlockedVehiclesMap(player: Player): { [string]: boolean }
	local unlocked: { [string]: boolean } = {
		Compact = true,
		hatchback = true,
	}
	local rawJson = player:GetAttribute("UnlockedVehicles")
	if type(rawJson) == "string" and rawJson ~= "" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(rawJson)
		end)
		if ok and type(decoded) == "table" then
			for k, v in pairs(decoded) do
				if type(k) == "number" and type(v) == "string" then
					unlocked[v] = true
				elseif type(k) == "string" and v == true then
					unlocked[k] = true
				end
			end
		end
	end
	return unlocked
end

local function setUnlockedVehiclesMap(player: Player, unlocked: { [string]: boolean })
	local list = {}
	for id, isUnlocked in pairs(unlocked) do
		if isUnlocked then
			table.insert(list, id)
			player:SetAttribute("Unlocked_" .. id, true)
		end
	end
	table.sort(list)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(list)
	end)
	if ok then
		player:SetAttribute("UnlockedVehicles", encoded)
	end
end

local function getTrackLevel(player: Player, track: TrackName): number
	local lvl = tonumber(player:GetAttribute("Upgrade_" .. track) or player:GetAttribute(track .. "Level")) or 1
	return math.clamp(math.floor(lvl), 1, MAX_UPGRADE_LEVEL)
end

local function findPlayerVehicleModel(player: Player): Model?
	-- Check Workspace.PlayerVehicles or character seat
	local vehiclesFolder = Workspace:FindFirstChild("PlayerVehicles") or Workspace:FindFirstChild("Vehicles")
	if vehiclesFolder then
		local byName = vehiclesFolder:FindFirstChild(player.Name .. "_Vehicle")
			or vehiclesFolder:FindFirstChild(player.Name)
			or vehiclesFolder:FindFirstChild("PlayerCar_" .. tostring(player.UserId))
		if byName and byName:IsA("Model") then
			return byName
		end
		for _, child in ipairs(vehiclesFolder:GetChildren()) do
			if child:IsA("Model") and (child:GetAttribute("OwnerUserId") == player.UserId or child:GetAttribute("Owner") == player.Name) then
				return child
			end
		end
	end

	local character = player.Character
	if character then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			local model = hum.SeatPart:FindFirstAncestorOfClass("Model")
			if model and model ~= character then
				return model
			end
		end
	end
	return nil
end

local function recomputeAndApplyStats(player: Player, fullHeal: boolean?)
	local equippedId = resolveVehicleId(player:GetAttribute("EquippedVehicle")) or "sports"
	local spec = VEHICLE_CATALOG[equippedId] or VEHICLE_CATALOG.sports
	local paintIndex = math.clamp(math.floor(tonumber(player:GetAttribute("SelectedPaint")) or 0), 0, 7)
	local paintInfo = PAINT_PALETTE[paintIndex] or PAINT_PALETTE[0]

	local engineLvl = getTrackLevel(player, "Engine")
	local armorLvl = getTrackLevel(player, "Armor")
	local nitroLvl = getTrackLevel(player, "Nitro")
	local plowLvl = getTrackLevel(player, "Plow")
	local magnetLvl = getTrackLevel(player, "Magnet")

	-- 1. Engine: Top Speed (+8% per lvl above 1) & Acceleration (+10% per lvl above 1)
	local topSpeedMult = spec.BaseTopSpeed * (1.0 + 0.08 * (engineLvl - 1))
	local accelMult = spec.BaseAccel * (1.0 + 0.10 * (engineLvl - 1))

	-- 2. Armor: Vehicle Max Health (+25% per lvl above 1) & Impact Resistance (-10% incoming damage per lvl above 1)
	local maxHealthMult = 1.0 + 0.25 * (armorLvl - 1)
	local maxHealth = math.floor(spec.BaseHealth * maxHealthMult)
	local incomingDamageScale = spec.BaseArmorFactor * (1.0 - 0.10 * (armorLvl - 1))
	local impactResistanceMult = 1.0 / math.max(0.25, incomingDamageScale)

	-- 3. Nitro: Boost Power (+12% per lvl above 1) & Recharge Rate (+18% per lvl above 1)
	local nitroPowerMult = 1.0 + 0.12 * (nitroLvl - 1)
	local nitroRechargeMult = 1.0 + 0.18 * (nitroLvl - 1)

	-- 4. Plow: Ramming Force (+22% per lvl above 1) & Destruction Speed Threshold Reduction (-12% per lvl above 1)
	local rammingForceMult = spec.BaseWreckPower * (1.0 + 0.22 * (plowLvl - 1))
	local destructionThresholdReduction = 0.12 * (plowLvl - 1) -- Up to 48% easier to smash heavy structures

	-- 5. Magnet: Cash & Chaos Point Multiplier (1.0x -> 1.15x -> 1.35x -> 1.60x -> 2.00x)
	local magnetMult = MAGNET_MULTIPLIERS[magnetLvl] or 1.0

	-- Mirror both Upgrade_<Track> and <Track>Level attributes
	player:SetAttribute("Upgrade_Engine", engineLvl)
	player:SetAttribute("Upgrade_Armor", armorLvl)
	player:SetAttribute("Upgrade_Nitro", nitroLvl)
	player:SetAttribute("Upgrade_Plow", plowLvl)
	player:SetAttribute("Upgrade_Magnet", magnetLvl)

	player:SetAttribute("EngineLevel", engineLvl)
	player:SetAttribute("ArmorLevel", armorLvl)
	player:SetAttribute("NitroLevel", nitroLvl)
	player:SetAttribute("PlowLevel", plowLvl)
	player:SetAttribute("MagnetLevel", magnetLvl)

	-- Derived Multipliers on Player
	player:SetAttribute("EquippedVehicle", spec.Id)
	player:SetAttribute("SelectedVehicle", spec.Id)
	player:SetAttribute("VehicleDisplayName", spec.DisplayName)
	player:SetAttribute("SelectedPaint", paintIndex)
	player:SetAttribute("SelectedPaintColor", paintInfo.Color)

	player:SetAttribute("TopSpeedMultiplier", tonumber(string.format("%.3f", topSpeedMult)))
	player:SetAttribute("AccelerationMultiplier", tonumber(string.format("%.3f", accelMult)))
	player:SetAttribute("SteerMultiplier", spec.BaseSteer)
	player:SetAttribute("MaxHealthMultiplier", tonumber(string.format("%.3f", maxHealthMult)))
	player:SetAttribute("DamageResistanceMultiplier", tonumber(string.format("%.3f", impactResistanceMult)))
	player:SetAttribute("IncomingDamageScale", tonumber(string.format("%.3f", incomingDamageScale)))
	player:SetAttribute("NitroPowerMultiplier", tonumber(string.format("%.3f", nitroPowerMult)))
	player:SetAttribute("NitroRechargeMultiplier", tonumber(string.format("%.3f", nitroRechargeMult)))
	player:SetAttribute("RammingForceMultiplier", tonumber(string.format("%.3f", rammingForceMult)))
	player:SetAttribute("DestructionThresholdReduction", tonumber(string.format("%.3f", destructionThresholdReduction)))
	player:SetAttribute("CashMagnetMultiplier", tonumber(string.format("%.3f", magnetMult)))
	player:SetAttribute("ChaosPointMultiplier", tonumber(string.format("%.3f", magnetMult)))

	player:SetAttribute("VehicleMaxHealth", maxHealth)
	local currentHealth = tonumber(player:GetAttribute("VehicleHealth"))
	if fullHeal or currentHealth == nil or currentHealth <= 0 then
		currentHealth = maxHealth
	else
		currentHealth = math.min(maxHealth, currentHealth)
	end
	player:SetAttribute("VehicleHealth", currentHealth)

	-- Push stats onto active Vehicle Model in Workspace if present
	local vehicleModel = findPlayerVehicleModel(player)
	if vehicleModel then
		vehicleModel:SetAttribute("VehicleType", spec.Id)
		vehicleModel:SetAttribute("TopSpeedMultiplier", topSpeedMult)
		vehicleModel:SetAttribute("AccelerationMultiplier", accelMult)
		vehicleModel:SetAttribute("RammingForceMultiplier", rammingForceMult)
		vehicleModel:SetAttribute("DestructionThresholdReduction", destructionThresholdReduction)
		vehicleModel:SetAttribute("NitroPowerMultiplier", nitroPowerMult)
		vehicleModel:SetAttribute("NitroRechargeMultiplier", nitroRechargeMult)
		vehicleModel:SetAttribute("DamageResistanceMultiplier", impactResistanceMult)
		vehicleModel:SetAttribute("MaxHealth", maxHealth)
		vehicleModel:SetAttribute("Health", currentHealth)
		vehicleModel:SetAttribute("PlowLevel", plowLvl)
		vehicleModel:SetAttribute("ArmorLevel", armorLvl)

		local seat = vehicleModel:FindFirstChildOfClass("VehicleSeat")
		if seat then
			-- Keep legacy VehicleSeat torque at 0 so VehicleClientController drives smoothly without solver conflict
			seat.MaxSpeed = 0
			seat.Torque = 0
		end
	end
end

--------------------------------------------------------------------------------
-- Cash Debit Helper (Supports SpendCashFunction + Direct Attribute Fallback)
--------------------------------------------------------------------------------
local function trySpendCash(player: Player, amount: number, reason: string): boolean
	local cost = math.floor(amount)
	if cost <= 0 then
		return true
	end

	local currentCash = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0))
	if currentCash < cost then
		return false
	end

	local ok, spent = pcall(function()
		return SpendCashFunction:Invoke(player, cost, reason)
	end)
	if ok and spent == true then
		return true
	end

	-- Fallback direct attribute & leaderstats deduction
	local freshCash = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0))
	if freshCash < cost then
		return false
	end
	local remaining = freshCash - cost
	player:SetAttribute("Cash", remaining)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash") :: IntValue?
		if cashVal then
			cashVal.Value = remaining
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Core Garage & Shop Operations
--------------------------------------------------------------------------------
local function buildGarageSnapshot(player: Player)
	local unlocked = getUnlockedVehiclesMap(player)
	local upgrades = {
		Engine = getTrackLevel(player, "Engine"),
		Armor = getTrackLevel(player, "Armor"),
		Nitro = getTrackLevel(player, "Nitro"),
		Plow = getTrackLevel(player, "Plow"),
		Magnet = getTrackLevel(player, "Magnet"),
	}
	local nextCosts = {
		Engine = UPGRADE_COSTS[upgrades.Engine],
		Armor = UPGRADE_COSTS[upgrades.Armor],
		Nitro = UPGRADE_COSTS[upgrades.Nitro],
		Plow = UPGRADE_COSTS[upgrades.Plow],
		Magnet = UPGRADE_COSTS[upgrades.Magnet],
	}
	return {
		Cash = tonumber(player:GetAttribute("Cash")) or 0,
		EquippedVehicle = player:GetAttribute("EquippedVehicle") or "sports",
		SelectedPaint = tonumber(player:GetAttribute("SelectedPaint")) or 0,
		UnlockedVehicles = unlocked,
		Upgrades = upgrades,
		NextCosts = nextCosts,
		MaxLevel = MAX_UPGRADE_LEVEL,
		Catalog = VEHICLE_CATALOG,
		Tracks = TRACK_METADATA,
		VehicleHealth = tonumber(player:GetAttribute("VehicleHealth")) or 100,
		VehicleMaxHealth = tonumber(player:GetAttribute("VehicleMaxHealth")) or 100,
	}
end

local function purchaseUpgrade(player: Player, rawTrack: any): (boolean, string)
	local track = resolveTrackName(rawTrack)
	if not track then
		return false, "Invalid upgrade track."
	end

	local currentLevel = getTrackLevel(player, track)
	if currentLevel >= MAX_UPGRADE_LEVEL then
		return false, string.format("%s is already MAX LEVEL (%d)!", track, MAX_UPGRADE_LEVEL)
	end

	local cost = UPGRADE_COSTS[currentLevel] or 3200
	if not trySpendCash(player, cost, "Upgrade_" .. track) then
		return false, string.format("Need $%d for %s Level %d!", cost, track, currentLevel + 1)
	end

	local newLevel = currentLevel + 1
	player:SetAttribute("Upgrade_" .. track, newLevel)
	player:SetAttribute(track .. "Level", newLevel)

	recomputeAndApplyStats(player, track == "Armor")

	UpdatePlayerDataEvent:Fire(player, "UpgradeTrack", {
		Track = track,
		Level = newLevel,
	})
	VehicleUpgradedEvent:Fire(player, track, newLevel)
	local folderEv = serverEventsFolder:FindFirstChild("VehicleUpgradedEvent") :: BindableEvent?
	if folderEv then
		folderEv:Fire(player, track, newLevel)
	end

	local msg = string.format("%s UPGRADED TO LVL %d!", string.upper(track), newLevel)
	StyleCalloutRemote:FireClient(player, {
		Callout = msg,
		Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
		ComboCount = tonumber(player:GetAttribute("ComboCount")) or 0,
		CashAwarded = 0,
	})

	GarageNotificationRemote:FireClient(player, "BuyUpgrade", true, msg, buildGarageSnapshot(player))
	return true, msg
end

local function unlockOrSelectVehicle(player: Player, rawVehicleId: any, optionalPaintIndex: any): (boolean, string)
	local vehicleId = resolveVehicleId(rawVehicleId)
	if not vehicleId then
		return false, "Unknown vehicle class."
	end

	local spec = VEHICLE_CATALOG[vehicleId]
	local unlocked = getUnlockedVehiclesMap(player)

	if not unlocked[vehicleId] then
		if not trySpendCash(player, spec.Price, "UnlockVehicle_" .. vehicleId) then
			return false, string.format("Need $%d to unlock %s!", spec.Price, spec.DisplayName)
		end
		unlocked[vehicleId] = true
		setUnlockedVehiclesMap(player, unlocked)
		UpdatePlayerDataEvent:Fire(player, "UnlockVehicle", vehicleId)
	end

	player:SetAttribute("EquippedVehicle", vehicleId)
	player:SetAttribute("SelectedVehicle", vehicleId)

	if type(optionalPaintIndex) == "number" then
		local paintIdx = math.clamp(math.floor(optionalPaintIndex), 0, 7)
		player:SetAttribute("SelectedPaint", paintIdx)
		UpdatePlayerDataEvent:Fire(player, "SelectedPaint", paintIdx)
	end

	recomputeAndApplyStats(player, true)
	UpdatePlayerDataEvent:Fire(player, "EquipVehicle", vehicleId)

	-- Notify any vehicle spawner script to hot-swap the player's car
	VehicleSpawnRequestEvent:Fire(player, vehicleId, player:GetAttribute("SelectedPaint"))
	local folderSpawnEv = serverEventsFolder:FindFirstChild("VehicleSpawnRequestEvent") :: BindableEvent?
	if folderSpawnEv then
		folderSpawnEv:Fire(player, vehicleId, player:GetAttribute("SelectedPaint"))
	end

	local msg = string.format("EQUIPPED %s!", spec.DisplayName)
	StyleCalloutRemote:FireClient(player, {
		Callout = msg,
		Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
		ComboCount = tonumber(player:GetAttribute("ComboCount")) or 0,
		CashAwarded = 0,
	})
	GarageNotificationRemote:FireClient(player, "SelectVehicle", true, msg, buildGarageSnapshot(player))
	return true, msg
end

local function selectPaint(player: Player, rawPaintIndex: any): (boolean, string)
	local paintIndex = math.clamp(math.floor(tonumber(rawPaintIndex) or 0), 0, 7)
	local paintInfo = PAINT_PALETTE[paintIndex] or PAINT_PALETTE[0]

	player:SetAttribute("SelectedPaint", paintIndex)
	player:SetAttribute("SelectedPaintColor", paintInfo.Color)
	recomputeAndApplyStats(player, false)
	UpdatePlayerDataEvent:Fire(player, "SelectedPaint", paintIndex)

	VehicleSpawnRequestEvent:Fire(player, player:GetAttribute("EquippedVehicle"), paintIndex)
	local msg = string.format("PAINT: %s!", string.upper(paintInfo.Name))
	GarageNotificationRemote:FireClient(player, "SelectPaint", true, msg, buildGarageSnapshot(player))
	return true, msg
end

local repairCooldowns: { [number]: number } = {}

local function repairPlayerVehicle(player: Player, stationName: string?, respawnCFrame: CFrame?): (boolean, string)
	local now = os.clock()
	if repairCooldowns[player.UserId] and now - repairCooldowns[player.UserId] < 1.5 then
		return false, "Repair cooling down."
	end
	repairCooldowns[player.UserId] = now

	recomputeAndApplyStats(player, true)
	local maxHealth = tonumber(player:GetAttribute("VehicleMaxHealth")) or 100
	player:SetAttribute("VehicleHealth", maxHealth)
	player:SetAttribute("VehicleDamageRatio", 0)
	player:SetAttribute("LastRepairTime", os.time())

	if respawnCFrame then
		player:SetAttribute("LastMechanicRespawnCFrame", respawnCFrame)
	end

	local vehicleModel = findPlayerVehicleModel(player)
	if vehicleModel then
		vehicleModel:SetAttribute("Health", maxHealth)
		vehicleModel:SetAttribute("Damage", 0)
		vehicleModel:SetAttribute("IsWrecked", false)
	end

	local label = if stationName and stationName ~= "" then stationName else "MECHANIC SPOT"
	local msg = string.format("WRENCH REPAIRED 100%% AT %s!", string.upper(label))

	VehicleRepairedEvent:Fire(player, label, 0)
	local folderRepairEv = serverEventsFolder:FindFirstChild("VehicleRepairedEvent") :: BindableEvent?
	if folderRepairEv then
		folderRepairEv:Fire(player, label, 0)
	end

	StyleCalloutRemote:FireClient(player, {
		Callout = "REPAIRED 100%!",
		Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
		ComboCount = tonumber(player:GetAttribute("ComboCount")) or 0,
		CashAwarded = 0,
	})
	GarageNotificationRemote:FireClient(player, "RepairVehicle", true, msg, buildGarageSnapshot(player))
	return true, msg
end

--------------------------------------------------------------------------------
-- RemoteEvent & RemoteFunction Wiring
--------------------------------------------------------------------------------
GetGarageDataFunction.OnServerInvoke = function(player: Player)
	return buildGarageSnapshot(player)
end

BuyUpgradeRemote.OnServerEvent:Connect(function(player: Player, trackName: any)
	purchaseUpgrade(player, trackName)
end)

PurchaseUpgradeFunction.OnServerInvoke = function(player: Player, trackName: any)
	local ok, _msg = purchaseUpgrade(player, trackName)
	return ok
end

UnlockVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
	unlockOrSelectVehicle(player, vehicleId, nil)
end)

SelectVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any, paintIndex: any)
	unlockOrSelectVehicle(player, vehicleId, paintIndex)
end)

RepairVehicleRemote.OnServerEvent:Connect(function(player: Player, stationName: any)
	repairPlayerVehicle(player, if type(stationName) == "string" then stationName else "Mechanic Spot", nil)
end)
RootMechanicRemote.OnServerEvent:Connect(function(player: Player, stationName: any)
	repairPlayerVehicle(player, if type(stationName) == "string" then stationName else "Mechanic Spot", nil)
end)

local function handleCompositeGarageAction(player: Player, action: any, arg1: any, arg2: any)
	local act = string.lower(tostring(action or ""))
	if act == "buyupgrade" or act == "upgrade" then
		purchaseUpgrade(player, arg1)
	elseif act == "unlockvehicle" or act == "buyvehicle" or act == "selectvehicle" or act == "equipvehicle" then
		unlockOrSelectVehicle(player, arg1, arg2)
	elseif act == "selectpaint" or act == "paint" then
		selectPaint(player, arg1)
	elseif act == "repair" or act == "repairvehicle" or act == "mechanicspot" then
		repairPlayerVehicle(player, if type(arg1) == "string" then arg1 else "Mechanic Spot", nil)
	elseif act == "openspeedshop" then
		player:SetAttribute("SpeedShopOpen", true)
		SpeedShopToggleRemote:FireClient(player, true, buildGarageSnapshot(player))
	elseif act == "closespeedshop" then
		player:SetAttribute("SpeedShopOpen", false)
		SpeedShopToggleRemote:FireClient(player, false, buildGarageSnapshot(player))
	end
end

GarageActionRemote.OnServerEvent:Connect(handleCompositeGarageAction)
SpeedShopActionRemote.OnServerEvent:Connect(handleCompositeGarageAction)
RootGarageRemote.OnServerEvent:Connect(handleCompositeGarageAction)
RootSpeedShopRemote.OnServerEvent:Connect(handleCompositeGarageAction)

--------------------------------------------------------------------------------
-- Drive-Through Mechanic Spots & Speed Shop Showroom Pads in Workspace
--------------------------------------------------------------------------------
local function resolvePlayerFromHit(hit: BasePart): Player?
	local char = hit:FindFirstAncestorOfClass("Model")
	if char then
		local directPlayer = Players:GetPlayerFromCharacter(char)
		if directPlayer then
			return directPlayer
		end
		local ownerId = char:GetAttribute("OwnerUserId")
		if type(ownerId) == "number" then
			return Players:GetPlayerByUserId(ownerId)
		end
		local seat = char:FindFirstChildOfClass("VehicleSeat")
		if seat and seat.Occupant and seat.Occupant.Parent then
			return Players:GetPlayerFromCharacter(seat.Occupant.Parent)
		end
	end
	return nil
end

local boundPads: { [Instance]: boolean } = {}
local speedShopPadDebounces: { [number]: number } = {}

local function bindMechanicSpotPad(pad: BasePart, spotName: string)
	if boundPads[pad] then
		return
	end
	boundPads[pad] = true
	pad:SetAttribute("IsMechanicSpot", true)

	pad.Touched:Connect(function(hit: BasePart)
		local player = resolvePlayerFromHit(hit)
		if not player then
			return
		end
		local respawnCF = pad.CFrame + Vector3.new(0, 4, 0)
		repairPlayerVehicle(player, spotName, respawnCF)
	end)
end

local function bindSpeedShopPad(pad: BasePart, shopName: string)
	if boundPads[pad] then
		return
	end
	boundPads[pad] = true
	pad:SetAttribute("IsSpeedShop", true)

	pad.Touched:Connect(function(hit: BasePart)
		local player = resolvePlayerFromHit(hit)
		if not player then
			return
		end
		local now = os.clock()
		if speedShopPadDebounces[player.UserId] and now - speedShopPadDebounces[player.UserId] < 3.0 then
			return
		end
		speedShopPadDebounces[player.UserId] = now

		player:SetAttribute("NearSpeedShop", true)
		player:SetAttribute("SpeedShopOpen", true)
		SpeedShopToggleRemote:FireClient(player, true, buildGarageSnapshot(player), shopName)
	end)
end

local function createBillboardLabel(_parent: BasePart, _titleText: string, _subtitleText: string, _accentColor: Color3)
	-- Disabled floating BillboardGui station signs so 3D SurfaceGui building signs stay clean and never overlap on screen!
end

local function ensureDefaultGaragePadsInWorkspace()
	-- First bind any existing MechanicSpot / SpeedShop instances created by world builder scripts
	for _, inst in ipairs(CollectionService:GetTagged("MechanicSpot")) do
		if inst:IsA("BasePart") then
			bindMechanicSpotPad(inst, inst.Name)
		elseif inst:IsA("Model") and inst.PrimaryPart then
			bindMechanicSpotPad(inst.PrimaryPart, inst.Name)
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("SpeedShop")) do
		if inst:IsA("BasePart") then
			bindSpeedShopPad(inst, inst.Name)
		elseif inst:IsA("Model") and inst.PrimaryPart then
			bindSpeedShopPad(inst.PrimaryPart, inst.Name)
		end
	end

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local lower = string.lower(desc.Name)
			if desc:GetAttribute("IsMechanicSpot") or string.find(lower, "mechanicspot") or string.find(lower, "repairpad") then
				bindMechanicSpotPad(desc, desc.Name)
			elseif desc:GetAttribute("IsSpeedShop") or string.find(lower, "speedshop") or string.find(lower, "upgradepad") then
				bindSpeedShopPad(desc, desc.Name)
			end
		end
	end

	-- If no pads exist yet, spawn drive-through Mechanic Spots & Speed Shop pads in Workspace.GarageSpots
	if next(boundPads) ~= nil then
		return
	end

	local spotsFolder = ensureFolder(Workspace, "GarageSpots")

	local mechanicLocations = {
		{ Name = "Downtown Mechanic Bay", Position = Vector3.new(45, 0.4, -45) },
		{ Name = "Harbor Repair Garage", Position = Vector3.new(-140, 0.4, 90) },
		{ Name = "Uptown Pit Stop", Position = Vector3.new(160, 0.4, 130) },
	}

	for _, loc in ipairs(mechanicLocations) do
		local pad = Instance.new("Part")
		pad.Name = loc.Name
		pad.Size = Vector3.new(18, 0.6, 18)
		pad.Position = loc.Position
		pad.Anchored = true
		pad.CanCollide = false
		pad.Material = Enum.Material.Neon
		pad.Color = Color3.fromRGB(40, 235, 115)
		pad.Transparency = 0.25
		pad.Parent = spotsFolder
		CollectionService:AddTag(pad, "MechanicSpot")
		createBillboardLabel(pad, "MECHANIC SPOT", "DRIVE THROUGH FOR INSTANT REPAIR", Color3.fromRGB(60, 255, 130))
		bindMechanicSpotPad(pad, loc.Name)
	end

	local speedShopLocations = {
		{ Name = "Leo City Speed Shop", Position = Vector3.new(-45, 0.4, -45) },
		{ Name = "Industrial Tuning Showroom", Position = Vector3.new(120, 0.4, -150) },
	}

	for _, loc in ipairs(speedShopLocations) do
		local pad = Instance.new("Part")
		pad.Name = loc.Name
		pad.Size = Vector3.new(20, 0.6, 20)
		pad.Position = loc.Position
		pad.Anchored = true
		pad.CanCollide = false
		pad.Material = Enum.Material.Neon
		pad.Color = Color3.fromRGB(255, 175, 35)
		pad.Transparency = 0.25
		pad.Parent = spotsFolder
		CollectionService:AddTag(pad, "SpeedShop")
		createBillboardLabel(pad, "SPEED SHOP & GARAGE", "UPGRADE ENGINE · ARMOR · NITRO · PLOW · MAGNET", Color3.fromRGB(255, 200, 50))
		bindSpeedShopPad(pad, loc.Name)
	end
end

task.defer(ensureDefaultGaragePadsInWorkspace)

-- Also listen for dynamically streamed MechanicSpot / SpeedShop parts
Workspace.DescendantAdded:Connect(function(desc: Instance)
	if desc:IsA("BasePart") then
		local lower = string.lower(desc.Name)
		if desc:GetAttribute("IsMechanicSpot") or string.find(lower, "mechanicspot") or string.find(lower, "repairpad") then
			bindMechanicSpotPad(desc, desc.Name)
		elseif desc:GetAttribute("IsSpeedShop") or string.find(lower, "speedshop") or string.find(lower, "upgradepad") then
			bindSpeedShopPad(desc, desc.Name)
		end
	end
end)

--------------------------------------------------------------------------------
-- Player Lifecycle Integration
--------------------------------------------------------------------------------
local function initPlayerGarage(player: Player)
	-- Ensure default upgrade attributes exist if PlayerDataService hasn't populated yet
	for _, track in ipairs({ "Engine", "Armor", "Nitro", "Plow", "Magnet" }) do
		if player:GetAttribute("Upgrade_" .. track) == nil then
			player:SetAttribute("Upgrade_" .. track, 1)
		end
	end
	if player:GetAttribute("EquippedVehicle") == nil then
		player:SetAttribute("EquippedVehicle", "Compact")
	end
	if player:GetAttribute("SelectedPaint") == nil then
		player:SetAttribute("SelectedPaint", 0)
	end

	recomputeAndApplyStats(player, true)

	player.CharacterAdded:Connect(function()
		task.wait(0.25)
		if player.Parent then
			recomputeAndApplyStats(player, true)
		end
	end)
end

PlayerDataLoadedEvent.Event:Connect(function(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		recomputeAndApplyStats(player, true)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayerGarage, player)
end
Players.PlayerAdded:Connect(initPlayerGarage)

Players.PlayerRemoving:Connect(function(player: Player)
	repairCooldowns[player.UserId] = nil
	speedShopPadDebounces[player.UserId] = nil
end)

-- Periodically refresh vehicle model multipliers in case a new vehicle was spawned
local syncAccum = 0
RunService.Heartbeat:Connect(function(dt: number)
	syncAccum += dt
	if syncAccum < 1.0 then
		return
	end
	syncAccum = 0
	for _, player in ipairs(Players:GetPlayers()) do
		recomputeAndApplyStats(player, false)
	end
end)
