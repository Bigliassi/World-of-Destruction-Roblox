--!strict
-- DestructionService.script.luau
-- High-impact Roblox physics destruction system for Leo City with 5-Tier Destruction Power System:
-- - Computes player SmashPowerTier (1..5) from vehicle archetype + Plow upgrade level and publishes
--   `player:SetAttribute("SmashPowerTier", tier)`.
-- - Enforces RequiredTier (1..5) per prop:
--   - When playerSmashTier >= requiredTier: smashes immediately and awards full Cash & Coins.
--   - When playerSmashTier < requiredTier: resists destruction, spawns metallic spark burst + clink sound,
--     and shows a 1.2s floating 3D badge ("NEED TIER X CAR OR PLOW! [PRESS B]" in gold/red, 1.5s cooldown).
-- - Preserves vehicle integrity on rammed vehicles (AITrafficVehicle, Vehicle, TrafficVehicle, ArmoredCashTruck):
--   NEVER breaks internal WeldConstraints and NEVER sets CanCollide = false on body parts; keeps all parts
--   welded to PrimaryPart (Chassis), unanchors Chassis, and applies a dramatic upward/forward flip impulse
--   (launchDir * 55 + Vector3.new(0, 32, 0)) + angular spin so the entire intact car flips and tumbles!
-- - Spawns water geysers, electric sparks, and chain-reaction explosions.
-- - Automatically respawns destroyed props after 45 seconds when players are far away.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- EVENTS & REMOTES SETUP
--------------------------------------------------------------------------------
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ServerStorage
end

local DestructionBindable = ServerEvents:FindFirstChild("DestructionOccurred") :: BindableEvent?
if not DestructionBindable then
	DestructionBindable = Instance.new("BindableEvent")
	DestructionBindable.Name = "DestructionOccurred"
	DestructionBindable.Parent = ServerEvents
end

local RepEvents = ReplicatedStorage:FindFirstChild("Remotes")
if not RepEvents then
	RepEvents = Instance.new("Folder")
	RepEvents.Name = "Remotes"
	RepEvents.Parent = ReplicatedStorage
end

local function ensureRemote(name: string): RemoteEvent
	local existing = RepEvents:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = RepEvents
	return re
end

local DestructionRemote = ensureRemote("DestructionOccurred")
local ExplosionRemote = ensureRemote("ExplosionEffect")
local ReportDestructionRemote = ensureRemote("ReportDestruction")
local SmashPropRemote = ensureRemote("SmashProp")

--------------------------------------------------------------------------------
-- CONSTANTS & STATE
--------------------------------------------------------------------------------
local RESPAWN_DELAY = 45.0
local SAFE_PLAYER_RESPAWN_DIST = 65.0
local EXPLOSION_BLAST_RADIUS = 38.0
local PROXIMITY_SWEEP_INTERVAL = 0.06
local CLIENT_REPORT_MAX_DIST = 45.0
local TIER_BLOCK_COOLDOWN = 1.5

type RespawnEntry = {
	template: Instance,
	parent: Instance,
	originCF: CFrame,
	destroyedAt: number,
	liveInstance: Instance,
}

local respawnQueue: { RespawnEntry } = {}
local boundInstances: { [Instance]: boolean } = {}
local boundParts: { [BasePart]: boolean } = {}
local tierBlockedCooldowns: { [Instance]: number } = {}

--------------------------------------------------------------------------------
-- 5-TIER DESTRUCTION POWER SYSTEM HELPERS
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

local function isVehicleDestructible(inst: Instance): boolean
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

local function showTierResistanceFeedback(propInst: Instance, requiredTier: number)
	local now = os.clock()
	local lastShown = tierBlockedCooldowns[propInst]
	if lastShown and (now - lastShown) < TIER_BLOCK_COOLDOWN then
		return
	end
	tierBlockedCooldowns[propInst] = now

	local adorneePart: BasePart? = if propInst:IsA("BasePart")
		then propInst
		elseif propInst:IsA("Model") then (propInst.PrimaryPart or propInst:FindFirstChildWhichIsA("BasePart", true))
		else nil
	if not adorneePart then
		return
	end

	-- Metallic spark burst + metallic clink sound
	local sparkHost = Instance.new("Part")
	sparkHost.Name = "TierResistSparkVFX"
	sparkHost.Size = Vector3.new(0.5, 0.5, 0.5)
	sparkHost.Position = adorneePart.Position
	sparkHost.Anchored = true
	sparkHost.CanCollide = false
	sparkHost.Transparency = 1
	sparkHost.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 235, 110), Color3.fromRGB(255, 110, 20))
	pe.LightEmission = 1.0
	pe.Size = NumberSequence.new(0.45, 0.0)
	pe.Lifetime = NumberRange.new(0.18, 0.42)
	pe.Speed = NumberRange.new(20, 38)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -45, 0)
	pe.Rate = 0
	pe.Parent = sparkHost
	pe:Emit(24)

	local clink = Instance.new("Sound")
	clink.Name = "MetallicResistClink"
	clink.SoundId = "rbxassetid://9114221580"
	clink.Volume = 0.7
	clink.PlaybackSpeed = 1.18
	clink.Parent = sparkHost
	clink:Play()

	Debris:AddItem(sparkHost, 0.8)

	if propInst:FindFirstChild("TierBlockedBadge") then
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
-- DESTRUCTIBLE RESOLUTION HELPERS
--------------------------------------------------------------------------------
local function isDestructibleRoot(inst: Instance): boolean
	if inst == Workspace or inst:IsA("Folder") then
		return false
	end
	if CollectionService:HasTag(inst, "Destructible") then
		return true
	end
	if inst:GetAttribute("IsDestructible") == true or inst:GetAttribute("PropType") ~= nil then
		return true
	end
	return false
end

local function resolveDestructibleInstance(candidate: Instance?): Instance?
	if not candidate or not candidate:IsDescendantOf(Workspace) then
		return nil
	end

	local bestMatch: Instance? = nil
	local curr: Instance? = candidate
	while curr and curr ~= Workspace do
		if isDestructibleRoot(curr) then
			bestMatch = curr
		end
		curr = curr.Parent
	end

	if bestMatch then
		if (tonumber(bestMatch:GetAttribute("OwnerUserId")) or 0) > 0 then
			return nil
		end
		return bestMatch
	end

	-- Check if inside Workspace.LeoCity.DestructibleProps or TrafficLights
	local leoCity = Workspace:FindFirstChild("LeoCity")
	if leoCity then
		local propsFolder = leoCity:FindFirstChild("DestructibleProps")
		local lightsFolder = leoCity:FindFirstChild("TrafficLights")
		local node: Instance? = candidate
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

local function getDestructiblePosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local primary = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			return primary.Position
		end
	end
	return nil
end

local function getEffectiveBreakThreshold(inst: Instance): number
	local rawThreshold = (inst:GetAttribute("BreakThreshold") :: number?) or 5
	local propType = (inst:GetAttribute("PropType") :: string?) or inst.Name
	if propType == "ConstructionCrane" or propType == "PlazaFountain" then
		return math.min(rawThreshold, 12)
	end
	return math.min(rawThreshold, 5)
end

--------------------------------------------------------------------------------
-- DRIVER & VEHICLE RESOLUTION
--------------------------------------------------------------------------------
local function resolveAttacker(hitPart: BasePart): (Player?, number, Vector3, Model?)
	local vel = hitPart.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local ramMultiplier = 1.0
	local attacker: Player? = nil
	local resolvedVehicleModel: Model? = nil

	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model then
		-- Check if it's a player character
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			attacker = plr
		end

		-- Check if it's a vehicle with a Driver/VehicleSeat or Owner attribute
		local vehicleModel = model
		while vehicleModel.Parent and vehicleModel.Parent:IsA("Model") and vehicleModel.Parent ~= Workspace do
			vehicleModel = vehicleModel.Parent :: Model
		end
		if CollectionService:HasTag(vehicleModel, "Vehicle") or vehicleModel:FindFirstChild("DriveSeat") then
			resolvedVehicleModel = vehicleModel
		end

		local ramAttr = (vehicleModel:GetAttribute("RamMultiplier") :: number?)
			or (vehicleModel:GetAttribute("RamPower") :: number?)
			or (model:GetAttribute("RamMultiplier") :: number?)
		if ramAttr then
			ramMultiplier = ramAttr
		end

		local ownerUserId = (vehicleModel:GetAttribute("OwnerUserId") :: number?)
			or (vehicleModel:GetAttribute("DriverUserId") :: number?)
		if ownerUserId and not attacker then
			attacker = Players:GetPlayerByUserId(ownerUserId)
		end

		local ownerName = (vehicleModel:GetAttribute("Owner") :: string?)
			or (vehicleModel:GetAttribute("DriverName") :: string?)
		if ownerName and not attacker then
			attacker = Players:FindFirstChild(ownerName) :: Player?
		end

		if not attacker then
			local seat = vehicleModel:FindFirstChildWhichIsA("VehicleSeat", true)
				or vehicleModel:FindFirstChildWhichIsA("Seat", true)
			if seat and seat.Occupant then
				local char = seat.Occupant.Parent
				if char then
					attacker = Players:GetPlayerFromCharacter(char)
				end
			end
		end

		-- Fallback velocity from vehicle primary part or driver attributes if collision stopped the bumper part
		local vPrimary = vehicleModel.PrimaryPart or vehicleModel:FindFirstChild("Chassis") :: BasePart?
		if vPrimary and vPrimary.AssemblyLinearVelocity.Magnitude > speed then
			vel = vPrimary.AssemblyLinearVelocity
			speed = vel.Magnitude
		end
		if attacker and speed < 8 then
			local attrSpeed = tonumber(attacker:GetAttribute("VehicleSpeed")) or 0
			if attrSpeed > speed and vPrimary then
				vel = vPrimary.CFrame.LookVector * attrSpeed
				speed = attrSpeed
			end
		end
	end

	-- Fallback: nearest player within 35 studs
	if not attacker then
		local bestDist = 35
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - hitPart.Position).Magnitude
				if d < bestDist then
					bestDist = d
					attacker = plr
					if speed < root.AssemblyLinearVelocity.Magnitude then
						vel = root.AssemblyLinearVelocity
						speed = vel.Magnitude
					end
				end
			end
		end
	end

	return attacker, ramMultiplier, vel, resolvedVehicleModel
end

--------------------------------------------------------------------------------
-- SPECIAL PROP VFX (GEYSERS, SPARKS, SHATTER DEBRIS, EXPLOSIONS)
--------------------------------------------------------------------------------
local function spawnWaterGeyser(pos: Vector3)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "HydrantWaterGeyser"
	emitterPart.Size = Vector3.new(1, 1, 1)
	emitterPart.Position = pos + Vector3.new(0, 0.5, 0)
	emitterPart.Anchored = true
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(165, 225, 255), Color3.fromRGB(240, 250, 255))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.6, 2.2),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(1.1, 1.6)
	pe.Rate = 85
	pe.Speed = NumberRange.new(34, 46)
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Acceleration = Vector3.new(0, -45, 0)
	pe.Parent = emitterPart

	Debris:AddItem(emitterPart, 8.0)
end

local function spawnElectricSparks(part: BasePart)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "ElectricSparks"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 230, 95), Color3.fromRGB(255, 120, 20))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.45, 0)
	pe.Lifetime = NumberRange.new(0.25, 0.55)
	pe.Rate = 60
	pe.Speed = NumberRange.new(16, 28)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -35, 0)
	pe.Parent = part

	task.delay(2.2, function()
		if pe and pe.Parent then
			pe.Enabled = false
		end
	end)
end

local WOOD_PROPS: { [string]: boolean } = {
	WoodenCrate = true,
	Crate = true,
	JackpotCrate = true,
	Fence = true,
	Bench = true,
	PalmTree = true,
}

local function spawnShatterDebrisBurst(
	originPos: Vector3,
	propType: string,
	baseColor: Color3,
	baseMaterial: Enum.Material,
	launchDir: Vector3,
	launchSpeed: number
)
	local isWood = WOOD_PROPS[propType]
		or baseMaterial == Enum.Material.Wood
		or baseMaterial == Enum.Material.WoodPlanks
	local fragmentCount = if isWood then 5 else 4
	local fragMaterial = if isWood then Enum.Material.WoodPlanks else Enum.Material.Metal
	local fragColor = if isWood
		then Color3.fromRGB(148, 102, 58)
		else baseColor

	for i = 1, fragmentCount do
		local frag = Instance.new("Part")
		frag.Name = if isWood then "WoodSplinter" else "MetalFragment"
		if isWood then
			frag.Size = Vector3.new(
				0.35 + math.random() * 0.35,
				0.22 + math.random() * 0.25,
				1.4 + math.random() * 1.4
			)
		else
			frag.Size = Vector3.new(
				0.45 + math.random() * 0.55,
				0.20 + math.random() * 0.35,
				0.75 + math.random() * 0.95
			)
		end
		frag.Color = fragColor
		frag.Material = fragMaterial
		frag.TopSurface = Enum.SurfaceType.Smooth
		frag.BottomSurface = Enum.SurfaceType.Smooth
		frag.Anchored = false
		frag.CanCollide = false
		frag.Massless = true

		local offset = Vector3.new(
			(math.random() - 0.5) * 2.6,
			0.8 + math.random() * 2.2,
			(math.random() - 0.5) * 2.6
		)
		frag.CFrame = CFrame.new(originPos + offset)
			* CFrame.Angles(
				math.random() * math.pi * 2,
				math.random() * math.pi * 2,
				math.random() * math.pi * 2
			)
		frag.Parent = Workspace

		local scatter = Vector3.new(
			(math.random() - 0.5) * 28,
			14 + math.random() * 18,
			(math.random() - 0.5) * 28
		)
		frag.AssemblyLinearVelocity = launchDir * math.clamp(launchSpeed * 1.05, 26, 72) + scatter
		frag.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 26,
			(math.random() - 0.5) * 26,
			(math.random() - 0.5) * 26
		)

		Debris:AddItem(frag, 3.5)
	end
end

local destroyProp: (inst: Instance, attacker: Player?, hitVel: Vector3, isFromExplosion: boolean) -> ()

local function breakAllInternalWelds(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("WeldConstraint") then
			desc.Enabled = false
			desc:Destroy()
		elseif desc:IsA("Weld") or desc:IsA("Snap") or desc:IsA("ManualWeld") then
			desc:Destroy()
		end
	end
end

local function triggerChainExplosion(pos: Vector3, attacker: Player?, sourcePropType: string?)
	local isRealExplosiveProp = (sourcePropType == "ExplosiveBarrel" or sourcePropType == "GasPump")

	local exp = Instance.new("Explosion")
	exp.BlastRadius = EXPLOSION_BLAST_RADIUS
	exp.BlastPressure = 0 -- Custom impulse handling for predictable arcade feel
	exp.DestroyJointRadiusPercent = 0
	exp.Visible = isRealExplosiveProp
	exp.Position = pos
	exp.Parent = Workspace

	if isRealExplosiveProp and ExplosionRemote then
		ExplosionRemote:FireAllClients(pos, EXPLOSION_BLAST_RADIUS)
	end

	-- Flash light burst
	local flashPart = Instance.new("Part")
	flashPart.Size = Vector3.new(1, 1, 1)
	flashPart.Position = pos
	flashPart.Anchored = true
	flashPart.CanCollide = false
	flashPart.Transparency = 1
	flashPart.Parent = Workspace

	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 150, 40)
	pl.Brightness = 6
	pl.Range = 55
	pl.Parent = flashPart
	Debris:AddItem(flashPart, 0.35)

	-- Blast nearby destructibles in radius with proportional shockwave velocity
	task.delay(0.08, function()
		local attackerTier = if attacker then (tonumber(attacker:GetAttribute("SmashPowerTier")) or getPlayerSmashTier(attacker, nil)) else 3
		for _, prop in ipairs(CollectionService:GetTagged("Destructible")) do
			if prop:GetAttribute("Destroyed") ~= true then
				local pPos = getDestructiblePosition(prop)
				if pPos then
					local delta = pPos - pos
					local dist = delta.Magnitude
					if dist <= EXPLOSION_BLAST_RADIUS then
						local reqTier = getPropRequiredTier(prop)
						if math.max(attackerTier, 3) >= reqTier then
							local dir = if dist > 0.1 then delta.Unit else Vector3.new(0, 1, 0)
							local falloff = math.clamp(1 - (dist / EXPLOSION_BLAST_RADIUS) * 0.5, 0.45, 1.0)
							destroyProp(prop, attacker, dir * (58 * falloff) + Vector3.new(0, 14, 0), true)
						end
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- CORE DESTRUCTION HANDLER
--------------------------------------------------------------------------------
destroyProp = function(inst: Instance, attacker: Player?, hitVel: Vector3, isFromExplosion: boolean)
	if not inst or not inst.Parent then
		return
	end
	if inst:GetAttribute("Destroyed") == true then
		return
	end
	inst:SetAttribute("Destroyed", true)

	local primary: BasePart? = if inst:IsA("Model")
		then (inst.PrimaryPart or (inst:FindFirstChild("Chassis") :: BasePart?) or inst:FindFirstChildWhichIsA("BasePart", true))
		elseif inst:IsA("BasePart") then inst
		else nil
	if not primary then
		return
	end

	local propPos = primary.Position
	local originCF = (inst:GetAttribute("OriginCFrame") :: CFrame?) or primary.CFrame
	local propType = (inst:GetAttribute("PropType") :: string?) or inst.Name
	local isVehicle = isVehicleDestructible(inst)
	local isJackpotCrate = (propType == "JackpotCrate")
		or (inst:GetAttribute("IsJackpotCrate") == true)
		or (string.find(string.lower(propType), "jackpot") ~= nil)
	local cashValue = (inst:GetAttribute("CashValue") :: number?) or 20
	local chaosPoints = (inst:GetAttribute("ChaosPoints") :: number?) or 15
	if isJackpotCrate then
		propType = "JackpotCrate"
		cashValue = math.floor(cashValue * 3)
		chaosPoints = math.floor(chaosPoints * 3)
	end
	local isExplosive = ((inst:GetAttribute("Explosive") :: boolean?) == true)
		or (propType == "ExplosiveBarrel")
		or (propType == "GasPump")

	-- Clone clean template for respawning before unanchoring/modifying (skip AI traffic cars which self-respawn)
	if inst.Parent and not CollectionService:HasTag(inst, "AITrafficVehicle") then
		local ok, cleanClone = pcall(function()
			return inst:Clone()
		end)
		if ok and cleanClone then
			cleanClone:SetAttribute("Destroyed", false)
			table.insert(respawnQueue, {
				template = cleanClone,
				parent = inst.Parent,
				originCF = originCF,
				destroyedAt = os.clock(),
				liveInstance = inst,
			})
		end
	end

	local flatVel = Vector3.new(hitVel.X, 0, hitVel.Z)
	local launchDir = if flatVel.Magnitude > 0.5
		then flatVel.Unit
		elseif hitVel.Magnitude > 0.5 then hitVel.Unit
		else Vector3.new(0, 1, 0)
	local launchSpeed = math.clamp(math.max(hitVel.Magnitude * 1.25, 36), 32, 78)

	local parts: { BasePart } = {}
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	elseif inst:IsA("BasePart") then
		table.insert(parts, inst)
	end

	if isVehicle then
		-- NEVER break internal WeldConstraints and NEVER set CanCollide = false on vehicle body parts!
		-- Keep all parts of the vehicle welded together to its PrimaryPart (Chassis), unanchor Chassis,
		-- and apply a dramatic upward/forward flip impulse + angular spin so the entire intact car flips!
		for _, p in ipairs(parts) do
			p.Anchored = false
		end
		primary.Anchored = false
		primary.CanCollide = true
		primary.AssemblyLinearVelocity = launchDir * 55 + Vector3.new(0, 32, 0)
		primary.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 18,
			(math.random() - 0.5) * 14,
			(math.random() - 0.5) * 18
		)
	else
		-- Regular destructible prop: break all internal welds so boards/crates/poles/signs shatter apart
		if inst:IsA("Model") then
			breakAllInternalWelds(inst)
		end

		local upwardLift = math.clamp(launchSpeed * 0.45, 18, 28)
		local spreadScale = math.clamp(launchSpeed * 0.25, 8, 18)

		for idx, p in ipairs(parts) do
			p.Anchored = false
			p.CanCollide = false
			local partSpeedScale = math.clamp(1.08 - (idx - 1) * 0.05, 0.78, 1.15)
			local spread = Vector3.new(
				(math.random() - 0.5) * 2.2,
				math.random() * 0.55 + 0.15,
				(math.random() - 0.5) * 2.2
			) * spreadScale
			p.AssemblyLinearVelocity = launchDir * (launchSpeed * partSpeedScale)
				+ Vector3.new(0, upwardLift, 0)
				+ spread
			p.AssemblyAngularVelocity = Vector3.new(
				(math.random() - 0.5) * 22,
				(math.random() - 0.5) * 22,
				(math.random() - 0.5) * 22
			)
		end

		-- Re-enable collision on flying debris after 0.35s once the vehicle has plowed past
		task.delay(0.35, function()
			if inst and inst.Parent then
				for _, p in ipairs(parts) do
					if p and p.Parent and p.Transparency < 0.95 then
						p.CanCollide = true
					end
				end
			end
		end)
	end

	-- Spawn extra flying wood splinters / metal fragments cleaned up after 3.5s
	spawnShatterDebrisBurst(propPos, propType, primary.Color, primary.Material, launchDir, launchSpeed)

	-- Special Prop Effects
	if propType == "FireHydrant" or propType == "PlazaFountain" then
		spawnWaterGeyser(originCF.Position)
	elseif propType == "StreetLight" or propType == "TrafficLight" or propType == "Billboard" then
		spawnElectricSparks(primary)
	end

	if isExplosive then
		local realType = if (propType == "ExplosiveBarrel" or propType == "GasPump") then propType else "ExplosiveBarrel"
		triggerChainExplosion(propPos, attacker, realType)
	end

	-- Broadcast DestructionOccurred to Economy/Combo systems and clients
	local payload = {
		player = attacker,
		Player = attacker,
		propType = propType,
		Type = propType,
		cashEarned = cashValue,
		CashReward = cashValue,
		chaosPoints = chaosPoints,
		position = propPos,
		Position = propPos,
		isExplosion = isExplosive,
		IsExplosion = isExplosive,
		isFromExplosion = isFromExplosion,
		isJackpotCrate = isJackpotCrate,
		IsJackpotCrate = isJackpotCrate,
		jackpotChargeGain = if isJackpotCrate then 35 else nil,
	}
	if DestructionBindable then
		DestructionBindable:Fire(payload)
	else
		local rootDestBindable = ServerStorage:FindFirstChild("DestructionEvent")
		if rootDestBindable and rootDestBindable:IsA("BindableEvent") and attacker then
			rootDestBindable:Fire(attacker, payload, cashValue, propPos)
		end
	end
	if DestructionRemote then
		if attacker then
			DestructionRemote:FireClient(attacker, payload)
		else
			DestructionRemote:FireAllClients(payload)
		end
	end

	-- Fade out broken non-vehicle physics parts after 6 seconds to keep framerate fast
	if not isVehicle then
		task.delay(6.0, function()
			if inst and inst.Parent then
				for _, p in ipairs(parts) do
					if p and p.Parent then
						p.Transparency = 1
						p.CanCollide = false
						p.Anchored = true
					end
				end
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- COLLISION BINDING (ALL DESCENDANT BASEPARTS)
--------------------------------------------------------------------------------
local function bindDestructible(inst: Instance)
	if boundInstances[inst] then
		return
	end
	boundInstances[inst] = true

	local function onTouched(otherPart: BasePart)
		if inst:GetAttribute("Destroyed") == true then
			return
		end
		if otherPart.Anchored then
			return
		end
		if otherPart:IsDescendantOf(inst) then
			return
		end
		if CollectionService:HasTag(otherPart, "Destructible") or otherPart:GetAttribute("Destroyed") == true then
			return
		end
		local otherModel = otherPart:FindFirstAncestorOfClass("Model")
		if otherModel then
			if CollectionService:HasTag(otherModel, "Destructible") and not CollectionService:HasTag(otherModel, "Vehicle") then
				return
			end
			if otherModel:GetAttribute("Destroyed") == true then
				return
			end
		end

		local attacker, ramMultiplier, hitVel, attackerVehModel = resolveAttacker(otherPart)
		local effectiveSpeed = hitVel.Magnitude * ramMultiplier
		local threshold = getEffectiveBreakThreshold(inst)

		if effectiveSpeed >= threshold or (attacker ~= nil and effectiveSpeed >= 2.0) then
			local smashTier = getPlayerSmashTier(attacker, attackerVehModel)
			local requiredTier = getPropRequiredTier(inst)
			if smashTier < requiredTier then
				showTierResistanceFeedback(inst, requiredTier)
				return
			end

			local launchVel = if hitVel.Magnitude >= 15
				then hitVel
				else (otherPart.CFrame.LookVector * 38 + Vector3.new(0, 12, 0))
			destroyProp(inst, attacker, launchVel, false)
		end
	end

	local function bindPart(p: BasePart)
		if boundParts[p] then
			return
		end
		boundParts[p] = true
		p.Touched:Connect(onTouched)
	end

	if inst:IsA("BasePart") then
		bindPart(inst)
	elseif inst:IsA("Model") then
		for _, desc in ipairs(inst:GetDescendants()) do
			if desc:IsA("BasePart") then
				bindPart(desc)
			end
		end
		inst.DescendantAdded:Connect(function(desc: Instance)
			if desc:IsA("BasePart") then
				bindPart(desc)
			end
		end)
	end
end

for _, inst in ipairs(CollectionService:GetTagged("Destructible")) do
	bindDestructible(inst)
end
CollectionService:GetInstanceAddedSignal("Destructible"):Connect(bindDestructible)

-- Also ensure any untagged props inside Workspace.LeoCity.DestructibleProps are tagged & bound
task.defer(function()
	local leoCity = Workspace:WaitForChild("LeoCity", 15)
	if not leoCity then
		return
	end
	local propsFolder = leoCity:WaitForChild("DestructibleProps", 10)
	if propsFolder then
		for _, child in ipairs(propsFolder:GetChildren()) do
			if not CollectionService:HasTag(child, "Destructible") then
				CollectionService:AddTag(child, "Destructible")
			end
			bindDestructible(child)
		end
		propsFolder.ChildAdded:Connect(function(child: Instance)
			if not CollectionService:HasTag(child, "Destructible") then
				CollectionService:AddTag(child, "Destructible")
			end
			bindDestructible(child)
		end)
	end
end)

--------------------------------------------------------------------------------
-- CLIENT REPORT DESTRUCTION / SMASH PROP REMOTE LISTENERS
--------------------------------------------------------------------------------
local function getPlayerReferencePositionAndVelocity(player: Player): (Vector3?, Vector3, Model?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	if hum and hum.SeatPart then
		local seatPart = hum.SeatPart
		local vehModel = seatPart:FindFirstAncestorOfClass("Model")
		local chassis = vehModel and (vehModel.PrimaryPart or vehModel:FindFirstChild("Chassis") :: BasePart?)
		if chassis then
			return chassis.Position, chassis.AssemblyLinearVelocity, vehModel
		end
		return seatPart.Position, seatPart.AssemblyLinearVelocity, vehModel
	end

	if hrp then
		return hrp.Position, hrp.AssemblyLinearVelocity, nil
	end
	return nil, Vector3.zero, nil
end

local function handleClientSmashRequest(player: Player, targetArg: any, velocityArg: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if typeof(targetArg) ~= "Instance" then
		return
	end

	local propInst = resolveDestructibleInstance(targetArg)
	if not propInst or propInst:GetAttribute("Destroyed") == true then
		return
	end

	local playerPos, fallbackVel, vehModel = getPlayerReferencePositionAndVelocity(player)
	if not playerPos then
		return
	end

	-- Verify proximity within 45 studs of any part of the destructible prop (or its primary position)
	local withinRange = false
	local propPos = getDestructiblePosition(propInst)
	if propPos then
		local flatDelta = Vector3.new(propPos.X - playerPos.X, 0, propPos.Z - playerPos.Z)
		if (propPos - playerPos).Magnitude <= CLIENT_REPORT_MAX_DIST or flatDelta.Magnitude <= CLIENT_REPORT_MAX_DIST then
			withinRange = true
		end
	end
	if not withinRange and targetArg:IsA("BasePart") then
		if (targetArg.Position - playerPos).Magnitude <= CLIENT_REPORT_MAX_DIST then
			withinRange = true
		end
	end
	if not withinRange then
		return
	end

	local smashTier = getPlayerSmashTier(player, vehModel)
	local requiredTier = getPropRequiredTier(propInst)
	if smashTier < requiredTier then
		showTierResistanceFeedback(propInst, requiredTier)
		return
	end

	local hitVel = if typeof(velocityArg) == "Vector3" then velocityArg else fallbackVel
	if hitVel.Magnitude < 25 then
		local look = if vehModel and vehModel.PrimaryPart
			then vehModel.PrimaryPart.CFrame.LookVector
			elseif propPos then (propPos - playerPos).Unit
			else Vector3.new(0, 0, -1)
		hitVel = look * 42 + Vector3.new(0, 18, 0)
	end

	destroyProp(propInst, player, hitVel, false)
end

ReportDestructionRemote.OnServerEvent:Connect(handleClientSmashRequest)
SmashPropRemote.OnServerEvent:Connect(handleClientSmashRequest)

--------------------------------------------------------------------------------
-- PLAYER SMASH POWER TIER ATTRIBUTE SYNC
--------------------------------------------------------------------------------
local function bindPlayerSmashTierSync(player: Player)
	getPlayerSmashTier(player, nil)
	for _, attr in ipairs({ "EquippedVehicle", "CurrentVehicleType", "Upgrade_Plow", "PlowLevel" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			local _, _, vehModel = getPlayerReferencePositionAndVelocity(player)
			getPlayerSmashTier(player, vehModel)
		end)
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(bindPlayerSmashTierSync, plr)
end
Players.PlayerAdded:Connect(bindPlayerSmashTierSync)

--------------------------------------------------------------------------------
-- SERVER-SIDE VEHICLE PROXIMITY SMASH SWEEP (EVERY 0.06s)
--------------------------------------------------------------------------------
local sweepOverlapParams = OverlapParams.new()
sweepOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

local sweepAccumulator = 0

local function sweepAroundVehicle(vehicleModel: Model, driver: Player?)
	local chassis = vehicleModel.PrimaryPart or vehicleModel:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end

	local smashTier = getPlayerSmashTier(driver, vehicleModel)

	local vel = chassis.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local attrSpeed = if driver then (tonumber(driver:GetAttribute("VehicleSpeed")) or 0) else 0
	local seat = vehicleModel:FindFirstChildWhichIsA("VehicleSeat", true)
	local throttleActive = seat ~= nil and math.abs(seat.ThrottleFloat) > 0.05

	if speed < 2.5 and attrSpeed < 2.5 and not throttleActive then
		return
	end

	local filter: { Instance } = { vehicleModel }
	if driver and driver.Character then
		table.insert(filter, driver.Character)
	end
	sweepOverlapParams.FilterDescendantsInstances = filter

	local boxCF = chassis.CFrame * CFrame.new(0, 0, -1.75)
	local boxSize = chassis.Size + Vector3.new(4.5, 3.0, 6.5)
	local hitParts = Workspace:GetPartBoundsInBox(boxCF, boxSize, sweepOverlapParams)

	local forwardDir = chassis.CFrame.LookVector
	local effectiveSpeed = math.max(speed, attrSpeed, 38)
	local launchVel = forwardDir * effectiveSpeed + Vector3.new(0, 18, 0)

	for _, part in ipairs(hitParts) do
		local propInst = resolveDestructibleInstance(part)
		if propInst and propInst ~= vehicleModel and propInst:GetAttribute("Destroyed") ~= true then
			local requiredTier = getPropRequiredTier(propInst)
			if smashTier >= requiredTier then
				destroyProp(propInst, driver, launchVel, false)
			else
				showTierResistanceFeedback(propInst, requiredTier)
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	sweepAccumulator += dt
	if sweepAccumulator < PROXIMITY_SWEEP_INTERVAL then
		return
	end
	sweepAccumulator = 0

	local sweptVehicles: { [Model]: boolean } = {}

	-- 1. Check all players seated in vehicles (or sprinting on foot into Tier 1 street props)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

		if hum and hum.SeatPart then
			local vehModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
			if vehModel and not sweptVehicles[vehModel] then
				sweptVehicles[vehModel] = true
				sweepAroundVehicle(vehModel, plr)
			end
		elseif hrp and hrp.AssemblyLinearVelocity.Magnitude >= 22 then
			-- High-speed on-foot dash/sprint prop smash (Tier 1 props only)
			sweepOverlapParams.FilterDescendantsInstances = if char then { char } else {}
			local hitParts = Workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(5.5, 6.0, 5.5), sweepOverlapParams)
			for _, part in ipairs(hitParts) do
				local propInst = resolveDestructibleInstance(part)
				if propInst and propInst:GetAttribute("Destroyed") ~= true then
					local requiredTier = getPropRequiredTier(propInst)
					if requiredTier <= 1 then
						destroyProp(propInst, plr, hrp.AssemblyLinearVelocity + Vector3.new(0, 14, 0), false)
					end
				end
			end
		end
	end

	-- 2. Also check any tagged Vehicle with an OwnerUserId or active occupant
	for _, inst in ipairs(CollectionService:GetTagged("Vehicle")) do
		if inst:IsA("Model") and not sweptVehicles[inst] then
			local seat = inst:FindFirstChildWhichIsA("VehicleSeat", true)
			local driver: Player? = nil
			if seat and seat.Occupant and seat.Occupant.Parent then
				driver = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
			end
			if not driver then
				local ownerId = tonumber(inst:GetAttribute("OwnerUserId"))
				if ownerId and ownerId > 0 then
					driver = Players:GetPlayerByUserId(ownerId)
				end
			end
			if driver or (inst.PrimaryPart and inst.PrimaryPart.AssemblyLinearVelocity.Magnitude >= 8) then
				sweptVehicles[inst] = true
				sweepAroundVehicle(inst, driver)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- AUTOMATIC PROP RESPAWNING LOOP (AFTER 45s WHEN PLAYERS ARE FAR AWAY)
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(3.0)
		local now = os.clock()
		for i = #respawnQueue, 1, -1 do
			local entry = respawnQueue[i]
			if now - entry.destroyedAt >= RESPAWN_DELAY then
				local farEnough = true
				for _, plr in ipairs(Players:GetPlayers()) do
					local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and (root.Position - entry.originCF.Position).Magnitude < SAFE_PLAYER_RESPAWN_DIST then
						farEnough = false
						break
					end
				end

				if farEnough then
					table.remove(respawnQueue, i)
					if entry.liveInstance and entry.liveInstance.Parent then
						boundInstances[entry.liveInstance] = nil
						tierBlockedCooldowns[entry.liveInstance] = nil
						entry.liveInstance:Destroy()
					end
					if entry.parent and entry.parent.Parent then
						local restored = entry.template
						if restored:IsA("Model") and restored.PrimaryPart then
							restored:PivotTo(entry.originCF)
						elseif restored:IsA("BasePart") then
							restored.CFrame = entry.originCF
						end
						restored.Parent = entry.parent
						CollectionService:AddTag(restored, "Destructible")
						bindDestructible(restored)
					end
				end
			end
		end
	end
end)

print("[DestructionService] Ready and monitoring destructible city props with 5-Tier Destruction Power System.")
