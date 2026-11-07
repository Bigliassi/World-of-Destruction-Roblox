--!strict
-- ViralRetentionAndZonesService.script.luau
-- Implements Driving Empire paycheck-for-driving loop, Playtime Gift Chests, and Rebirth multiplier.
-- (Out-of-place neon viral archways, laser gates, spinning diamond cube, and shredder pit disabled
-- to preserve an authentic Snowy Christmas Manhattan aesthetic.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Clean up any legacy LeoCityViralZones folder if present
local existingZones = Workspace:FindFirstChild("LeoCityViralZones")
if existingZones then
	existingZones:Destroy()
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteFunction(name: string): RemoteFunction
	local existing = remotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = remotesFolder
	return rf
end

local claimPlaytimeGiftRF = ensureRemoteFunction("ClaimPlaytimeGift")
local requestRebirthRF = ensureRemoteFunction("RequestRebirth")

local PLAYTIME_GIFTS = {
	{ Index = 1, Seconds = 45, Reward = 500, Label = "45s Holiday Gift" },
	{ Index = 2, Seconds = 120, Reward = 1200, Label = "2m Holiday Gift" },
	{ Index = 3, Seconds = 240, Reward = 2500, Label = "4m Holiday Gift" },
	{ Index = 4, Seconds = 420, Reward = 5000, Label = "7m Holiday Gift" },
	{ Index = 5, Seconds = 600, Reward = 10000, Label = "10m Holiday Gift" },
	{ Index = 6, Seconds = 900, Reward = 25000, Label = "15m Holiday Jackpot" },
}

local playerClaimedGifts: { [Player]: { [number]: boolean } } = {}
local playerLastDrivePos: { [Player]: Vector3 } = {}
local playerDriveStuds: { [Player]: number } = {}

local function getRebirthMultiplier(player: Player): number
	local mult = tonumber(player:GetAttribute("RebirthMultiplier")) or 1
	return math.max(1, mult)
end

local function getPlayerCash(player: Player): number
	local attrCash = tonumber(player:GetAttribute("Cash"))
	if attrCash ~= nil then
		return attrCash
	end
	local ls = player:FindFirstChild("leaderstats")
	local cashVal = ls and ls:FindFirstChild("Cash")
	if cashVal and cashVal:IsA("IntValue") then
		return cashVal.Value
	end
	return 0
end

local function addPlayerCash(player: Player, baseAmount: number, reason: string?): number
	local finalAmount = math.floor(baseAmount * getRebirthMultiplier(player) + 0.5)
	local addCashBindable = ServerStorage:FindFirstChild("AddCashEvent")
	if addCashBindable and addCashBindable:IsA("BindableEvent") then
		addCashBindable:Fire(player, finalAmount, reason or "ViralReward")
	else
		local newCash = math.max(0, getPlayerCash(player) + finalAmount)
		player:SetAttribute("Cash", newCash)
		local ls = player:FindFirstChild("leaderstats")
		local cashVal = ls and ls:FindFirstChild("Cash")
		if cashVal and cashVal:IsA("IntValue") then
			cashVal.Value = newCash
		end
	end
	if reason then
		player:SetAttribute("LastViralBonusText", string.format("+$%d %s", finalAmount, reason))
	end
	return finalAmount
end

local function setPlayerCashExact(player: Player, newCash: number)
	local current = getPlayerCash(player)
	local delta = newCash - current
	local addCashBindable = ServerStorage:FindFirstChild("AddCashEvent")
	if addCashBindable and addCashBindable:IsA("BindableEvent") then
		addCashBindable:Fire(player, delta, "RebirthReset")
	end
	player:SetAttribute("Cash", newCash)
	local ls = player:FindFirstChild("leaderstats")
	local cashVal = ls and ls:FindFirstChild("Cash")
	if cashVal and cashVal:IsA("IntValue") then
		cashVal.Value = newCash
	end
end

local function updateCrownTitle(player: Player)
	local rebirths = tonumber(player:GetAttribute("RebirthCount")) or 0
	if rebirths <= 0 then
		return
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local existing = head:FindFirstChild("RebirthCrownTag")
	if existing then
		existing:Destroy()
	end
end

local function syncGiftAttributes(player: Player)
	local claimed = playerClaimedGifts[player] or {}
	local playSec = tonumber(player:GetAttribute("PlaytimeSeconds")) or 0
	local list = {}
	local nextRemaining = 0
	local readyCount = 0
	for _, g in ipairs(PLAYTIME_GIFTS) do
		if claimed[g.Index] then
			table.insert(list, tostring(g.Index))
		elseif playSec >= g.Seconds then
			readyCount += 1
		elseif nextRemaining == 0 then
			nextRemaining = math.max(1, g.Seconds - playSec)
		end
	end
	player:SetAttribute("ClaimedGiftsCSV", table.concat(list, ","))
	player:SetAttribute("ReadyGiftCount", readyCount)
	player:SetAttribute("NextGiftSecondsLeft", nextRemaining)
end

claimPlaytimeGiftRF.OnServerInvoke = function(player: Player, giftIndex: any)
	local idx = tonumber(giftIndex)
	local gift = idx and PLAYTIME_GIFTS[idx]
	if not gift then
		return { Success = false, Message = "Invalid gift" }
	end
	playerClaimedGifts[player] = playerClaimedGifts[player] or {}
	if playerClaimedGifts[player][idx] then
		return { Success = false, Message = "Already claimed" }
	end
	local playSec = tonumber(player:GetAttribute("PlaytimeSeconds")) or 0
	if playSec < gift.Seconds then
		return { Success = false, Message = "Keep playing to unlock!" }
	end
	playerClaimedGifts[player][idx] = true
	local earned = addPlayerCash(player, gift.Reward, "HOLIDAY GIFT")
	syncGiftAttributes(player)
	return { Success = true, Reward = earned, GiftIndex = idx }
end

requestRebirthRF.OnServerInvoke = function(player: Player)
	local rebirths = tonumber(player:GetAttribute("RebirthCount")) or 0
	local cost = 25000 * (rebirths + 1)
	local cash = getPlayerCash(player)
	if cash < cost then
		return { Success = false, Message = string.format("Need $%d Cash to Rebirth!", cost), Cost = cost }
	end
	rebirths += 1
	local newMult = 1 + rebirths * 1.0
	player:SetAttribute("RebirthCount", rebirths)
	player:SetAttribute("RebirthMultiplier", newMult)
	setPlayerCashExact(player, 1500)
	updateCrownTitle(player)
	return { Success = true, RebirthCount = rebirths, RebirthMultiplier = newMult, NextCost = 25000 * (rebirths + 1) }
end

local function setupPlayer(player: Player)
	playerClaimedGifts[player] = {}
	playerDriveStuds[player] = 0
	player:SetAttribute("PlaytimeSeconds", 0)
	player:SetAttribute("RebirthCount", tonumber(player:GetAttribute("RebirthCount")) or 0)
	player:SetAttribute("RebirthMultiplier", 1 + (tonumber(player:GetAttribute("RebirthCount")) or 0) * 1.0)
	player:SetAttribute("DrivePaycheckEarned", 0)
	syncGiftAttributes(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		updateCrownTitle(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	playerClaimedGifts[player] = nil
	playerLastDrivePos[player] = nil
	playerDriveStuds[player] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local playSec = (tonumber(player:GetAttribute("PlaytimeSeconds")) or 0) + 1
			player:SetAttribute("PlaytimeSeconds", playSec)
			syncGiftAttributes(player)

			local char = player.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				local pos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
				local last = playerLastDrivePos[player]
				playerLastDrivePos[player] = pos
				if last then
					local step = (pos - last).Magnitude
					if step >= 3 and step <= 220 then
						local accum = (playerDriveStuds[player] or 0) + step
						while accum >= 80 do
							accum -= 80
							local paid = addPlayerCash(player, 25, "DRIVE PAYCHECK")
							player:SetAttribute("DrivePaycheckEarned", (tonumber(player:GetAttribute("DrivePaycheckEarned")) or 0) + paid)
						end
						playerDriveStuds[player] = accum
					end
				end
			end
		end
	end
end)
