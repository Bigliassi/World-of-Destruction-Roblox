--!strict
--[[
	ProgressionAndLevelsService.script.luau
	World of Destruction (Roblox) — Version 1.0
	
	Full 50-Level Player Progression System:
	- Configures `Level` on `leaderstats` and Player Attributes (`Level`, `XP`,
	  `XPRequired`, `TotalXP`, `RankTitle`, `NextRankTitle`, `XPProgressRatio`).
	- Rank Titles from Lv.1 Street Rookie, Lv.5 Curb Crusher, Lv.10 Asphalt Outlaw,
	  Lv.20 Demolition Expert, Lv.35 Apex Wrecker, up to Lv.50 Lord of Destruction.
	- Awards XP for every prop destroyed, combo banked, stunt landed, mission
	  completed, and police cruiser wrecked.
	- Grants scaling Cash bonuses + unlocks milestone rewards on every Level Up,
	  firing celebratory client notifications, HUD callouts, and 3D golden level-up VFX.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--------------------------------------------------------------------------------
-- Constants & 50-Level Configuration
--------------------------------------------------------------------------------
local MAX_LEVEL = 50

export type RankTier = {
	MinLevel: number,
	Title: string,
	BadgeColor: Color3,
	MilestoneRewardNote: string?,
}

-- Ordered highest to lowest for fast lookup, containing all canonical v1.0 ranks
local RANK_TIERS: { RankTier } = {
	{
		MinLevel = 50,
		Title = "Lord of Destruction",
		BadgeColor = Color3.fromRGB(255, 215, 0),
		MilestoneRewardNote = "MAX LEVEL 50! +$50,000 Apex Sovereign Bonus & Golden Aura!",
	},
	{
		MinLevel = 45,
		Title = "Cataclysm King",
		BadgeColor = Color3.fromRGB(255, 95, 45),
		MilestoneRewardNote = "Unlocked Cataclysm King Title & +$20,000 Bonus!",
	},
	{
		MinLevel = 40,
		Title = "Titan of Chaos",
		BadgeColor = Color3.fromRGB(255, 65, 110),
		MilestoneRewardNote = "Unlocked Titan of Chaos Title & +$15,000 Bonus!",
	},
	{
		MinLevel = 35,
		Title = "Apex Wrecker",
		BadgeColor = Color3.fromRGB(215, 70, 255),
		MilestoneRewardNote = "Unlocked Apex Wrecker Rank & +$12,000 Bonus!",
	},
	{
		MinLevel = 30,
		Title = "Heat Bringer",
		BadgeColor = Color3.fromRGB(165, 90, 255),
		MilestoneRewardNote = "Unlocked Heat Bringer Rank & +$9,000 Bonus!",
	},
	{
		MinLevel = 25,
		Title = "City Flattener",
		BadgeColor = Color3.fromRGB(80, 175, 255),
		MilestoneRewardNote = "Unlocked City Flattener Rank & +$7,500 Bonus!",
	},
	{
		MinLevel = 20,
		Title = "Demolition Expert",
		BadgeColor = Color3.fromRGB(0, 225, 255),
		MilestoneRewardNote = "Unlocked Demolition Expert Rank & +$5,000 Bonus!",
	},
	{
		MinLevel = 15,
		Title = "Neon Menace",
		BadgeColor = Color3.fromRGB(50, 240, 150),
		MilestoneRewardNote = "Unlocked Neon Menace Rank & +$3,500 Bonus!",
	},
	{
		MinLevel = 10,
		Title = "Asphalt Outlaw",
		BadgeColor = Color3.fromRGB(120, 255, 90),
		MilestoneRewardNote = "Unlocked Asphalt Outlaw Rank & +$2,500 Bonus!",
	},
	{
		MinLevel = 5,
		Title = "Curb Crusher",
		BadgeColor = Color3.fromRGB(255, 200, 65),
		MilestoneRewardNote = "Unlocked Curb Crusher Rank & +$1,250 Bonus!",
	},
	{
		MinLevel = 1,
		Title = "Street Rookie",
		BadgeColor = Color3.fromRGB(210, 220, 235),
		MilestoneRewardNote = "Welcome to Leo City!",
	},
}

-- Smooth polynomial XP curve from Lv.1 -> Lv.50
-- Lv.1 requires 250 XP, Lv.5 requires 650 XP, Lv.10 requires 1,350 XP,
-- Lv.20 requires 3,200 XP, Lv.35 requires 7,100 XP, Lv.49->50 requires 12,000 XP.
local function getXPRequiredForLevel(level: number): number
	local clamped = math.clamp(math.floor(level), 1, MAX_LEVEL)
	if clamped >= MAX_LEVEL then
		return 0
	end
	return math.floor(180 + (clamped * 65) + math.pow(clamped, 1.75) * 10)
end

local function getRankInfoForLevel(level: number): (RankTier, RankTier?)
	local clamped = math.clamp(math.floor(level), 1, MAX_LEVEL)
	local currentTier = RANK_TIERS[#RANK_TIERS]
	local nextTier: RankTier? = nil

	for i, tier in ipairs(RANK_TIERS) do
		if clamped >= tier.MinLevel then
			currentTier = tier
			if i > 1 then
				nextTier = RANK_TIERS[i - 1]
			end
			break
		end
	end
	return currentTier, nextTier
end

local function getLevelUpCashReward(newLevel: number): number
	-- Base cash reward scales with level, plus extra milestone jackpots
	local base = newLevel * 250
	if newLevel == 50 then
		return 50000
	elseif newLevel == 45 then
		return 20000
	elseif newLevel == 40 then
		return 15000
	elseif newLevel == 35 then
		return 12000
	elseif newLevel == 30 then
		return 9000
	elseif newLevel == 25 then
		return 7500
	elseif newLevel == 20 then
		return 5000
	elseif newLevel == 15 then
		return 3500
	elseif newLevel == 10 then
		return 2500
	elseif newLevel == 5 then
		return 1250
	end
	return base
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

-- Server Bindables
local DestructionBindable = ensureBindableEvent(ServerStorage, "DestructionEvent")
local OnObjectDestroyedBindable = ensureBindableEvent(ServerStorage, "OnObjectDestroyed")
local StuntBindable = ensureBindableEvent(ServerStorage, "StuntEvent")
local PoliceTakedownBindable = ensureBindableEvent(ServerStorage, "PoliceTakedownEvent")
local AddCashBindable = ensureBindableEvent(ServerStorage, "AddCashEvent")
local AwardXPBindable = ensureBindableEvent(ServerStorage, "AwardXPEvent")
local LevelUpBindable = ensureBindableEvent(ServerStorage, "PlayerLevelUpEvent")

local FolderDestructionBindable = ensureBindableEvent(serverEventsFolder, "DestructionEvent")
local FolderStuntBindable = ensureBindableEvent(serverEventsFolder, "StuntEvent")
local FolderPoliceTakedownBindable = ensureBindableEvent(serverEventsFolder, "PoliceTakedownEvent")
local FolderAwardXPBindable = ensureBindableEvent(serverEventsFolder, "AwardXPEvent")
local FolderLevelUpBindable = ensureBindableEvent(serverEventsFolder, "PlayerLevelUpEvent")

-- Client Remotes
local LevelUpRemote = ensureRemoteEvent(remotesFolder, "LevelUp")
local XPGainedRemote = ensureRemoteEvent(remotesFolder, "XPGained")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")
local GetProgressionTableRemote = ensureRemoteFunction(remotesFolder, "GetProgressionTable")

-- Root Remote Aliases
local RootLevelUpRemote = ensureRemoteEvent(ReplicatedStorage, "LevelUpEvent")
local RootStyleCalloutRemote = ensureRemoteEvent(ReplicatedStorage, "StyleCalloutEvent")

--------------------------------------------------------------------------------
-- Per-Player Progression State
--------------------------------------------------------------------------------
type PlayerProgressionState = {
	Level: number,
	XP: number,
	TotalXP: number,
	XPRequired: number,
	RankTitle: string,
	LastDestructionXPAt: number,
	LastTakedownXPAt: number,
	TrackedDestructions: number,
	TrackedTakedowns: number,
	TrackedMissions: number,
	PeakUnbankedComboCash: number,
	PeakComboChain: number,
}

local playerProgression: { [number]: PlayerProgressionState } = {}
local playerConnections: { [number]: { RBXScriptConnection } } = {}

local function getXPMultiplier(player: Player): number
	local mult = tonumber(player:GetAttribute("XPMultiplier")) or 1.0
	if player:GetAttribute("Pass_VIP2xCash") == true or player:GetAttribute("VIP2xCash") == true then
		mult = math.max(mult, 2.0)
	end
	if player:GetAttribute("OverdriveBoostActive") == true then
		mult = mult * 1.5
	end
	return math.clamp(mult, 1.0, 10.0)
end

local function ensureLevelLeaderstat(player: Player, initialLevel: number): IntValue
	local ls = player:FindFirstChild("leaderstats")
	if not (ls and ls:IsA("Folder")) then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local lvlValue = ls:FindFirstChild("Level")
	if lvlValue and lvlValue:IsA("IntValue") then
		lvlValue.Value = initialLevel
		return lvlValue
	end
	local iv = Instance.new("IntValue")
	iv.Name = "Level"
	iv.Value = initialLevel
	iv.Parent = ls
	return iv
end

local function syncProgressionAttributes(player: Player, state: PlayerProgressionState)
	local currentTier, nextTier = getRankInfoForLevel(state.Level)
	state.RankTitle = currentTier.Title
	state.XPRequired = getXPRequiredForLevel(state.Level)

	local ratio = 1.0
	if state.Level < MAX_LEVEL and state.XPRequired > 0 then
		ratio = math.clamp(state.XP / state.XPRequired, 0, 1)
	end

	player:SetAttribute("Level", state.Level)
	player:SetAttribute("XP", state.XP)
	player:SetAttribute("TotalXP", state.TotalXP)
	player:SetAttribute("XPRequired", state.XPRequired)
	player:SetAttribute("XPProgressRatio", tonumber(string.format("%.3f", ratio)))
	player:SetAttribute("RankTitle", state.RankTitle)
	player:SetAttribute("NextRankTitle", if nextTier then nextTier.Title else "MAX RANK")
	player:SetAttribute("NextRankLevel", if nextTier then nextTier.MinLevel else MAX_LEVEL)

	local lvlStat = ensureLevelLeaderstat(player, state.Level)
	lvlStat.Value = state.Level
end

local function spawnCelebratoryLevelUpVFX(player: Player, newLevel: number, tier: RankTier)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Create expanding golden shockwave ring around player/vehicle
	local ring = Instance.new("Part")
	ring.Name = "LevelUpShockwave_" .. tostring(newLevel)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = tier.BadgeColor
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.6, 6, 6)
	ring.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	task.spawn(function()
		local steps = 20
		for i = 1, steps do
			local alpha = i / steps
			local radius = 6 + alpha * 38
			ring.Size = Vector3.new(math.max(0.15, 0.6 * (1 - alpha)), radius, radius)
			ring.Transparency = 0.15 + (0.85 * alpha)
			ring.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, 0, math.rad(90))
			task.wait(0.025)
		end
		ring:Destroy()
	end)
end

local function grantCashBonus(player: Player, cashBonus: number, reason: string)
	if cashBonus <= 0 then
		return
	end
	-- Fire AddCashEvent so ChaosAndEconomyService and PlayerDataService stay in sync
	AddCashBindable:Fire(player, cashBonus, reason)
end

local function awardXP(player: Player, baseXP: number, sourceReason: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local state = playerProgression[player.UserId]
	if not state then
		return
	end

	local rawXP = math.max(1, math.floor(tonumber(baseXP) or 0))
	if rawXP <= 0 then
		return
	end

	local mult = getXPMultiplier(player)
	local finalXP = math.max(1, math.floor(rawXP * mult))

	state.TotalXP += finalXP

	if state.Level >= MAX_LEVEL then
		state.XP = 0
		syncProgressionAttributes(player, state)
		return
	end

	state.XP += finalXP
	local leveledUpCount = 0
	local totalCashAwarded = 0
	local latestMilestoneNote: string? = nil

	while state.Level < MAX_LEVEL do
		local req = getXPRequiredForLevel(state.Level)
		if state.XP >= req then
			state.XP -= req
			state.Level += 1
			leveledUpCount += 1

			local cashBonus = getLevelUpCashReward(state.Level)
			totalCashAwarded += cashBonus

			local newTier = getRankInfoForLevel(state.Level)
			if newTier.MinLevel == state.Level and newTier.MilestoneRewardNote then
				latestMilestoneNote = newTier.MilestoneRewardNote
			end
		else
			break
		end
	end

	if state.Level >= MAX_LEVEL then
		state.XP = 0
	end

	syncProgressionAttributes(player, state)

	-- Notify client of XP gain
	XPGainedRemote:FireClient(player, {
		Amount = finalXP,
		Reason = sourceReason or "ChaosAction",
		Level = state.Level,
		XP = state.XP,
		XPRequired = state.XPRequired,
		RankTitle = state.RankTitle,
	})

	-- Handle Level Up celebrations & rewards
	if leveledUpCount > 0 then
		grantCashBonus(player, totalCashAwarded, "LevelUp_" .. tostring(state.Level))
		local tier, nextTier = getRankInfoForLevel(state.Level)
		spawnCelebratoryLevelUpVFX(player, state.Level, tier)

		local levelUpPayload = {
			NewLevel = state.Level,
			LevelsGained = leveledUpCount,
			RankTitle = tier.Title,
			RankColor = {
				R = math.floor(tier.BadgeColor.R * 255),
				G = math.floor(tier.BadgeColor.G * 255),
				B = math.floor(tier.BadgeColor.B * 255),
			},
			CashReward = totalCashAwarded,
			MilestoneNote = latestMilestoneNote or string.format("Reached Level %d — %s!", state.Level, tier.Title),
			NextRankTitle = if nextTier then nextTier.Title else "MAX RANK",
			NextRankLevel = if nextTier then nextTier.MinLevel else MAX_LEVEL,
			XP = state.XP,
			XPRequired = state.XPRequired,
		}

		LevelUpRemote:FireClient(player, levelUpPayload)
		RootLevelUpRemote:FireClient(player, levelUpPayload)

		-- Also broadcast celebratory banner via StyleCalloutRemote so GameHUD displays it prominently
		local calloutBanner = {
			Callout = string.format("LEVEL UP! LV.%d %s (+$%d)", state.Level, string.upper(tier.Title), totalCashAwarded),
			Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
			ComboCount = tonumber(player:GetAttribute("ComboCount")) or 1,
			CashAwarded = totalCashAwarded,
			ChaosAwarded = leveledUpCount * 500,
			IsLevelUpBanner = true,
			NewLevel = state.Level,
			RankTitle = tier.Title,
		}
		StyleCalloutRemote:FireClient(player, calloutBanner)
		RootStyleCalloutRemote:FireClient(player, calloutBanner)

		LevelUpBindable:Fire(player, state.Level, tier.Title, totalCashAwarded)
		FolderLevelUpBindable:Fire(player, state.Level, tier.Title, totalCashAwarded)
	end
end

--------------------------------------------------------------------------------
-- Event Listeners for Prop Destructions, Stunts, Combos, Missions & Cop Takedowns
--------------------------------------------------------------------------------
local function onPropDestroyed(playerOrPayload: any, objectTypeOrInfo: any, baseCashReward: number?)
	local player: Player = playerOrPayload
	if type(playerOrPayload) == "table" and objectTypeOrInfo == nil then
		player = playerOrPayload.player or playerOrPayload.Player
		objectTypeOrInfo = playerOrPayload
		baseCashReward = tonumber(playerOrPayload.cashEarned or playerOrPayload.CashReward)
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local state = playerProgression[player.UserId]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastDestructionXPAt < 0.02 then
		return
	end
	state.LastDestructionXPAt = now

	local cashVal = tonumber(baseCashReward) or 25
	if type(objectTypeOrInfo) == "table" then
		cashVal = tonumber(objectTypeOrInfo.CashReward or objectTypeOrInfo.cashEarned or objectTypeOrInfo.CoinReward or objectTypeOrInfo.Value) or cashVal
	elseif typeof(objectTypeOrInfo) == "Instance" then
		cashVal = tonumber(objectTypeOrInfo:GetAttribute("CashReward") or objectTypeOrInfo:GetAttribute("CoinReward")) or cashVal
	end

	-- Prop destruction awards between 15 and 220 XP depending on target size
	local xpReward = math.clamp(math.floor(12 + cashVal * 0.45), 15, 220)
	awardXP(player, xpReward, "PropDestroyed")
end

local function onStuntLanded(player: Player, stuntType: string?, rawValue: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local val = math.clamp(tonumber(rawValue) or 1, 0.5, 12)
	local xpReward = math.clamp(math.floor(25 + val * 15), 30, 180)
	awardXP(player, xpReward, "Stunt:" .. tostring(stuntType or "Jump"))
end

local function onPoliceTakedown(player: Player, _unitType: string?, _worldPos: Vector3?, customBonusCash: number?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local state = playerProgression[player.UserId]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.LastTakedownXPAt < 0.05 then
		return
	end
	state.LastTakedownXPAt = now

	local bonus = tonumber(customBonusCash) or 175
	local xpReward = math.clamp(math.floor(110 + bonus * 0.35), 120, 350)
	awardXP(player, xpReward, "CopTakedown")
end

DestructionBindable.Event:Connect(onPropDestroyed)
OnObjectDestroyedBindable.Event:Connect(onPropDestroyed)
FolderDestructionBindable.Event:Connect(onPropDestroyed)

local serverEventsAlt = ensureFolder(ServerStorage, "ServerEvents")
local altDestructionBindable = ensureBindableEvent(serverEventsAlt, "DestructionOccurred")
altDestructionBindable.Event:Connect(onPropDestroyed)

StuntBindable.Event:Connect(onStuntLanded)
FolderStuntBindable.Event:Connect(onStuntLanded)

PoliceTakedownBindable.Event:Connect(onPoliceTakedown)
FolderPoliceTakedownBindable.Event:Connect(onPoliceTakedown)

AwardXPBindable.Event:Connect(function(player: Player, amount: number, reason: string?)
	awardXP(player, amount, reason)
end)
FolderAwardXPBindable.Event:Connect(function(player: Player, amount: number, reason: string?)
	awardXP(player, amount, reason)
end)

-- RemoteFunction so TutorialAndGuideUI can display the full 50-Level Rank Table
GetProgressionTableRemote.OnServerInvoke = function(player: Player)
	local state = playerProgression[player.UserId]
	local ranksOut = {}
	for i = #RANK_TIERS, 1, -1 do
		local tier = RANK_TIERS[i]
		table.insert(ranksOut, {
			MinLevel = tier.MinLevel,
			Title = tier.Title,
			CashBonus = getLevelUpCashReward(tier.MinLevel),
			Note = tier.MilestoneRewardNote or "",
		})
	end
	return {
		MaxLevel = MAX_LEVEL,
		CurrentLevel = if state then state.Level else (tonumber(player:GetAttribute("Level")) or 1),
		CurrentXP = if state then state.XP else (tonumber(player:GetAttribute("XP")) or 0),
		XPRequired = if state then state.XPRequired else getXPRequiredForLevel(1),
		RankTitle = if state then state.RankTitle else "Street Rookie",
		Ranks = ranksOut,
	}
end

--------------------------------------------------------------------------------
-- Player Setup & Attribute Watchers (Combos Banked & Missions Completed)
--------------------------------------------------------------------------------
local function setupPlayerProgression(player: Player)
	local savedLevel = math.clamp(math.floor(tonumber(player:GetAttribute("Level")) or 1), 1, MAX_LEVEL)
	local savedXP = math.max(0, math.floor(tonumber(player:GetAttribute("XP")) or 0))
	local savedTotalXP = math.max(savedXP, math.floor(tonumber(player:GetAttribute("TotalXP")) or 0))
	local initialTier = getRankInfoForLevel(savedLevel)

	local state: PlayerProgressionState = {
		Level = savedLevel,
		XP = savedXP,
		TotalXP = savedTotalXP,
		XPRequired = getXPRequiredForLevel(savedLevel),
		RankTitle = initialTier.Title,
		LastDestructionXPAt = 0,
		LastTakedownXPAt = 0,
		TrackedDestructions = tonumber(player:GetAttribute("TotalDestructions")) or 0,
		TrackedTakedowns = tonumber(player:GetAttribute("CopTakedowns")) or 0,
		TrackedMissions = tonumber(player:GetAttribute("MissionsCompleted")) or 0,
		PeakUnbankedComboCash = 0,
		PeakComboChain = 0,
	}
	playerProgression[player.UserId] = state
	syncProgressionAttributes(player, state)

	local conns: { RBXScriptConnection } = {}

	-- 1. Watch MissionsCompleted attribute for Mission Complete XP rewards (+250 XP)
	table.insert(conns, player:GetAttributeChangedSignal("MissionsCompleted"):Connect(function()
		local currentMissions = tonumber(player:GetAttribute("MissionsCompleted")) or 0
		if currentMissions > state.TrackedMissions then
			local delta = currentMissions - state.TrackedMissions
			state.TrackedMissions = currentMissions
			awardXP(player, delta * 250, "MissionCompleted")
		end
	end))

	-- 2. Watch ComboCount & UnbankedComboCash to award Combo Banked XP when a combo finishes
	table.insert(conns, player:GetAttributeChangedSignal("ComboCount"):Connect(function()
		local chain = tonumber(player:GetAttribute("ComboCount")) or 0
		if chain > state.PeakComboChain then
			state.PeakComboChain = chain
		elseif chain == 0 and state.PeakComboChain >= 3 then
			local completedChain = state.PeakComboChain
			local bankedCash = state.PeakUnbankedComboCash
			state.PeakComboChain = 0
			state.PeakUnbankedComboCash = 0

			-- Only award Combo Banked XP if not busted
			if player:GetAttribute("CurrentStreakName") ~= "BUSTED!" then
				local comboXP = math.clamp(math.floor(completedChain * 12 + bankedCash * 0.08), 25, 600)
				awardXP(player, comboXP, "ComboBanked_x" .. tostring(completedChain))
			end
		end
	end))

	table.insert(conns, player:GetAttributeChangedSignal("UnbankedComboCash"):Connect(function()
		local unbanked = tonumber(player:GetAttribute("UnbankedComboCash")) or 0
		if unbanked > state.PeakUnbankedComboCash then
			state.PeakUnbankedComboCash = unbanked
		end
	end))

	-- 3. Backup watcher on TotalDestructions in case another service increments it without firing Bindable
	table.insert(conns, player:GetAttributeChangedSignal("TotalDestructions"):Connect(function()
		local total = tonumber(player:GetAttribute("TotalDestructions")) or 0
		if total > state.TrackedDestructions then
			state.TrackedDestructions = total
			if os.clock() - state.LastDestructionXPAt > 0.15 then
				state.LastDestructionXPAt = os.clock()
				awardXP(player, 25, "PropDestroyed")
			end
		end
	end))

	-- 4. Backup watcher on CopTakedowns
	table.insert(conns, player:GetAttributeChangedSignal("CopTakedowns"):Connect(function()
		local takedowns = tonumber(player:GetAttribute("CopTakedowns")) or 0
		if takedowns > state.TrackedTakedowns then
			state.TrackedTakedowns = takedowns
			if os.clock() - state.LastTakedownXPAt > 0.15 then
				state.LastTakedownXPAt = os.clock()
				awardXP(player, 150, "CopTakedown")
			end
		end
	end))

	playerConnections[player.UserId] = conns
end

local function cleanupPlayerProgression(player: Player)
	local conns = playerConnections[player.UserId]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		playerConnections[player.UserId] = nil
	end
	playerProgression[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayerProgression, player)
end
Players.PlayerAdded:Connect(setupPlayerProgression)
Players.PlayerRemoving:Connect(cleanupPlayerProgression)
