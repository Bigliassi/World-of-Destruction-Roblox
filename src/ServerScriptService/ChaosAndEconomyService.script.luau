--!strict
--[[
	ChaosAndEconomyService.script.luau
	World of Destruction (Roblox)
	
	Core Gameplay Loop, Chaos Combo Tracker, Cash Economy & Live Chaos Missions:
	- Configures Roblox `leaderstats` (`Cash`, `ChaosScore`, `MaxCombo`, `HeatLevel`)
	  and Player Attributes (`Cash`, `ComboCount`, `ComboMultiplier`, `ComboTimer`,
	  `HeatStars`, `HeatProgress`, `CurrentStreakName`).
	- Listens for destruction events, stunt jumps (airtime), drift scores,
	  near-misses, and police takedowns via BindableEvents, RemoteEvents, and
	  character/vehicle attribute signals.
	- Implements the Chaos Combo Tracker:
	  * 4.5s dynamic base combo timer that refreshes on every hit or stunt.
	  * Multiplier tiers: 1x -> 2x -> 3x -> 5x -> 8x -> 10x OVERDRIVE!
	  * Style callouts: "SMASH!", "HYDRO BLAST!", "CHAIN EXPLOSION!",
	    "MEGA AIR!", "DRIFT KING!", "COP TAKEDOWN!", plus "NEAR MISS!" &
	    "10x OVERDRIVE!".
	  * Continuously scales cash & chaos points by (ComboMultiplier * CashMagnetMultiplier * WantedHeatMultiplier)
	    and banks a 25% combo completion bonus when a big combo finishes.
	- Runs cycling Live Chaos Missions / Timed Challenges (e.g.
	  "60s Destruction Derby: Cause $5,000 damage!",
	  "Smash 10 Fire Hydrants!",
	  "Survive 3-Star Heat for 45s!") with automatic rotation and payouts.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- Constants & Tuning
--------------------------------------------------------------------------------
local COMBO_BASE_WINDOW = 4.5 -- seconds before an active combo finishes & banks bonus
local COMBO_BONUS_RATE = 0.25 -- +25% bonus cash banked when a combo chain >= 3 completes
local MISSION_INTERMISSION = 6.0 -- seconds between timed Live Chaos Missions
local REMOTE_RATE_LIMIT = 0.04 -- anti-spam minimum interval for client stunt reports

-- Multiplier Tiers: 1x -> 2x -> 3x -> 5x -> 8x -> 10x OVERDRIVE!
local MULTIPLIER_TIERS = {
	{ MinChain = 20, Multiplier = 10, IsOverdrive = true, Label = "10x OVERDRIVE!" },
	{ MinChain = 13, Multiplier = 8, IsOverdrive = false, Label = "8x MAYHEM!" },
	{ MinChain = 8, Multiplier = 5, IsOverdrive = false, Label = "5x RAMPAGE!" },
	{ MinChain = 5, Multiplier = 3, IsOverdrive = false, Label = "3x DESTRUCTION!" },
	{ MinChain = 2, Multiplier = 2, IsOverdrive = false, Label = "2x COMBO!" },
	{ MinChain = 0, Multiplier = 1, IsOverdrive = false, Label = "1x" },
}

-- Wanted Heat Risk-Reward Cash Multiplier (mirrors original Swift wantedBountyMultiplier)
local WANTED_BOUNTY_MULTIPLIER: { [number]: number } = {
	[0] = 1.0,
	[1] = 1.25,
	[2] = 1.5,
	[3] = 2.0,
	[4] = 2.5,
	[5] = 3.0,
}

--------------------------------------------------------------------------------
-- 5-Act Story Campaign ("OPERATION: TAKE BACK LEO CITY") + Live Chaos Missions
--------------------------------------------------------------------------------
export type CampaignActDefinition = {
	Act: number,
	Id: string,
	ActBadge: string,
	Title: string,
	StoryText: string,
	ObjectiveText: string,
	Goal: number,
	RewardCash: number,
	RewardChaos: number,
	Kind: "PropsCount" | "HydrantsOrProps" | "DamageValue" | "StuntsAndCops" | "BossFinale",
}

local CAMPAIGN_ACTS: { CampaignActDefinition } = {
	{
		Act = 1,
		Id = "act_1_break_out",
		ActBadge = "ACT 1/5: BREAK OUT OF LEO PLAZA",
		Title = "ACT 1/5: BREAK OUT OF LEO PLAZA",
		StoryText = "Mayor Vance & MegaCorp have locked down Leo Plaza with surveillance barriers. Spark the uprising!",
		ObjectiveText = "Smash 12 MegaCorp Props or Barriers to spark the uprising!",
		Goal = 12,
		RewardCash = 2500,
		RewardChaos = 3500,
		Kind = "PropsCount",
	},
	{
		Act = 2,
		Id = "act_2_midtown_grid",
		ActBadge = "ACT 2/5: FLOOD THE MIDTOWN GRID",
		Title = "ACT 2/5: FLOOD THE MIDTOWN GRID",
		StoryText = "Cut off MegaCorp's downtown surveillance grid by wrecking hydrants and street power poles!",
		ObjectiveText = "Smash 6 Fire Hydrants or Streetlights & reach a 3x Chaos Combo!",
		Goal = 6,
		RewardCash = 5000,
		RewardChaos = 7500,
		Kind = "HydrantsOrProps",
	},
	{
		Act = 3,
		Id = "act_3_industrial_sabotage",
		ActBadge = "ACT 3/5: INDUSTRIAL SABOTAGE",
		Title = "ACT 3/5: INDUSTRIAL SABOTAGE",
		StoryText = "Cripple MegaCorp's supply depots and fuel reserves across the industrial sector!",
		ObjectiveText = "Cause $15,000 in Destruction Value or detonate Boom Gas Station!",
		Goal = 15000,
		RewardCash = 10000,
		RewardChaos = 15000,
		Kind = "DamageValue",
	},
	{
		Act = 4,
		Id = "act_4_break_blockade",
		ActBadge = "ACT 4/5: BREAK THE BLOCKADE",
		Title = "ACT 4/5: BREAK THE BLOCKADE",
		StoryText = "MegaCorp Enforcers have blockaded the avenues! Launch over their traps and wreck their cruisers!",
		ObjectiveText = "Land 2 Stunt Jumps or Drifts & Wreck 1 Enforcer Cruiser!",
		Goal = 3,
		RewardCash = 18000,
		RewardChaos = 25000,
		Kind = "StuntsAndCops",
	},
	{
		Act = 5,
		Id = "act_5_goliath_finale",
		ActBadge = "ACT 5/5 FINALE: DEFEAT MAYOR VANCE'S GOLIATH CONVOY",
		Title = "ACT 5/5: DEFEAT MAYOR VANCE'S GOLIATH CONVOY",
		StoryText = "FINAL SHOWDOWN! Mayor Vance's armored Boss Goliath is patrolling Grand Central Ave. Ram it to liberate Leo City!",
		ObjectiveText = "Ram & Destroy Mayor Vance's Boss Goliath Convoy on Grand Central Ave!",
		Goal = 1000,
		RewardCash = 50000,
		RewardChaos = 75000,
		Kind = "BossFinale",
	},
}

export type MissionDefinition = {
	Id: string,
	Title: string,
	Description: string,
	Duration: number,
	Goal: number,
	RewardCash: number,
	RewardChaos: number,
	Kind: "DamageValue" | "Hydrants" | "SurviveHeat" | "ComboMultiplier" | "Airtime" | "DriftScore" | "CopTakedowns" | "PropsCount",
	RequiredHeatStars: number?,
}

local LIVE_CHAOS_MISSIONS: { MissionDefinition } = {
	{
		Id = "destruction_derby_5k",
		Title = "60s Destruction Derby: Cause $5,000 damage!",
		Description = "Smash props, cars, and structures to rack up $5,000 in chaos value within 60s!",
		Duration = 60,
		Goal = 5000,
		RewardCash = 1200,
		RewardChaos = 2500,
		Kind = "DamageValue",
	},
	{
		Id = "smash_10_hydrants",
		Title = "Smash 10 Fire Hydrants!",
		Description = "Blast through 10 Fire Hydrants or street water mains for HYDRO BLAST bonuses!",
		Duration = 60,
		Goal = 10,
		RewardCash = 1000,
		RewardChaos = 2000,
		Kind = "Hydrants",
	},
	{
		Id = "survive_3star_heat",
		Title = "Survive 3-Star Heat for 45s!",
		Description = "Keep at least 3-Star Police Heat and evade getting BUSTED for 45 seconds!",
		Duration = 75,
		Goal = 45,
		RewardCash = 1500,
		RewardChaos = 3000,
		Kind = "SurviveHeat",
		RequiredHeatStars = 3,
	},
	{
		Id = "overdrive_combo",
		Title = "Reach 8x Combo Multiplier!",
		Description = "Chain hits, drifts, and jumps without letting your 4.5s combo timer expire!",
		Duration = 50,
		Goal = 8,
		RewardCash = 900,
		RewardChaos = 1800,
		Kind = "ComboMultiplier",
	},
	{
		Id = "cop_takedown_spree",
		Title = "Wreck 3 Police Cruisers!",
		Description = "Ram pursuing Police units at high speed for COP TAKEDOWN bonuses!",
		Duration = 65,
		Goal = 3,
		RewardCash = 1350,
		RewardChaos = 2700,
		Kind = "CopTakedowns",
	},
	{
		Id = "drift_and_air_challenge",
		Title = "Score 1,500 Drift & Stunt Points!",
		Description = "Slide around city corners and launch off stunt ramps for MEGA AIR & DRIFT KING!",
		Duration = 55,
		Goal = 1500,
		RewardCash = 950,
		RewardChaos = 1900,
		Kind = "DriftScore",
	},
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

local serverEventsFolder = ensureFolder(ServerStorage, "Events")
local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")

-- ServerStorage BindableEvents & BindableFunctions
local DestructionBindable = ensureBindableEvent(ServerStorage, "DestructionEvent")
local OnObjectDestroyedBindable = ensureBindableEvent(ServerStorage, "OnObjectDestroyed")
local StuntBindable = ensureBindableEvent(ServerStorage, "StuntEvent")
local PoliceTakedownBindable = ensureBindableEvent(ServerStorage, "PoliceTakedownEvent")
local AddCashBindable = ensureBindableEvent(ServerStorage, "AddCashEvent")
local SpendCashFunction = ensureBindableFunction(ServerStorage, "SpendCashFunction")
local AddHeatBindable = ensureBindableEvent(ServerStorage, "AddHeatEvent")
local PlayerBustedBindable = ensureBindableEvent(ServerStorage, "PlayerBustedEvent")
local UpdatePlayerDataBindable = ensureBindableEvent(ServerStorage, "UpdatePlayerDataEvent")
local AwardXPBindable = ensureBindableEvent(ServerStorage, "AwardXPEvent")
local RepairPlayerVehicleBindable = ensureBindableEvent(ServerStorage, "RepairPlayerVehicleEvent")

-- Mirror in ServerStorage.Events for scripts expecting subfolder hierarchy
local FolderDestructionBindable = ensureBindableEvent(serverEventsFolder, "DestructionEvent")
local FolderStuntBindable = ensureBindableEvent(serverEventsFolder, "StuntEvent")
local FolderPoliceTakedownBindable = ensureBindableEvent(serverEventsFolder, "PoliceTakedownEvent")
local FolderAddCashBindable = ensureBindableEvent(serverEventsFolder, "AddCashEvent")
local FolderAddHeatBindable = ensureBindableEvent(serverEventsFolder, "AddHeatEvent")
local FolderPlayerBustedBindable = ensureBindableEvent(serverEventsFolder, "PlayerBustedEvent")

-- ReplicatedStorage RemoteEvents (both in ReplicatedStorage.Remotes and root ReplicatedStorage)
local ReportDestructionRemote = ensureRemoteEvent(remotesFolder, "ReportDestruction")
local ReportStuntRemote = ensureRemoteEvent(remotesFolder, "ReportStunt")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")
local ComboCompletedRemote = ensureRemoteEvent(remotesFolder, "ComboCompleted")
local MissionUpdateRemote = ensureRemoteEvent(remotesFolder, "MissionUpdate")
local CampaignUpdateRemote = ensureRemoteEvent(remotesFolder, "CampaignUpdate")
local BossUpdateRemote = ensureRemoteEvent(remotesFolder, "BossUpdate")
local ReportBossImpactRemote = ensureRemoteEvent(remotesFolder, "ReportBossImpact")
local NotificationRemote = ensureRemoteEvent(remotesFolder, "Notification")
local SkipMissionRemote = ensureRemoteEvent(remotesFolder, "SkipMission")

-- Root aliases in ReplicatedStorage for broad compatibility
local RootDestructionRemote = ensureRemoteEvent(ReplicatedStorage, "DestructionEvent")
local RootStuntRemote = ensureRemoteEvent(ReplicatedStorage, "StuntEvent")
local RootStyleCalloutRemote = ensureRemoteEvent(ReplicatedStorage, "StyleCalloutEvent")
local RootMissionUpdateRemote = ensureRemoteEvent(ReplicatedStorage, "MissionUpdateEvent")

--------------------------------------------------------------------------------
-- Per-Player Runtime State
--------------------------------------------------------------------------------
type PlayerChaosState = {
	ComboCount: number,
	ComboMultiplier: number,
	ComboTimer: number,
	UnbankedComboCash: number,
	CurrentStreakName: string,
	JackpotCharge: number,
	JackpotSpinsCount: number,
	GoldenFrenzyRemaining: number,
	CampaignAct: number,
	CampaignProgress: number,
	CampaignCompleted: boolean,
	MissionIndex: number,
	MissionProgress: number,
	MissionTimeRemaining: number,
	MissionIntermission: number,
	HeatSurvivalAccumulator: number,
	LastClientReportAt: number,
	LastBossHitAt: number,
}

local playerStates: { [number]: PlayerChaosState } = {}

--------------------------------------------------------------------------------
-- Next Vehicle Unlock Progression Ladder
-- (Sedan -> Muscle -> SUV -> Pickup -> Sports -> MonsterTruck -> Bulldozer)
--------------------------------------------------------------------------------
export type VehicleUnlockMilestone = {
	Id: string,
	DisplayName: string,
	Tier: string,
	UnlockCost: number,
	UnlockLevel: number,
}

local VEHICLE_UNLOCK_LADDER: { VehicleUnlockMilestone } = {
	{ Id = "Sedan", DisplayName = "CRUISER V8 Sedan", Tier = "Street", UnlockCost = 250, UnlockLevel = 2 },
	{ Id = "Muscle", DisplayName = "V8 Hellfire Muscle", Tier = "Muscle", UnlockCost = 650, UnlockLevel = 4 },
	{ Id = "SUV", DisplayName = "TITAN 4x4 SUV", Tier = "Heavy", UnlockCost = 900, UnlockLevel = 6 },
	{ Id = "Pickup", DisplayName = "RANCH RAMMER Pickup", Tier = "Heavy", UnlockCost = 1200, UnlockLevel = 9 },
	{ Id = "Sports", DisplayName = "APEX GT Supercar", Tier = "Super", UnlockCost = 2000, UnlockLevel = 12 },
	{ Id = "MonsterTruck", DisplayName = "CRUSHER XL Monster Truck", Tier = "Demolition", UnlockCost = 3500, UnlockLevel = 16 },
	{ Id = "Bulldozer", DisplayName = "GOLIATH DOZER Bulldozer", Tier = "Siege", UnlockCost = 5500, UnlockLevel = 22 },
}

local function isVehicleOwnedByPlayer(player: Player, vehicleId: string): boolean
	if player:GetAttribute("Unlocked_" .. vehicleId) == true or player:GetAttribute("Owned_" .. vehicleId) == true then
		return true
	end
	local eq = tostring(player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle") or "")
	if string.lower(eq) == string.lower(vehicleId) then
		return true
	end
	local ownedCsv = tostring(player:GetAttribute("OwnedVehicles") or player:GetAttribute("UnlockedVehicles") or "")
	if ownedCsv ~= "" and string.find(string.lower(ownedCsv), string.lower(vehicleId), 1, true) ~= nil then
		return true
	end
	return false
end

local function updateNextVehicleUnlockAttributes(player: Player)
	local cash = math.max(0, tonumber(player:GetAttribute("Cash")) or 0)

	local targetVehicle: VehicleUnlockMilestone? = nil
	for _, milestone in ipairs(VEHICLE_UNLOCK_LADDER) do
		if not isVehicleOwnedByPlayer(player, milestone.Id) then
			targetVehicle = milestone
			break
		end
	end

	if not targetVehicle then
		local lastMilestone = VEHICLE_UNLOCK_LADDER[#VEHICLE_UNLOCK_LADDER]
		player:SetAttribute("NextUnlockVehicleId", lastMilestone.Id)
		player:SetAttribute("NextUnlockVehicleName", lastMilestone.DisplayName .. " (MAXED!)")
		player:SetAttribute("NextUnlockVehicleCost", lastMilestone.UnlockCost)
		player:SetAttribute("NextUnlockVehicleTier", lastMilestone.Tier)
		player:SetAttribute("NextUnlockProgressRatio", 1.0)
		player:SetAttribute("CanAffordNextVehicle", cash >= lastMilestone.UnlockCost)
		return
	end

	local canAfford = cash >= targetVehicle.UnlockCost
	local progressRatio = math.clamp(cash / math.max(1, targetVehicle.UnlockCost), 0, 1)
	if canAfford then
		progressRatio = 1.0
	end

	player:SetAttribute("NextUnlockVehicleId", targetVehicle.Id)
	player:SetAttribute("NextUnlockVehicleName", targetVehicle.DisplayName)
	player:SetAttribute("NextUnlockVehicleCost", targetVehicle.UnlockCost)
	player:SetAttribute("NextUnlockVehicleTier", targetVehicle.Tier)
	player:SetAttribute("NextUnlockProgressRatio", tonumber(string.format("%.3f", progressRatio)))
	player:SetAttribute("CanAffordNextVehicle", canAfford)
end

local function getMagnetMultiplier(player: Player): number
	local attrMult = player:GetAttribute("CashMagnetMultiplier")
	if type(attrMult) == "number" and attrMult >= 1 then
		return attrMult
	end
	local magnetLvl = tonumber(player:GetAttribute("Upgrade_Magnet") or player:GetAttribute("MagnetLevel")) or 1
	-- Level 1 = 1.0x, Level 2 = 1.15x, Level 3 = 1.35x, Level 4 = 1.60x, Level 5 = 2.0x
	local tableMult = { 1.0, 1.15, 1.35, 1.60, 2.0 }
	return tableMult[math.clamp(math.floor(magnetLvl), 1, 5)] or 1.0
end

local function getWantedMultiplier(player: Player): number
	local stars = math.clamp(math.floor(tonumber(player:GetAttribute("HeatStars")) or 0), 0, 5)
	return WANTED_BOUNTY_MULTIPLIER[stars] or 1.0
end

local function computeMultiplierTier(chain: number): (number, boolean, string)
	for _, tier in ipairs(MULTIPLIER_TIERS) do
		if chain >= tier.MinChain then
			return tier.Multiplier, tier.IsOverdrive, tier.Label
		end
	end
	return 1, false, "1x"
end

--------------------------------------------------------------------------------
-- Leaderstats & Attributes Setup
--------------------------------------------------------------------------------
local function ensurePlayerSetup(player: Player): Folder
	local ls = player:FindFirstChild("leaderstats")
	if not (ls and ls:IsA("Folder")) then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local function ensureIntValue(name: string, defaultValue: number): IntValue
		local existing = ls:FindFirstChild(name)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		local iv = Instance.new("IntValue")
		iv.Name = name
		iv.Value = defaultValue
		iv.Parent = ls
		return iv
	end

	local initialCash = tonumber(player:GetAttribute("Cash")) or 500
	local initialChaos = tonumber(player:GetAttribute("ChaosScore")) or 0
	local initialMaxCombo = tonumber(player:GetAttribute("MaxCombo")) or 0
	local initialHeat = tonumber(player:GetAttribute("HeatStars")) or 0

	ensureIntValue("Cash", initialCash)
	ensureIntValue("ChaosScore", initialChaos)
	ensureIntValue("MaxCombo", initialMaxCombo)
	ensureIntValue("HeatLevel", initialHeat)

	-- Required Player Attributes
	if player:GetAttribute("Cash") == nil then
		player:SetAttribute("Cash", initialCash)
	end
	if player:GetAttribute("ChaosScore") == nil then
		player:SetAttribute("ChaosScore", initialChaos)
	end
	if player:GetAttribute("MaxCombo") == nil then
		player:SetAttribute("MaxCombo", initialMaxCombo)
	end
	player:SetAttribute("ComboCount", 0)
	player:SetAttribute("ComboMultiplier", 1)
	player:SetAttribute("ComboTimer", 0)
	player:SetAttribute("ComboTimerRatio", 0)
	player:SetAttribute("ComboMaxTime", COMBO_BASE_WINDOW)
	if player:GetAttribute("HeatStars") == nil then
		player:SetAttribute("HeatStars", 0)
	end
	if player:GetAttribute("HeatProgress") == nil then
		player:SetAttribute("HeatProgress", 0)
	end
	player:SetAttribute("CurrentStreakName", "")
	player:SetAttribute("UnbankedComboCash", 0)
	if player:GetAttribute("JackpotCharge") == nil then
		player:SetAttribute("JackpotCharge", 0)
	end
	if player:GetAttribute("JackpotSpinsCount") == nil then
		player:SetAttribute("JackpotSpinsCount", 0)
	end
	player:SetAttribute("Golden3xFrenzyActive", false)
	player:SetAttribute("Golden3xFrenzyRemaining", 0)
	updateNextVehicleUnlockAttributes(player)

	return ls
end

--------------------------------------------------------------------------------
-- Economy Helpers (Cash & ChaosScore)
--------------------------------------------------------------------------------
local function addCash(player: Player, amount: number, _reason: string?): number
	local delta = math.floor(amount)
	if delta <= 0 then
		return tonumber(player:GetAttribute("Cash")) or 0
	end

	local current = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0))
	local newCash = current + delta
	player:SetAttribute("Cash", newCash)

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash") :: IntValue?
		if cashVal then
			cashVal.Value = newCash
		end
	end

	updateNextVehicleUnlockAttributes(player)
	return newCash
end

local function debitCash(player: Player, amount: number, _reason: string?): boolean
	local cost = math.floor(amount)
	if cost <= 0 then
		return true
	end
	local current = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0))
	if current < cost then
		return false
	end

	local newCash = current - cost
	player:SetAttribute("Cash", newCash)

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash") :: IntValue?
		if cashVal then
			cashVal.Value = newCash
		end
	end

	updateNextVehicleUnlockAttributes(player)
	return true
end

local function addChaosScore(player: Player, points: number)
	local delta = math.floor(points)
	if delta <= 0 then
		return
	end
	local current = math.max(0, math.floor(tonumber(player:GetAttribute("ChaosScore")) or 0))
	local newScore = current + delta
	player:SetAttribute("ChaosScore", newScore)

	local highScore = math.max(0, math.floor(tonumber(player:GetAttribute("HighScore")) or 0))
	if newScore > highScore then
		player:SetAttribute("HighScore", newScore)
	end

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local chaosVal = ls:FindFirstChild("ChaosScore") :: IntValue?
		if chaosVal then
			chaosVal.Value = newScore
		end
	end
end

--------------------------------------------------------------------------------
-- 5-Act Campaign & Act 5 Boss Goliath Convoy Management
--------------------------------------------------------------------------------
local BOSS_MAX_HEALTH = 1000
local activeBossModel: Model? = nil
local activeBossHull: BasePart? = nil
local activeBossHpFill: Frame? = nil
local activeBossHpLabel: TextLabel? = nil
local activeBossHealth = BOSS_MAX_HEALTH
local bossPatrolPhase = 0

local function getCampaignActDef(actNum: number): CampaignActDefinition
	local clamped = math.clamp(math.floor(actNum), 1, #CAMPAIGN_ACTS)
	return CAMPAIGN_ACTS[clamped]
end

local function spawnBossGoliathConvoy(): Model
	if activeBossModel and activeBossModel.Parent then
		return activeBossModel
	end

	local existing = Workspace:FindFirstChild("MegaCorpBossConvoy")
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end

	local m = Instance.new("Model")
	m.Name = "MegaCorpBossConvoy"
	m:SetAttribute("IsBossConvoy", true)
	m:SetAttribute("BossMaxHealth", BOSS_MAX_HEALTH)
	m:SetAttribute("BossHealth", BOSS_MAX_HEALTH)
	activeBossHealth = BOSS_MAX_HEALTH

	local hull = Instance.new("Part")
	hull.Name = "GoliathHull"
	hull.Size = Vector3.new(9.5, 6.2, 22.0)
	hull.CFrame = CFrame.new(0, 3.8, -80)
	hull.Color = Color3.fromRGB(22, 24, 32)
	hull.Material = Enum.Material.Metal
	hull.Anchored = true
	hull.CanCollide = true
	hull.TopSurface = Enum.SurfaceType.Smooth
	hull.BottomSurface = Enum.SurfaceType.Smooth
	hull.Parent = m

	local goldTrim = Instance.new("Part")
	goldTrim.Name = "GoldArmorBelt"
	goldTrim.Size = Vector3.new(9.9, 1.4, 22.4)
	goldTrim.CFrame = hull.CFrame * CFrame.new(0, 0.4, 0)
	goldTrim.Color = Color3.fromRGB(255, 200, 45)
	goldTrim.Material = Enum.Material.Metal
	goldTrim.Anchored = false
	goldTrim.CanCollide = false
	goldTrim.Parent = m

	local plow = Instance.new("WedgePart")
	plow.Name = "GoliathRamPlow"
	plow.Size = Vector3.new(10.4, 3.8, 4.2)
	plow.CFrame = hull.CFrame * CFrame.new(0, -1.0, -12.6)
	plow.Color = Color3.fromRGB(255, 185, 35)
	plow.Material = Enum.Material.DiamondPlate
	plow.Anchored = false
	plow.CanCollide = false
	plow.Parent = m

	local beacon = Instance.new("Part")
	beacon.Name = "BossBeacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(12.0, 2.2, 2.2)
	beacon.CFrame = hull.CFrame * CFrame.new(0, 9.0, 0) * CFrame.Angles(0, 0, math.rad(90))
	beacon.Color = Color3.fromRGB(255, 45, 55)
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.25
	beacon.Anchored = false
	beacon.CanCollide = false
	beacon.Parent = m

	for _, child in ipairs({ goldTrim, plow, beacon }) do
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = hull
		wc.Part1 = child
		wc.Parent = hull
	end

	-- 3D Floating Boss Health Bar BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "BossHealthBillboard"
	bb.Size = UDim2.fromOffset(260, 64)
	bb.StudsOffset = Vector3.new(0, 8.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 450
	bb.Parent = hull

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 45)
	stroke.Thickness = 2.5
	stroke.Parent = card

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -12, 0, 26)
	titleLbl.Position = UDim2.fromOffset(6, 4)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.Text = "MAYOR VANCE • BOSS GOLIATH [RAM ME!]"
	titleLbl.TextColor3 = Color3.fromRGB(255, 215, 55)
	titleLbl.TextScaled = true
	titleLbl.Parent = card

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -16, 0, 20)
	barBg.Position = UDim2.fromOffset(8, 34)
	barBg.BackgroundColor3 = Color3.fromRGB(36, 20, 24)
	barBg.BorderSizePixel = 0
	barBg.Parent = card

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 55, 65)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = barFill

	local hpText = Instance.new("TextLabel")
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.GothamBlack
	hpText.Text = string.format("HP: %d / %d", BOSS_MAX_HEALTH, BOSS_MAX_HEALTH)
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.TextScaled = true
	hpText.Parent = barBg

	m.PrimaryPart = hull
	m.Parent = Workspace

	activeBossModel = m
	activeBossHull = hull
	activeBossHpFill = barFill
	activeBossHpLabel = hpText
	return m
end

local function spawnGoldCashCrateDrop(pos: Vector3)
	local crate = Instance.new("Part")
	crate.Name = "BossGoldCrate"
	crate.Size = Vector3.new(2.6, 2.6, 2.6)
	crate.Position = pos + Vector3.new((math.random() - 0.5) * 8, 4.5, (math.random() - 0.5) * 8)
	crate.Color = Color3.fromRGB(255, 210, 45)
	crate.Material = Enum.Material.Neon
	crate.Anchored = false
	crate.CanCollide = false
	crate.Parent = Workspace
	crate.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 28, 22, (math.random() - 0.5) * 28)
	Debris:AddItem(crate, 2.5)
end

local function syncCampaignAttributesToPlayer(player: Player, state: PlayerChaosState)
	local actDef = getCampaignActDef(state.CampaignAct)
	local bossPos = if activeBossHull and activeBossHull.Parent then activeBossHull.Position else Vector3.new(0, 3.8, -80)
	local isBossAct = (state.CampaignAct == 5 and not state.CampaignCompleted)

	player:SetAttribute("CampaignAct", state.CampaignAct)
	player:SetAttribute("CampaignTotalActs", #CAMPAIGN_ACTS)
	player:SetAttribute("CampaignActTitle", actDef.Title)
	player:SetAttribute("CampaignStoryText", actDef.StoryText)
	player:SetAttribute("CampaignObjectiveText", actDef.ObjectiveText)
	player:SetAttribute("CampaignProgress", math.min(actDef.Goal, math.floor(state.CampaignProgress)))
	player:SetAttribute("CampaignGoal", actDef.Goal)
	player:SetAttribute("CampaignRewardCash", actDef.RewardCash)
	player:SetAttribute("CampaignCompleted", state.CampaignCompleted)

	player:SetAttribute("BossActive", isBossAct)
	player:SetAttribute("BossHealth", if isBossAct then math.max(0, math.floor(activeBossHealth)) else 0)
	player:SetAttribute("BossMaxHealth", BOSS_MAX_HEALTH)
	player:SetAttribute("BossPosition", bossPos)

	-- Keep Mission* attributes synced to Campaign Act while Campaign is in progress so HUD works seamlessly
	if not state.CampaignCompleted then
		player:SetAttribute("MissionId", actDef.Id)
		player:SetAttribute("MissionTitle", actDef.Title .. " — " .. actDef.ObjectiveText)
		player:SetAttribute("MissionDescription", actDef.StoryText)
		player:SetAttribute("MissionProgress", math.min(actDef.Goal, math.floor(state.CampaignProgress)))
		player:SetAttribute("MissionGoal", actDef.Goal)
		player:SetAttribute("MissionReward", actDef.RewardCash)
	end

	CampaignUpdateRemote:FireClient(player, {
		Act = state.CampaignAct,
		TotalActs = #CAMPAIGN_ACTS,
		ActTitle = actDef.Title,
		StoryText = actDef.StoryText,
		ObjectiveText = actDef.ObjectiveText,
		Progress = math.min(actDef.Goal, math.floor(state.CampaignProgress)),
		Goal = actDef.Goal,
		RewardCash = actDef.RewardCash,
		Completed = state.CampaignCompleted,
		BossActive = isBossAct,
		BossHealth = activeBossHealth,
		BossMaxHealth = BOSS_MAX_HEALTH,
		BossPosition = bossPos,
	})
end

local function advanceCampaignProgress(player: Player, eventKind: string, amount: number)
	local state = playerStates[player.UserId]
	if not state or state.CampaignCompleted then
		return
	end

	local actDef = getCampaignActDef(state.CampaignAct)
	local matched = false

	if actDef.Kind == "PropsCount" and (eventKind == "PropsCount" or eventKind == "Hydrants") then
		state.CampaignProgress += amount
		matched = true
	elseif actDef.Kind == "HydrantsOrProps" and (eventKind == "Hydrants" or eventKind == "PropsCount" or eventKind == "Combo3x") then
		state.CampaignProgress += amount
		matched = true
	elseif actDef.Kind == "DamageValue" and (eventKind == "DamageValue" or eventKind == "GasExplosion") then
		state.CampaignProgress += amount
		matched = true
	elseif actDef.Kind == "StuntsAndCops" and (eventKind == "Stunt" or eventKind == "CopTakedowns" or eventKind == "PropsCount") then
		state.CampaignProgress += amount
		matched = true
	elseif actDef.Kind == "BossFinale" and (eventKind == "BossDamage" or eventKind == "DamageValue") then
		state.CampaignProgress += amount
		matched = true
	end

	if not matched then
		return
	end

	if state.CampaignProgress >= actDef.Goal then
		-- Act Completed!
		local magnetMult = getMagnetMultiplier(player)
		local rewardCash = math.floor(actDef.RewardCash * magnetMult)
		local rewardChaos = math.floor(actDef.RewardChaos * magnetMult)
		addCash(player, rewardCash, "CampaignAct" .. tostring(state.CampaignAct))
		addChaosScore(player, rewardChaos)

		if state.CampaignAct < #CAMPAIGN_ACTS then
			local completedActNum = state.CampaignAct
			state.CampaignAct += 1
			state.CampaignProgress = 0
			if state.CampaignAct == 5 then
				spawnBossGoliathConvoy()
			end
			syncCampaignAttributesToPlayer(player, state)

			local nextActDef = getCampaignActDef(state.CampaignAct)
			local bannerMsg = string.format("ACT %d COMPLETE! +$%d • NEXT: %s", completedActNum, rewardCash, nextActDef.Title)
			StyleCalloutRemote:FireClient(player, {
				Callout = bannerMsg,
				Multiplier = state.ComboMultiplier,
				ComboCount = state.ComboCount,
				CashAwarded = rewardCash,
				ChaosAwarded = rewardChaos,
				IsMissionBanner = true,
			})
			NotificationRemote:FireClient(player, bannerMsg, "Campaign")
		else
			-- ACT 5 GRAND FINALE VICTORY!
			state.CampaignProgress = actDef.Goal
			state.CampaignCompleted = true
			activeBossHealth = 0
			if activeBossModel and activeBossModel.Parent then
				activeBossModel:Destroy()
				activeBossModel = nil
				activeBossHull = nil
			end
			syncCampaignAttributesToPlayer(player, state)

			-- Award 5,000 XP via DestructionBindable / XPGained if available
			local xpEvent = ServerStorage:FindFirstChild("AwardXPEvent")
			if xpEvent and xpEvent:IsA("BindableEvent") then
				xpEvent:Fire(player, 5000, "CampaignVictory")
			end

			local victoryMsg = "VICTORY! LEO CITY LIBERATED! +$50,000"
			StyleCalloutRemote:FireClient(player, {
				Callout = victoryMsg,
				Multiplier = 10,
				IsOverdrive = true,
				ComboCount = state.ComboCount,
				CashAwarded = rewardCash,
				ChaosAwarded = rewardChaos,
				IsMissionBanner = true,
			})
			NotificationRemote:FireClient(player, victoryMsg, "Victory")
		end
	else
		syncCampaignAttributesToPlayer(player, state)
	end
end

local function damageBossConvoy(player: Player, rawDamage: number)
	local state = playerStates[player.UserId]
	if not state or state.CampaignCompleted or state.CampaignAct ~= 5 then
		return
	end
	local now = os.clock()
	if now - state.LastBossHitAt < 0.45 then
		return
	end
	state.LastBossHitAt = now

	local dmg = math.clamp(math.floor(rawDamage), 200, 350)
	activeBossHealth = math.max(0, activeBossHealth - dmg)
	if activeBossModel then
		activeBossModel:SetAttribute("BossHealth", activeBossHealth)
	end
	if activeBossHpFill then
		activeBossHpFill.Size = UDim2.fromScale(math.clamp(activeBossHealth / BOSS_MAX_HEALTH, 0, 1), 1)
	end
	if activeBossHpLabel then
		activeBossHpLabel.Text = string.format("HP: %d / %d", activeBossHealth, BOSS_MAX_HEALTH)
	end
	if activeBossHull then
		spawnGoldCashCrateDrop(activeBossHull.Position)
	end

	addCash(player, 450, "BossGoliathHit")
	StyleCalloutRemote:FireClient(player, {
		Callout = string.format("GOLIATH HIT! -%d HP (+$450)", dmg),
		Multiplier = state.ComboMultiplier,
		ComboCount = state.ComboCount,
		CashAwarded = 450,
	})
	BossUpdateRemote:FireClient(player, {
		BossHealth = activeBossHealth,
		BossMaxHealth = BOSS_MAX_HEALTH,
		DamageDealt = dmg,
	})

	advanceCampaignProgress(player, "BossDamage", dmg)
end

ReportBossImpactRemote.OnServerEvent:Connect(function(player: Player, impactSpeed: any)
	local spd = math.clamp(tonumber(impactSpeed) or 65, 20, 160)
	damageBossConvoy(player, math.clamp(spd * 3.8, 220, 350))
end)

--------------------------------------------------------------------------------
-- Live Chaos Missions Management
--------------------------------------------------------------------------------
local function getActiveMissionDef(state: PlayerChaosState): MissionDefinition
	local idx = ((state.MissionIndex - 1) % #LIVE_CHAOS_MISSIONS) + 1
	return LIVE_CHAOS_MISSIONS[idx]
end

local function syncMissionToPlayer(player: Player, state: PlayerChaosState, status: string?)
	local def = getActiveMissionDef(state)
	-- While the 5-Act Story Campaign is active, keep MissionTitle/Progress/Goal synced to the Campaign Act!
	if not state.CampaignCompleted then
		syncCampaignAttributesToPlayer(player, state)
		return
	end
	player:SetAttribute("MissionId", def.Id)
	player:SetAttribute("MissionTitle", def.Title)
	player:SetAttribute("MissionDescription", def.Description)
	player:SetAttribute("MissionProgress", math.min(def.Goal, math.floor(state.MissionProgress)))
	player:SetAttribute("MissionGoal", def.Goal)
	player:SetAttribute("MissionTimeRemaining", math.max(0, math.ceil(state.MissionTimeRemaining)))
	player:SetAttribute("MissionReward", def.RewardCash)

	local payload = {
		Id = def.Id,
		Title = def.Title,
		Description = def.Description,
		Progress = math.min(def.Goal, math.floor(state.MissionProgress)),
		Goal = def.Goal,
		TimeRemaining = math.max(0, math.ceil(state.MissionTimeRemaining)),
		RewardCash = def.RewardCash,
		RewardChaos = def.RewardChaos,
		Status = status or "Active",
	}
	MissionUpdateRemote:FireClient(player, payload)
	RootMissionUpdateRemote:FireClient(player, payload)
end

local function startMission(player: Player, state: PlayerChaosState, missionIndex: number)
	state.MissionIndex = missionIndex
	state.MissionProgress = 0
	state.MissionIntermission = 0
	state.HeatSurvivalAccumulator = 0
	local def = getActiveMissionDef(state)
	state.MissionTimeRemaining = def.Duration
	syncMissionToPlayer(player, state, "Started")
end

local function advanceMissionProgress(player: Player, kind: string, amount: number)
	local state = playerStates[player.UserId]
	if not state or state.MissionIntermission > 0 or state.MissionTimeRemaining <= 0 then
		return
	end

	local def = getActiveMissionDef(state)
	if def.Kind ~= kind then
		return
	end

	if kind == "ComboMultiplier" then
		state.MissionProgress = math.max(state.MissionProgress, amount)
	else
		state.MissionProgress = math.min(def.Goal, state.MissionProgress + amount)
	end

	if state.MissionProgress >= def.Goal then
		-- Mission Complete!
		local magnetMult = getMagnetMultiplier(player)
		local finalCash = math.floor(def.RewardCash * magnetMult)
		local finalChaos = math.floor(def.RewardChaos * magnetMult)

		addCash(player, finalCash, "MissionComplete:" .. def.Id)
		addChaosScore(player, finalChaos)

		local completedCount = (tonumber(player:GetAttribute("MissionsCompleted")) or 0) + 1
		player:SetAttribute("MissionsCompleted", completedCount)

		state.MissionProgress = def.Goal
		state.MissionIntermission = MISSION_INTERMISSION
		syncMissionToPlayer(player, state, "Completed")

		StyleCalloutRemote:FireClient(player, {
			Callout = string.format("CHALLENGE COMPLETE! +$%d", finalCash),
			Multiplier = state.ComboMultiplier,
			ComboCount = state.ComboCount,
			CashAwarded = finalCash,
			ChaosAwarded = finalChaos,
			IsMissionBanner = true,
		})
	else
		syncMissionToPlayer(player, state, "Active")
	end
end

--------------------------------------------------------------------------------
-- Chaos Combo Tracker & Style Callouts
--------------------------------------------------------------------------------
local function resolveDestructionCallout(objectType: string, isChainExplosion: boolean?, multiplier: number): string
	local upper = string.upper(objectType)
	if isChainExplosion or string.find(upper, "EXPLOS") or string.find(upper, "TANK") or string.find(upper, "BARREL") or string.find(upper, "GAS") then
		return "CHAIN EXPLOSION!"
	elseif string.find(upper, "HYDRANT") or string.find(upper, "WATER") or string.find(upper, "FOUNTAIN") or string.find(upper, "HYDRO") then
		return "HYDRO BLAST!"
	elseif string.find(upper, "POLICE") or string.find(upper, "COP") or string.find(upper, "CRUISER") or string.find(upper, "SWAT") or string.find(upper, "INTERCEPTOR") then
		return "COP TAKEDOWN!"
	elseif multiplier >= 10 then
		return "10x OVERDRIVE!"
	else
		return "SMASH!"
	end
end

local function syncComboAttributes(player: Player, state: PlayerChaosState)
	player:SetAttribute("ComboCount", state.ComboCount)
	player:SetAttribute("ComboMultiplier", state.ComboMultiplier)
	player:SetAttribute("ComboTimer", tonumber(string.format("%.2f", state.ComboTimer)))
	player:SetAttribute("ComboTimerRatio", math.clamp(state.ComboTimer / COMBO_BASE_WINDOW, 0, 1))
	player:SetAttribute("CurrentStreakName", state.CurrentStreakName)
	player:SetAttribute("UnbankedComboCash", state.UnbankedComboCash)

	local maxCombo = math.max(0, math.floor(tonumber(player:GetAttribute("MaxCombo")) or 0))
	if state.ComboCount > maxCombo then
		player:SetAttribute("MaxCombo", state.ComboCount)
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local mcVal = ls:FindFirstChild("MaxCombo") :: IntValue?
			if mcVal then
				mcVal.Value = state.ComboCount
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Casino Jackpot Fever & Lucky Spin Progression System
--------------------------------------------------------------------------------
local JACKPOT_PRIZES = {
	{ Id = "MegaCash", Weight = 32, BaseTitle = "MEGA CASH JACKPOT! +$3,500" },
	{ Id = "GoldenFrenzy", Weight = 25, BaseTitle = "30s GOLDEN 3X FRENZY!" },
	{ Id = "SuperNitroRepair", Weight = 20, BaseTitle = "SUPER NITRO & FULL REPAIR JACKPOT!" },
	{ Id = "InstantLevelUp", Weight = 13, BaseTitle = "INSTANT LEVEL-UP JACKPOT!" },
	{ Id = "GrandRoyal", Weight = 10, BaseTitle = "GRAND ROYAL JACKPOT! +$10,000" },
}

local function triggerCasinoJackpotSpin(player: Player, state: PlayerChaosState, worldPosition: Vector3?)
	state.JackpotCharge = 0
	state.JackpotSpinsCount += 1
	player:SetAttribute("JackpotCharge", 0)
	player:SetAttribute("JackpotSpinsCount", state.JackpotSpinsCount)

	-- Weighted roll among the 5 exciting Casino Jackpot Prizes
	local totalWeight = 0
	for _, prize in ipairs(JACKPOT_PRIZES) do
		totalWeight += prize.Weight
	end
	local roll = math.random(1, totalWeight)
	local picked = JACKPOT_PRIZES[1]
	for _, prize in ipairs(JACKPOT_PRIZES) do
		if roll <= prize.Weight then
			picked = prize
			break
		end
		roll -= prize.Weight
	end

	local level = math.max(1, tonumber(player:GetAttribute("Level")) or 1)
	local levelScale = 1 + math.min((level - 1) * 0.08, 1.5)
	local prizeTitle = picked.BaseTitle
	local cashAwarded = 0
	local bonusMult = math.max(state.ComboMultiplier, 3)

	if picked.Id == "MegaCash" then
		cashAwarded = math.floor(3500 * levelScale)
		prizeTitle = "MEGA CASH JACKPOT! +$3,500"
		addCash(player, cashAwarded, "Jackpot_MegaCash")
		addChaosScore(player, cashAwarded * 2)
	elseif picked.Id == "GoldenFrenzy" then
		prizeTitle = "30s GOLDEN 3X FRENZY!"
		cashAwarded = 1500
		bonusMult = 3
		state.GoldenFrenzyRemaining = 30.0
		player:SetAttribute("Golden3xFrenzyActive", true)
		player:SetAttribute("Golden3xFrenzyRemaining", 30)
		addCash(player, cashAwarded, "Jackpot_GoldenFrenzy")
		addChaosScore(player, 4500)
	elseif picked.Id == "SuperNitroRepair" then
		prizeTitle = "SUPER NITRO & FULL REPAIR JACKPOT!"
		cashAwarded = 2000
		addCash(player, cashAwarded, "Jackpot_SuperNitroRepair")
		addChaosScore(player, 4000)
		player:SetAttribute("UnlimitedNitroRemaining", 15)
		player:SetAttribute("TouchNitro", true)
		RepairPlayerVehicleBindable:Fire(player)
		task.delay(6.0, function()
			if player and player.Parent then
				player:SetAttribute("TouchNitro", false)
			end
		end)
	elseif picked.Id == "InstantLevelUp" then
		prizeTitle = "INSTANT LEVEL-UP JACKPOT!"
		local xpReq = math.max(250, tonumber(player:GetAttribute("XPRequired")) or 500)
		cashAwarded = math.max(2500, level * 350)
		addCash(player, cashAwarded, "Jackpot_InstantLevelUp")
		addChaosScore(player, 5000)
		AwardXPBindable:Fire(player, xpReq, "CasinoJackpotInstantLevelUp")
	elseif picked.Id == "GrandRoyal" then
		cashAwarded = 10000
		prizeTitle = "GRAND ROYAL JACKPOT! +$10,000"
		bonusMult = 10
		addCash(player, cashAwarded, "Jackpot_GrandRoyal")
		addChaosScore(player, 20000)
	end

	updateNextVehicleUnlockAttributes(player)

	local spinPayload = {
		IsJackpotSpin = true,
		PrizeId = picked.Id,
		PrizeTitle = prizeTitle,
		Callout = "🎰 " .. prizeTitle,
		CashAwarded = cashAwarded,
		ChaosAwarded = cashAwarded * 2,
		Multiplier = bonusMult,
		ComboCount = state.ComboCount,
		JackpotSpinsCount = state.JackpotSpinsCount,
		Position = worldPosition,
	}
	StyleCalloutRemote:FireClient(player, spinPayload)
	RootStyleCalloutRemote:FireClient(player, spinPayload)
	NotificationRemote:FireClient(player, "🎰 CASINO JACKPOT: " .. prizeTitle, "Jackpot")
end

local function addJackpotCharge(player: Player, amount: number, worldPosition: Vector3?)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	state.JackpotCharge = math.clamp(state.JackpotCharge + math.floor(amount), 0, 100)
	player:SetAttribute("JackpotCharge", state.JackpotCharge)

	if state.JackpotCharge >= 100 then
		triggerCasinoJackpotSpin(player, state, worldPosition)
	end
end

local function registerComboAction(
	player: Player,
	baseCash: number,
	baseChaos: number,
	styleCallout: string,
	heatDelta: number,
	worldPosition: Vector3?
): (number, number)
	local state = playerStates[player.UserId]
	if not state then
		return 0, 0
	end

	-- Advance chain and refresh 4.5s dynamic combo timer
	state.ComboCount += 1
	state.ComboTimer = COMBO_BASE_WINDOW

	local mult, isOverdrive, _tierLabel = computeMultiplierTier(state.ComboCount)
	state.ComboMultiplier = mult

	-- Upgrade callout to 10x OVERDRIVE! on exact threshold crossing
	local finalCallout = styleCallout
	if isOverdrive and state.ComboCount == 20 then
		finalCallout = "10x OVERDRIVE!"
	end
	state.CurrentStreakName = finalCallout

	-- Scale reward by ComboMultiplier * CashMagnetMultiplier * WantedHeatMultiplier * Golden3xFrenzy
	local magnetMult = getMagnetMultiplier(player)
	local wantedMult = getWantedMultiplier(player)
	local frenzyMult = if state.GoldenFrenzyRemaining > 0 or player:GetAttribute("Golden3xFrenzyActive") == true then 3.0 else 1.0
	local totalScalar = mult * magnetMult * wantedMult * frenzyMult

	local awardedCash = math.max(1, math.floor(baseCash * totalScalar))
	local awardedChaos = math.max(5, math.floor(baseChaos * totalScalar))

	-- Continuously credit cash & chaos score AND accumulate unbanked combo bonus pool
	addCash(player, awardedCash, finalCallout)
	addChaosScore(player, awardedChaos)
	state.UnbankedComboCash += awardedCash

	syncComboAttributes(player, state)

	-- Advance active missions & 5-Act Story Campaign
	advanceMissionProgress(player, "DamageValue", awardedCash * 15)
	advanceMissionProgress(player, "ComboMultiplier", state.ComboMultiplier)
	advanceCampaignProgress(player, "DamageValue", awardedCash * 18)
	if state.ComboMultiplier >= 3 then
		advanceCampaignProgress(player, "Combo3x", 1)
	end

	-- Broadcast Heat increase to PoliceHeatService
	if heatDelta > 0 then
		AddHeatBindable:Fire(player, heatDelta, finalCallout, worldPosition)
	end

	-- Fire Style Callout to Client HUD
	local payload = {
		Callout = finalCallout,
		Multiplier = state.ComboMultiplier,
		IsOverdrive = isOverdrive,
		ComboCount = state.ComboCount,
		ComboTimer = state.ComboTimer,
		CashAwarded = awardedCash,
		ChaosAwarded = awardedChaos,
		Position = worldPosition,
	}
	StyleCalloutRemote:FireClient(player, payload)
	RootStyleCalloutRemote:FireClient(player, payload)

	return awardedCash, awardedChaos
end

local function finishAndBankCombo(player: Player, state: PlayerChaosState)
	local completedChain = state.ComboCount
	local comboEarned = state.UnbankedComboCash

	local bankedBonus = 0
	if completedChain >= 3 and comboEarned > 0 then
		local magnetMult = getMagnetMultiplier(player)
		bankedBonus = math.max(10, math.floor(comboEarned * COMBO_BONUS_RATE * magnetMult))
		addCash(player, bankedBonus, "ComboBankBonus")
		addChaosScore(player, bankedBonus * 2)
	end

	state.ComboCount = 0
	state.ComboMultiplier = 1
	state.ComboTimer = 0
	state.UnbankedComboCash = 0
	state.CurrentStreakName = ""
	syncComboAttributes(player, state)

	if completedChain >= 2 then
		ComboCompletedRemote:FireClient(player, {
			CompletedChain = completedChain,
			BankedBonusCash = bankedBonus,
			TotalComboCash = comboEarned + bankedBonus,
		})
	end
end

--------------------------------------------------------------------------------
-- Event Handlers: Destruction, Stunts (Air/Drift/Near-Miss), Cop Takedowns
--------------------------------------------------------------------------------
local function handleDestructionEvent(
	playerOrPayload: any,
	objectTypeOrInfo: any,
	baseCashReward: number?,
	worldPos: Vector3?,
	extraMeta: { [string]: any }?
)
	local player: Player = playerOrPayload
	if type(playerOrPayload) == "table" and objectTypeOrInfo == nil then
		player = playerOrPayload.player or playerOrPayload.Player
		objectTypeOrInfo = playerOrPayload
		baseCashReward = tonumber(playerOrPayload.cashEarned or playerOrPayload.CashReward)
		worldPos = playerOrPayload.position or playerOrPayload.Position
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local objectType = "Prop"
	local baseCash = tonumber(baseCashReward) or 25
	local pos = if typeof(worldPos) == "Vector3" then worldPos else nil
	local isChainExplosion = false
	-- Paced Police Heat per prop:
	-- Small/medium street props (Crate, Fence, Bench, TrashCan, Mailbox, Cone): 3.5 heat (~28 small props to trigger 1 Star!)
	-- Streetlights / Hydrants / Bus Stops / Billboards: 5.0 heat
	-- Gas Pumps / Explosive Barrels: 14.0 heat
	local heatGenerated = 3.5

	if type(objectTypeOrInfo) == "table" then
		objectType = tostring(objectTypeOrInfo.Type or objectTypeOrInfo.propType or objectTypeOrInfo.Category or objectTypeOrInfo.Name or "Prop")
		baseCash = tonumber(objectTypeOrInfo.CashReward or objectTypeOrInfo.cashEarned or objectTypeOrInfo.CoinReward or objectTypeOrInfo.Value) or baseCash
		if typeof(objectTypeOrInfo.Position) == "Vector3" then
			pos = objectTypeOrInfo.Position
		elseif typeof(objectTypeOrInfo.position) == "Vector3" then
			pos = objectTypeOrInfo.position
		end
		isChainExplosion = objectTypeOrInfo.IsExplosion == true or objectTypeOrInfo.isExplosion == true or objectTypeOrInfo.ChainExplosion == true
	elseif type(objectTypeOrInfo) == "string" then
		objectType = objectTypeOrInfo
	elseif typeof(objectTypeOrInfo) == "Instance" then
		objectType = objectTypeOrInfo:GetAttribute("DestructibleType")
			or objectTypeOrInfo:GetAttribute("Category")
			or objectTypeOrInfo.Name
		baseCash = tonumber(objectTypeOrInfo:GetAttribute("CashReward") or objectTypeOrInfo:GetAttribute("CoinReward")) or baseCash
		if objectTypeOrInfo:IsA("BasePart") then
			pos = objectTypeOrInfo.Position
		elseif objectTypeOrInfo:IsA("Model") and objectTypeOrInfo.PrimaryPart then
			pos = objectTypeOrInfo.PrimaryPart.Position
		end
	end

	if extraMeta and type(extraMeta) == "table" then
		if extraMeta.IsChainExplosion or extraMeta.IsExplosion then
			isChainExplosion = true
		end
	end

	local upperType = string.upper(objectType)
	local isJackpotCrate = (upperType == "JACKPOTCRATE") or (string.find(upperType, "JACKPOT") ~= nil)
	if type(objectTypeOrInfo) == "table" and (objectTypeOrInfo.isJackpotCrate == true or objectTypeOrInfo.IsJackpotCrate == true) then
		isJackpotCrate = true
	end

	local isGoldATM = (upperType == "GOLDATM") or (string.find(upperType, "ATM") ~= nil)
	local isArmoredCashTruck = (upperType == "ARMOREDCASH_TRUCK")
		or (upperType == "ARMOREDCASHTRUCK")
		or (string.find(upperType, "ARMORED") ~= nil and string.find(upperType, "TRUCK") ~= nil)
		or (string.find(upperType, "CASHTRUCK") ~= nil)
	local isMegaCorpBankVault = (upperType == "MEGACORPBANKVAULT")
		or (string.find(upperType, "VAULT") ~= nil)
		or (string.find(upperType, "BANK") ~= nil)

	if string.find(upperType, "LIGHT") or string.find(upperType, "HYDRANT") or string.find(upperType, "BUS") or string.find(upperType, "BILLBOARD") or string.find(upperType, "TOWER") then
		heatGenerated = 5.0
	end

	baseCash = math.clamp(math.floor(baseCash), 5, 2500)
	local baseChaos = baseCash * 3

	local state = playerStates[player.UserId]
	local nextMult = if state then select(1, computeMultiplierTier(state.ComboCount + 1)) else 1
	local callout = resolveDestructionCallout(objectType, isChainExplosion, nextMult)
	local highTierChargeBonus: number? = nil

	if isMegaCorpBankVault then
		baseCash = math.max(baseCash * 3, 550)
		baseChaos = math.max(baseChaos * 3, 1650)
		heatGenerated = 20.0
		callout = "BANK VAULT HEIST!"
		highTierChargeBonus = 50
	elseif isArmoredCashTruck then
		baseCash = math.max(baseCash * 2, 380)
		baseChaos = math.max(baseChaos * 2, 1140)
		heatGenerated = 15.0
		callout = "ARMORED TRUCK SMASH!"
		highTierChargeBonus = 40
	elseif isJackpotCrate then
		baseCash = math.max(baseCash * 2, 250)
		baseChaos = math.max(baseChaos * 2, 750)
		callout = "JACKPOT CRATE 3X!"
		highTierChargeBonus = 35
	elseif isGoldATM then
		baseCash = math.max(baseCash * 2, 200)
		baseChaos = math.max(baseChaos * 2, 600)
		heatGenerated = 8.0
		callout = "GOLD ATM BUST!"
		highTierChargeBonus = 25
	elseif callout == "CHAIN EXPLOSION!" then
		baseCash = math.floor(baseCash * 1.6)
		baseChaos = math.floor(baseChaos * 1.8)
		heatGenerated = 14.0
		advanceCampaignProgress(player, "GasExplosion", 5000)
	elseif callout == "HYDRO BLAST!" then
		baseCash = math.floor(baseCash * 1.35)
		baseChaos = math.floor(baseChaos * 1.4)
		heatGenerated = 5.0
		advanceMissionProgress(player, "Hydrants", 1)
		advanceCampaignProgress(player, "Hydrants", 1)
	elseif callout == "COP TAKEDOWN!" then
		baseCash = math.max(baseCash, 150)
		baseChaos = math.max(baseChaos, 500)
		heatGenerated = 18.0
		advanceMissionProgress(player, "CopTakedowns", 1)
		advanceCampaignProgress(player, "CopTakedowns", 1)
	end

	local totalDest = (tonumber(player:GetAttribute("TotalDestructions")) or 0) + 1
	player:SetAttribute("TotalDestructions", totalDest)
	advanceMissionProgress(player, "PropsCount", 1)
	advanceCampaignProgress(player, "PropsCount", 1)

	-- If player is in Act 5 and smashes props near the Boss Convoy, deal bonus collateral damage to Goliath!
	if state and state.CampaignAct == 5 and not state.CampaignCompleted then
		if pos and activeBossHull and (pos - activeBossHull.Position).Magnitude <= 85 then
			damageBossConvoy(player, 200)
		end
	end

	registerComboAction(player, baseCash, baseChaos, callout, heatGenerated, pos)

	-- Advance Casino Jackpot Fever Charge (+25 to +50 for high-tier targets: GoldATM, JackpotCrate, ArmoredCashTruck, MegaCorpBankVault; +9 to +18 for regular props!)
	local chargeGain = highTierChargeBonus or math.random(9, 18)
	if type(objectTypeOrInfo) == "table" and tonumber(objectTypeOrInfo.jackpotChargeGain) then
		chargeGain = math.max(chargeGain, tonumber(objectTypeOrInfo.jackpotChargeGain) :: number)
	end
	addJackpotCharge(player, chargeGain, pos)
end

local function handleStuntEvent(player: Player, stuntType: string, rawValue: number?, worldPos: Vector3?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local kind = string.upper(tostring(stuntType or "STUNT"))
	local val = math.max(0.1, tonumber(rawValue) or 1.0)
	local pos = if typeof(worldPos) == "Vector3" then worldPos else nil

	if string.find(kind, "AIR") or string.find(kind, "JUMP") then
		-- Airtime jump (val = seconds in air or height)
		local clampedAir = math.clamp(val, 0.4, 12.0)
		local baseCash = math.floor(35 * clampedAir)
		local baseChaos = math.floor(120 * clampedAir)
		registerComboAction(player, baseCash, baseChaos, "MEGA AIR!", 2.5, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
		advanceMissionProgress(player, "Airtime", math.ceil(clampedAir))
		advanceCampaignProgress(player, "Stunt", 1)
	elseif string.find(kind, "DRIFT") then
		-- Drift score (val = drift duration seconds or drift score points)
		local normalized = if val > 25 then math.clamp(val / 100, 0.5, 10) else math.clamp(val, 0.5, 10)
		local baseCash = math.floor(30 * normalized)
		local baseChaos = math.floor(110 * normalized)
		registerComboAction(player, baseCash, baseChaos, "DRIFT KING!", 2.0, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
		advanceCampaignProgress(player, "Stunt", 1)
	elseif string.find(kind, "NEAR") or string.find(kind, "MISS") then
		-- High-speed traffic/police near-miss
		local baseCash = 40
		local baseChaos = 125
		registerComboAction(player, baseCash, baseChaos, "NEAR MISS!", 1.5, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
		advanceCampaignProgress(player, "Stunt", 1)
	end
end

local function handlePoliceTakedown(player: Player, unitType: string?, worldPos: Vector3?, customBonusCash: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local unit = tostring(unitType or "Patrol Cruiser")
	local baseCash = math.clamp(tonumber(customBonusCash) or 175, 100, 1000)
	local baseChaos = baseCash * 4
	local pos = if typeof(worldPos) == "Vector3" then worldPos else nil

	local takedowns = (tonumber(player:GetAttribute("CopTakedowns")) or 0) + 1
	player:SetAttribute("CopTakedowns", takedowns)

	advanceMissionProgress(player, "CopTakedowns", 1)
	advanceCampaignProgress(player, "CopTakedowns", 1)
	registerComboAction(player, baseCash, baseChaos, "COP TAKEDOWN!", 18, pos)

	-- Persist milestone update
	UpdatePlayerDataBindable:Fire(player, {
		CopTakedowns = takedowns,
	})
	local _ = unit
end

--------------------------------------------------------------------------------
-- Wire BindableEvents & RemoteEvents
--------------------------------------------------------------------------------
DestructionBindable.Event:Connect(handleDestructionEvent)
OnObjectDestroyedBindable.Event:Connect(handleDestructionEvent)
FolderDestructionBindable.Event:Connect(handleDestructionEvent)

local serverEventsAlt = ensureFolder(ServerStorage, "ServerEvents")
local altDestructionBindable = ensureBindableEvent(serverEventsAlt, "DestructionOccurred")
altDestructionBindable.Event:Connect(handleDestructionEvent)

StuntBindable.Event:Connect(handleStuntEvent)
FolderStuntBindable.Event:Connect(handleStuntEvent)

PoliceTakedownBindable.Event:Connect(handlePoliceTakedown)
FolderPoliceTakedownBindable.Event:Connect(handlePoliceTakedown)

AddCashBindable.Event:Connect(function(player: Player, amount: number, reason: string?)
	if typeof(player) == "Instance" and player:IsA("Player") then
		addCash(player, tonumber(amount) or 0, reason)
	end
end)
FolderAddCashBindable.Event:Connect(function(player: Player, amount: number, reason: string?)
	if typeof(player) == "Instance" and player:IsA("Player") then
		addCash(player, tonumber(amount) or 0, reason)
	end
end)

SpendCashFunction.OnInvoke = function(player: Player, amount: number, reason: string?): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	return debitCash(player, tonumber(amount) or 0, reason)
end

-- Handle "BUSTED!" penalty from PoliceHeatService:
-- Confiscates a small % of unbanked combo cash (plus a small capped fine if no combo is active)
local function onPlayerBusted(player: Player, penaltyOverride: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local state = playerStates[player.UserId]
	local confiscated = 0

	if state then
		if state.UnbankedComboCash > 0 then
			-- Confiscate 30% of unbanked combo cash
			confiscated = math.max(10, math.floor(state.UnbankedComboCash * 0.30))
		else
			-- Small 8% wallet fine capped at $150
			local currentCash = tonumber(player:GetAttribute("Cash")) or 0
			confiscated = math.min(150, math.floor(currentCash * 0.08))
		end

		if type(penaltyOverride) == "number" and penaltyOverride > 0 then
			confiscated = math.floor(penaltyOverride)
		end

		if confiscated > 0 then
			debitCash(player, confiscated, "BustedPenalty")
		end

		-- Reset active combo without banking bonus
		state.ComboCount = 0
		state.ComboMultiplier = 1
		state.ComboTimer = 0
		state.UnbankedComboCash = 0
		state.CurrentStreakName = "BUSTED!"
		syncComboAttributes(player, state)
	end
end

PlayerBustedBindable.Event:Connect(onPlayerBusted)
FolderPlayerBustedBindable.Event:Connect(onPlayerBusted)

-- Client Remote listeners (with basic rate limiting & validation)
local function onClientDestructionReport(player: Player, objectTypeOrInfo: any, baseCash: any, worldPos: any, extraMeta: any)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastClientReportAt < REMOTE_RATE_LIMIT then
		return
	end
	state.LastClientReportAt = now
	local clampedCash = math.clamp(tonumber(baseCash) or 25, 5, 400)
	handleDestructionEvent(player, objectTypeOrInfo, clampedCash, worldPos, extraMeta)
end

ReportDestructionRemote.OnServerEvent:Connect(onClientDestructionReport)
RootDestructionRemote.OnServerEvent:Connect(onClientDestructionReport)

local function onClientStuntReport(player: Player, stuntType: any, value: any, worldPos: any)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastClientReportAt < REMOTE_RATE_LIMIT then
		return
	end
	state.LastClientReportAt = now
	handleStuntEvent(player, tostring(stuntType or "Jump"), tonumber(value) or 1, worldPos)
end

ReportStuntRemote.OnServerEvent:Connect(onClientStuntReport)
RootStuntRemote.OnServerEvent:Connect(onClientStuntReport)

SkipMissionRemote.OnServerEvent:Connect(function(player: Player)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	startMission(player, state, state.MissionIndex + 1)
end)

--------------------------------------------------------------------------------
-- Player Lifecycle & HeatLevel Leaderstat Mirroring
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local ls = ensurePlayerSetup(player)
	local state: PlayerChaosState = {
		ComboCount = 0,
		ComboMultiplier = 1,
		ComboTimer = 0,
		UnbankedComboCash = 0,
		CurrentStreakName = "",
		JackpotCharge = tonumber(player:GetAttribute("JackpotCharge")) or 0,
		JackpotSpinsCount = tonumber(player:GetAttribute("JackpotSpinsCount")) or 0,
		GoldenFrenzyRemaining = 0,
		CampaignAct = 1,
		CampaignProgress = 0,
		CampaignCompleted = false,
		MissionIndex = 1,
		MissionProgress = 0,
		MissionTimeRemaining = LIVE_CHAOS_MISSIONS[1].Duration,
		MissionIntermission = 0,
		HeatSurvivalAccumulator = 0,
		LastClientReportAt = 0,
		LastBossHitAt = 0,
	}
	playerStates[player.UserId] = state
	syncCampaignAttributesToPlayer(player, state)
	updateNextVehicleUnlockAttributes(player)

	for _, attrName in ipairs({ "Cash", "Level", "EquippedVehicle", "SelectedVehicle", "OwnedVehicles", "UnlockedVehicles" }) do
		player:GetAttributeChangedSignal(attrName):Connect(function()
			updateNextVehicleUnlockAttributes(player)
		end)
	end
	for _, milestone in ipairs(VEHICLE_UNLOCK_LADDER) do
		player:GetAttributeChangedSignal("Unlocked_" .. milestone.Id):Connect(function()
			updateNextVehicleUnlockAttributes(player)
		end)
		player:GetAttributeChangedSignal("Owned_" .. milestone.Id):Connect(function()
			updateNextVehicleUnlockAttributes(player)
		end)
	end

	-- Mirror HeatStars attribute to leaderstats.HeatLevel automatically
	player:GetAttributeChangedSignal("HeatStars"):Connect(function()
		local stars = math.clamp(math.floor(tonumber(player:GetAttribute("HeatStars")) or 0), 0, 5)
		local heatVal = ls:FindFirstChild("HeatLevel") :: IntValue?
		if heatVal then
			heatVal.Value = stars
		end
	end)

	-- Start first Live Chaos Mission / Campaign Act shortly after join
	task.delay(1.5, function()
		if player.Parent and playerStates[player.UserId] == state then
			syncCampaignAttributesToPlayer(player, state)
			startMission(player, state, 1)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	playerStates[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

--------------------------------------------------------------------------------
-- Main Heartbeat Loop: Dynamic Combo Timer & Live Chaos Mission Cycling
--------------------------------------------------------------------------------
local missionSyncAccumulator = 0

RunService.Heartbeat:Connect(function(dt: number)
	missionSyncAccumulator += dt
	local shouldBroadcastMission = missionSyncAccumulator >= 1.0
	if shouldBroadcastMission then
		missionSyncAccumulator = 0
	end

	-- Update Act 5 Boss Goliath Convoy patrol along Grand Central Avenue ((-140 <-> 140)) & check player ramming
	if activeBossHull and activeBossHull.Parent and activeBossHealth > 0 then
		bossPatrolPhase += dt * 0.45
		local zPos = math.sin(bossPatrolPhase) * 140
		local dirZ = math.cos(bossPatrolPhase)
		local yaw = if dirZ >= 0 then math.pi else 0
		activeBossHull.CFrame = CFrame.new(0, 3.8, zPos) * CFrame.Angles(0, yaw, 0)

		for _, plr in ipairs(Players:GetPlayers()) do
			local st = playerStates[plr.UserId]
			if st and st.CampaignAct == 5 and not st.CampaignCompleted then
				plr:SetAttribute("BossPosition", activeBossHull.Position)
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local refPart: BasePart? = if hum and hum.SeatPart then hum.SeatPart else (char and char:FindFirstChild("HumanoidRootPart") :: BasePart?)
				if refPart then
					local dist = (refPart.Position - activeBossHull.Position).Magnitude
					local spd = refPart.AssemblyLinearVelocity.Magnitude
					if dist <= 22.0 and spd >= 24.0 then
						damageBossConvoy(plr, math.clamp(spd * 4.0, 220, 350))
					end
				end
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerStates[player.UserId]
		if not state then
			continue
		end

		-- 1. Tick dynamic 4.5s Chaos Combo timer
		if state.ComboCount > 0 and state.ComboTimer > 0 then
			state.ComboTimer = math.max(0, state.ComboTimer - dt)
			player:SetAttribute("ComboTimer", tonumber(string.format("%.2f", state.ComboTimer)))
			player:SetAttribute("ComboTimerRatio", math.clamp(state.ComboTimer / COMBO_BASE_WINDOW, 0, 1))

			if state.ComboTimer <= 0 then
				finishAndBankCombo(player, state)
			end
		end

		-- 1B. Tick 30s Golden 3X Frenzy Jackpot buff
		if state.GoldenFrenzyRemaining > 0 then
			state.GoldenFrenzyRemaining = math.max(0, state.GoldenFrenzyRemaining - dt)
			if state.GoldenFrenzyRemaining <= 0 then
				player:SetAttribute("Golden3xFrenzyActive", false)
				player:SetAttribute("Golden3xFrenzyRemaining", 0)
			elseif shouldBroadcastMission then
				player:SetAttribute("Golden3xFrenzyRemaining", math.ceil(state.GoldenFrenzyRemaining))
			end
		end

		-- 2. Tick Live Chaos Mission / Timed Challenge
		if state.MissionIntermission > 0 then
			state.MissionIntermission = math.max(0, state.MissionIntermission - dt)
			if state.MissionIntermission <= 0 then
				startMission(player, state, state.MissionIndex + 1)
			end
		elseif state.MissionTimeRemaining > 0 then
			state.MissionTimeRemaining = math.max(0, state.MissionTimeRemaining - dt)

			-- Check "Survive 3-Star Heat for 45s!" mission type
			local def = getActiveMissionDef(state)
			if def.Kind == "SurviveHeat" then
				local reqStars = def.RequiredHeatStars or 3
				local currentStars = tonumber(player:GetAttribute("HeatStars")) or 0
				local isBusted = player:GetAttribute("IsBusted") == true
				if currentStars >= reqStars and not isBusted then
					state.HeatSurvivalAccumulator += dt
					if state.HeatSurvivalAccumulator >= 1.0 then
						local wholeSeconds = math.floor(state.HeatSurvivalAccumulator)
						state.HeatSurvivalAccumulator -= wholeSeconds
						advanceMissionProgress(player, "SurviveHeat", wholeSeconds)
					end
				end
			end

			if state.MissionTimeRemaining <= 0 and state.MissionIntermission <= 0 then
				-- Mission timer expired; rotate to next mission after short intermission
				state.MissionIntermission = MISSION_INTERMISSION * 0.65
				syncMissionToPlayer(player, state, "Expired")
			elseif shouldBroadcastMission then
				player:SetAttribute("MissionTimeRemaining", math.max(0, math.ceil(state.MissionTimeRemaining)))
			end
		end
	end
end)
