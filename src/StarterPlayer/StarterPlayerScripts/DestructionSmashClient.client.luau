--!strict
--[[
	DestructionSmashClient.client.luau
	Client-side zero-resistance prop smashing, 5-tier destruction power system,
	intact traffic-vehicle flip physics, responsive high-grip brake assist,
	and dynamic brake lights + skid trails for World of Destruction (Leo City).

	Features:
	  1. 5-Tier Destruction Power System & Zero-Resistance Client Bumper Smash Sweep:
	     - Computes playerSmashTier (1..5) from vehicle archetype + Plow upgrade level and publishes
	       `player:SetAttribute("SmashPowerTier", tier)`.
	     - When playerSmashTier >= requiredTier:
	       - For regular props: breaks internal welds, sets CanCollide = false / Anchored = false,
	         and launches pieces forward + upward with spin with ZERO slowdown.
	       - For vehicles (AITrafficVehicle, Vehicle, TrafficVehicle, ArmoredCashTruck):
	         NEVER breaks internal welds and NEVER sets CanCollide = false on body parts!
	         Keeps the vehicle intact, unanchors Chassis (Anchored = false, CanCollide = true),
	         and applies a dramatic upward/forward flip impulse (launchDir * 55 + Vector3.new(0, 32, 0))
	         + angular spin so the entire intact car flips and tumbles through the air!
	     - When playerSmashTier < requiredTier:
	       - Does NOT destroy the heavy target; spawns a metallic spark burst, plays a metallic clink,
	         and displays a 1.2s floating 3D badge ("NEED TIER X CAR OR PLOW! [PRESS B]" in gold/red)
	         with a 1.5s per-object cooldown.
	  2. Responsive Brake Assist, Recessed Dark-Red LED Brake Lights & Skid Trails:
	     - Applies progressive high-grip braking deceleration assist when holding Brake (S/Down while
	       moving forward, or Space Handbrake) so stopping is crisp, predictable, and responsive.
	     - Lights up recessed LED taillight strips and activates SkidTrailL / SkidTrailR during hard braking.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Remotes Lookup
--------------------------------------------------------------------------------
local function getRemoteEvent(name: string): RemoteEvent?
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		local found = remotesFolder:FindFirstChild(name)
		if found and found:IsA("RemoteEvent") then
			return found
		end
	end
	local rootFound = ReplicatedStorage:FindFirstChild(name)
	if rootFound and rootFound:IsA("RemoteEvent") then
		return rootFound
	end
	return nil
end

--------------------------------------------------------------------------------
-- State & Constants
--------------------------------------------------------------------------------
local locallySmashedProps: { [Instance]: number } = {}
local tierBlockedCooldowns: { [Instance]: number } = {}
local SMASH_CACHE_TTL = 8.0
local TIER_BLOCK_COOLDOWN = 1.5

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local lastVehicleModel: Model? = nil
local lastRecordedHealth: number = 100
local lastChassisSpeed: number = 0
local lastPreImpactVelocity: Vector3 = Vector3.zero
local lastImpactSparkAt: number = 0

--------------------------------------------------------------------------------
-- 5-Tier Destruction Power System Lookup Tables & Helpers
--------------------------------------------------------------------------------
local VEHICLE_CLASS_BASE_TIER: { [string]: number } = {
	Compact = 1,
	Hatchback = 1,
	Sedan = 2,
	Muscle = 2,
	SUV = 3,
	Van = 3,
	Pickup = 3,
	Sports = 3,
	MonsterTruck = 4,
	Monster = 4,
	Bulldozer = 5,
	Tank = 5,
	ArmoredTank = 5,
	BoxTruck = 5,
}

local PROP_REQUIRED_TIER: { [string]: number } = {
	-- Tier 1: All Everyday Street Props, Hydrants, Streetlights, Bus Stops, Billboards & Taxis (Starter Car Smashes All!)
	Crate = 1,
	WoodenCrate = 1,
	JackpotCrate = 1,
	TrafficCone = 1,
	Fence = 1,
	Bench = 1,
	StreetBench = 1,
	TrashCan = 1,
	RecyclingBin = 1,
	Mailbox = 1,
	NewspaperBox = 1,
	FoodVendorCart = 1,
	CafePatio = 1,
	ConstructionBarrier = 1,
	FireHydrant = 1,
	StreetLight = 1,
	TrafficLight = 1,
	BusStop = 1,
	PalmTree = 1,
	Billboard = 1,
	TrafficVehicle = 1,

	-- Tier 2: Gold ATMs & Explosive Fuel Targets (Unlocked by Sedan / Muscle or Plow Lv.2)
	GoldATM = 2,
	GasPump = 2,
	ExplosiveBarrel = 2,

	-- Tier 3: Heavy Armored Cash Trucks & Surveillance Towers (Unlocked by SUV / Pickup / Sports or Plow Lv.3)
	ArmoredCashTruck = 3,
	MegaCorpTower = 3,

	-- Tier 4: Massive Civic Landmarks & Transit Buses (Unlocked by Monster Truck or Plow Lv.4)
	CityBus = 4,
	ConstructionCrane = 4,
	PlazaFountain = 4,

	-- Tier 5: Ultra-Armored End-Game Targets (Unlocked by Goliath Bulldozer or Plow Lv.5)
	MegaCorpBankVault = 5,
	BossGoliath = 5,
}

local function getPlayerSmashTier(player: Player?, vehicleModel: Model?): number
	local vClass = ""
	if vehicleModel then
		vClass = tostring(vehicleModel:GetAttribute("VehicleType") or vehicleModel.Name)
	end
	if (vClass == "" or not VEHICLE_CLASS_BASE_TIER[vClass]) and player then
		vClass = tostring(player:GetAttribute("CurrentVehicleType") or player:GetAttribute("EquippedVehicle") or "Compact")
	end

	local baseTier = VEHICLE_CLASS_BASE_TIER[vClass]
	if not baseTier and vehicleModel then
		baseTier = tonumber(vehicleModel:GetAttribute("BaseSmashTier"))
	end
	baseTier = baseTier or 1

	local plowUpgrade = 1
	if player then
		plowUpgrade = tonumber(player:GetAttribute("Upgrade_Plow")) or 1
	end
	local plowBonus = math.floor((plowUpgrade - 1) * 0.75)
	local tier = math.clamp(baseTier + plowBonus, 1, 5)

	if player and player:GetAttribute("SmashPowerTier") ~= tier then
		player:SetAttribute("SmashPowerTier", tier)
	end
	return tier
end

local function isVehicleTarget(inst: Instance): boolean
	if
		CollectionService:HasTag(inst, "AITrafficVehicle")
		or CollectionService:HasTag(inst, "TrafficVehicle")
		or CollectionService:HasTag(inst, "Vehicle")
	then
		return true
	end
	local propType = tostring(inst:GetAttribute("PropType") or inst.Name)
	if propType == "TrafficVehicle" or propType == "ArmoredCashTruck" then
		return true
	end
	return false
end

local function getPropRequiredTier(inst: Instance): number
	local explicit = tonumber(inst:GetAttribute("RequiredTier"))
	if explicit and explicit >= 1 then
		return math.clamp(math.floor(explicit), 1, 5)
	end

	local propType = tostring(inst:GetAttribute("PropType") or inst.Name)
	if PROP_REQUIRED_TIER[propType] then
		return PROP_REQUIRED_TIER[propType]
	end

	if CollectionService:HasTag(inst, "AITrafficVehicle") or CollectionService:HasTag(inst, "TrafficVehicle") then
		return 1
	end

	local lower = string.lower(propType)
	if string.find(lower, "bankvault") or string.find(lower, "bossgoliath") then
		return 5
	elseif string.find(lower, "citybus") or string.find(lower, "crane") or string.find(lower, "fountain") then
		return 4
	elseif string.find(lower, "cashtruck") or string.find(lower, "megacorptower") then
		return 3
	elseif string.find(lower, "atm") or string.find(lower, "gaspump") or string.find(lower, "barrel") then
		return 2
	end

	return 1
end

--------------------------------------------------------------------------------
-- Helper: Find Active Seated Vehicle & Chassis
--------------------------------------------------------------------------------
local function getActiveVehicleAndChassis(): (VehicleSeat?, Model?, BasePart?)
	local char = localPlayer.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or not hum.SeatPart or not hum.SeatPart:IsA("VehicleSeat") then
		return nil, nil, nil
	end

	local seat = hum.SeatPart :: VehicleSeat
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil, nil
	end
	local chassis = model.PrimaryPart or (model:FindFirstChild("Chassis") :: BasePart?)
	if not chassis then
		return nil, nil, nil
	end

	return seat, model, chassis
end

--------------------------------------------------------------------------------
-- Helper: Resolve Destructible Root Instance from Any Hit Part
--------------------------------------------------------------------------------
local function resolveDestructibleProp(part: BasePart, myVehicle: Model): Instance?
	if part:IsDescendantOf(myVehicle) then
		return nil
	end
	if localPlayer.Character and part:IsDescendantOf(localPlayer.Character) then
		return nil
	end

	local bestMatch: Instance? = nil
	local curr: Instance? = part
	while curr and curr ~= Workspace do
		if not curr:IsA("Folder") then
			if
				CollectionService:HasTag(curr, "Destructible")
				or curr:GetAttribute("IsDestructible") == true
				or curr:GetAttribute("PropType") ~= nil
			then
				bestMatch = curr
			end
		end
		curr = curr.Parent
	end

	if bestMatch then
		-- Never treat a player's personal vehicle as a destructible street prop
		if (tonumber(bestMatch:GetAttribute("OwnerUserId")) or 0) > 0 then
			return nil
		end
		return bestMatch
	end

	-- Also check if the part lives inside Workspace.LeoCity.DestructibleProps or TrafficLights
	local leoCity = Workspace:FindFirstChild("LeoCity")
	if leoCity then
		local propsFolder = leoCity:FindFirstChild("DestructibleProps")
		local lightsFolder = leoCity:FindFirstChild("TrafficLights")
		local node: Instance? = part
		while node and node.Parent and node.Parent ~= Workspace do
			if (propsFolder and node.Parent == propsFolder) or (lightsFolder and node.Parent == lightsFolder) then
				if node:IsA("Model") or node:IsA("BasePart") then
					return node
				end
			end
			node = node.Parent
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Helper: Spawn Instant Client-Side Impact Sparks / Splinters & Tier Blocked Badge
--------------------------------------------------------------------------------
local function spawnClientImpactSparks(worldPos: Vector3, isWood: boolean, playMetallicClink: boolean?)
	local now = os.clock()
	if not playMetallicClink and (now - lastImpactSparkAt < 0.06) then
		return
	end
	lastImpactSparkAt = now

	local host = Instance.new("Part")
	host.Name = "ClientImpactVFX"
	host.Size = Vector3.new(0.5, 0.5, 0.5)
	host.Position = worldPos
	host.Anchored = true
	host.CanCollide = false
	host.Transparency = 1
	host.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	if isWood then
		pe.Color = ColorSequence.new(Color3.fromRGB(195, 145, 85), Color3.fromRGB(130, 88, 46))
		pe.LightEmission = 0.2
		pe.Size = NumberSequence.new(0.38, 0.08)
	else
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 235, 110), Color3.fromRGB(255, 110, 20))
		pe.LightEmission = 1.0
		pe.Size = NumberSequence.new(0.42, 0.0)
	end
	pe.Lifetime = NumberRange.new(0.18, 0.42)
	pe.Speed = NumberRange.new(20, 38)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -45, 0)
	pe.Rate = 0
	pe.Parent = host
	pe:Emit(if playMetallicClink then 28 else 18)

	if playMetallicClink then
		local clink = Instance.new("Sound")
		clink.Name = "MetallicResistClink"
		clink.SoundId = "rbxassetid://9114221580"
		clink.Volume = 0.75
		clink.PlaybackSpeed = 1.18
		clink.Parent = host
		clink:Play()
	end

	Debris:AddItem(host, 0.8)
end

local function showTierResistanceBadge(propInst: Instance, requiredTier: number, impactPos: Vector3)
	local now = os.clock()
	local lastShown = tierBlockedCooldowns[propInst]
	if lastShown and (now - lastShown) < TIER_BLOCK_COOLDOWN then
		return
	end
	tierBlockedCooldowns[propInst] = now

	spawnClientImpactSparks(impactPos, false, true)

	if propInst:FindFirstChild("TierBlockedBadge") then
		return
	end

	local adorneePart: BasePart? = if propInst:IsA("BasePart")
		then propInst
		elseif propInst:IsA("Model") then (propInst.PrimaryPart or propInst:FindFirstChildWhichIsA("BasePart", true))
		else nil
	if not adorneePart then
		return
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "TierBlockedBadge"
	bb.Adornee = adorneePart
	bb.Size = UDim2.fromOffset(310, 54)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 95
	bb.Parent = propInst

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(135, 18, 24)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 205, 45)
	stroke.Thickness = 2.5
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = "NEED TIER " .. tostring(requiredTier) .. " CAR OR PLOW! [PRESS B]"
	label.TextColor3 = Color3.fromRGB(255, 220, 65)
	label.TextStrokeColor3 = Color3.fromRGB(40, 8, 10)
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.Parent = frame

	TweenService:Create(
		bb,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 6.8, 0) }
	):Play()

	Debris:AddItem(bb, 1.2)
end

--------------------------------------------------------------------------------
-- 1. Zero-Resistance Client Bumper Smash Sweep (With Intact Vehicle Flip & Tier Gate)
--------------------------------------------------------------------------------
local function smashPropLocallyAndNotifyServer(
	propInst: Instance,
	carForward: Vector3,
	speed: number,
	carVelocity: Vector3
)
	local now = os.clock()
	if locallySmashedProps[propInst] and (now - locallySmashedProps[propInst]) < SMASH_CACHE_TTL then
		return
	end
	locallySmashedProps[propInst] = now

	local launchDir = if carForward.Magnitude > 0.05 then carForward.Unit else Vector3.new(0, 0, -1)
	local isVehicle = isVehicleTarget(propInst)

	if isVehicle then
		-- NEVER break internal WeldConstraints and NEVER set CanCollide = false on vehicle body parts!
		-- Keep all parts welded to PrimaryPart (Chassis), unanchor Chassis, and flip the entire intact vehicle!
		local targetChassis: BasePart? = if propInst:IsA("Model")
			then (propInst.PrimaryPart or (propInst:FindFirstChild("Chassis") :: BasePart?) or propInst:FindFirstChildWhichIsA("BasePart", true))
			elseif propInst:IsA("BasePart") then propInst
			else nil

		if propInst:IsA("Model") then
			for _, desc in ipairs(propInst:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = false
				end
			end
		end

		if targetChassis then
			targetChassis.Anchored = false
			targetChassis.CanCollide = true
			targetChassis.AssemblyLinearVelocity = launchDir * 55 + Vector3.new(0, 32, 0)
			targetChassis.AssemblyAngularVelocity = Vector3.new(
				(math.random() - 0.5) * 18,
				(math.random() - 0.5) * 14,
				(math.random() - 0.5) * 18
			)
			spawnClientImpactSparks(targetChassis.Position, false, false)
		end

		local outboundVel = launchDir * 55 + Vector3.new(0, 32, 0)
		local reportRemote = getRemoteEvent("ReportDestruction")
		if reportRemote then
			reportRemote:FireServer(propInst, outboundVel)
		end
		local smashRemote = getRemoteEvent("SmashProp")
		if smashRemote then
			smashRemote:FireServer(propInst, outboundVel)
		end
		return
	end

	-- Non-vehicle destructible prop: break all internal welds on client so composite props shatter apart
	if propInst:IsA("Model") then
		for _, desc in ipairs(propInst:GetDescendants()) do
			if desc:IsA("WeldConstraint") then
				desc.Enabled = false
				desc:Destroy()
			elseif desc:IsA("Weld") or desc:IsA("Snap") or desc:IsA("ManualWeld") then
				desc:Destroy()
			end
		end
	end

	local parts: { BasePart } = {}
	if propInst:IsA("BasePart") then
		table.insert(parts, propInst)
	elseif propInst:IsA("Model") then
		for _, desc in ipairs(propInst:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	local baseLaunchSpeed = math.max(35, speed * 1.35)
	local baseLaunchVel = launchDir * baseLaunchSpeed + Vector3.new(0, 22, 0)
	local firstPos: Vector3? = nil
	local isWood = false

	for idx, p in ipairs(parts) do
		if not firstPos then
			firstPos = p.Position
			isWood = (p.Material == Enum.Material.Wood or p.Material == Enum.Material.WoodPlanks)
		end
		-- Immediately disable collision and anchor on client so the car NEVER hits a brick wall
		p.CanCollide = false
		p.Anchored = false

		local spread = Vector3.new(
			(math.random() - 0.5) * 18,
			math.random() * 8,
			(math.random() - 0.5) * 18
		)
		local scale = math.clamp(1.06 - (idx - 1) * 0.05, 0.80, 1.12)
		p.AssemblyLinearVelocity = baseLaunchVel * scale + spread
		p.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 24,
			(math.random() - 0.5) * 24,
			(math.random() - 0.5) * 24
		)
	end

	if firstPos then
		spawnClientImpactSparks(firstPos, isWood, false)
	end

	-- Fire server remotes immediately so server triggers geysers, explosions, combo, and cash
	local outboundVel = if carVelocity.Magnitude >= 30 then carVelocity else baseLaunchVel
	local reportRemote = getRemoteEvent("ReportDestruction")
	if reportRemote then
		reportRemote:FireServer(propInst, outboundVel)
	end
	local smashRemote = getRemoteEvent("SmashProp")
	if smashRemote then
		smashRemote:FireServer(propInst, outboundVel)
	end
end

local function performBumperSmashSweep(seat: VehicleSeat, model: Model, chassis: BasePart, throttleInput: number)
	local playerSmashTier = getPlayerSmashTier(localPlayer, model)

	local vel = chassis.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local attrSpeed = tonumber(localPlayer:GetAttribute("VehicleSpeed")) or 0
	local effectiveSpeed = math.max(speed, attrSpeed)

	-- Sweep whenever moving >= 3.5 studs/s OR pressing throttle W/S
	if effectiveSpeed < 3.5 and math.abs(throttleInput) < 0.05 then
		return
	end

	local filterList: { Instance } = { model }
	if localPlayer.Character then
		table.insert(filterList, localPlayer.Character)
	end
	overlapParams.FilterDescendantsInstances = filterList

	local lookVec = chassis.CFrame.LookVector
	local flatForward = Vector3.new(lookVec.X, 0, lookVec.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end

	-- Sweep slightly ahead of and around the car
	local sweepCF = chassis.CFrame * CFrame.new(0, 0, -2.0)
	local sweepSize = chassis.Size + Vector3.new(4.0, 3.0, 6.0)
	local hitParts = Workspace:GetPartBoundsInBox(sweepCF, sweepSize, overlapParams)

	local smashedAny = false
	for _, part in ipairs(hitParts) do
		local propInst = resolveDestructibleProp(part, model)
		if propInst and propInst:GetAttribute("Destroyed") ~= true then
			local requiredTier = getPropRequiredTier(propInst)
			if playerSmashTier >= requiredTier then
				smashedAny = true
				local travelDir = if throttleInput < -0.1 and vel:Dot(flatForward) < -1
					then -flatForward
					else flatForward
				smashPropLocallyAndNotifyServer(propInst, travelDir, effectiveSpeed, vel)
			else
				showTierResistanceBadge(propInst, requiredTier, part.Position)
			end
		end
	end

	-- If the physics solver already clipped an anchored prop that we smashed in this substep, restore pre-impact velocity
	if smashedAny and lastPreImpactVelocity.Magnitude > vel.Magnitude + 6 then
		chassis.AssemblyLinearVelocity = Vector3.new(
			lastPreImpactVelocity.X,
			vel.Y,
			lastPreImpactVelocity.Z
		)
	end
end

--------------------------------------------------------------------------------
-- 2. Responsive Brake Assist, Recessed Dark-Red LED Brake Lights & Skid Trails
--------------------------------------------------------------------------------
local function readBrakingAndThrottleState(seat: VehicleSeat, forwardSpeed: number): (number, boolean, boolean)
	local kbThrottle = 0
	local spaceDown = false

	if not UserInputService:GetFocusedTextBox() then
		local wDown = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		local sDown = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
		if wDown then
			kbThrottle += 1
		end
		if sDown then
			kbThrottle -= 1
		end
		spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space)
			or UserInputService:IsKeyDown(Enum.KeyCode.ButtonR1)
	end

	local touchThrottle = tonumber(localPlayer:GetAttribute("TouchThrottle")) or 0
	local seatThrottle = seat.ThrottleFloat
	local finalThrottle = kbThrottle
	if math.abs(touchThrottle) > math.abs(finalThrottle) then
		finalThrottle = touchThrottle
	end
	if math.abs(seatThrottle) > math.abs(finalThrottle) then
		finalThrottle = seatThrottle
	end

	local handbrakeActive = spaceDown or (localPlayer:GetAttribute("TouchDrift") == true)
	local reverseBraking = (finalThrottle < -0.1 and forwardSpeed > 3.5)
		or (finalThrottle > 0.1 and forwardSpeed < -3.5)
	local isBraking = reverseBraking or (handbrakeActive and math.abs(forwardSpeed) > 3.5)

	return finalThrottle, isBraking, handbrakeActive
end

local function updateBrakeLightsAndSkidTrails(
	model: Model,
	chassis: BasePart,
	isBraking: boolean,
	absSpeed: number
)
	local tailBar = model:FindFirstChild("TaillightBar") :: BasePart?
	local clusterL = model:FindFirstChild("TaillightClusterL") :: BasePart?
	local clusterR = model:FindFirstChild("TaillightClusterR") :: BasePart?

	-- Keep recessed dark-red LED strips (185, 24, 30) when cruising; crisp red brake glow when braking
	local activeColor = if isBraking
		then Color3.fromRGB(220, 28, 34)
		else Color3.fromRGB(185, 24, 30)
	local activeMaterial = if isBraking then Enum.Material.Neon else Enum.Material.SmoothPlastic

	for _, part in ipairs({ tailBar, clusterL, clusterR }) do
		if part then
			part.Color = activeColor
			part.Material = activeMaterial
		end
	end

	if tailBar then
		local brakeLight = tailBar:FindFirstChild("BrakeGlowLight") :: PointLight?
		if not brakeLight then
			brakeLight = Instance.new("PointLight")
			brakeLight.Name = "BrakeGlowLight"
			brakeLight.Color = Color3.fromRGB(220, 28, 34)
			brakeLight.Range = 12
			brakeLight.Parent = tailBar
		end
		brakeLight.Enabled = isBraking
		brakeLight.Brightness = if isBraking then 2.4 else 0
	end

	-- Enable rear tire skid trails and smoke during hard braking
	local hardBraking = isBraking and absSpeed > 16
	local isDriftingAttr = localPlayer:GetAttribute("IsDrifting") == true
	local showSkids = hardBraking or isDriftingAttr

	for _, trailName in ipairs({ "SkidTrailL", "SkidTrailR" }) do
		local trail = chassis:FindFirstChild(trailName) :: Trail?
		if trail then
			trail.Enabled = showSkids
		end
	end

	for _, attName in ipairs({ "DriftAttachmentL", "DriftAttachmentR" }) do
		local att = chassis:FindFirstChild(attName)
		local smoke = att and att:FindFirstChild("DriftSmoke") :: ParticleEmitter?
		if smoke then
			smoke.Enabled = showSkids
		end
	end
end

local function applyResponsiveBrakeAssist(
	model: Model,
	chassis: BasePart,
	dt: number,
	throttleInput: number,
	isBraking: boolean,
	handbrakeActive: boolean
)
	local vel = chassis.AssemblyLinearVelocity
	local lookVec = chassis.CFrame.LookVector
	local flatForward = Vector3.new(lookVec.X, 0, lookVec.Z)
	if flatForward.Magnitude < 0.01 then
		return
	end
	flatForward = flatForward.Unit
	local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)

	local forwardSpeed = vel:Dot(flatForward)
	local lateralSpeed = vel:Dot(flatRight)
	local absForward = math.abs(forwardSpeed)

	updateBrakeLightsAndSkidTrails(model, chassis, isBraking, absForward)

	if not isBraking then
		return
	end

	local isDrifting = localPlayer:GetAttribute("IsDrifting") == true
	local baseBrakeDecel = tonumber(model:GetAttribute("BrakeDecel")) or 120

	-- Progressive high-grip braking deceleration assist
	local gripMultiplier = if (throttleInput < -0.1 and forwardSpeed > 2)
		then 1.65
		elseif (handbrakeActive and not isDrifting) then 1.85
		else 0.85

	local decelStep = baseBrakeDecel * gripMultiplier * dt
	local newForwardSpeed = forwardSpeed
	if math.abs(forwardSpeed) <= decelStep or math.abs(forwardSpeed) < 3.0 then
		newForwardSpeed = 0
	elseif forwardSpeed > 0 then
		newForwardSpeed = math.max(0, forwardSpeed - decelStep)
	else
		newForwardSpeed = math.min(0, forwardSpeed + decelStep)
	end

	-- Dampen unwanted lateral slide when straight-line braking
	local newLateralSpeed = if isDrifting
		then lateralSpeed
		else lateralSpeed * math.max(0, 1 - dt * 14)

	local newHoriz = flatForward * newForwardSpeed + flatRight * newLateralSpeed
	chassis.AssemblyLinearVelocity = Vector3.new(newHoriz.X, vel.Y, newHoriz.Z)

	-- Dampen yaw spin when coming to a complete stop
	if math.abs(newForwardSpeed) < 2.0 and not isDrifting then
		chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity * math.max(0, 1 - dt * 18)
	end
end

--------------------------------------------------------------------------------
-- Main Heartbeat Loop
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	if dt <= 0 or dt > 0.2 then
		return
	end

	local seat, model, chassis = getActiveVehicleAndChassis()
	if not seat or not model or not chassis then
		getPlayerSmashTier(localPlayer, nil)
		lastVehicleModel = nil
		lastChassisSpeed = 0
		lastPreImpactVelocity = Vector3.zero
		return
	end

	local currentHealth = tonumber(model:GetAttribute("Health")) or 100

	if model ~= lastVehicleModel then
		lastVehicleModel = model
		lastRecordedHealth = currentHealth
		lastChassisSpeed = chassis.AssemblyLinearVelocity.Magnitude
		lastPreImpactVelocity = chassis.AssemblyLinearVelocity
	end

	-- 1. Check for Health drop to spawn impact sparks (NEVER modify welds/C0!)
	if currentHealth ~= lastRecordedHealth then
		if currentHealth < lastRecordedHealth then
			local frontPos = (chassis.CFrame * CFrame.new(0, 0.2, -chassis.Size.Z * 0.5)).Position
			spawnClientImpactSparks(frontPos, false, false)
		end
		lastRecordedHealth = currentHealth
	end

	-- 2. Read driving & braking inputs
	local vel = chassis.AssemblyLinearVelocity
	local forwardSpeed = vel:Dot(chassis.CFrame.LookVector)
	local throttleInput, isBraking, handbrakeActive = readBrakingAndThrottleState(seat, forwardSpeed)

	-- 3. Zero-Resistance Client Bumper Smash Sweep (with 5-Tier Destruction Power Check)
	performBumperSmashSweep(seat, model, chassis, throttleInput)

	-- 4. Responsive Brake Assist, Brake Lights & Skid Trails
	applyResponsiveBrakeAssist(model, chassis, dt, throttleInput, isBraking, handbrakeActive)

	-- 5. Hard Wall Impact Sparks (when hitting non-destructible building walls at speed)
	local newSpeed = chassis.AssemblyLinearVelocity.Magnitude
	if (lastChassisSpeed - newSpeed) > 34 and lastChassisSpeed > 42 and not isBraking then
		local frontPos = (chassis.CFrame * CFrame.new(0, 0.2, -chassis.Size.Z * 0.5)).Position
		spawnClientImpactSparks(frontPos, false, false)
	end

	lastChassisSpeed = newSpeed
	if newSpeed >= 4.0 then
		lastPreImpactVelocity = chassis.AssemblyLinearVelocity
	end
end)

-- Periodic cleanup of old entries in locallySmashedProps and tierBlockedCooldowns caches
task.spawn(function()
	while true do
		task.wait(10.0)
		local now = os.clock()
		for inst, ts in pairs(locallySmashedProps) do
			if not inst.Parent or (now - ts) > SMASH_CACHE_TTL then
				locallySmashedProps[inst] = nil
			end
		end
		for inst, ts in pairs(tierBlockedCooldowns) do
			if not inst.Parent or (now - ts) > SMASH_CACHE_TTL then
				tierBlockedCooldowns[inst] = nil
			end
		end
	end
end)
