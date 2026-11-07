--!strict
--[[
	DestructionSmashClient.client.luau
	Client-side zero-resistance prop smashing, responsive high-grip brake assist,
	dynamic brake lights + skid trails, and progressive visual car damage/crumple
	for World of Destruction (Leo City).

	Features:
	  1. Zero-Resistance Client Bumper Smash Sweep (RunService.Heartbeat):
	     - Sweeps ahead of and around the player's active vehicle (chassis.Size + Vector3.new(4, 3, 6)).
	     - Immediately sets CanCollide = false and Anchored = false on all BaseParts of any hit
	       "Destructible" prop, breaks internal welds, and launches pieces forward + upward with spin
	       so the vehicle plows straight through fences, streetlights, hydrants, crates, and bus stops
	       with ZERO slowdown or brick-wall bounce.
	     - Preserves vehicle momentum across prop impacts and fires ReportDestruction & SmashProp remotes.
	  2. Responsive Brake Assist, Intense Brake Lights & Skid Trails:
	     - Applies progressive high-grip braking deceleration assist when holding Brake (S/Down while
	       moving forward, or Space Handbrake) so stopping is crisp, predictable, and responsive.
	     - Lights up TaillightBar & TaillightClusters with neon red + PointLight glow and activates
	       SkidTrailL / SkidTrailR during hard braking.
	  3. Progressive Visual Car Damage, Crumple & Impact Sparks:
	     - Monitors vehicle Health vs MaxHealth (< 80%, < 50%, < 25%) and offsets/tilts Hood,
	       FrontBumper, RearBumper, and Windshield welds for physical denting/crumpling.
	     - Spawns metallic impact sparks on hard wall collisions or health drops.
	     - Restores all panels to pristine factory alignment when repaired (Health >= MaxHealth).
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local SMASH_CACHE_TTL = 8.0

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local lastVehicleModel: Model? = nil
local lastRecordedHealth: number = 100
local lastChassisSpeed: number = 0
local lastPreImpactVelocity: Vector3 = Vector3.zero
local lastImpactSparkAt: number = 0
local appliedDamageTier: { [Model]: number } = {}

-- Crumple configuration per part for damage tiers:
-- Tier 0 = Pristine (>= 80% HP)
-- Tier 1 = Light Dent (< 80% HP)
-- Tier 2 = Medium Crumple (< 50% HP)
-- Tier 3 = Heavy Wreck Crumple (< 25% HP)
type CrumpleSpec = {
	PartName: string,
	Offset: Vector3,
	Angles: Vector3, -- radians (pitch, yaw, roll)
}

local CRUMPLE_SPECS: { CrumpleSpec } = {
	{
		PartName = "Hood",
		Offset = Vector3.new(0.04, 0.22, 0.28),
		Angles = Vector3.new(math.rad(11), math.rad(-3), math.rad(4)),
	},
	{
		PartName = "HoodNoseWedge",
		Offset = Vector3.new(-0.03, 0.16, 0.32),
		Angles = Vector3.new(math.rad(14), math.rad(2), math.rad(-3)),
	},
	{
		PartName = "HoodPowerDome",
		Offset = Vector3.new(0.04, 0.24, 0.26),
		Angles = Vector3.new(math.rad(11), math.rad(-3), math.rad(4)),
	},
	{
		PartName = "FrontBumper",
		Offset = Vector3.new(0.06, -0.14, 0.34),
		Angles = Vector3.new(math.rad(-9), math.rad(4), math.rad(-6)),
	},
	{
		PartName = "FrontSplitter",
		Offset = Vector3.new(-0.04, -0.16, 0.36),
		Angles = Vector3.new(math.rad(-10), math.rad(-3), math.rad(5)),
	},
	{
		PartName = "RearBumper",
		Offset = Vector3.new(-0.05, -0.12, -0.26),
		Angles = Vector3.new(math.rad(7), math.rad(-3), math.rad(5)),
	},
	{
		PartName = "Windshield",
		Offset = Vector3.new(0.0, -0.08, 0.14),
		Angles = Vector3.new(math.rad(-6), math.rad(2), math.rad(-3)),
	},
}

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
-- Helper: Spawn Instant Client-Side Impact Sparks / Splinters
--------------------------------------------------------------------------------
local function spawnClientImpactSparks(worldPos: Vector3, isWood: boolean)
	local now = os.clock()
	if now - lastImpactSparkAt < 0.06 then
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
	pe:Emit(18)

	Debris:AddItem(host, 0.6)
end

--------------------------------------------------------------------------------
-- 1. Zero-Resistance Client Bumper Smash Sweep
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

	-- Break all internal welds on the client immediately so composite props shatter apart
	if propInst:IsA("Model") and not CollectionService:HasTag(propInst, "AITrafficVehicle") then
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
	local baseLaunchVel = carForward * baseLaunchSpeed + Vector3.new(0, 22, 0)
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
		spawnClientImpactSparks(firstPos, isWood)
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
			smashedAny = true
			local travelDir = if throttleInput < -0.1 and vel:Dot(flatForward) < -1
				then -flatForward
				else flatForward
			smashPropLocallyAndNotifyServer(propInst, travelDir, effectiveSpeed, vel)
		end
	end

	-- If the physics solver already clipped an anchored prop in this substep, restore pre-impact velocity
	if smashedAny and lastPreImpactVelocity.Magnitude > vel.Magnitude + 6 then
		chassis.AssemblyLinearVelocity = Vector3.new(
			lastPreImpactVelocity.X,
			vel.Y,
			lastPreImpactVelocity.Z
		)
	end
end

--------------------------------------------------------------------------------
-- 2. Responsive Brake Assist, Brake Lights & Rear Tire Skid Trails
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

	local activeColor = if isBraking
		then Color3.fromRGB(255, 38, 28)
		else Color3.fromRGB(165, 18, 18)
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
			brakeLight.Color = Color3.fromRGB(255, 30, 20)
			brakeLight.Range = 16
			brakeLight.Parent = tailBar
		end
		brakeLight.Enabled = isBraking
		brakeLight.Brightness = if isBraking then 3.8 else 0
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
	-- Stronger stopping power when holding S/Down or Space without drifting
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
-- 3. Progressive Visual Car Damage, Crumple & Repair Alignment
--------------------------------------------------------------------------------
local function computeDamageTier(health: number, maxHealth: number): number
	local ratio = health / math.max(1, maxHealth)
	if ratio >= 0.99 then
		return 0
	elseif ratio < 0.25 then
		return 3
	elseif ratio < 0.50 then
		return 2
	elseif ratio < 0.80 then
		return 1
	end
	return 0
end

local function updateVehicleCrumpleVisuals(model: Model, forceUpdate: boolean?)
	local health = tonumber(model:GetAttribute("Health")) or 100
	local maxHealth = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)
	local tier = computeDamageTier(health, maxHealth)

	if not forceUpdate and appliedDamageTier[model] == tier then
		return
	end
	appliedDamageTier[model] = tier

	-- Scale factor for crumple intensity (0 = pristine, 0.35 = <80%, 0.70 = <50%, 1.15 = <25%)
	local intensity = if tier == 0
		then 0.0
		elseif tier == 1 then 0.38
		elseif tier == 2 then 0.75
		else 1.18

	for _, spec in ipairs(CRUMPLE_SPECS) do
		local part = model:FindFirstChild(spec.PartName) :: BasePart?
		if part then
			local weld = (part:FindFirstChild(spec.PartName .. "_Weld") or part:FindFirstChildOfClass("Weld")) :: Weld?
			if weld then
				local pristineC0 = part:GetAttribute("PristineBaseC0")
				if typeof(pristineC0) ~= "CFrame" then
					local existingBase = part:GetAttribute("BaseC0")
					pristineC0 = if typeof(existingBase) == "CFrame" then existingBase else weld.C0
					part:SetAttribute("PristineBaseC0", pristineC0)
				end

				local baseCF = pristineC0 :: CFrame
				if intensity <= 0.001 then
					-- Restore to pristine factory alignment when repaired
					part:SetAttribute("BaseC0", baseCF)
					weld.C0 = baseCF
				else
					local offset = spec.Offset * intensity
					local rot = CFrame.Angles(
						spec.Angles.X * intensity,
						spec.Angles.Y * intensity,
						spec.Angles.Z * intensity
					)
					local crumpledCF = baseCF * CFrame.new(offset) * rot
					-- Updating BaseC0 ensures VehicleClientController's RenderStepped tilt preserves the crumple!
					part:SetAttribute("BaseC0", crumpledCF)
					weld.C0 = crumpledCF
				end
			end
		end
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
		lastVehicleModel = nil
		lastChassisSpeed = 0
		lastPreImpactVelocity = Vector3.zero
		return
	end

	local currentHealth = tonumber(model:GetAttribute("Health")) or 100
	local maxHealth = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)

	if model ~= lastVehicleModel then
		lastVehicleModel = model
		lastRecordedHealth = currentHealth
		lastChassisSpeed = chassis.AssemblyLinearVelocity.Magnitude
		lastPreImpactVelocity = chassis.AssemblyLinearVelocity
		updateVehicleCrumpleVisuals(model, true)
	end

	-- 1. Check for Health drop or Repair to update visual crumple & spawn impact sparks
	if currentHealth ~= lastRecordedHealth then
		if currentHealth < lastRecordedHealth then
			local frontPos = (chassis.CFrame * CFrame.new(0, 0.2, -chassis.Size.Z * 0.5)).Position
			spawnClientImpactSparks(frontPos, false)
		end
		lastRecordedHealth = currentHealth
		updateVehicleCrumpleVisuals(model, true)
	else
		updateVehicleCrumpleVisuals(model, false)
	end

	-- 2. Read driving & braking inputs
	local vel = chassis.AssemblyLinearVelocity
	local forwardSpeed = vel:Dot(chassis.CFrame.LookVector)
	local throttleInput, isBraking, handbrakeActive = readBrakingAndThrottleState(seat, forwardSpeed)

	-- 3. Zero-Resistance Client Bumper Smash Sweep (runs every Heartbeat)
	performBumperSmashSweep(seat, model, chassis, throttleInput)

	-- 4. Responsive Brake Assist, Brake Lights & Skid Trails
	applyResponsiveBrakeAssist(model, chassis, dt, throttleInput, isBraking, handbrakeActive)

	-- 5. Hard Wall Impact Sparks (when hitting non-destructible building walls at speed)
	local newSpeed = chassis.AssemblyLinearVelocity.Magnitude
	if (lastChassisSpeed - newSpeed) > 34 and lastChassisSpeed > 42 and not isBraking then
		local frontPos = (chassis.CFrame * CFrame.new(0, 0.2, -chassis.Size.Z * 0.5)).Position
		spawnClientImpactSparks(frontPos, false)
	end

	lastChassisSpeed = newSpeed
	if newSpeed >= 4.0 then
		lastPreImpactVelocity = chassis.AssemblyLinearVelocity
	end
end)

-- Periodic cleanup of old entries in locallySmashedProps cache
task.spawn(function()
	while true do
		task.wait(10.0)
		local now = os.clock()
		for inst, ts in pairs(locallySmashedProps) do
			if not inst.Parent or (now - ts) > SMASH_CACHE_TTL then
				locallySmashedProps[inst] = nil
			end
		end
	end
end)
