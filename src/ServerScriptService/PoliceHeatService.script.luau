--!strict
--[[
	PoliceHeatService.script.luau
	World of Destruction (Roblox)
	
	Full 5-Star Wanted Heat & Autonomous Police Pursuit System:
	- Heat builds as the player causes destruction; decays when out of police
	  line-of-sight during the cooldown / evade phase.
	- Spawns autonomous AI Police units scaled by Heat Stars (1 to 5):
	  * Star 1: Patrol Cruiser (flashing red/blue lightbar sirens, pursues player).
	  * Star 2: Multiple Cruisers + aggressive ramming maneuvers.
	  * Star 3: Police SUV Interceptors + Roadblocks deployed ahead of player.
	  * Star 4: Heavy SWAT Enforcer trucks + Spike Strips that slow/pop tires.
	  * Star 5: All units + Helicopter Spotlight tracking from above!
	- Players can smash/wreck police cruisers at speed for huge Chaos & Cash
	  bonuses ("COP TAKEDOWN!") and heat relief.
	- If the player's car is immobilized or boxed in at close range for 4.0
	  seconds, triggers "BUSTED!" (confiscates a small % of unbanked combo cash,
	  resets heat, repairs/respawns player at Police Station or Garage).
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- Constants & 5-Star Heat Configuration
--------------------------------------------------------------------------------
local HEAT_POINTS_PER_STAR = 100
local MAX_HEAT_STARS = 5
local MAX_TOTAL_HEAT = HEAT_POINTS_PER_STAR * MAX_HEAT_STARS -- 500

local LINE_OF_SIGHT_RANGE = 155 -- studs within which police maintain active sight
local EVADE_COOLDOWN_DELAY = 4.0 -- seconds out of sight before heat begins decaying
local HEAT_DECAY_PER_SECOND = 22.0 -- heat points drained per second while evading

local BUSTED_RANGE = 18.0 -- studs proximity for boxing in / arresting player
local BUSTED_MAX_PLAYER_SPEED = 16.0 -- studs/sec considered immobilized / boxed in
local BUSTED_HOLD_DURATION = 4.0 -- 4 seconds immobilized/boxed in -> "BUSTED!"
local BUSTED_DECAY_RATE = 1.6 -- how quickly the busted meter drains when breaking free

local TAKEDOWN_CONTACT_RANGE = 13.5 -- studs proximity for vehicle-vs-cop collision check
local TAKEDOWN_MIN_SPEED = 42.0 -- studs/sec minimum ramming speed to damage police unit
local TAKEDOWN_INSTANT_WRECK_SPEED = 78.0 -- studs/sec instant smash threshold

local ROADBLOCK_COOLDOWN = 16.0 -- seconds between roadblock deployments (Star 3+)
local SPIKESTRIP_COOLDOWN = 14.0 -- seconds between spike strip deployments (Star 4+)

local DEFAULT_POLICE_STATION_CFRAME = CFrame.new(0, 4.5, 0)

export type PoliceUnitKind = "Cruiser" | "InterceptorSUV" | "SWATEnforcer"

type UnitArchetype = {
	Kind: PoliceUnitKind,
	DisplayName: string,
	BodySize: Vector3,
	BodyColor: Color3,
	AccentColor: Color3,
	Speed: number,
	TurnRate: number,
	MaxHP: number,
	TakedownCash: number,
	RamAggression: number,
}

local UNIT_ARCHETYPES: { [PoliceUnitKind]: UnitArchetype } = {
	Cruiser = {
		Kind = "Cruiser",
		DisplayName = "Police Patrol Cruiser",
		BodySize = Vector3.new(6.2, 3.2, 13.5),
		BodyColor = Color3.fromRGB(238, 240, 246),
		AccentColor = Color3.fromRGB(16, 28, 78),
		Speed = 62,
		TurnRate = 2.4,
		MaxHP = 100,
		TakedownCash = 175,
		RamAggression = 1.0,
	},
	InterceptorSUV = {
		Kind = "InterceptorSUV",
		DisplayName = "Police SUV Interceptor",
		BodySize = Vector3.new(6.8, 4.2, 14.8),
		BodyColor = Color3.fromRGB(22, 26, 36),
		AccentColor = Color3.fromRGB(230, 235, 245),
		Speed = 70,
		TurnRate = 2.6,
		MaxHP = 150,
		TakedownCash = 260,
		RamAggression = 1.35,
	},
	SWATEnforcer = {
		Kind = "SWATEnforcer",
		DisplayName = "Heavy SWAT Enforcer",
		BodySize = Vector3.new(8.2, 5.8, 18.5),
		BodyColor = Color3.fromRGB(28, 36, 52),
		AccentColor = Color3.fromRGB(12, 16, 24),
		Speed = 56,
		TurnRate = 1.85,
		MaxHP = 260,
		TakedownCash = 400,
		RamAggression = 1.75,
	},
}

-- Star-by-Star Force Roster
local STAR_ROSTER: { [number]: { Units: { PoliceUnitKind }, EnableRoadblocks: boolean, EnableSpikeStrips: boolean, EnableHelicopter: boolean } } = {
	[1] = {
		Units = { "Cruiser" },
		EnableRoadblocks = false,
		EnableSpikeStrips = false,
		EnableHelicopter = false,
	},
	[2] = {
		Units = { "Cruiser", "Cruiser", "Cruiser" },
		EnableRoadblocks = false,
		EnableSpikeStrips = false,
		EnableHelicopter = false,
	},
	[3] = {
		Units = { "Cruiser", "Cruiser", "InterceptorSUV", "InterceptorSUV" },
		EnableRoadblocks = true,
		EnableSpikeStrips = false,
		EnableHelicopter = false,
	},
	[4] = {
		Units = { "Cruiser", "InterceptorSUV", "InterceptorSUV", "SWATEnforcer", "SWATEnforcer" },
		EnableRoadblocks = true,
		EnableSpikeStrips = true,
		EnableHelicopter = false,
	},
	[5] = {
		Units = { "Cruiser", "InterceptorSUV", "InterceptorSUV", "SWATEnforcer", "SWATEnforcer" },
		EnableRoadblocks = true,
		EnableSpikeStrips = true,
		EnableHelicopter = true,
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
local policeWorldFolder = ensureFolder(Workspace, "PoliceUnits")

-- ServerStorage Bindables
local AddHeatBindable = ensureBindableEvent(ServerStorage, "AddHeatEvent")
local PoliceTakedownBindable = ensureBindableEvent(ServerStorage, "PoliceTakedownEvent")
local PlayerBustedBindable = ensureBindableEvent(ServerStorage, "PlayerBustedEvent")
local AddCashBindable = ensureBindableEvent(ServerStorage, "AddCashEvent")
local VehicleRepairedBindable = ensureBindableEvent(ServerStorage, "VehicleRepairedEvent")

local FolderAddHeatBindable = ensureBindableEvent(serverEventsFolder, "AddHeatEvent")
local FolderPoliceTakedownBindable = ensureBindableEvent(serverEventsFolder, "PoliceTakedownEvent")
local FolderPlayerBustedBindable = ensureBindableEvent(serverEventsFolder, "PlayerBustedEvent")

-- ReplicatedStorage Remotes
local PoliceAlertRemote = ensureRemoteEvent(remotesFolder, "PoliceAlert")
local HeatUpdateRemote = ensureRemoteEvent(remotesFolder, "HeatUpdate")
local PlayerBustedRemote = ensureRemoteEvent(remotesFolder, "PlayerBusted")
local ReportCopImpactRemote = ensureRemoteEvent(remotesFolder, "ReportCopImpact")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")

local RootPoliceAlertRemote = ensureRemoteEvent(ReplicatedStorage, "PoliceAlertEvent")
local RootPlayerBustedRemote = ensureRemoteEvent(ReplicatedStorage, "PlayerBustedEvent")
local RootReportCopImpactRemote = ensureRemoteEvent(ReplicatedStorage, "PoliceTakedown")

--------------------------------------------------------------------------------
-- Active Pursuit Data Structures
--------------------------------------------------------------------------------
type ActiveCopUnit = {
	Id: string,
	Kind: PoliceUnitKind,
	Archetype: UnitArchetype,
	Model: Model,
	Chassis: Part,
	RedSiren: Part,
	BlueSiren: Part,
	RedLight: PointLight,
	BlueLight: PointLight,
	Heading: number,
	HP: number,
	StunTimer: number,
	RamPhase: number,
	SlotIndex: number,
}

type ActiveRoadblock = {
	Model: Model,
	SpawnedAt: number,
}

type ActiveSpikeStrip = {
	Model: Model,
	TriggerPart: Part,
	Triggered: boolean,
	SpawnedAt: number,
}

type ActiveHelicopter = {
	Model: Model,
	Hull: Part,
	Rotor: Part,
	SearchlightBeam: Beam?,
	SpotLight: SpotLight,
	GroundSpot: Part,
	OrbitAngle: number,
}

type PlayerHeatState = {
	TotalHeat: number, -- 0..500
	HeatStars: number, -- 0..5
	HeatProgress: number, -- 0..100 within current star
	LastCrimeAt: number,
	LastSeenByPoliceAt: number,
	InLineOfSight: boolean,
	BustedTimer: number, -- 0..4.0 seconds
	ReachedFiveStarBanner: boolean,
	Units: { ActiveCopUnit },
	Roadblocks: { ActiveRoadblock },
	SpikeStrips: { ActiveSpikeStrip },
	Helicopter: ActiveHelicopter?,
	LastRoadblockAt: number,
	LastSpikeStripAt: number,
	LastImpactReportAt: number,
}

local playerHeatStates: { [number]: PlayerHeatState } = {}

--------------------------------------------------------------------------------
-- Player & Vehicle Pose / Velocity Helpers
--------------------------------------------------------------------------------
local function getPlayerVehicleOrRoot(player: Player): (BasePart?, Model?)
	local vehiclesFolder = Workspace:FindFirstChild("PlayerVehicles") or Workspace:FindFirstChild("Vehicles")
	if vehiclesFolder then
		local vModel = vehiclesFolder:FindFirstChild(player.Name .. "_Vehicle")
			or vehiclesFolder:FindFirstChild(player.Name)
			or vehiclesFolder:FindFirstChild("PlayerCar_" .. tostring(player.UserId))
		if vModel and vModel:IsA("Model") then
			local primary = vModel.PrimaryPart or vModel:FindFirstChildWhichIsA("BasePart")
			if primary then
				return primary, vModel
			end
		end
	end

	local character = player.Character
	if character then
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			local seatModel = hum.SeatPart:FindFirstAncestorOfClass("Model")
			return hum.SeatPart, seatModel
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp, character
		end
	end
	return nil, nil
end

local function getPlayerMotion(player: Player): (Vector3, Vector3, number, Vector3)
	local rootPart, model = getPlayerVehicleOrRoot(player)
	if not rootPart then
		return Vector3.new(0, 3, 0), Vector3.new(0, 0, -1), 0, Vector3.zero
	end

	local pos = rootPart.Position
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
	else
		flatLook = Vector3.new(0, 0, -1)
	end

	local vel = rootPart.AssemblyLinearVelocity
	local speed = vel.Magnitude

	-- Also support kinematic vehicle controllers that store speed as an attribute
	local attrSpeed = tonumber(
		rootPart:GetAttribute("CurrentSpeed")
		or (if model then model:GetAttribute("CurrentSpeed") or model:GetAttribute("Speed") else nil)
		or player:GetAttribute("VehicleSpeed")
	)
	if attrSpeed and math.abs(attrSpeed) > speed then
		speed = math.abs(attrSpeed)
		vel = flatLook * attrSpeed
	end

	return pos, flatLook, speed, vel
end

--------------------------------------------------------------------------------
-- Model Builders: Police Cruisers, SUV Interceptors, SWAT Trucks, Roadblocks,
-- Spike Strips & Star-5 Police Helicopter with Spotlight!
--------------------------------------------------------------------------------
local unitSerial = 0

local function buildPoliceVehicle(kind: PoliceUnitKind, spawnPos: Vector3, heading: number, slotIndex: number): ActiveCopUnit
	unitSerial += 1
	local arch = UNIT_ARCHETYPES[kind]
	local model = Instance.new("Model")
	model.Name = string.format("Police_%s_%d", kind, unitSerial)
	model:SetAttribute("IsPoliceUnit", true)
	model:SetAttribute("PoliceUnitKind", kind)
	model:SetAttribute("MaxHP", arch.MaxHP)
	model:SetAttribute("HP", arch.MaxHP)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = arch.BodySize
	chassis.Color = arch.BodyColor
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = true
	chassis.CanCollide = true
	chassis.CFrame = CFrame.new(spawnPos) * CFrame.Angles(0, heading, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- Side Police Livery Stripe / Cabin
	local cabin = Instance.new("Part")
	cabin.Name = "Cabin"
	cabin.Size = Vector3.new(arch.BodySize.X * 0.86, arch.BodySize.Y * 0.65, arch.BodySize.Z * 0.52)
	cabin.Color = arch.AccentColor
	cabin.Material = Enum.Material.SmoothPlastic
	cabin.Anchored = true
	cabin.CanCollide = false
	cabin.CFrame = chassis.CFrame * CFrame.new(0, arch.BodySize.Y * 0.62, 0.4)
	cabin.Parent = model

	-- Front Push-Bumper / Bullbar
	local bumper = Instance.new("Part")
	bumper.Name = "PushBumper"
	bumper.Size = Vector3.new(arch.BodySize.X * 0.92, arch.BodySize.Y * 0.45, 0.8)
	bumper.Color = Color3.fromRGB(20, 22, 26)
	bumper.Material = Enum.Material.Metal
	bumper.Anchored = true
	bumper.CanCollide = false
	bumper.CFrame = chassis.CFrame * CFrame.new(0, -arch.BodySize.Y * 0.15, -arch.BodySize.Z * 0.5 - 0.35)
	bumper.Parent = model

	-- Roof Siren Lightbar (Red + Blue)
	local barY = arch.BodySize.Y * 0.98
	local redSiren = Instance.new("Part")
	redSiren.Name = "SirenRed"
	redSiren.Size = Vector3.new(arch.BodySize.X * 0.36, 0.45, 0.9)
	redSiren.Color = Color3.fromRGB(255, 35, 35)
	redSiren.Material = Enum.Material.Neon
	redSiren.Anchored = true
	redSiren.CanCollide = false
	redSiren.CFrame = chassis.CFrame * CFrame.new(-arch.BodySize.X * 0.2, barY, 0)
	redSiren.Parent = model

	local redLight = Instance.new("PointLight")
	redLight.Color = Color3.fromRGB(255, 40, 40)
	redLight.Range = 28
	redLight.Brightness = 3.5
	redLight.Parent = redSiren

	local blueSiren = Instance.new("Part")
	blueSiren.Name = "SirenBlue"
	blueSiren.Size = Vector3.new(arch.BodySize.X * 0.36, 0.45, 0.9)
	blueSiren.Color = Color3.fromRGB(35, 110, 255)
	blueSiren.Material = Enum.Material.Neon
	blueSiren.Anchored = true
	blueSiren.CanCollide = false
	blueSiren.CFrame = chassis.CFrame * CFrame.new(arch.BodySize.X * 0.2, barY, 0)
	blueSiren.Parent = model

	local blueLight = Instance.new("PointLight")
	blueLight.Color = Color3.fromRGB(40, 120, 255)
	blueLight.Range = 28
	blueLight.Brightness = 0.5
	blueLight.Parent = blueSiren

	CollectionService:AddTag(model, "PoliceUnit")
	model.Parent = policeWorldFolder

	return {
		Id = model.Name,
		Kind = kind,
		Archetype = arch,
		Model = model,
		Chassis = chassis,
		RedSiren = redSiren,
		BlueSiren = blueSiren,
		RedLight = redLight,
		BlueLight = blueLight,
		Heading = heading,
		HP = arch.MaxHP,
		StunTimer = 0,
		RamPhase = math.random() * math.pi * 2,
		SlotIndex = slotIndex,
	}
end

local function updateCopModelTransform(unit: ActiveCopUnit, pos: Vector3, heading: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, heading, 0)
	unit.Chassis.CFrame = cf
	local arch = unit.Archetype
	local cabin = unit.Model:FindFirstChild("Cabin") :: BasePart?
	if cabin then
		cabin.CFrame = cf * CFrame.new(0, arch.BodySize.Y * 0.62, 0.4)
	end
	local bumper = unit.Model:FindFirstChild("PushBumper") :: BasePart?
	if bumper then
		bumper.CFrame = cf * CFrame.new(0, -arch.BodySize.Y * 0.15, -arch.BodySize.Z * 0.5 - 0.35)
	end
	local barY = arch.BodySize.Y * 0.98
	unit.RedSiren.CFrame = cf * CFrame.new(-arch.BodySize.X * 0.2, barY, 0)
	unit.BlueSiren.CFrame = cf * CFrame.new(arch.BodySize.X * 0.2, barY, 0)
end

local function spawnDebrisBurst(position: Vector3, tint: Color3)
	for i = 1, 7 do
		local chunk = Instance.new("Part")
		chunk.Name = "CopDebris"
		chunk.Size = Vector3.new(1.2 + math.random(), 0.8 + math.random(), 1.4 + math.random())
		chunk.Color = if i % 2 == 0 then tint else Color3.fromRGB(45, 50, 60)
		chunk.Material = Enum.Material.Metal
		chunk.Position = position + Vector3.new(math.random(-3, 3), 2 + math.random() * 2, math.random(-3, 3))
		chunk.Anchored = false
		chunk.CanCollide = false
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-38, 38), math.random(24, 52), math.random(-38, 38))
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		chunk.Parent = policeWorldFolder
		Debris:AddItem(chunk, 2.2)
	end
end

local function deployRoadblockAhead(playerPos: Vector3, playerForward: Vector3): ActiveRoadblock
	local centerPos = Vector3.new(playerPos.X, 2.0, playerPos.Z) + playerForward * 115
	local facingCF = CFrame.lookAt(centerPos, centerPos - playerForward)
	local rightVec = facingCF.RightVector

	local rbModel = Instance.new("Model")
	rbModel.Name = "PoliceRoadblock"
	rbModel:SetAttribute("IsPoliceRoadblock", true)
	rbModel:SetAttribute("DestructibleType", "PoliceRoadblock")
	rbModel:SetAttribute("CashReward", 120)

	-- Two angled Interceptor barriers + concrete sawhorses in the gap
	for _, offset in ipairs({ -11, 11 }) do
		local cruiserBarrier = Instance.new("Part")
		cruiserBarrier.Name = "RoadblockInterceptor"
		cruiserBarrier.Size = Vector3.new(6.5, 3.8, 14.0)
		cruiserBarrier.Color = Color3.fromRGB(25, 30, 44)
		cruiserBarrier.Material = Enum.Material.Metal
		cruiserBarrier.Anchored = true
		cruiserBarrier.CanCollide = true
		cruiserBarrier.CFrame = CFrame.new(centerPos + rightVec * offset)
			* CFrame.Angles(0, math.rad(if offset < 0 then 72 else -72), 0)
		cruiserBarrier.Parent = rbModel
	end

	for _, barricadeOffset in ipairs({ -3.5, 3.5 }) do
		local barrier = Instance.new("Part")
		barrier.Name = "PoliceBarricade"
		barrier.Size = Vector3.new(5.5, 3.0, 1.8)
		barrier.Color = Color3.fromRGB(255, 140, 20)
		barrier.Material = Enum.Material.Neon
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.CFrame = facingCF * CFrame.new(barricadeOffset, -0.3, 0)
		barrier.Parent = rbModel
	end

	rbModel.Parent = policeWorldFolder
	return {
		Model = rbModel,
		SpawnedAt = os.clock(),
	}
end

local function deploySpikeStripAhead(targetPlayer: Player, playerPos: Vector3, playerForward: Vector3): ActiveSpikeStrip
	local stripPos = Vector3.new(playerPos.X, 0.35, playerPos.Z) + playerForward * 92
	local stripCF = CFrame.lookAt(stripPos, stripPos + playerForward)

	local stripModel = Instance.new("Model")
	stripModel.Name = "PoliceSpikeStrip"
	stripModel:SetAttribute("IsSpikeStrip", true)

	local basePart = Instance.new("Part")
	basePart.Name = "SpikeStripBar"
	basePart.Size = Vector3.new(22, 0.45, 2.2)
	basePart.Color = Color3.fromRGB(250, 200, 30)
	basePart.Material = Enum.Material.Metal
	basePart.Anchored = true
	basePart.CanCollide = false
	basePart.CFrame = stripCF
	basePart.Parent = stripModel
	stripModel.PrimaryPart = basePart

	local stateRecord: ActiveSpikeStrip = {
		Model = stripModel,
		TriggerPart = basePart,
		Triggered = false,
		SpawnedAt = os.clock(),
	}

	basePart.Touched:Connect(function(hit: BasePart)
		if stateRecord.Triggered then
			return
		end
		local rootPart, vehicleModel = getPlayerVehicleOrRoot(targetPlayer)
		if not rootPart then
			return
		end
		if hit == rootPart or (vehicleModel and hit:IsDescendantOf(vehicleModel)) or (targetPlayer.Character and hit:IsDescendantOf(targetPlayer.Character)) then
			stateRecord.Triggered = true
			targetPlayer:SetAttribute("TiresPopped", true)
			targetPlayer:SetAttribute("SpikeStripSlowUntil", os.clock() + 4.5)

			if vehicleModel then
				vehicleModel:SetAttribute("TiresPopped", true)
				local seat = vehicleModel:FindFirstChildOfClass("VehicleSeat")
				if seat then
					local originalSpeed = seat.MaxSpeed
					seat.MaxSpeed = math.max(24, originalSpeed * 0.45)
					task.delay(4.5, function()
						if seat.Parent then
							seat.MaxSpeed = originalSpeed
						end
						if vehicleModel.Parent then
							vehicleModel:SetAttribute("TiresPopped", false)
						end
						if targetPlayer.Parent then
							targetPlayer:SetAttribute("TiresPopped", false)
						end
					end)
				end
			end

			StyleCalloutRemote:FireClient(targetPlayer, {
				Callout = "SPIKE STRIP HIT! TIRES DAMAGED!",
				Multiplier = tonumber(targetPlayer:GetAttribute("ComboMultiplier")) or 1,
				ComboCount = tonumber(targetPlayer:GetAttribute("ComboCount")) or 0,
				CashAwarded = 0,
			})
		end
	end)

	stripModel.Parent = policeWorldFolder
	return stateRecord
end

local function spawnPoliceHelicopter(playerPos: Vector3): ActiveHelicopter
	local heliModel = Instance.new("Model")
	heliModel.Name = "PoliceChopper_Star5"
	heliModel:SetAttribute("IsPoliceHelicopter", true)

	local hull = Instance.new("Part")
	hull.Name = "HeliHull"
	hull.Size = Vector3.new(7.5, 5.2, 18.0)
	hull.Color = Color3.fromRGB(18, 26, 48)
	hull.Material = Enum.Material.Metal
	hull.Anchored = true
	hull.CanCollide = false
	hull.Position = playerPos + Vector3.new(0, 82, 0)
	hull.Parent = heliModel
	heliModel.PrimaryPart = hull

	local rotor = Instance.new("Part")
	rotor.Name = "MainRotor"
	rotor.Size = Vector3.new(26.0, 0.25, 1.8)
	rotor.Color = Color3.fromRGB(220, 225, 235)
	rotor.Material = Enum.Material.Metal
	rotor.Anchored = true
	rotor.CanCollide = false
	rotor.Position = hull.Position + Vector3.new(0, 3.1, 0)
	rotor.Parent = heliModel

	local spotLight = Instance.new("SpotLight")
	spotLight.Name = "ChopperSearchlight"
	spotLight.Face = Enum.NormalId.Bottom
	spotLight.Angle = 45
	spotLight.Brightness = 6.0
	spotLight.Range = 120
	spotLight.Color = Color3.fromRGB(255, 250, 215)
	spotLight.Parent = hull

	local groundSpot = Instance.new("Part")
	groundSpot.Name = "SearchlightPool"
	groundSpot.Shape = Enum.PartType.Cylinder
	groundSpot.Size = Vector3.new(0.3, 28, 28)
	groundSpot.Color = Color3.fromRGB(255, 250, 200)
	groundSpot.Material = Enum.Material.Neon
	groundSpot.Transparency = 0.68
	groundSpot.Anchored = true
	groundSpot.CanCollide = false
	groundSpot.CFrame = CFrame.new(playerPos.X, 0.3, playerPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	groundSpot.Parent = heliModel

	-- Visible Volumetric Spotlight Beam from Helicopter to Ground Pool
	local attachTop = Instance.new("Attachment")
	attachTop.Name = "BeamTop"
	attachTop.Position = Vector3.new(0, -2.4, -3.0)
	attachTop.Parent = hull

	local attachBottom = Instance.new("Attachment")
	attachBottom.Name = "BeamBottom"
	attachBottom.Parent = groundSpot

	local beam = Instance.new("Beam")
	beam.Name = "SpotlightBeam"
	beam.Attachment0 = attachTop
	beam.Attachment1 = attachBottom
	beam.Width0 = 2.2
	beam.Width1 = 22.0
	beam.FaceCamera = true
	beam.LightEmission = 1.0
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 252, 215))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0.88),
	})
	beam.Parent = hull

	heliModel.Parent = policeWorldFolder

	return {
		Model = heliModel,
		Hull = hull,
		Rotor = rotor,
		SearchlightBeam = beam,
		SpotLight = spotLight,
		GroundSpot = groundSpot,
		OrbitAngle = 0,
	}
end

--------------------------------------------------------------------------------
-- State Synchronization & Force Spawning
--------------------------------------------------------------------------------
local function syncHeatAttributes(player: Player, state: PlayerHeatState)
	local stars = 0
	if state.TotalHeat > 0 then
		stars = math.clamp(math.ceil(state.TotalHeat / HEAT_POINTS_PER_STAR), 1, MAX_HEAT_STARS)
	end
	state.HeatStars = stars

	local progressInStar = 0
	if stars > 0 then
		local starFloor = (stars - 1) * HEAT_POINTS_PER_STAR
		progressInStar = math.clamp(((state.TotalHeat - starFloor) / HEAT_POINTS_PER_STAR) * 100, 0, 100)
	end
	state.HeatProgress = math.floor(progressInStar + 0.5)

	local bustedRatio = math.clamp(state.BustedTimer / BUSTED_HOLD_DURATION, 0, 1)
	local isEvading = stars > 0 and not state.InLineOfSight and (os.clock() - state.LastSeenByPoliceAt >= EVADE_COOLDOWN_DELAY)

	player:SetAttribute("HeatStars", stars)
	player:SetAttribute("HeatProgress", state.HeatProgress)
	player:SetAttribute("HeatProgressNormalized", tonumber(string.format("%.3f", state.HeatProgress / 100)))
	player:SetAttribute("PoliceInSight", state.InLineOfSight)
	player:SetAttribute("PoliceEvading", isEvading)
	player:SetAttribute("BustedProgress", tonumber(string.format("%.3f", bustedRatio)))

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local heatVal = ls:FindFirstChild("HeatLevel") :: IntValue?
		if heatVal and heatVal.Value ~= stars then
			heatVal.Value = stars
		end
	end
end

local function clearAllPursuitAssets(state: PlayerHeatState)
	for _, unit in ipairs(state.Units) do
		if unit.Model and unit.Model.Parent then
			unit.Model:Destroy()
		end
	end
	table.clear(state.Units)

	for _, rb in ipairs(state.Roadblocks) do
		if rb.Model and rb.Model.Parent then
			rb.Model:Destroy()
		end
	end
	table.clear(state.Roadblocks)

	for _, ss in ipairs(state.SpikeStrips) do
		if ss.Model and ss.Model.Parent then
			ss.Model:Destroy()
		end
	end
	table.clear(state.SpikeStrips)

	if state.Helicopter then
		if state.Helicopter.Model and state.Helicopter.Model.Parent then
			state.Helicopter.Model:Destroy()
		end
		state.Helicopter = nil
	end
end

local function reconcilePoliceForceForStars(player: Player, state: PlayerHeatState)
	local stars = state.HeatStars
	if stars <= 0 then
		clearAllPursuitAssets(state)
		return
	end

	local roster = STAR_ROSTER[stars]
	if not roster then
		return
	end

	local playerPos, _playerFwd = getPlayerMotion(player)

	-- Count currently active units by kind
	local desiredCounts: { [PoliceUnitKind]: number } = {
		Cruiser = 0,
		InterceptorSUV = 0,
		SWATEnforcer = 0,
	}
	for _, kind in ipairs(roster.Units) do
		desiredCounts[kind] = (desiredCounts[kind] or 0) + 1
	end

	local currentCounts: { [PoliceUnitKind]: number } = {
		Cruiser = 0,
		InterceptorSUV = 0,
		SWATEnforcer = 0,
	}
	for _, u in ipairs(state.Units) do
		currentCounts[u.Kind] = (currentCounts[u.Kind] or 0) + 1
	end

	-- Spawn missing units in a wide perimeter ring (85..125 studs out)
	for _, kind in ipairs({ "Cruiser", "InterceptorSUV", "SWATEnforcer" } :: { PoliceUnitKind }) do
		local needed = (desiredCounts[kind] or 0) - (currentCounts[kind] or 0)
		for _ = 1, needed do
			local angle = math.random() * math.pi * 2
			local dist = math.random(85, 125)
			local spawnPos = Vector3.new(
				playerPos.X + math.cos(angle) * dist,
				UNIT_ARCHETYPES[kind].BodySize.Y * 0.5 + 0.5,
				playerPos.Z + math.sin(angle) * dist
			)
			local slotIndex = #state.Units + 1
			local newUnit = buildPoliceVehicle(kind, spawnPos, angle + math.pi, slotIndex)
			table.insert(state.Units, newUnit)
		end
	end

	-- Star 5 Helicopter Spotlight from above!
	if roster.EnableHelicopter and not state.Helicopter then
		state.Helicopter = spawnPoliceHelicopter(playerPos)
		PoliceAlertRemote:FireClient(player, {
			HeatStars = 5,
			Headline = "5-STAR MAXIMUM HEAT! POLICE CHOPPER INBOUND!",
			UnitType = "Helicopter",
		})
	elseif not roster.EnableHelicopter and state.Helicopter then
		if state.Helicopter.Model and state.Helicopter.Model.Parent then
			state.Helicopter.Model:Destroy()
		end
		state.Helicopter = nil
	end
end

--------------------------------------------------------------------------------
-- Cop Takedowns & "BUSTED!" Sequence
--------------------------------------------------------------------------------
local function destroyPoliceUnit(player: Player, state: PlayerHeatState, unitIndex: number)
	local unit = state.Units[unitIndex]
	if not unit then
		return
	end

	local crashPos = unit.Chassis.Position
	local kindName = unit.Archetype.DisplayName
	local takedownBonus = unit.Archetype.TakedownCash

	spawnDebrisBurst(crashPos, unit.Archetype.BodyColor)
	if unit.Model and unit.Model.Parent then
		unit.Model:Destroy()
	end
	table.remove(state.Units, unitIndex)

	-- Grant slight heat relief when wrecking a pursuer, while firing COP TAKEDOWN!
	state.TotalHeat = math.max(40, state.TotalHeat - 30)
	syncHeatAttributes(player, state)

	PoliceTakedownBindable:Fire(player, kindName, crashPos, takedownBonus)
	FolderPoliceTakedownBindable:Fire(player, kindName, crashPos, takedownBonus)
end

local function findRespawnLocation(player: Player): (CFrame, string)
	-- Check for a Police Station or Garage spawn point in Workspace
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local lower = string.lower(desc.Name)
			if string.find(lower, "policestation") or string.find(lower, "precinct") then
				return desc.CFrame + Vector3.new(0, 4.5, 0), "Police Station Precinct"
			end
		end
	end

	local lastMechanicCF = player:GetAttribute("LastMechanicRespawnCFrame")
	if typeof(lastMechanicCF) == "CFrame" then
		return lastMechanicCF, "Mechanic Garage"
	end

	local spotsFolder = Workspace:FindFirstChild("GarageSpots")
	if spotsFolder then
		local firstSpot = spotsFolder:FindFirstChildWhichIsA("BasePart")
		if firstSpot then
			return firstSpot.CFrame + Vector3.new(0, 4.5, 0), firstSpot.Name
		end
	end

	local spawnLoc = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLoc then
		return spawnLoc.CFrame + Vector3.new(0, 4.5, 0), "Central Police Station"
	end

	return DEFAULT_POLICE_STATION_CFRAME, "Central Police Station"
end

local function triggerPlayerBusted(player: Player, state: PlayerHeatState)
	player:SetAttribute("IsBusted", true)

	local unbankedCombo = math.max(0, math.floor(tonumber(player:GetAttribute("UnbankedComboCash")) or 0))
	local currentCash = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0))
	local confiscated = if unbankedCombo > 0
		then math.max(10, math.floor(unbankedCombo * 0.30))
		else math.min(150, math.floor(currentCash * 0.08))

	local respawnCF, locationName = findRespawnLocation(player)

	-- Reset heat and clear all police units
	state.TotalHeat = 0
	state.HeatStars = 0
	state.HeatProgress = 0
	state.BustedTimer = 0
	state.InLineOfSight = false
	state.ReachedFiveStarBanner = false
	clearAllPursuitAssets(state)
	syncHeatAttributes(player, state)

	-- Notify ChaosAndEconomyService to confiscate unbanked combo % & reset combo
	PlayerBustedBindable:Fire(player, confiscated, respawnCF)
	FolderPlayerBustedBindable:Fire(player, confiscated, respawnCF)

	-- Repair & teleport player vehicle or character to Police Station / Garage
	local maxHealth = tonumber(player:GetAttribute("VehicleMaxHealth")) or 100
	player:SetAttribute("VehicleHealth", maxHealth)
	player:SetAttribute("TiresPopped", false)

	local rootPart, vehicleModel = getPlayerVehicleOrRoot(player)
	if vehicleModel and vehicleModel:IsA("Model") then
		vehicleModel:SetAttribute("Health", maxHealth)
		vehicleModel:SetAttribute("Damage", 0)
		vehicleModel:PivotTo(respawnCF)
		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	elseif rootPart then
		rootPart.CFrame = respawnCF
		rootPart.AssemblyLinearVelocity = Vector3.zero
	end

	VehicleRepairedBindable:Fire(player, locationName, 0)

	local bustPayload = {
		Banner = "BUSTED!",
		ConfiscatedCash = confiscated,
		RespawnLocation = locationName,
	}
	PlayerBustedRemote:FireClient(player, bustPayload)
	RootPlayerBustedRemote:FireClient(player, bustPayload)
	StyleCalloutRemote:FireClient(player, {
		Callout = if confiscated > 0 then string.format("BUSTED! -$%d", confiscated) else "BUSTED!",
		Multiplier = 1,
		ComboCount = 0,
		CashAwarded = 0,
	})

	task.delay(2.0, function()
		if player.Parent then
			player:SetAttribute("IsBusted", false)
		end
	end)
end

--------------------------------------------------------------------------------
-- Heat Escalation Listener
--------------------------------------------------------------------------------
local function addHeatToPlayer(player: Player, heatDelta: number, _reason: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if player:GetAttribute("IsBusted") == true then
		return
	end

	local state = playerHeatStates[player.UserId]
	if not state then
		return
	end

	local delta = math.max(1, tonumber(heatDelta) or 10)
	local prevStars = state.HeatStars
	local now = os.clock()

	state.TotalHeat = math.clamp(state.TotalHeat + delta, 0, MAX_TOTAL_HEAT)
	state.LastCrimeAt = now
	state.LastSeenByPoliceAt = now
	state.InLineOfSight = true

	syncHeatAttributes(player, state)

	if state.HeatStars > prevStars then
		reconcilePoliceForceForStars(player, state)

		local starMessages = {
			[1] = "1-STAR HEAT: PATROL CRUISER DISPATCHED!",
			[2] = "2-STAR HEAT: AGGRESSIVE CRUISER SQUAD INBOUND!",
			[3] = "3-STAR HEAT: SUV INTERCEPTORS & ROADBLOCKS ACTIVE!",
			[4] = "4-STAR HEAT: HEAVY SWAT ENFORCERS & SPIKE STRIPS!",
			[5] = "5-STAR MAXIMUM WANTED: ALL UNITS + HELICOPTER SPOTLIGHT!",
		}
		local alertMsg = starMessages[state.HeatStars] or "WANTED LEVEL INCREASED!"
		PoliceAlertRemote:FireClient(player, {
			HeatStars = state.HeatStars,
			HeatProgress = state.HeatProgress,
			Headline = alertMsg,
		})
		RootPoliceAlertRemote:FireClient(player, {
			HeatStars = state.HeatStars,
			HeatProgress = state.HeatProgress,
			Headline = alertMsg,
		})
	end
end

AddHeatBindable.Event:Connect(addHeatToPlayer)
FolderAddHeatBindable.Event:Connect(addHeatToPlayer)

-- Client Remote for reporting high-speed police impacts
local function onClientReportCopImpact(player: Player, targetUnitOrId: any, impactSpeed: any)
	local state = playerHeatStates[player.UserId]
	if not state or #state.Units == 0 then
		return
	end
	local now = os.clock()
	if now - state.LastImpactReportAt < 0.15 then
		return
	end
	state.LastImpactReportAt = now

	local playerPos, _playerFwd, measuredSpeed = getPlayerMotion(player)
	local plowMult = tonumber(player:GetAttribute("RammingForceMultiplier")) or 1.0
	local effSpeed = math.max(measuredSpeed, math.min(130, tonumber(impactSpeed) or 0)) * plowMult

	for i, u in ipairs(state.Units) do
		local matches = (u.Model == targetUnitOrId) or (u.Id == targetUnitOrId)
		local dist = (u.Chassis.Position - playerPos).Magnitude
		if (matches or dist <= TAKEDOWN_CONTACT_RANGE * 1.45) and dist <= 26 then
			if effSpeed >= TAKEDOWN_INSTANT_WRECK_SPEED then
				destroyPoliceUnit(player, state, i)
			elseif effSpeed >= TAKEDOWN_MIN_SPEED * 0.75 then
				u.HP -= 55 * plowMult
				u.StunTimer = 1.8
				if u.HP <= 0 then
					destroyPoliceUnit(player, state, i)
				end
			end
			break
		end
	end
end

ReportCopImpactRemote.OnServerEvent:Connect(onClientReportCopImpact)
RootReportCopImpactRemote.OnServerEvent:Connect(onClientReportCopImpact)

--------------------------------------------------------------------------------
-- Player Lifecycle
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	playerHeatStates[player.UserId] = {
		TotalHeat = 0,
		HeatStars = 0,
		HeatProgress = 0,
		LastCrimeAt = 0,
		LastSeenByPoliceAt = 0,
		InLineOfSight = false,
		BustedTimer = 0,
		ReachedFiveStarBanner = false,
		Units = {},
		Roadblocks = {},
		SpikeStrips = {},
		Helicopter = nil,
		LastRoadblockAt = 0,
		LastSpikeStripAt = 0,
		LastImpactReportAt = 0,
	}
	player:SetAttribute("HeatStars", 0)
	player:SetAttribute("HeatProgress", 0)
	player:SetAttribute("PoliceInSight", false)
	player:SetAttribute("PoliceEvading", false)
	player:SetAttribute("BustedProgress", 0)
	player:SetAttribute("IsBusted", false)
end

local function onPlayerRemoving(player: Player)
	local state = playerHeatStates[player.UserId]
	if state then
		clearAllPursuitAssets(state)
		playerHeatStates[player.UserId] = nil
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

--------------------------------------------------------------------------------
-- Autonomous AI Pursuit, Tactical Deployments, Siren Strobe & Busted Loop
--------------------------------------------------------------------------------
local sirenClock = 0
local sirenPhaseOn = true

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()

	-- Toggle red/blue lightbars ~6 times a second
	sirenClock += dt
	local toggledSiren = false
	if sirenClock >= 0.16 then
		sirenClock = 0
		sirenPhaseOn = not sirenPhaseOn
		toggledSiren = true
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerHeatStates[player.UserId]
		if not state or state.HeatStars <= 0 then
			continue
		end

		local stars = state.HeatStars
		local roster = STAR_ROSTER[stars]
		local playerPos, playerFwd, playerSpeed, _playerVel = getPlayerMotion(player)
		local playerRight = Vector3.new(-playerFwd.Z, 0, playerFwd.X)
		local plowMult = tonumber(player:GetAttribute("RammingForceMultiplier")) or 1.0

		-- Ensure unit count stays topped up during active chase
		if #state.Units < #roster.Units then
			reconcilePoliceForceForStars(player, state)
		end

		-- Deploy Star 3+ Roadblocks ahead of fast-moving player
		if roster.EnableRoadblocks and playerSpeed > 28 and (now - state.LastRoadblockAt >= ROADBLOCK_COOLDOWN) then
			state.LastRoadblockAt = now
			if #state.Roadblocks >= 2 then
				local oldest = table.remove(state.Roadblocks, 1)
				if oldest and oldest.Model and oldest.Model.Parent then
					oldest.Model:Destroy()
				end
			end
			table.insert(state.Roadblocks, deployRoadblockAhead(playerPos, playerFwd))
		end

		-- Deploy Star 4+ Spike Strips ahead of player
		if roster.EnableSpikeStrips and playerSpeed > 32 and (now - state.LastSpikeStripAt >= SPIKESTRIP_COOLDOWN) then
			state.LastSpikeStripAt = now
			if #state.SpikeStrips >= 2 then
				local oldest = table.remove(state.SpikeStrips, 1)
				if oldest and oldest.Model and oldest.Model.Parent then
					oldest.Model:Destroy()
				end
			end
			table.insert(state.SpikeStrips, deploySpikeStripAhead(player, playerPos, playerFwd))
		end

		-- Update Star 5 Police Helicopter + Spotlight from above
		local heliInSight = false
		if state.Helicopter and state.Helicopter.Model.Parent then
			local heli = state.Helicopter
			heli.OrbitAngle += dt * 0.65
			local targetHeliPos = Vector3.new(
				playerPos.X + math.cos(heli.OrbitAngle) * 26,
				playerPos.Y + 78,
				playerPos.Z + math.sin(heli.OrbitAngle) * 26
			)
			local nextHeliPos = heli.Hull.Position:Lerp(targetHeliPos, math.clamp(dt * 4.5, 0, 1))
			local lookAtTarget = Vector3.new(playerPos.X, nextHeliPos.Y - 12, playerPos.Z)
			heli.Hull.CFrame = CFrame.lookAt(nextHeliPos, lookAtTarget)
			heli.Rotor.CFrame = CFrame.new(nextHeliPos + Vector3.new(0, 3.1, 0))
				* CFrame.Angles(0, now * 18.0, 0)
			heli.GroundSpot.CFrame = CFrame.new(playerPos.X, 0.3, playerPos.Z)
				* CFrame.Angles(0, 0, math.rad(90))
			heliInSight = true
		end

		-- Update Autonomous Ground Police Units
		local anyCopInLineOfSight = heliInSight
		local anyCopBoxingInPlayer = false
		local unitsToDestroy: { number } = {}

		for i, unit in ipairs(state.Units) do
			if not (unit.Model and unit.Model.Parent) then
				table.insert(unitsToDestroy, i)
				continue
			end

			if toggledSiren then
				unit.RedLight.Brightness = if sirenPhaseOn then 3.8 else 0.4
				unit.BlueLight.Brightness = if sirenPhaseOn then 0.4 else 3.8
				unit.RedSiren.Transparency = if sirenPhaseOn then 0.0 else 0.45
				unit.BlueSiren.Transparency = if sirenPhaseOn then 0.45 else 0.0
			end

			local unitPos = unit.Chassis.Position
			local toPlayer = Vector3.new(playerPos.X - unitPos.X, 0, playerPos.Z - unitPos.Z)
			local dist = toPlayer.Magnitude

			-- Teleport far-behind police closer along pursuit perimeter so chase stays intense
			if dist > 260 then
				local respawnAngle = math.random() * math.pi * 2
				local respawnDist = math.random(95, 130)
				unitPos = Vector3.new(
					playerPos.X + math.cos(respawnAngle) * respawnDist,
					unit.Archetype.BodySize.Y * 0.5 + 0.5,
					playerPos.Z + math.sin(respawnAngle) * respawnDist
				)
				toPlayer = Vector3.new(playerPos.X - unitPos.X, 0, playerPos.Z - unitPos.Z)
				dist = toPlayer.Magnitude
			end

			if dist <= LINE_OF_SIGHT_RANGE then
				anyCopInLineOfSight = true
			end

			-- Stunned spin-out state after glancing hit
			if unit.StunTimer > 0 then
				unit.StunTimer = math.max(0, unit.StunTimer - dt)
				unit.Heading += dt * 4.5
				local coastFwd = Vector3.new(-math.sin(unit.Heading), 0, -math.cos(unit.Heading))
				local nextPos = unitPos + coastFwd * (unit.Archetype.Speed * 0.25 * dt)
				updateCopModelTransform(unit, nextPos, unit.Heading)
				continue
			end

			-- Check High-Speed Player Ram -> COP TAKEDOWN!
			local effRamSpeed = playerSpeed * plowMult
			if dist <= TAKEDOWN_CONTACT_RANGE and effRamSpeed >= TAKEDOWN_MIN_SPEED then
				if effRamSpeed >= TAKEDOWN_INSTANT_WRECK_SPEED then
					table.insert(unitsToDestroy, i)
					continue
				else
					unit.HP -= 55 * plowMult
					unit.Model:SetAttribute("HP", math.max(0, unit.HP))
					if unit.HP <= 0 then
						table.insert(unitsToDestroy, i)
						continue
					end
					unit.StunTimer = 2.0
					continue
				end
			end

			-- Check close-range boxing in / immobilization for BUSTED timer
			if dist <= BUSTED_RANGE and playerSpeed <= BUSTED_MAX_PLAYER_SPEED then
				anyCopBoxingInPlayer = true
			end

			-- Tactical Steering Target:
			-- Star 1: Direct pursuit
			-- Star 2+: Aggressive ramming weave + flanking / PIT intercept ahead of player
			local seekTarget = Vector3.new(playerPos.X, unitPos.Y, playerPos.Z)
			if stars >= 2 and i > 1 then
				local flankSide = if i % 2 == 0 then 1 else -1
				local leadDistance = if unit.Kind == "InterceptorSUV" then 26 elseif unit.Kind == "SWATEnforcer" then 34 else 14
				local weaveOffset = math.sin(now * 2.6 + unit.RamPhase) * 6 * unit.Archetype.RamAggression
				seekTarget = seekTarget
					+ playerFwd * leadDistance
					+ playerRight * (flankSide * 11 + weaveOffset)
			end

			local toSeek = Vector3.new(seekTarget.X - unitPos.X, 0, seekTarget.Z - unitPos.Z)
			if toSeek.Magnitude > 0.1 then
				local desiredDir = toSeek.Unit
				local desiredHeading = math.atan2(-desiredDir.X, -desiredDir.Z)
				local deltaAngle = math.atan2(math.sin(desiredHeading - unit.Heading), math.cos(desiredHeading - unit.Heading))
				local maxStep = unit.Archetype.TurnRate * (1 + (stars - 1) * 0.05) * dt
				unit.Heading += math.clamp(deltaAngle, -maxStep, maxStep)
			end

			local moveFwd = Vector3.new(-math.sin(unit.Heading), 0, -math.cos(unit.Heading))
			local speedBoost = 1.0 + (stars - 1) * 0.04
			-- Slight ram burst when closing in at Star 2+
			if stars >= 2 and dist < 38 and dist > 9 then
				speedBoost *= (1.0 + 0.12 * unit.Archetype.RamAggression)
			end

			local nextPos = unitPos + moveFwd * (unit.Archetype.Speed * speedBoost * dt)
			nextPos = Vector3.new(nextPos.X, unit.Archetype.BodySize.Y * 0.5 + 0.5, nextPos.Z)

			-- Prevent clipping straight inside the player's chassis
			local dxP = nextPos.X - playerPos.X
			local dzP = nextPos.Z - playerPos.Z
			local dP = math.sqrt(dxP * dxP + dzP * dzP)
			local minPlayerSep = 8.2
			if dP < minPlayerSep and dP > 0.01 then
				nextPos = Vector3.new(
					playerPos.X + (dxP / dP) * minPlayerSep,
					nextPos.Y,
					playerPos.Z + (dzP / dP) * minPlayerSep
				)
			end

			-- Separation between fellow police units so they form a surrounding box
			for j = 1, i - 1 do
				local other = state.Units[j]
				if other and other.Chassis and other.Chassis.Parent then
					local oPos = other.Chassis.Position
					local dxC = nextPos.X - oPos.X
					local dzC = nextPos.Z - oPos.Z
					local dC = math.sqrt(dxC * dxC + dzC * dzC)
					if dC < 10.5 and dC > 0.01 then
						nextPos = Vector3.new(
							oPos.X + (dxC / dC) * 10.5,
							nextPos.Y,
							oPos.Z + (dzC / dC) * 10.5
						)
					end
				end
			end

			updateCopModelTransform(unit, nextPos, unit.Heading)
		end

		-- Process wrecked police units in reverse index order
		for idx = #unitsToDestroy, 1, -1 do
			destroyPoliceUnit(player, state, unitsToDestroy[idx])
		end

		-- Update Line-of-Sight & Cooldown / Evade Heat Decay
		state.InLineOfSight = anyCopInLineOfSight
		if anyCopInLineOfSight then
			state.LastSeenByPoliceAt = now
		elseif now - state.LastSeenByPoliceAt >= EVADE_COOLDOWN_DELAY and now - state.LastCrimeAt >= EVADE_COOLDOWN_DELAY then
			local prevStars = state.HeatStars
			state.TotalHeat = math.max(0, state.TotalHeat - HEAT_DECAY_PER_SECOND * dt)
			syncHeatAttributes(player, state)

			if state.TotalHeat <= 0 then
				-- Player successfully evaded the pursuit! Award Escape Bounty!
				local escapeBounty = math.max(150, prevStars * 175)
				clearAllPursuitAssets(state)
				AddCashBindable:Fire(player, escapeBounty, "PoliceEscapeBounty")
				StyleCalloutRemote:FireClient(player, {
					Callout = string.format("ESCAPED POLICE! +$%d BOUNTY!", escapeBounty),
					Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
					ComboCount = tonumber(player:GetAttribute("ComboCount")) or 0,
					CashAwarded = escapeBounty,
				})
				HeatUpdateRemote:FireClient(player, 0, 0, "ESCAPED", 0)
				continue
			end
		end

		-- Update 4-Second "BUSTED!" Immobilized / Boxed-In Timer
		if anyCopBoxingInPlayer then
			state.BustedTimer = math.min(BUSTED_HOLD_DURATION, state.BustedTimer + dt)
			if state.BustedTimer >= BUSTED_HOLD_DURATION then
				triggerPlayerBusted(player, state)
				continue
			end
		else
			state.BustedTimer = math.max(0, state.BustedTimer - dt * BUSTED_DECAY_RATE)
		end

		syncHeatAttributes(player, state)
	end
end)
