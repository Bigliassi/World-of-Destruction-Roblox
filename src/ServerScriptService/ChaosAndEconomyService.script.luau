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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

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
-- Live Chaos Missions / Timed Challenges Catalog
--------------------------------------------------------------------------------
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
	MissionIndex: number,
	MissionProgress: number,
	MissionTimeRemaining: number,
	MissionIntermission: number,
	HeatSurvivalAccumulator: number,
	LastClientReportAt: number,
}

local playerStates: { [number]: PlayerChaosState } = {}

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

	return ls
end

--------------------------------------------------------------------------------
-- Economy Helpers (Cash & ChaosScore)
--------------------------------------------------------------------------------
local function addCash(player: Player, amount: number, reason: string?): number
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
-- Live Chaos Missions Management
--------------------------------------------------------------------------------
local function getActiveMissionDef(state: PlayerChaosState): MissionDefinition
	local idx = ((state.MissionIndex - 1) % #LIVE_CHAOS_MISSIONS) + 1
	return LIVE_CHAOS_MISSIONS[idx]
end

local function syncMissionToPlayer(player: Player, state: PlayerChaosState, status: string?)
	local def = getActiveMissionDef(state)
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

	-- Scale reward by ComboMultiplier * CashMagnetMultiplier * WantedHeatMultiplier
	local magnetMult = getMagnetMultiplier(player)
	local wantedMult = getWantedMultiplier(player)
	local totalScalar = mult * magnetMult * wantedMult

	local awardedCash = math.max(1, math.floor(baseCash * totalScalar))
	local awardedChaos = math.max(5, math.floor(baseChaos * totalScalar))

	-- Continuously credit cash & chaos score AND accumulate unbanked combo bonus pool
	addCash(player, awardedCash, finalCallout)
	addChaosScore(player, awardedChaos)
	state.UnbankedComboCash += awardedCash

	syncComboAttributes(player, state)

	-- Advance active missions that track damage dollar value or combo multiplier
	advanceMissionProgress(player, "DamageValue", awardedCash * 15)
	advanceMissionProgress(player, "ComboMultiplier", state.ComboMultiplier)

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
	local heatGenerated = 8 -- base heat progress points (0..100 per star)

	if type(objectTypeOrInfo) == "table" then
		objectType = tostring(objectTypeOrInfo.Type or objectTypeOrInfo.propType or objectTypeOrInfo.Category or objectTypeOrInfo.Name or "Prop")
		baseCash = tonumber(objectTypeOrInfo.CashReward or objectTypeOrInfo.cashEarned or objectTypeOrInfo.CoinReward or objectTypeOrInfo.Value) or baseCash
		if typeof(objectTypeOrInfo.Position) == "Vector3" then
			pos = objectTypeOrInfo.Position
		elseif typeof(objectTypeOrInfo.position) == "Vector3" then
			pos = objectTypeOrInfo.position
		end
		isChainExplosion = objectTypeOrInfo.IsExplosion == true or objectTypeOrInfo.isExplosion == true or objectTypeOrInfo.ChainExplosion == true
		if type(objectTypeOrInfo.Heat) == "number" then
			heatGenerated = objectTypeOrInfo.Heat
		end
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

	baseCash = math.clamp(math.floor(baseCash), 5, 2500)
	local baseChaos = baseCash * 3

	local state = playerStates[player.UserId]
	local nextMult = if state then select(1, computeMultiplierTier(state.ComboCount + 1)) else 1
	local callout = resolveDestructionCallout(objectType, isChainExplosion, nextMult)

	if callout == "CHAIN EXPLOSION!" then
		baseCash = math.floor(baseCash * 1.6)
		baseChaos = math.floor(baseChaos * 1.8)
		heatGenerated = math.max(heatGenerated, 18)
	elseif callout == "HYDRO BLAST!" then
		baseCash = math.floor(baseCash * 1.35)
		baseChaos = math.floor(baseChaos * 1.4)
		heatGenerated = math.max(heatGenerated, 12)
		advanceMissionProgress(player, "Hydrants", 1)
	elseif callout == "COP TAKEDOWN!" then
		baseCash = math.max(baseCash, 150)
		baseChaos = math.max(baseChaos, 500)
		heatGenerated = math.max(heatGenerated, 25)
		advanceMissionProgress(player, "CopTakedowns", 1)
	end

	local totalDest = (tonumber(player:GetAttribute("TotalDestructions")) or 0) + 1
	player:SetAttribute("TotalDestructions", totalDest)
	advanceMissionProgress(player, "PropsCount", 1)

	registerComboAction(player, baseCash, baseChaos, callout, heatGenerated, pos)
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
		registerComboAction(player, baseCash, baseChaos, "MEGA AIR!", 4, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
		advanceMissionProgress(player, "Airtime", math.ceil(clampedAir))
	elseif string.find(kind, "DRIFT") then
		-- Drift score (val = drift duration seconds or drift score points)
		local normalized = if val > 25 then math.clamp(val / 100, 0.5, 10) else math.clamp(val, 0.5, 10)
		local baseCash = math.floor(30 * normalized)
		local baseChaos = math.floor(110 * normalized)
		registerComboAction(player, baseCash, baseChaos, "DRIFT KING!", 3, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
	elseif string.find(kind, "NEAR") or string.find(kind, "MISS") then
		-- High-speed traffic/police near-miss
		local baseCash = 40
		local baseChaos = 125
		registerComboAction(player, baseCash, baseChaos, "NEAR MISS!", 2, pos)
		advanceMissionProgress(player, "DriftScore", baseChaos)
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
	registerComboAction(player, baseCash, baseChaos, "COP TAKEDOWN!", 22, pos)

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
		MissionIndex = 1,
		MissionProgress = 0,
		MissionTimeRemaining = LIVE_CHAOS_MISSIONS[1].Duration,
		MissionIntermission = 0,
		HeatSurvivalAccumulator = 0,
		LastClientReportAt = 0,
	}
	playerStates[player.UserId] = state

	-- Mirror HeatStars attribute to leaderstats.HeatLevel automatically
	player:GetAttributeChangedSignal("HeatStars"):Connect(function()
		local stars = math.clamp(math.floor(tonumber(player:GetAttribute("HeatStars")) or 0), 0, 5)
		local heatVal = ls:FindFirstChild("HeatLevel") :: IntValue?
		if heatVal then
			heatVal.Value = stars
		end
	end)

	-- Start first Live Chaos Mission shortly after join
	task.delay(1.5, function()
		if player.Parent and playerStates[player.UserId] == state then
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
