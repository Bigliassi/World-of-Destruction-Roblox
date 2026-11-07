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
local WARNING_DECAY_DELAY = 3.5 -- seconds of not smashing before 0-Star warning heat decays
local WARNING_DECAY_PER_SECOND = 10.0 -- heat points/sec drained during 0-Star warning (< 100 heat)
local FIRST_STAR_DISPATCH_DELAY = 3.5 -- seconds dispatch delay when first crossing TotalHeat >= 100
local PURSUIT_SPAWN_MIN_DIST = 150 -- minimum road corridor spawn distance (studs)
local PURSUIT_SPAWN_MAX_DIST = 190 -- maximum road corridor spawn distance (studs)

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
		Units = { "Cruiser", "Cruiser" },
		EnableRoadblocks = false,
		EnableSpikeStrips = false,
		EnableHelicopter = false,
	},
	[3] = {
		Units = { "Cruiser", "Cruiser", "InterceptorSUV" },
		EnableRoadblocks = true,
		EnableSpikeStrips = false,
		EnableHelicopter = false,
	},
	[4] = {
		Units = { "Cruiser", "InterceptorSUV", "SWATEnforcer", "SWATEnforcer" },
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
type CopPartOffset = {
	Part: BasePart,
	Offset: CFrame,
}

type CopWheelEntry = {
	Tire: BasePart,
	Rim: BasePart,
	Spoke: BasePart,
	BaseOffset: CFrame,
}

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
	PartOffsets: { CopPartOffset },
	Wheels: { CopWheelEntry },
	WheelRadius: number,
	WheelSpin: number,
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
	HeatProgress: number, -- 0..100 within current star (or 0..99% warning toward Star 1)
	LastCrimeAt: number,
	LastSeenByPoliceAt: number,
	InLineOfSight: boolean,
	BustedTimer: number, -- 0..4.0 seconds
	ReachedFiveStarBanner: boolean,
	PursuitDispatchPending: boolean,
	PursuitDispatchReadyAt: number,
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
-- Building Obstacle Filters & Road Grid Navigation Helpers
--------------------------------------------------------------------------------
local roadCoords: { number } = { -630, -450, -270, -90, 0, 90, 270, 450, 630 }
local FEELER_ANGLES_RAD: { number } = {
	0,
	math.rad(-25),
	math.rad(25),
	math.rad(-55),
	math.rad(55),
}
local FEELER_RAY_LENGTH = 26.0
local BUMPER_RAY_Y = 2.5

local obstacleRayParams = RaycastParams.new()
obstacleRayParams.IgnoreWater = true
obstacleRayParams.RespectCanCollide = true

local obstacleOverlapParams = OverlapParams.new()
obstacleOverlapParams.RespectCanCollide = true

local lastFilterRefreshAt = 0

local function refreshObstacleFilters()
	local now = os.clock()
	if now - lastFilterRefreshAt < 1.0 then
		return
	end
	lastFilterRefreshAt = now

	local leoCity = Workspace:FindFirstChild("LeoCity")
	local buildingsFolder = if leoCity then leoCity:FindFirstChild("Buildings") else nil
	local landmarksFolder = if leoCity then leoCity:FindFirstChild("Landmarks") else nil

	if buildingsFolder or landmarksFolder then
		local includeList: { Instance } = {}
		if buildingsFolder then
			table.insert(includeList, buildingsFolder)
		end
		if landmarksFolder then
			table.insert(includeList, landmarksFolder)
		end
		obstacleRayParams.FilterType = Enum.RaycastFilterType.Include
		obstacleRayParams.FilterDescendantsInstances = includeList
		obstacleOverlapParams.FilterType = Enum.RaycastFilterType.Include
		obstacleOverlapParams.FilterDescendantsInstances = includeList
	else
		local excludeList: { Instance } = { policeWorldFolder }
		for _, folderName in ipairs({ "Vehicles", "PlayerVehicles", "ParkedVehicles", "LeoCityAI" }) do
			local f = Workspace:FindFirstChild(folderName)
			if f then
				table.insert(excludeList, f)
			end
		end
		if leoCity then
			for _, subName in ipairs({ "DestructibleProps", "Roads", "Sidewalks", "Trees" }) do
				local sub = leoCity:FindFirstChild(subName)
				if sub then
					table.insert(excludeList, sub)
				end
			end
		end
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate then
			table.insert(excludeList, baseplate)
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then
				table.insert(excludeList, plr.Character)
			end
		end
		obstacleRayParams.FilterType = Enum.RaycastFilterType.Exclude
		obstacleRayParams.FilterDescendantsInstances = excludeList
		obstacleOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
		obstacleOverlapParams.FilterDescendantsInstances = excludeList
	end
end

local function nearestRoadCoord(val: number): number
	local best = roadCoords[1]
	local bestDiff = math.abs(val - best)
	for i = 2, #roadCoords do
		local c = roadCoords[i]
		local diff = math.abs(val - c)
		if diff < bestDiff then
			bestDiff = diff
			best = c
		end
	end
	return best
end

local function checkBuildingOverlapAt(pos: Vector3, heading: number, bodySize: Vector3): (boolean, BasePart?)
	refreshObstacleFilters()
	local boxCF = CFrame.new(pos) * CFrame.Angles(0, heading, 0)
	local hitParts = Workspace:GetPartBoundsInBox(boxCF, bodySize * 0.9, obstacleOverlapParams)
	for _, part in ipairs(hitParts) do
		-- Ignore flat ground slabs; any vertical wall / building structure extends above Y = 1.4
		if (part.Position.Y + part.Size.Y * 0.5) > 1.4 then
			return true, part
		end
	end
	return false, nil
end

local function computeOutwardNormalFromPart(unitPos: Vector3, part: BasePart): Vector3
	local localPos = part.CFrame:PointToObjectSpace(unitPos)
	local halfX = math.max(0.5, part.Size.X * 0.5)
	local halfZ = math.max(0.5, part.Size.Z * 0.5)
	local nx = localPos.X / halfX
	local nz = localPos.Z / halfZ
	local worldNormal: Vector3
	if math.abs(nx) >= math.abs(nz) then
		local signX = if nx >= 0 then 1 else -1
		worldNormal = part.CFrame.RightVector * signX
	else
		local signZ = if nz >= 0 then 1 else -1
		worldNormal = -part.CFrame.LookVector * signZ
	end
	local flat = Vector3.new(worldNormal.X, 0, worldNormal.Z)
	if flat.Magnitude > 0.01 then
		return flat.Unit
	end
	local fallback = Vector3.new(unitPos.X - part.Position.X, 0, unitPos.Z - part.Position.Z)
	if fallback.Magnitude > 0.01 then
		return fallback.Unit
	end
	return Vector3.new(0, 0, 1)
end

local function findRoadSnapSpawn(rawPos: Vector3, playerPos: Vector3, bodySize: Vector3): (Vector3, number)
	refreshObstacleFilters()
	local spawnY = bodySize.Y * 0.5 + 0.5
	local nearX = nearestRoadCoord(rawPos.X)
	local nearZ = nearestRoadCoord(rawPos.Z)
	local distToRoadX = math.abs(rawPos.X - nearX)
	local distToRoadZ = math.abs(rawPos.Z - nearZ)

	local candidates: { Vector3 } = {}
	if distToRoadX <= distToRoadZ then
		table.insert(candidates, Vector3.new(nearX, spawnY, math.clamp(rawPos.Z, -630, 630)))
		table.insert(candidates, Vector3.new(math.clamp(rawPos.X, -630, 630), spawnY, nearZ))
	else
		table.insert(candidates, Vector3.new(math.clamp(rawPos.X, -630, 630), spawnY, nearZ))
		table.insert(candidates, Vector3.new(nearX, spawnY, math.clamp(rawPos.Z, -630, 630)))
	end
	table.insert(candidates, Vector3.new(nearX, spawnY, nearZ))

	-- Additional road intersection & boulevard fallbacks around playerPos (150..190 studs out)
	local playerRoadX = nearestRoadCoord(playerPos.X)
	local playerRoadZ = nearestRoadCoord(playerPos.Z)
	for _, offset in ipairs({ -185, -155, 155, 185 }) do
		table.insert(candidates, Vector3.new(playerRoadX, spawnY, math.clamp(playerPos.Z + offset, -630, 630)))
		table.insert(candidates, Vector3.new(math.clamp(playerPos.X + offset, -630, 630), spawnY, playerRoadZ))
	end
	for _, rx in ipairs(roadCoords) do
		for _, rz in ipairs(roadCoords) do
			local p = Vector3.new(rx, spawnY, rz)
			local d = (p - playerPos).Magnitude
			if d >= 140 and d <= 205 then
				table.insert(candidates, p)
			end
		end
	end

	-- Prefer road corridor candidates >= 135 studs away so pursuit units arrive from a fair distance
	for _, cand in ipairs(candidates) do
		local toPlayer = Vector3.new(playerPos.X - cand.X, 0, playerPos.Z - cand.Z)
		local heading = if toPlayer.Magnitude > 0.1 then math.atan2(-toPlayer.X, -toPlayer.Z) else 0
		local blocked = checkBuildingOverlapAt(cand, heading, bodySize)
		if not blocked and toPlayer.Magnitude >= 135 then
			return cand, heading
		end
	end

	for _, cand in ipairs(candidates) do
		local toPlayer = Vector3.new(playerPos.X - cand.X, 0, playerPos.Z - cand.Z)
		local heading = if toPlayer.Magnitude > 0.1 then math.atan2(-toPlayer.X, -toPlayer.Z) else 0
		local blocked = checkBuildingOverlapAt(cand, heading, bodySize)
		if not blocked and toPlayer.Magnitude >= 85 then
			return cand, heading
		end
	end

	local fallbackPos = Vector3.new(playerRoadX, spawnY, math.clamp(playerPos.Z + 165, -630, 630))
	local toPlayer = Vector3.new(playerPos.X - fallbackPos.X, 0, playerPos.Z - fallbackPos.Z)
	local fallbackHeading = if toPlayer.Magnitude > 0.1 then math.atan2(-toPlayer.X, -toPlayer.Z) else 0
	return fallbackPos, fallbackHeading
end

local function selectRoadWaypointToward(unitPos: Vector3, seekTarget: Vector3): Vector3
	refreshObstacleFilters()
	local origin = Vector3.new(unitPos.X, BUMPER_RAY_Y, unitPos.Z)
	local targetRayPos = Vector3.new(seekTarget.X, BUMPER_RAY_Y, seekTarget.Z)
	local toTarget = targetRayPos - origin
	if toTarget.Magnitude <= 6 then
		return seekTarget
	end

	-- Cast direct line-of-sight ray from unitPos to seekTarget
	local directHit = Workspace:Raycast(origin, toTarget, obstacleRayParams)
	if not directHit then
		return seekTarget
	end

	-- Building blocks line-of-sight: evaluate nearest Road Intersections & Boulevard corridors
	local unitRoadX = nearestRoadCoord(unitPos.X)
	local unitRoadZ = nearestRoadCoord(unitPos.Z)
	local targetRoadX = nearestRoadCoord(seekTarget.X)
	local targetRoadZ = nearestRoadCoord(seekTarget.Z)

	local waypoints: { Vector3 } = {
		Vector3.new(unitRoadX, unitPos.Y, unitRoadZ),
		Vector3.new(unitRoadX, unitPos.Y, targetRoadZ),
		Vector3.new(targetRoadX, unitPos.Y, unitRoadZ),
		Vector3.new(unitRoadX, unitPos.Y, seekTarget.Z),
		Vector3.new(seekTarget.X, unitPos.Y, unitRoadZ),
		Vector3.new(0, unitPos.Y, unitRoadZ),
		Vector3.new(unitRoadX, unitPos.Y, 0),
	}

	for _, rx in ipairs(roadCoords) do
		if math.abs(rx - unitPos.X) <= 220 then
			table.insert(waypoints, Vector3.new(rx, unitPos.Y, unitRoadZ))
			table.insert(waypoints, Vector3.new(rx, unitPos.Y, targetRoadZ))
		end
	end
	for _, rz in ipairs(roadCoords) do
		if math.abs(rz - unitPos.Z) <= 220 then
			table.insert(waypoints, Vector3.new(unitRoadX, unitPos.Y, rz))
			table.insert(waypoints, Vector3.new(targetRoadX, unitPos.Y, rz))
		end
	end

	local bestWP = Vector3.new(unitRoadX, unitPos.Y, unitRoadZ)
	local bestScore = math.huge

	for _, wp in ipairs(waypoints) do
		local flatToWP = Vector3.new(wp.X - unitPos.X, 0, wp.Z - unitPos.Z)
		local distToWP = flatToWP.Magnitude
		if distToWP >= 10 then
			local wpOrigin = Vector3.new(wp.X, BUMPER_RAY_Y, wp.Z)
			local hitToWP = Workspace:Raycast(origin, wpOrigin - origin, obstacleRayParams)
			if not hitToWP then
				local distWPToGoal = Vector3.new(seekTarget.X - wp.X, 0, seekTarget.Z - wp.Z).Magnitude
				local hitWPToGoal = Workspace:Raycast(wpOrigin, targetRayPos - wpOrigin, obstacleRayParams)
				local losBonus = if not hitWPToGoal then -45 else 0
				local score = distWPToGoal + distToWP * 0.55 + losBonus
				if score < bestScore then
					bestScore = score
					bestWP = wp
				end
			end
		end
	end

	return bestWP
end

--------------------------------------------------------------------------------
-- Model Builders: High-Detail Police Cruisers, SUV Interceptors, SWAT Trucks,
-- Roadblocks, Spike Strips & Star-5 Police Helicopter with Spotlight!
--------------------------------------------------------------------------------
local unitSerial = 0

local function addCopSubPart(
	model: Model,
	chassisCF: CFrame,
	offsets: { CopPartOffset },
	className: string,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	relCF: CFrame,
	transparency: number?
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = chassisCF * relCF
	part.Parent = model
	table.insert(offsets, {
		Part = part,
		Offset = relCF,
	})
	return part
end

local function attachDoorMarking(doorPart: BasePart, face: Enum.NormalId, labelText: string, textColor: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "PoliceDoorMarking"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0.25
	sg.Parent = doorPart

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextColor3 = textColor
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Parent = sg
end

local function buildPoliceVehicle(kind: PoliceUnitKind, spawnPos: Vector3, heading: number, slotIndex: number): ActiveCopUnit
	unitSerial += 1
	local arch = UNIT_ARCHETYPES[kind]
	local w = arch.BodySize.X
	local h = arch.BodySize.Y
	local len = arch.BodySize.Z

	local model = Instance.new("Model")
	model.Name = string.format("Police_%s_%d", kind, unitSerial)
	model:SetAttribute("IsPoliceUnit", true)
	model:SetAttribute("PoliceUnitKind", kind)
	model:SetAttribute("MaxHP", arch.MaxHP)
	model:SetAttribute("HP", arch.MaxHP)

	local chassisCF = CFrame.new(spawnPos) * CFrame.Angles(0, heading, 0)
	local partOffsets: { CopPartOffset } = {}
	local wheels: { CopWheelEntry } = {}

	-- Primary colors by Police Unit Archetype
	local lowerHullColor = if kind == "Cruiser"
		then Color3.fromRGB(18, 22, 30)
		elseif kind == "InterceptorSUV" then Color3.fromRGB(22, 26, 36)
		else Color3.fromRGB(28, 36, 52)
	local doorPanelColor = if kind == "Cruiser"
		then Color3.fromRGB(242, 245, 250)
		elseif kind == "InterceptorSUV" then Color3.fromRGB(28, 33, 44)
		else Color3.fromRGB(22, 30, 46)
	local roofColor = if kind == "Cruiser"
		then Color3.fromRGB(242, 245, 250)
		elseif kind == "InterceptorSUV" then Color3.fromRGB(24, 28, 38)
		else Color3.fromRGB(26, 34, 50)
	local hullMaterial = if kind == "SWATEnforcer" then Enum.Material.Metal else Enum.Material.SmoothPlastic

	-- 1. Sculpted Lower Chassis Base
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(w, h * 0.50, len)
	chassis.Color = lowerHullColor
	chassis.Material = hullMaterial
	chassis.Anchored = true
	chassis.CanCollide = true
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CFrame = chassisCF
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- 2. Pursuit Door Panels / Tactical Side Panels / Armored SWAT Hull
	local doorLen = if kind == "SWATEnforcer" then len * 0.64 else len * 0.46
	local doorCenterZ = if kind == "SWATEnforcer" then len * 0.08 else 0.15
	local doorPanel = addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"PursuitDoorPanels",
		Vector3.new(w * 1.02, h * 0.48, doorLen),
		doorPanelColor,
		hullMaterial,
		CFrame.new(0, h * 0.04, doorCenterZ)
	)
	local doorLabelText = if kind == "SWATEnforcer" then "SWAT" else "POLICE"
	local doorTextColor = if kind == "Cruiser"
		then Color3.fromRGB(16, 28, 78)
		else Color3.fromRGB(235, 240, 252)
	attachDoorMarking(doorPanel, Enum.NormalId.Left, doorLabelText, doorTextColor)
	attachDoorMarking(doorPanel, Enum.NormalId.Right, doorLabelText, doorTextColor)

	-- Accent tactical stripe along the sides for InterceptorSUV and SWATEnforcer
	if kind ~= "Cruiser" then
		addCopSubPart(
			model,
			chassisCF,
			partOffsets,
			"Part",
			"TacticalSideStripe",
			Vector3.new(w * 1.03, h * 0.10, len * 0.78),
			if kind == "InterceptorSUV" then Color3.fromRGB(220, 228, 242) else Color3.fromRGB(185, 195, 215),
			Enum.Material.SmoothPlastic,
			CFrame.new(0, h * 0.10, 0.2)
		)
	end

	-- 3. Sloped Front Hood (WedgePart) & Rear Deck / SWAT Troop Bay
	local hoodLen = if kind == "SWATEnforcer" then len * 0.24 else len * 0.28
	local hoodH = h * 0.24
	local hoodZ = -len * 0.5 + hoodLen * 0.5 + 0.15
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"WedgePart",
		"SlopedHood",
		Vector3.new(w * 0.96, hoodH, hoodLen),
		lowerHullColor,
		hullMaterial,
		CFrame.new(0, h * 0.25 + hoodH * 0.5, hoodZ)
	)

	-- 4. Cabin Greenhouse, Angled Front Windshield (WedgePart), Painted Roof & Sloped Rear Window
	local cabW = w * 0.88
	local cabH = if kind == "Cruiser" then h * 0.54 elseif kind == "InterceptorSUV" then h * 0.58 else h * 0.62
	local cabLen = if kind == "Cruiser" then len * 0.36 elseif kind == "InterceptorSUV" then len * 0.48 else len * 0.58
	local cabZ = if kind == "Cruiser" then 0.35 elseif kind == "InterceptorSUV" then 0.85 else 1.25
	local cabY = h * 0.25 + cabH * 0.5

	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"Cabin",
		Vector3.new(cabW, cabH, cabLen),
		Color3.fromRGB(26, 36, 52),
		Enum.Material.Glass,
		CFrame.new(0, cabY, cabZ),
		0.25
	)

	-- Angled Front Windshield (WedgePart, Material.Glass)
	local windLen = if kind == "SWATEnforcer" then 1.35 else 1.75
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"WedgePart",
		"FrontWindshield",
		Vector3.new(cabW * 0.98, cabH * 0.96, windLen),
		Color3.fromRGB(38, 54, 76),
		Enum.Material.Glass,
		CFrame.new(0, cabY, cabZ - cabLen * 0.5 - windLen * 0.5),
		0.2
	)

	-- Sloped Rear Window (WedgePart rotated 180 deg)
	local rearWinLen = if kind == "Cruiser" then 1.55 else 0.95
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"WedgePart",
		"RearWindow",
		Vector3.new(cabW * 0.96, cabH * 0.94, rearWinLen),
		Color3.fromRGB(34, 48, 68),
		Enum.Material.Glass,
		CFrame.new(0, cabY, cabZ + cabLen * 0.5 + rearWinLen * 0.5) * CFrame.Angles(0, math.rad(180), 0),
		0.25
	)

	-- Painted Roof Cap
	local roofY = h * 0.25 + cabH + 0.12
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"PaintedRoof",
		Vector3.new(cabW * 1.02, 0.24, cabLen * 0.98),
		roofColor,
		hullMaterial,
		CFrame.new(0, roofY, cabZ)
	)

	-- Rear Trunk Deck for Cruiser / Armored Step Bumper for SWAT
	if kind == "Cruiser" then
		local trunkLen = len * 0.20
		addCopSubPart(
			model,
			chassisCF,
			partOffsets,
			"Part",
			"TrunkDeck",
			Vector3.new(w * 0.96, h * 0.20, trunkLen),
			lowerHullColor,
			Enum.Material.SmoothPlastic,
			CFrame.new(0, h * 0.25 + h * 0.10, len * 0.5 - trunkLen * 0.5 - 0.1)
		)
	elseif kind == "SWATEnforcer" then
		for _, sx in ipairs({ -1, 1 }) do
			addCopSubPart(
				model,
				chassisCF,
				partOffsets,
				"Part",
				if sx < 0 then "ArmorSkirtL" else "ArmorSkirtR",
				Vector3.new(0.35, h * 0.36, len * 0.84),
				Color3.fromRGB(16, 20, 30),
				Enum.Material.DiamondPlate,
				CFrame.new(sx * (w * 0.51), -h * 0.08, 0)
			)
		end
	end

	-- 5. Heavy Steel Front Push-Bumper / PIT Bullbar with Vertical Ram Guards & Rear Bumper
	local bumperZ = -len * 0.5 - 0.42
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"PushBumper",
		Vector3.new(w * 0.96, h * 0.26, 0.72),
		Color3.fromRGB(20, 22, 26),
		Enum.Material.Metal,
		CFrame.new(0, -h * 0.10, bumperZ)
	)
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"BullbarCrossTube",
		Vector3.new(w * 0.68, 0.28, 0.34),
		Color3.fromRGB(32, 36, 42),
		Enum.Material.Metal,
		CFrame.new(0, h * 0.16, bumperZ - 0.12)
	)
	for _, sx in ipairs({ -1, 1 }) do
		addCopSubPart(
			model,
			chassisCF,
			partOffsets,
			"Part",
			if sx < 0 then "RamGuardL" else "RamGuardR",
			Vector3.new(0.36, h * 0.56, 0.52),
			Color3.fromRGB(24, 28, 34),
			Enum.Material.Metal,
			CFrame.new(sx * (w * 0.24), h * 0.02, bumperZ - 0.10)
		)
	end
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"RearBumper",
		Vector3.new(w * 0.98, h * 0.24, 0.55),
		Color3.fromRGB(22, 24, 30),
		Enum.Material.Metal,
		CFrame.new(0, -h * 0.12, len * 0.5 + 0.24)
	)

	-- 6. Front Grille, Front LED Headlights (with SpotLight), Rear Red Taillights & Side Mirrors
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"FrontGrille",
		Vector3.new(w * 0.46, h * 0.26, 0.18),
		Color3.fromRGB(30, 34, 40),
		Enum.Material.DiamondPlate,
		CFrame.new(0, h * 0.06, -len * 0.5 - 0.06)
	)

	for _, sx in ipairs({ -1, 1 }) do
		local headlight = addCopSubPart(
			model,
			chassisCF,
			partOffsets,
			"Part",
			if sx < 0 then "HeadlightL" else "HeadlightR",
			Vector3.new(w * 0.20, h * 0.16, 0.20),
			Color3.fromRGB(240, 248, 255),
			Enum.Material.Neon,
			CFrame.new(sx * (w * 0.35), h * 0.08, -len * 0.5 - 0.07)
		)
		local spot = Instance.new("SpotLight")
		spot.Name = "HeadlightSpot"
		spot.Face = Enum.NormalId.Front
		spot.Brightness = 2.6
		spot.Range = 54
		spot.Angle = 55
		spot.Color = Color3.fromRGB(245, 250, 255)
		spot.Parent = headlight

		-- Side Mirrors
		addCopSubPart(
			model,
			chassisCF,
			partOffsets,
			"Part",
			if sx < 0 then "SideMirrorL" else "SideMirrorR",
			Vector3.new(0.55, 0.34, 0.42),
			lowerHullColor,
			Enum.Material.SmoothPlastic,
			CFrame.new(sx * (cabW * 0.5 + 0.25), cabY - cabH * 0.12, cabZ - cabLen * 0.42)
		)
	end

	-- Rear Red Taillights
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"TaillightBar",
		Vector3.new(w * 0.82, h * 0.16, 0.18),
		Color3.fromRGB(255, 32, 32),
		Enum.Material.Neon,
		CFrame.new(0, h * 0.08, len * 0.5 + 0.07)
	)

	-- 7. 4 Cylinder Wheels (WheelFL, WheelFR, WheelRL, WheelRR) with Metallic Rims that spin
	local wheelRadius = if kind == "Cruiser" then 1.35 elseif kind == "InterceptorSUV" then 1.55 else 1.85
	local wheelDiameter = wheelRadius * 2.0
	local wheelWidth = if kind == "SWATEnforcer" then 1.45 else 1.15
	local chassisCenterY = h * 0.5 + 0.5
	local wheelLocalY = -chassisCenterY + wheelRadius
	local wheelTrackX = w * 0.5 + wheelWidth * 0.28
	local wheelBaseZ = len * 0.33

	local wheelSpecs = {
		{ Name = "WheelFL", X = -wheelTrackX, Z = -wheelBaseZ },
		{ Name = "WheelFR", X = wheelTrackX, Z = -wheelBaseZ },
		{ Name = "WheelRL", X = -wheelTrackX, Z = wheelBaseZ },
		{ Name = "WheelRR", X = wheelTrackX, Z = wheelBaseZ },
	}

	for _, ws in ipairs(wheelSpecs) do
		local baseOffset = CFrame.new(ws.X, wheelLocalY, ws.Z)

		local tire = Instance.new("Part")
		tire.Name = ws.Name
		tire.Shape = Enum.PartType.Cylinder
		tire.Size = Vector3.new(wheelWidth, wheelDiameter, wheelDiameter)
		tire.Color = Color3.fromRGB(20, 22, 26)
		tire.Material = Enum.Material.SmoothPlastic
		tire.Anchored = true
		tire.CanCollide = false
		tire.TopSurface = Enum.SurfaceType.Smooth
		tire.BottomSurface = Enum.SurfaceType.Smooth
		tire.CFrame = chassisCF * baseOffset
		tire.Parent = model

		local rim = Instance.new("Part")
		rim.Name = ws.Name .. "_Rim"
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(wheelWidth + 0.12, wheelDiameter * 0.56, wheelDiameter * 0.56)
		rim.Color = Color3.fromRGB(190, 198, 212)
		rim.Material = Enum.Material.Metal
		rim.Anchored = true
		rim.CanCollide = false
		rim.TopSurface = Enum.SurfaceType.Smooth
		rim.BottomSurface = Enum.SurfaceType.Smooth
		rim.CFrame = tire.CFrame
		rim.Parent = model

		local spoke = Instance.new("Part")
		spoke.Name = ws.Name .. "_Spoke"
		spoke.Size = Vector3.new(wheelWidth + 0.18, wheelDiameter * 0.48, 0.22)
		spoke.Color = Color3.fromRGB(95, 102, 118)
		spoke.Material = Enum.Material.Metal
		spoke.Anchored = true
		spoke.CanCollide = false
		spoke.CFrame = tire.CFrame
		spoke.Parent = model

		table.insert(wheels, {
			Tire = tire,
			Rim = rim,
			Spoke = spoke,
			BaseOffset = baseOffset,
		})
	end

	-- 8. Detailed Roof Lightbar Bridge with Center Speaker Box and Red/Blue Strobe Lenses
	local barY = roofY + 0.36
	local barZ = cabZ - cabLen * 0.12

	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"LightbarBridge",
		Vector3.new(cabW * 0.86, 0.18, 0.95),
		Color3.fromRGB(32, 36, 44),
		Enum.Material.Metal,
		CFrame.new(0, barY - 0.18, barZ)
	)
	addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"SirenSpeakerBox",
		Vector3.new(cabW * 0.18, 0.44, 0.96),
		Color3.fromRGB(18, 20, 26),
		Enum.Material.Metal,
		CFrame.new(0, barY, barZ)
	)

	local redOffset = CFrame.new(-cabW * 0.26, barY, barZ)
	local redSiren = addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"SirenRed",
		Vector3.new(cabW * 0.34, 0.42, 0.88),
		Color3.fromRGB(255, 35, 35),
		Enum.Material.Neon,
		redOffset
	) :: Part

	local redLight = Instance.new("PointLight")
	redLight.Color = Color3.fromRGB(255, 40, 40)
	redLight.Range = 28
	redLight.Brightness = 3.5
	redLight.Parent = redSiren

	local blueOffset = CFrame.new(cabW * 0.26, barY, barZ)
	local blueSiren = addCopSubPart(
		model,
		chassisCF,
		partOffsets,
		"Part",
		"SirenBlue",
		Vector3.new(cabW * 0.34, 0.42, 0.88),
		Color3.fromRGB(35, 110, 255),
		Enum.Material.Neon,
		blueOffset
	) :: Part

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
		PartOffsets = partOffsets,
		Wheels = wheels,
		WheelRadius = wheelRadius,
		WheelSpin = 0,
		Heading = heading,
		HP = arch.MaxHP,
		StunTimer = 0,
		RamPhase = math.random() * math.pi * 2,
		SlotIndex = slotIndex,
	}
end

local function updateCopModelTransform(unit: ActiveCopUnit, pos: Vector3, heading: number, distanceTraveled: number?)
	local cf = CFrame.new(pos) * CFrame.Angles(0, heading, 0)
	unit.Chassis.CFrame = cf

	for _, entry in ipairs(unit.PartOffsets) do
		if entry.Part and entry.Part.Parent then
			entry.Part.CFrame = cf * entry.Offset
		end
	end

	local stepDist = distanceTraveled or 0
	if stepDist ~= 0 and unit.WheelRadius > 0.1 then
		unit.WheelSpin = (unit.WheelSpin - stepDist / unit.WheelRadius) % (math.pi * 2)
	end
	local spinCF = CFrame.Angles(unit.WheelSpin, 0, 0)
	for _, wEntry in ipairs(unit.Wheels) do
		local wCF = cf * wEntry.BaseOffset * spinCF
		if wEntry.Tire and wEntry.Tire.Parent then
			wEntry.Tire.CFrame = wCF
		end
		if wEntry.Rim and wEntry.Rim.Parent then
			wEntry.Rim.CFrame = wCF
		end
		if wEntry.Spoke and wEntry.Spoke.Parent then
			wEntry.Spoke.CFrame = wCF
		end
	end
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
	-- Paced 5-Star Heat Calculation:
	--   0..99   Heat = 0 Stars (HEAT WARNING / RADAR ALERT, 0..99% gauge toward Star 1)
	--   100..199 Heat = 1 Star  (1 Patrol Cruiser)
	--   200..299 Heat = 2 Stars (2 Cruisers)
	--   300..399 Heat = 3 Stars (Cruisers + SUV Interceptor + Roadblocks)
	--   400..499 Heat = 4 Stars (SWAT Enforcer + Spike Strips)
	--   500     Heat = 5 Stars (Full Force + Helicopter Spotlight)
	local stars = 0
	if state.TotalHeat >= HEAT_POINTS_PER_STAR then
		stars = math.clamp(math.floor(state.TotalHeat / HEAT_POINTS_PER_STAR), 1, MAX_HEAT_STARS)
	end
	state.HeatStars = stars

	local progressInStar = 0
	if stars == 0 then
		-- 0..99% Radar Warning gauge toward 1 Star
		progressInStar = math.clamp((state.TotalHeat / HEAT_POINTS_PER_STAR) * 100, 0, 99)
	elseif stars >= MAX_HEAT_STARS then
		progressInStar = 100
	else
		local starFloor = stars * HEAT_POINTS_PER_STAR
		progressInStar = math.clamp(((state.TotalHeat - starFloor) / HEAT_POINTS_PER_STAR) * 100, 0, 100)
	end
	state.HeatProgress = math.floor(progressInStar + 0.5)

	local bustedRatio = math.clamp(state.BustedTimer / BUSTED_HOLD_DURATION, 0, 1)
	local isEvading = stars > 0 and not state.InLineOfSight and (os.clock() - state.LastSeenByPoliceAt >= EVADE_COOLDOWN_DELAY)
	local isWarning = stars == 0 and state.TotalHeat > 0

	player:SetAttribute("TotalHeat", math.floor(state.TotalHeat + 0.5))
	player:SetAttribute("HeatStars", stars)
	player:SetAttribute("HeatProgress", state.HeatProgress)
	player:SetAttribute("HeatProgressNormalized", tonumber(string.format("%.3f", state.HeatProgress / 100)))
	player:SetAttribute("HeatWarning", isWarning)
	player:SetAttribute("PoliceDispatchPending", state.PursuitDispatchPending)
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

	-- Spawn missing units snapped to the nearest clear Road Line (150..190 studs out)
	for _, kind in ipairs({ "Cruiser", "InterceptorSUV", "SWATEnforcer" } :: { PoliceUnitKind }) do
		local needed = (desiredCounts[kind] or 0) - (currentCounts[kind] or 0)
		for _ = 1, needed do
			local angle = math.random() * math.pi * 2
			local dist = math.random(PURSUIT_SPAWN_MIN_DIST, PURSUIT_SPAWN_MAX_DIST)
			local rawSpawnPos = Vector3.new(
				playerPos.X + math.cos(angle) * dist,
				UNIT_ARCHETYPES[kind].BodySize.Y * 0.5 + 0.5,
				playerPos.Z + math.sin(angle) * dist
			)
			local spawnPos, spawnHeading = findRoadSnapSpawn(rawSpawnPos, playerPos, UNIT_ARCHETYPES[kind].BodySize)
			local slotIndex = #state.Units + 1
			local newUnit = buildPoliceVehicle(kind, spawnPos, spawnHeading, slotIndex)
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
	state.TotalHeat = math.max(HEAT_POINTS_PER_STAR, state.TotalHeat - 30)
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
	state.PursuitDispatchPending = false
	state.PursuitDispatchReadyAt = 0
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

	local delta = math.max(0.5, tonumber(heatDelta) or 3.5)
	local prevStars = state.HeatStars
	local now = os.clock()

	state.TotalHeat = math.clamp(state.TotalHeat + delta, 0, MAX_TOTAL_HEAT)
	state.LastCrimeAt = now

	syncHeatAttributes(player, state)

	if state.HeatStars > prevStars then
		state.LastSeenByPoliceAt = now
		state.InLineOfSight = true

		if prevStars == 0 and state.HeatStars >= 1 then
			-- Crossing TotalHeat >= 100 (1 Star) for the first time in a pursuit:
			-- Wait a 3.5s dispatch delay before spawning police units 150..190 studs out!
			state.PursuitDispatchPending = true
			state.PursuitDispatchReadyAt = now + FIRST_STAR_DISPATCH_DELAY
			syncHeatAttributes(player, state)

			local dispatchAlert = "DISPATCH ALERT: PATROL UNIT EN ROUTE!"
			PoliceAlertRemote:FireClient(player, {
				HeatStars = state.HeatStars,
				HeatProgress = state.HeatProgress,
				Headline = dispatchAlert,
				DispatchDelay = FIRST_STAR_DISPATCH_DELAY,
			})
			RootPoliceAlertRemote:FireClient(player, {
				HeatStars = state.HeatStars,
				HeatProgress = state.HeatProgress,
				Headline = dispatchAlert,
				DispatchDelay = FIRST_STAR_DISPATCH_DELAY,
			})
			StyleCalloutRemote:FireClient(player, {
				Callout = dispatchAlert,
				Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
				ComboCount = tonumber(player:GetAttribute("ComboCount")) or 0,
				CashAwarded = 0,
			})
		else
			if not state.PursuitDispatchPending then
				reconcilePoliceForceForStars(player, state)
			end

			local starMessages = {
				[1] = "1-STAR HEAT: PATROL CRUISER DISPATCHED!",
				[2] = "2-STAR HEAT: CRUISER SQUAD INBOUND!",
				[3] = "3-STAR HEAT: SUV INTERCEPTOR & ROADBLOCKS ACTIVE!",
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
	elseif state.HeatStars > 0 then
		state.LastSeenByPoliceAt = now
		state.InLineOfSight = true
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
		PursuitDispatchPending = false,
		PursuitDispatchReadyAt = 0,
		Units = {},
		Roadblocks = {},
		SpikeStrips = {},
		Helicopter = nil,
		LastRoadblockAt = 0,
		LastSpikeStripAt = 0,
		LastImpactReportAt = 0,
	}
	player:SetAttribute("TotalHeat", 0)
	player:SetAttribute("HeatStars", 0)
	player:SetAttribute("HeatProgress", 0)
	player:SetAttribute("HeatWarning", false)
	player:SetAttribute("PoliceDispatchPending", false)
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
		if not state then
			continue
		end

		-- 0-Star Warning Phase (0..99 Heat): no police spawned; decays at 10 heat/sec after 3.5s of not smashing
		if state.HeatStars <= 0 then
			if #state.Units > 0 or #state.Roadblocks > 0 or #state.SpikeStrips > 0 or state.Helicopter then
				clearAllPursuitAssets(state)
			end
			state.PursuitDispatchPending = false
			state.PursuitDispatchReadyAt = 0
			state.InLineOfSight = false
			if state.TotalHeat > 0 and (now - state.LastCrimeAt >= WARNING_DECAY_DELAY) then
				state.TotalHeat = math.max(0, state.TotalHeat - WARNING_DECAY_PER_SECOND * dt)
				syncHeatAttributes(player, state)
			end
			continue
		end

		local stars = state.HeatStars
		local roster = STAR_ROSTER[stars]
		local playerPos, playerFwd, playerSpeed, _playerVel = getPlayerMotion(player)
		local playerRight = Vector3.new(-playerFwd.Z, 0, playerFwd.X)
		local plowMult = tonumber(player:GetAttribute("RammingForceMultiplier")) or 1.0

		-- Handle 3.5s first-star dispatch delay before spawning pursuit units 150..190 studs away
		if state.PursuitDispatchPending then
			if now >= state.PursuitDispatchReadyAt then
				state.PursuitDispatchPending = false
				state.LastSeenByPoliceAt = now
				reconcilePoliceForceForStars(player, state)
				syncHeatAttributes(player, state)

				local arrivedMsg = "1-STAR HEAT: PATROL CRUISER DISPATCHED!"
				PoliceAlertRemote:FireClient(player, {
					HeatStars = state.HeatStars,
					HeatProgress = state.HeatProgress,
					Headline = arrivedMsg,
				})
				RootPoliceAlertRemote:FireClient(player, {
					HeatStars = state.HeatStars,
					HeatProgress = state.HeatProgress,
					Headline = arrivedMsg,
				})
			else
				state.LastSeenByPoliceAt = now
				syncHeatAttributes(player, state)
				continue
			end
		end

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

			-- Teleport far-behind police closer along pursuit perimeter snapped to nearest clear Road Line (150..190 studs)
			if dist > 280 then
				local respawnAngle = math.random() * math.pi * 2
				local respawnDist = math.random(PURSUIT_SPAWN_MIN_DIST, PURSUIT_SPAWN_MAX_DIST)
				local rawRespawnPos = Vector3.new(
					playerPos.X + math.cos(respawnAngle) * respawnDist,
					unit.Archetype.BodySize.Y * 0.5 + 0.5,
					playerPos.Z + math.sin(respawnAngle) * respawnDist
				)
				local snappedPos, snappedHeading = findRoadSnapSpawn(rawRespawnPos, playerPos, unit.Archetype.BodySize)
				unitPos = snappedPos
				unit.Heading = snappedHeading
				toPlayer = Vector3.new(playerPos.X - unitPos.X, 0, playerPos.Z - unitPos.Z)
				dist = toPlayer.Magnitude
			end

			if dist <= LINE_OF_SIGHT_RANGE then
				anyCopInLineOfSight = true
			end

			-- Stunned spin-out state after glancing hit (still prevented from entering buildings)
			if unit.StunTimer > 0 then
				unit.StunTimer = math.max(0, unit.StunTimer - dt)
				unit.Heading += dt * 4.5
				local coastFwd = Vector3.new(-math.sin(unit.Heading), 0, -math.cos(unit.Heading))
				local coastStep = unit.Archetype.Speed * 0.25 * dt
				local nextPos = unitPos + coastFwd * coastStep
				local blocked = checkBuildingOverlapAt(nextPos, unit.Heading, unit.Archetype.BodySize)
				if blocked then
					nextPos = unitPos
				end
				updateCopModelTransform(unit, nextPos, unit.Heading, (nextPos - unitPos).Magnitude)
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

			-- Smart Road Waypoint Navigation: if a building blocks line-of-sight to seekTarget,
			-- steer toward the nearest clear Road Intersection / Boulevard corridor leading to player
			local steerTarget = selectRoadWaypointToward(unitPos, seekTarget)
			local toSeek = Vector3.new(steerTarget.X - unitPos.X, 0, steerTarget.Z - unitPos.Z)
			local desiredHeading = unit.Heading
			if toSeek.Magnitude > 0.1 then
				local desiredDir = toSeek.Unit
				desiredHeading = math.atan2(-desiredDir.X, -desiredDir.Z)
			end

			-- 5-Ray Forward Feeler Obstacle Avoidance (0°, -25°, +25°, -55°, +55° up to 26 studs at Y = 2.5)
			refreshObstacleFilters()
			local feelerOrigin = Vector3.new(unitPos.X, BUMPER_RAY_Y, unitPos.Z)
			local centerOrInnerBlocked = false
			local bestOpenHeading = desiredHeading
			local bestOpenScore = -math.huge

			for rayIdx, angleOffset in ipairs(FEELER_ANGLES_RAD) do
				local rayHeading = unit.Heading + angleOffset
				local rayDir = Vector3.new(-math.sin(rayHeading), 0, -math.cos(rayHeading))
				local rayHit = Workspace:Raycast(feelerOrigin, rayDir * FEELER_RAY_LENGTH, obstacleRayParams)
				local clearDist = if rayHit then (rayHit.Position - feelerOrigin).Magnitude else FEELER_RAY_LENGTH
				if rayHit and rayIdx <= 3 then
					centerOrInnerBlocked = true
				end

				-- Score candidate feeler directions by open distance and alignment with desiredHeading
				local headingDiff = math.abs(math.atan2(math.sin(rayHeading - desiredHeading), math.cos(rayHeading - desiredHeading)))
				local score = clearDist * 2.2 - headingDiff * 5.0
				if score > bestOpenScore then
					bestOpenScore = score
					bestOpenHeading = rayHeading
				end
			end

			local turnRateMultiplier = 1.0
			local avoidanceSpeedScale = 1.0
			if centerOrInnerBlocked then
				-- Also sample wide escape angles (-85°, +85°) in case all 5 forward feelers face a wide wall
				for _, wideOffset in ipairs({ math.rad(-85), math.rad(85) }) do
					local wideHeading = unit.Heading + wideOffset
					local wideDir = Vector3.new(-math.sin(wideHeading), 0, -math.cos(wideHeading))
					local wideHit = Workspace:Raycast(feelerOrigin, wideDir * FEELER_RAY_LENGTH, obstacleRayParams)
					local clearDist = if wideHit then (wideHit.Position - feelerOrigin).Magnitude else FEELER_RAY_LENGTH
					local headingDiff = math.abs(math.atan2(math.sin(wideHeading - desiredHeading), math.cos(wideHeading - desiredHeading)))
					local score = clearDist * 2.1 - headingDiff * 4.0
					if score > bestOpenScore then
						bestOpenScore = score
						bestOpenHeading = wideHeading
					end
				end
				desiredHeading = bestOpenHeading
				turnRateMultiplier = 2.65
				avoidanceSpeedScale = 0.78
			end

			local deltaAngle = math.atan2(math.sin(desiredHeading - unit.Heading), math.cos(desiredHeading - unit.Heading))
			local maxStep = unit.Archetype.TurnRate * turnRateMultiplier * (1 + (stars - 1) * 0.05) * dt
			unit.Heading += math.clamp(deltaAngle, -maxStep, maxStep)

			local moveFwd = Vector3.new(-math.sin(unit.Heading), 0, -math.cos(unit.Heading))
			local speedBoost = (1.0 + (stars - 1) * 0.04) * avoidanceSpeedScale
			-- Slight ram burst when closing in at Star 2+
			if not centerOrInnerBlocked and stars >= 2 and dist < 38 and dist > 9 then
				speedBoost *= (1.0 + 0.12 * unit.Archetype.RamAggression)
			end

			local stepDist = unit.Archetype.Speed * speedBoost * dt
			local targetY = unit.Archetype.BodySize.Y * 0.5 + 0.5
			local nextPos = Vector3.new(
				unitPos.X + moveFwd.X * stepDist,
				targetY,
				unitPos.Z + moveFwd.Z * stepDist
			)

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

			-- Hard Wall Collision Prevention:
			-- Cast a short sweep ray from unitPos to nextPos (+ 4 stud margin) and verify via GetPartBoundsInBox
			local moveVec = Vector3.new(nextPos.X - unitPos.X, 0, nextPos.Z - unitPos.Z)
			local moveLen = moveVec.Magnitude
			local sweepHit: RaycastResult? = nil
			if moveLen > 0.01 then
				local sweepDir = moveVec / moveLen
				local halfFrontExtent = unit.Archetype.BodySize.Z * 0.5
				sweepHit = Workspace:Raycast(
					feelerOrigin,
					sweepDir * (moveLen + halfFrontExtent + 4.0),
					obstacleRayParams
				)
			end
			local boxBlocked, hitBuildingPart = checkBuildingOverlapAt(nextPos, unit.Heading, unit.Archetype.BodySize)

			if sweepHit or boxBlocked then
				local wallNormal: Vector3
				if sweepHit then
					local flatN = Vector3.new(sweepHit.Normal.X, 0, sweepHit.Normal.Z)
					wallNormal = if flatN.Magnitude > 0.01 then flatN.Unit else -moveFwd
				elseif hitBuildingPart then
					wallNormal = computeOutwardNormalFromPart(unitPos, hitBuildingPart)
				else
					wallNormal = -moveFwd
				end

				-- Pick the wall tangent pointing toward steerTarget / open road
				local tangentA = Vector3.new(-wallNormal.Z, 0, wallNormal.X)
				local tangentB = -tangentA
				local toGoal = Vector3.new(steerTarget.X - unitPos.X, 0, steerTarget.Z - unitPos.Z)
				local chosenTangent = if tangentA:Dot(toGoal) >= tangentB:Dot(toGoal) then tangentA else tangentB

				local slidePos = Vector3.new(
					unitPos.X + (chosenTangent.X * stepDist * 0.72) + wallNormal.X * 1.1,
					targetY,
					unitPos.Z + (chosenTangent.Z * stepDist * 0.72) + wallNormal.Z * 1.1
				)
				local slideHeading = math.atan2(-chosenTangent.X, -chosenTangent.Z)

				if not checkBuildingOverlapAt(slidePos, slideHeading, unit.Archetype.BodySize) then
					nextPos = slidePos
					unit.Heading = slideHeading
				else
					-- Try opposite tangent or push cleanly away from wall normal toward road
					local altSlidePos = Vector3.new(
						unitPos.X - (chosenTangent.X * stepDist * 0.65) + wallNormal.X * 1.5,
						targetY,
						unitPos.Z - (chosenTangent.Z * stepDist * 0.65) + wallNormal.Z * 1.5
					)
					local altHeading = math.atan2(chosenTangent.X, chosenTangent.Z)
					if not checkBuildingOverlapAt(altSlidePos, altHeading, unit.Archetype.BodySize) then
						nextPos = altSlidePos
						unit.Heading = altHeading
					else
						local pushOutPos = Vector3.new(
							unitPos.X + wallNormal.X * 2.2,
							targetY,
							unitPos.Z + wallNormal.Z * 2.2
						)
						if not checkBuildingOverlapAt(pushOutPos, slideHeading, unit.Archetype.BodySize) then
							nextPos = pushOutPos
						else
							nextPos = unitPos
						end
						unit.Heading = slideHeading
					end
				end
			end

			local actualStep = (nextPos - unitPos).Magnitude
			updateCopModelTransform(unit, nextPos, unit.Heading, actualStep)
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

			if state.HeatStars <= 0 then
				-- Player successfully evaded the pursuit! Reset warning gauge and award Escape Bounty!
				state.TotalHeat = 0
				state.PursuitDispatchPending = false
				state.PursuitDispatchReadyAt = 0
				local escapeBounty = math.max(150, prevStars * 175)
				clearAllPursuitAssets(state)
				syncHeatAttributes(player, state)
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
