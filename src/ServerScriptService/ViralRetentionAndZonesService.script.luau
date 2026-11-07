--!strict
-- ViralRetentionAndZonesService.script.luau
-- Implements physical tier-gated breakable vault zones (Car Crushers 2 / Pet Sim 99 style),
-- the Mega Shredder Pit, Driving Empire paycheck-for-driving loop, Playtime Gift Chests, and Rebirth multiplier.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local VehicleCatalog = Shared and Shared:FindFirstChild("VehicleCatalog") and require(Shared.VehicleCatalog) or nil

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
	{ Index = 1, Seconds = 45, Reward = 500, Label = "45s Chest" },
	{ Index = 2, Seconds = 120, Reward = 1200, Label = "2m Chest" },
	{ Index = 3, Seconds = 240, Reward = 2500, Label = "4m Chest" },
	{ Index = 4, Seconds = 420, Reward = 5000, Label = "7m Chest" },
	{ Index = 5, Seconds = 600, Reward = 10000, Label = "10m Chest" },
	{ Index = 6, Seconds = 900, Reward = 25000, Label = "15m Jackpot" },
}

local playerClaimedGifts: { [Player]: { [number]: boolean } } = {}
local playerLastDrivePos: { [Player]: Vector3 } = {}
local playerDriveStuds: { [Player]: number } = {}
local shredderCooldowns: { [Player]: number } = {}
local propCooldowns: { [BasePart]: boolean } = {}
local rotatingParts: { { Part: BasePart, Speed: number, Axis: string } } = {}

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

local function resolveVehicleAndDriver(hitPart: BasePart): (Player?, Model?, number)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	while model and model.Parent ~= Workspace and model.Parent do
		local parentModel = model.Parent:FindFirstAncestorOfClass("Model")
		if parentModel then
			model = parentModel
		else
			break
		end
	end
	if not model then
		return nil, nil, 1
	end
	local player = Players:GetPlayerFromCharacter(model)
	local vehicleModel: Model? = nil
	if not player then
		local ownerId = tonumber(model:GetAttribute("OwnerUserId"))
		if ownerId then
			player = Players:GetPlayerByUserId(ownerId)
			vehicleModel = model
		end
		if not player then
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("VehicleSeat") and desc.Occupant then
					local char = desc.Occupant.Parent
					if char then
						player = Players:GetPlayerFromCharacter(char)
						vehicleModel = model
						break
					end
				end
			end
		end
	end
	local tier = 1
	if vehicleModel then
		local attrTier = tonumber(vehicleModel:GetAttribute("Tier")) or tonumber(vehicleModel:GetAttribute("VehicleTier"))
		if attrTier then
			tier = attrTier
		elseif VehicleCatalog and type(VehicleCatalog.GetById) == "function" then
			local vId = tostring(vehicleModel:GetAttribute("VehicleId") or vehicleModel.Name)
			local entry = VehicleCatalog.GetById(vId)
			if entry and entry.Tier then
				tier = entry.Tier
			end
		end
	end
	if player then
		local pTier = tonumber(player:GetAttribute("ActiveVehicleTier")) or tonumber(player:GetAttribute("HighestTierUnlocked")) or 1
		tier = math.max(tier, pTier)
	end
	return player, vehicleModel, tier
end

local function attachBillboard(parent: BasePart, titleText: string, subText: string, accent: Color3, heightOffset: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ZoneBillboard"
	bb.Size = UDim2.fromOffset(260, 56)
	bb.StudsOffset = Vector3.new(0, heightOffset, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 260
	bb.Parent = parent

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(14, 18, 26)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = bb
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -8, 0.55, 0)
	title.Position = UDim2.fromOffset(4, 2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = titleText
	title.TextColor3 = accent
	title.TextScaled = true
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -8, 0.4, 0)
	sub.Position = UDim2.new(0, 4, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.Text = subText
	sub.TextColor3 = Color3.fromRGB(240, 245, 255)
	sub.TextScaled = true
	sub.Parent = frame
end

local function registerBreakableLoot(part: BasePart, requiredTier: number, cashBonus: number, labelText: string)
	part:SetAttribute("RequiredTier", requiredTier)
	part:SetAttribute("CashBonus", cashBonus)
	part:SetAttribute("PropHealth", requiredTier * 35)
	part:SetAttribute("MaxHealth", requiredTier * 35)
	CollectionService:AddTag(part, "DestructibleProp")

	local originCFrame = part.CFrame
	local originSize = part.Size
	part.Touched:Connect(function(hit: BasePart)
		if propCooldowns[part] then
			return
		end
		local player, _, tier = resolveVehicleAndDriver(hit)
		if not player then
			return
		end
		if tier < requiredTier then
			player:SetAttribute("LastViralBonusText", string.format("LOCKED! NEED TIER %d CAR", requiredTier))
			return
		end
		propCooldowns[part] = true
		addPlayerCash(player, cashBonus, labelText)
		part.Transparency = 0.85
		part.CanCollide = false
		task.delay(10, function()
			if part and part.Parent then
				part.Size = originSize
				part.CFrame = originCFrame
				part.Transparency = 0
				part.CanCollide = true
			end
			propCooldowns[part] = nil
		end)
	end)
end

local function buildArchZone(folder: Instance, name: string, center: Vector3, accent: Color3, titleText: string, subText: string, gateTier: number?)
	local zoneModel = Instance.new("Model")
	zoneModel.Name = name
	zoneModel.Parent = folder

	for _, side in ipairs({ -1, 1 }) do
		local pillar = Instance.new("Part")
		pillar.Name = "ArchPillar"
		pillar.Size = Vector3.new(2.2, 13, 2.2)
		pillar.Position = center + Vector3.new(side * 10, 6.5, 0)
		pillar.Anchored = true
		pillar.Material = Enum.Material.Neon
		pillar.Color = accent
		pillar.Parent = zoneModel
	end

	local header = Instance.new("Part")
	header.Name = "ArchHeader"
	header.Size = Vector3.new(22.5, 2.6, 2.6)
	header.Position = center + Vector3.new(0, 13.5, 0)
	header.Anchored = true
	header.Material = Enum.Material.SmoothPlastic
	header.Color = Color3.fromRGB(22, 26, 34)
	header.Parent = zoneModel
	attachBillboard(header, titleText, subText, accent, 3.6)

	if gateTier and gateTier > 1 then
		local gate = Instance.new("Part")
		gate.Name = "BreakableLaserGate"
		gate.Size = Vector3.new(17.5, 6.5, 1.0)
		gate.Position = center + Vector3.new(0, 3.5, 0)
		gate.Anchored = true
		gate.Transparency = 0.3
		gate.Material = Enum.Material.ForceField
		gate.Color = accent
		gate.Parent = zoneModel
		registerBreakableLoot(gate, gateTier, gateTier * 200, string.format("TIER %d GATE SMASH", gateTier))
	end
	return zoneModel
end

local function buildViralZones()
	local existing = Workspace:FindFirstChild("LeoCityViralZones")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "LeoCityViralZones"
	root.Parent = Workspace

	-- Zone 1: BRONZE ALLEY [TIER 1 — FREE CAR]
	local z1Center = Vector3.new(-30, 0.3, -42)
	local z1 = buildArchZone(root, "BronzeAlleyZone", z1Center, Color3.fromRGB(46, 204, 113), "BRONZE ALLEY [TIER 1 — FREE CAR]", "SMASH GOLD CRATES FOR +$150 EACH!", nil)
	for i = 1, 6 do
		local col = ((i - 1) % 3) - 1
		local row = math.floor((i - 1) / 3)
		local crate = Instance.new("Part")
		crate.Name = "GoldCashCrate_" .. i
		crate.Size = Vector3.new(3.6, 3.6, 3.6)
		crate.Position = z1Center + Vector3.new(col * 5.2, 2.1, -6 - row * 5.5)
		crate.Anchored = true
		crate.Material = Enum.Material.Metal
		crate.Color = Color3.fromRGB(255, 205, 55)
		crate.Parent = z1
		registerBreakableLoot(crate, 1, 150, "BRONZE CRATE")
	end

	-- Zone 2: GOLD BANK PLAZA [NEED TIER 2 CAR]
	local z2Center = Vector3.new(30, 0.3, -42)
	local z2 = buildArchZone(root, "GoldBankPlazaZone", z2Center, Color3.fromRGB(255, 200, 45), "GOLD BANK PLAZA [NEED TIER 2 CAR]", "BREAK LASER GATE FOR $600 GOLD STACKS!", 2)
	for i = 1, 6 do
		local col = ((i - 1) % 3) - 1
		local row = math.floor((i - 1) / 3)
		local stack = Instance.new("Part")
		stack.Name = "GiantGoldBullion_" .. i
		stack.Size = Vector3.new(4.2, 4.4, 3.2)
		stack.Position = z2Center + Vector3.new(col * 5.5, 2.5, -7 - row * 6)
		stack.Anchored = true
		stack.Material = Enum.Material.Foil
		stack.Color = Color3.fromRGB(255, 215, 0)
		stack.Parent = z2
		registerBreakableLoot(stack, 2, 600, "GOLD BULLION")
	end

	-- Zone 3: DIAMOND VAULT [NEED TIER 4 CAR]
	local z3Center = Vector3.new(0, 0.3, -105)
	local z3 = buildArchZone(root, "DiamondVaultZone", z3Center, Color3.fromRGB(0, 230, 255), "DIAMOND VAULT [NEED TIER 4 CAR]", "SMASH GATE FOR $5,000 SPINNING DIAMOND SAFE!", 4)
	local diamondSafe = Instance.new("Part")
	diamondSafe.Name = "SpinningDiamondSafe"
	diamondSafe.Size = Vector3.new(7, 7, 7)
	diamondSafe.Position = z3Center + Vector3.new(0, 4.8, -9)
	diamondSafe.Anchored = true
	diamondSafe.Material = Enum.Material.Neon
	diamondSafe.Color = Color3.fromRGB(0, 240, 255)
	diamondSafe.Parent = z3
	attachBillboard(diamondSafe, "DIAMOND VAULT SAFE", "+$5,000 JACKPOT SMASH", Color3.fromRGB(165, 94, 234), 5.2)
	registerBreakableLoot(diamondSafe, 4, 5000, "DIAMOND SAFE JACKPOT")
	table.insert(rotatingParts, { Part = diamondSafe, Speed = 1.4, Axis = "Y" })

	-- Car Crushers 2 Style MEGA SHREDDER PIT at (52, 0.3, 28)
	local shredCenter = Vector3.new(52, 0.3, 28)
	local shredModel = Instance.new("Model")
	shredModel.Name = "MegaShredderPit"
	shredModel.Parent = root

	local pitBase = Instance.new("Part")
	pitBase.Name = "ShredderHousing"
	pitBase.Size = Vector3.new(18, 1.4, 16)
	pitBase.Position = shredCenter + Vector3.new(0, 0.4, 0)
	pitBase.Anchored = true
	pitBase.Material = Enum.Material.DiamondPlate
	pitBase.Color = Color3.fromRGB(45, 48, 56)
	pitBase.Parent = shredModel
	attachBillboard(pitBase, "MEGA SHREDDER PIT", "DRIVE IN FOR +$1,000 SHREDDER BONUS!", Color3.fromRGB(255, 195, 0), 8.5)

	for i = -1, 1, 2 do
		local roller = Instance.new("Part")
		roller.Name = "HazardRoller"
		roller.Shape = Enum.PartType.Cylinder
		roller.Size = Vector3.new(14, 4.2, 4.2)
		roller.CFrame = CFrame.new(shredCenter + Vector3.new(i * 2.6, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		roller.Anchored = true
		roller.Material = Enum.Material.Metal
		roller.Color = if i == -1 then Color3.fromRGB(255, 190, 20) else Color3.fromRGB(28, 30, 36)
		roller.Parent = shredModel
		table.insert(rotatingParts, { Part = roller, Speed = 3.5 * i, Axis = "X" })

		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 90, 20))
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(0.25, 0.55)
		sparks.Rate = 18
		sparks.Speed = NumberRange.new(14, 26)
		sparks.Parent = roller

		roller.Touched:Connect(function(hit: BasePart)
			local player, vehicleModel = resolveVehicleAndDriver(hit)
			if not player then
				return
			end
			local now = os.clock()
			if (shredderCooldowns[player] or 0) > now then
				return
			end
			shredderCooldowns[player] = now + 6
			addPlayerCash(player, 1000, "SHREDDER BONUS")
			sparks:Emit(45)
			if vehicleModel and vehicleModel.PrimaryPart then
				vehicleModel:PivotTo(CFrame.new(shredCenter + Vector3.new(-16, 4.5, 0), shredCenter + Vector3.new(-30, 4.5, 0)))
			elseif player.Character and player.Character.PrimaryPart then
				player.Character:PivotTo(CFrame.new(shredCenter + Vector3.new(-14, 4.5, 0)))
			end
		end)
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
	attachBillboard(head, string.format("REBIRTH %d CROWN", rebirths), string.format("%.1fx PERMANENT CASH", getRebirthMultiplier(player)), Color3.fromRGB(255, 215, 0), 2.8)
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
	local earned = addPlayerCash(player, gift.Reward, "PLAYTIME GIFT")
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
	shredderCooldowns[player] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end

buildViralZones()

RunService.Heartbeat:Connect(function(dt: number)
	for _, item in ipairs(rotatingParts) do
		if item.Part and item.Part.Parent then
			if item.Axis == "Y" then
				item.Part.CFrame *= CFrame.Angles(0, item.Speed * dt, 0)
			else
				item.Part.CFrame *= CFrame.Angles(item.Speed * dt, 0, 0)
			end
		end
	end
end)

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
