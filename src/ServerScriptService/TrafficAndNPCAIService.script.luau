--!strict
-- TrafficAndNPCAIService.script.luau
-- Manages Leo City's living, chaotic ambient world:
-- 1. Synchronized intersection traffic light cycling (Green -> Yellow -> Red) with orthogonal NS/EW phases.
-- 2. 32 Autonomous AI traffic vehicles (Yellow Taxis, City Transit Buses, Delivery Vans, Fuel Tankers,
--    Police Patrols, and Sports Cars) driving along 4-lane sunlit avenues, obeying traffic lights until hit
--    or panicked by nearby chaos/explosions, then swerving and fleeing at high speed!
-- 3. 45 Lively NPC city characters with distinct roles (Hotdog Chef, Business Executive, Construction Worker,
--    Street Skater, Tourist, Jogger), periodic ambient city chatter bubbles, and dramatic comical panic leaps
--    + funny reaction callouts whenever a player speeds past or smashes nearby props!

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- WAIT FOR CITY & CONFIG
--------------------------------------------------------------------------------
local BLOCK_SIZE = (Workspace:GetAttribute("LeoCityBlockSize") :: number?) or 200
local ROAD_WIDTH = (Workspace:GetAttribute("LeoCityRoadWidth") :: number?) or 42
local GRID_RADIUS = (Workspace:GetAttribute("LeoCityGridRadius") :: number?) or 4
local LANE_OFFSET = 9.5
local SIDEWALK_OFFSET = ROAD_WIDTH * 0.5 + 6.5

local AIFolder = Instance.new("Folder")
AIFolder.Name = "LeoCityAI"
AIFolder.Parent = Workspace

local TrafficFolder = Instance.new("Folder")
TrafficFolder.Name = "AITraffic"
TrafficFolder.Parent = AIFolder

local PedestriansFolder = Instance.new("Folder")
PedestriansFolder.Name = "AIPedestrians"
PedestriansFolder.Parent = AIFolder

local roadCoords: { number } = {}
for i = -GRID_RADIUS - 1, GRID_RADIUS do
	table.insert(roadCoords, (i + 0.5) * BLOCK_SIZE)
end
local CITY_LIMIT = (GRID_RADIUS + 1) * BLOCK_SIZE - 15

--------------------------------------------------------------------------------
-- 1. SYNCHRONIZED TRAFFIC LIGHT CYCLING (GREEN -> YELLOW -> RED)
--------------------------------------------------------------------------------
local nsPhase = "Green"
local ewPhase = "Red"

local function applyTrafficLightVisuals(model: Instance, state: string)
	if model:GetAttribute("Destroyed") == true then
		return
	end
	model:SetAttribute("LightState", state)
	local red = model:FindFirstChild("RedLens") :: BasePart?
	local yellow = model:FindFirstChild("YellowLens") :: BasePart?
	local green = model:FindFirstChild("GreenLens") :: BasePart?

	if red then
		red.Material = if state == "Red" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		red.Color = if state == "Red" then Color3.fromRGB(255, 50, 50) else Color3.fromRGB(95, 25, 25)
	end
	if yellow then
		yellow.Material = if state == "Yellow" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		yellow.Color = if state == "Yellow" then Color3.fromRGB(255, 210, 40) else Color3.fromRGB(95, 80, 20)
	end
	if green then
		green.Material = if state == "Green" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		green.Color = if state == "Green" then Color3.fromRGB(45, 255, 95) else Color3.fromRGB(20, 85, 35)
	end
end

local function updateAllTrafficLights()
	Workspace:SetAttribute("TrafficPhaseNS", nsPhase)
	Workspace:SetAttribute("TrafficPhaseEW", ewPhase)
	for _, light in ipairs(CollectionService:GetTagged("TrafficLight")) do
		local axis = (light:GetAttribute("TrafficAxis") :: string?) or "NS"
		applyTrafficLightVisuals(light, if axis == "NS" then nsPhase else ewPhase)
	end
end

task.spawn(function()
	while true do
		nsPhase, ewPhase = "Green", "Red"
		updateAllTrafficLights()
		task.wait(7.0)

		nsPhase, ewPhase = "Yellow", "Red"
		updateAllTrafficLights()
		task.wait(2.0)

		nsPhase, ewPhase = "Red", "Green"
		updateAllTrafficLights()
		task.wait(7.0)

		nsPhase, ewPhase = "Red", "Yellow"
		updateAllTrafficLights()
		task.wait(2.0)
	end
end)

--------------------------------------------------------------------------------
-- 2. AUTONOMOUS AI TRAFFIC VEHICLES (32 DIVERSE CITY VEHICLES)
--------------------------------------------------------------------------------
type AICar = {
	model: Model,
	primary: BasePart,
	vehicleRole: string,
	axis: string, -- "NS" or "EW"
	dir: number, -- 1 or -1
	roadLine: number,
	posAlong: number,
	baseSpeed: number,
	currentSpeed: number,
	panicTimer: number,
	swerveAngle: number,
	smashed: boolean,
}

local aiCars: { AICar } = {}

local VEHICLE_TYPES = {
	"YellowTaxi",
	"CityTransitBus",
	"DeliveryVan",
	"FuelTanker",
	"PolicePatrol",
	"SportsCar",
}

local SPORTS_CAR_COLORS = {
	Color3.fromRGB(235, 45, 55),
	Color3.fromRGB(45, 165, 255),
	Color3.fromRGB(255, 145, 30),
	Color3.fromRGB(90, 235, 120),
	Color3.fromRGB(185, 75, 245),
}

local function addCarPart(
	parentModel: Model,
	className: string,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape and p:IsA("Part") then
		p.Shape = shape
	end
	p.Parent = parentModel
	return p
end

local function addSurfaceLabel(part: BasePart, text: string, textColor: Color3, face: Enum.NormalId)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.LightInfluence = 0
	sg.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = textColor
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextStrokeTransparency = 0.25
	lbl.Parent = sg
end

local function buildTrafficVehicleByType(vehicleType: string, idx: number): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "AI_" .. vehicleType

	local color = Color3.fromRGB(240, 190, 40)
	local chassisLen = 12.6
	local chassisWidth = 6.0
	local cashVal = 95
	local chaosPts = 70
	local breakThresh = 26
	local explosive = false

	if vehicleType == "YellowTaxi" then
		color = Color3.fromRGB(250, 200, 38)
	elseif vehicleType == "CityTransitBus" then
		color = Color3.fromRGB(48, 138, 232)
		chassisLen = 18.5
		chassisWidth = 6.8
		cashVal = 165
		chaosPts = 115
		breakThresh = 32
	elseif vehicleType == "DeliveryVan" then
		color = Color3.fromRGB(242, 244, 248)
		chassisLen = 14.2
		chassisWidth = 6.2
		cashVal = 120
		chaosPts = 85
	elseif vehicleType == "FuelTanker" then
		color = Color3.fromRGB(228, 52, 42)
		chassisLen = 17.5
		chassisWidth = 6.6
		cashVal = 240
		chaosPts = 175
		breakThresh = 22
		explosive = true
	elseif vehicleType == "PolicePatrol" then
		color = Color3.fromRGB(28, 34, 48)
		cashVal = 145
		chaosPts = 105
	else
		color = SPORTS_CAR_COLORS[(idx % #SPORTS_CAR_COLORS) + 1]
		cashVal = 135
		chaosPts = 90
	end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(chassisWidth, 1.5, chassisLen)
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = true
	chassis.CanCollide = true
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = m

	local baseCF = chassis.CFrame
	local trimColor = Color3.fromRGB(30, 34, 42)
	local glassColor = Color3.fromRGB(72, 145, 205)
	local halfZ = chassisLen * 0.5

	if vehicleType == "CityTransitBus" then
		local busBody = addCarPart(m, "Part", "BusCoachBody", Vector3.new(chassisWidth, 5.4, chassisLen - 0.4), baseCF * CFrame.new(0, 3.1, 0), color, Enum.Material.SmoothPlastic)
		addCarPart(m, "Part", "BusRoofStripe", Vector3.new(chassisWidth + 0.1, 0.8, chassisLen - 0.6), baseCF * CFrame.new(0, 5.4, 0), Color3.fromRGB(245, 248, 255), Enum.Material.SmoothPlastic)
		addCarPart(m, "Part", "BusWindows", Vector3.new(chassisWidth + 0.16, 2.1, chassisLen - 3.2), baseCF * CFrame.new(0, 3.6, 0.2), glassColor, Enum.Material.Glass, 0.2)
		addCarPart(m, "Part", "BusWindshield", Vector3.new(chassisWidth - 0.6, 2.4, 0.3), baseCF * CFrame.new(0, 3.5, -halfZ + 0.15), glassColor, Enum.Material.Glass, 0.18)
		addSurfaceLabel(busBody, "LEO METRO TRANSIT", Color3.fromRGB(255, 235, 85), Enum.NormalId.Left)
		addSurfaceLabel(busBody, "LEO METRO TRANSIT", Color3.fromRGB(255, 235, 85), Enum.NormalId.Right)
	elseif vehicleType == "DeliveryVan" then
		addCarPart(m, "Part", "CabFront", Vector3.new(chassisWidth - 0.2, 2.8, 4.4), baseCF * CFrame.new(0, 1.8, -halfZ + 2.4), color, Enum.Material.SmoothPlastic)
		addCarPart(m, "WedgePart", "Windshield", Vector3.new(chassisWidth - 0.6, 1.8, 1.6), baseCF * CFrame.new(0, 2.1, -halfZ + 1.0), glassColor, Enum.Material.Glass, 0.2)
		local cargoBox = addCarPart(m, "Part", "CargoBox", Vector3.new(chassisWidth + 0.2, 4.4, chassisLen - 4.8), baseCF * CFrame.new(0, 2.7, 2.1), Color3.fromRGB(248, 246, 240), Enum.Material.SmoothPlastic)
		addCarPart(m, "Part", "AccentStripe", Vector3.new(chassisWidth + 0.28, 0.65, chassisLen - 5.0), baseCF * CFrame.new(0, 2.4, 2.1), Color3.fromRGB(255, 142, 35), Enum.Material.SmoothPlastic)
		addSurfaceLabel(cargoBox, "MEGACORP EXPRESS", Color3.fromRGB(235, 65, 45), Enum.NormalId.Left)
		addSurfaceLabel(cargoBox, "MEGACORP EXPRESS", Color3.fromRGB(235, 65, 45), Enum.NormalId.Right)
	elseif vehicleType == "FuelTanker" then
		addCarPart(m, "Part", "TruckCab", Vector3.new(chassisWidth - 0.2, 3.6, 4.8), baseCF * CFrame.new(0, 2.2, -halfZ + 2.6), Color3.fromRGB(230, 52, 42), Enum.Material.Metal)
		addCarPart(m, "Part", "CabWindshield", Vector3.new(chassisWidth - 0.8, 1.6, 0.3), baseCF * CFrame.new(0, 2.8, -halfZ + 0.25), glassColor, Enum.Material.Glass, 0.2)
		local tank = addCarPart(
			m,
			"Part",
			"FuelTankCylinder",
			Vector3.new(chassisLen - 5.6, 5.4, 5.4),
			baseCF * CFrame.new(0, 3.1, 2.4) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(235, 238, 245),
			Enum.Material.Metal,
			0,
			Enum.PartType.Cylinder
		)
		addCarPart(m, "Part", "HazardStripe", Vector3.new(chassisWidth + 0.1, 0.9, chassisLen - 5.8), baseCF * CFrame.new(0, 3.1, 2.4), Color3.fromRGB(255, 195, 35), Enum.Material.Neon)
		addSurfaceLabel(tank, "BOOM FUEL - EXPLOSIVE", Color3.fromRGB(225, 35, 35), Enum.NormalId.Top)
	else
		-- Sedan / YellowTaxi / PolicePatrol / SportsCar
		addCarPart(m, "Part", "BodyBeltline", Vector3.new(6.1, 0.85, 7.6), baseCF * CFrame.new(0, 0.55, 0.15), color, Enum.Material.SmoothPlastic)
		addCarPart(m, "Part", "TrunkDeck", Vector3.new(5.8, 0.68, 2.4), baseCF * CFrame.new(0, 0.56, 4.95), color, Enum.Material.SmoothPlastic)
		addCarPart(m, "WedgePart", "SlopedHood", Vector3.new(5.8, 0.78, 3.6), baseCF * CFrame.new(0, 0.62, -4.30), color, Enum.Material.SmoothPlastic)
		addCarPart(m, "Part", "Cabin", Vector3.new(5.3, 1.65, 4.4), baseCF * CFrame.new(0, 1.62, 0.10), glassColor, Enum.Material.Glass, 0.25)
		local roofColor = if vehicleType == "PolicePatrol" then Color3.fromRGB(245, 248, 255) else color
		addCarPart(m, "Part", "RoofCap", Vector3.new(5.36, 0.22, 4.35), baseCF * CFrame.new(0, 2.50, 0.10), roofColor, Enum.Material.SmoothPlastic)
		addCarPart(m, "WedgePart", "Windshield", Vector3.new(5.2, 1.58, 1.75), baseCF * CFrame.new(0, 1.60, -2.95), glassColor, Enum.Material.Glass, 0.20)
		addCarPart(
			m,
			"WedgePart",
			"RearWindow",
			Vector3.new(5.1, 1.48, 1.45),
			baseCF * CFrame.new(0, 1.56, 3.00) * CFrame.Angles(0, math.rad(180), 0),
			glassColor,
			Enum.Material.Glass,
			0.25
		)

		if vehicleType == "YellowTaxi" then
			addCarPart(m, "Part", "TaxiSign", Vector3.new(2.2, 0.65, 1.0), baseCF * CFrame.new(0, 2.92, -0.2), Color3.fromRGB(255, 225, 75), Enum.Material.Neon)
			addCarPart(m, "Part", "TaxiSideStripe", Vector3.new(6.16, 0.22, 7.4), baseCF * CFrame.new(0, 0.45, 0.15), Color3.fromRGB(24, 26, 32), Enum.Material.SmoothPlastic)
		elseif vehicleType == "PolicePatrol" then
			addCarPart(m, "Part", "PoliceDoors", Vector3.new(6.18, 0.82, 4.2), baseCF * CFrame.new(0, 0.55, 0.1), Color3.fromRGB(245, 248, 255), Enum.Material.SmoothPlastic)
			addCarPart(m, "Part", "SirenBarRed", Vector3.new(2.1, 0.42, 0.75), baseCF * CFrame.new(-1.1, 2.82, -0.1), Color3.fromRGB(255, 42, 42), Enum.Material.Neon)
			addCarPart(m, "Part", "SirenBarBlue", Vector3.new(2.1, 0.42, 0.75), baseCF * CFrame.new(1.1, 2.82, -0.1), Color3.fromRGB(45, 135, 255), Enum.Material.Neon)
		elseif vehicleType == "SportsCar" then
			addCarPart(m, "Part", "RearSpoilerWing", Vector3.new(5.6, 0.25, 1.1), baseCF * CFrame.new(0, 1.45, 5.75), Color3.fromRGB(28, 32, 40), Enum.Material.Metal)
			addCarPart(m, "Part", "RacingStripe", Vector3.new(1.1, 0.88, 12.2), baseCF * CFrame.new(0, 0.62, 0), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic)
		end
	end

	-- Bumpers, Headlights, Taillights & 4 Wheels
	addCarPart(m, "Part", "FrontBumper", Vector3.new(chassisWidth + 0.2, 0.62, 0.62), baseCF * CFrame.new(0, -0.32, -halfZ - 0.1), trimColor, Enum.Material.Metal)
	addCarPart(m, "Part", "RearBumper", Vector3.new(chassisWidth + 0.2, 0.62, 0.62), baseCF * CFrame.new(0, -0.32, halfZ + 0.1), trimColor, Enum.Material.Metal)
	addCarPart(m, "Part", "Headlights", Vector3.new(chassisWidth - 0.8, 0.42, 0.18), baseCF * CFrame.new(0, 0.24, -halfZ - 0.05), Color3.fromRGB(255, 245, 200), Enum.Material.Neon)
	addCarPart(m, "Part", "Taillights", Vector3.new(chassisWidth - 0.8, 0.36, 0.18), baseCF * CFrame.new(0, 0.24, halfZ + 0.05), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)

	local wheelZ = halfZ - 2.45
	local wheelX = chassisWidth * 0.5 - 0.08
	local wheelSpecs = {
		{ Name = "WheelFL", X = -wheelX, Z = -wheelZ },
		{ Name = "WheelFR", X = wheelX, Z = -wheelZ },
		{ Name = "WheelRL", X = -wheelX, Z = wheelZ },
		{ Name = "WheelRR", X = wheelX, Z = wheelZ },
	}
	for _, ws in ipairs(wheelSpecs) do
		local wCF = baseCF * CFrame.new(ws.X, -0.55, ws.Z)
		addCarPart(m, "Part", ws.Name, Vector3.new(1.10, 2.50, 2.50), wCF, Color3.fromRGB(22, 24, 28), Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
		addCarPart(m, "Part", ws.Name .. "_Hubcap", Vector3.new(1.22, 1.44, 1.44), wCF, Color3.fromRGB(198, 206, 220), Enum.Material.Metal, 0, Enum.PartType.Cylinder)
	end

	for _, desc in ipairs(m:GetChildren()) do
		if desc:IsA("BasePart") and desc ~= chassis then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = chassis
			wc.Part1 = desc
			wc.Parent = chassis
			desc.Anchored = false
		end
	end

	m.PrimaryPart = chassis
	m:SetAttribute("PropType", "TrafficVehicle")
	m:SetAttribute("DestructibleType", vehicleType)
	m:SetAttribute("IsDestructible", true)
	m:SetAttribute("CashValue", cashVal)
	m:SetAttribute("CashReward", cashVal)
	m:SetAttribute("ChaosPoints", chaosPts)
	m:SetAttribute("BreakThreshold", breakThresh)
	m:SetAttribute("Explosive", explosive)
	CollectionService:AddTag(m, "AITrafficVehicle")
	CollectionService:AddTag(m, "Destructible")
	m.Parent = TrafficFolder

	return m, chassis
end

local function computeCarCFrame(car: AICar): CFrame
	local laneShift = car.dir * LANE_OFFSET
	if car.axis == "NS" then
		local x = car.roadLine - laneShift
		local z = car.posAlong
		local yaw = if car.dir > 0 then math.pi else 0
		return CFrame.new(x, 1.8, z) * CFrame.Angles(0, yaw + car.swerveAngle, 0)
	else
		local z = car.roadLine + laneShift
		local x = car.posAlong
		local yaw = if car.dir > 0 then -math.pi * 0.5 else math.pi * 0.5
		return CFrame.new(x, 1.8, z) * CFrame.Angles(0, yaw + car.swerveAngle, 0)
	end
end

local function spawnTrafficCars(count: number)
	for i = 1, count do
		local vType = VEHICLE_TYPES[((i - 1) % #VEHICLE_TYPES) + 1]
		local model, primary = buildTrafficVehicleByType(vType, i)

		local axis = if i % 2 == 0 then "NS" else "EW"
		local dir = if (i % 4 < 2) then 1 else -1
		local roadLine = roadCoords[((i - 1) % #roadCoords) + 1]
		local posAlong = -CITY_LIMIT + ((i * 97) % (CITY_LIMIT * 2))

		local speedByRole = if vType == "SportsCar"
			then 48
			elseif vType == "PolicePatrol" then 44
			elseif vType == "CityTransitBus" or vType == "FuelTanker" then 30
			else 36

		local car: AICar = {
			model = model,
			primary = primary,
			vehicleRole = vType,
			axis = axis,
			dir = dir,
			roadLine = roadLine,
			posAlong = posAlong,
			baseSpeed = speedByRole + (i % 4) * 2,
			currentSpeed = speedByRole,
			panicTimer = 0,
			swerveAngle = 0,
			smashed = false,
		}
		primary.CFrame = computeCarCFrame(car)

		-- React if hit by a player vehicle
		primary.Touched:Connect(function(hit: BasePart)
			if not hit.Anchored and hit.AssemblyLinearVelocity.Magnitude > 22 and not hit:IsDescendantOf(model) then
				car.panicTimer = 7.0
				car.swerveAngle = (math.random() - 0.5) * 0.45
			end
		end)

		table.insert(aiCars, car)
	end
end

local trafficRayParams = RaycastParams.new()
trafficRayParams.FilterType = Enum.RaycastFilterType.Exclude
trafficRayParams.IgnoreWater = true
trafficRayParams.RespectCanCollide = true

local FORWARD_CHECK_DIST = 34.0
local MIN_STOP_GAP = 8.0

local function computeForwardSpacingFactor(car: AICar, playerRoots: { BasePart }): number
	local cf = car.primary.CFrame
	local forwardVec = cf.LookVector
	local rightVec = cf.RightVector
	local frontBumperPos = cf.Position + forwardVec * 6.5 + Vector3.new(0, 0.35, 0)

	trafficRayParams.FilterDescendantsInstances = { car.model, PedestriansFolder }

	local minGap = FORWARD_CHECK_DIST
	for _, lateralOffset in ipairs({ 0, -2.1, 2.1 }) do
		local rayOrigin = frontBumperPos + rightVec * lateralOffset
		local hit = Workspace:Raycast(rayOrigin, forwardVec * FORWARD_CHECK_DIST, trafficRayParams)
		if hit then
			local d = (hit.Position - rayOrigin).Magnitude
			if d < minGap then
				minGap = d
			end
		end
	end

	for _, other in ipairs(aiCars) do
		if other ~= car and not other.smashed and other.axis == car.axis and other.roadLine == car.roadLine and other.dir == car.dir then
			local centerGap = (other.posAlong - car.posAlong) * car.dir
			if centerGap > 0 then
				local bumperGap = math.max(0, centerGap - 15.0)
				if bumperGap < minGap then
					minGap = bumperGap
				end
			end
		end
	end

	for _, root in ipairs(playerRoots) do
		local rel = root.Position - frontBumperPos
		local flatRel = Vector3.new(rel.X, 0, rel.Z)
		local forwardDist = flatRel:Dot(forwardVec)
		local lateralDist = math.abs(flatRel:Dot(rightVec))
		if forwardDist > -3.0 and forwardDist < FORWARD_CHECK_DIST and lateralDist < 5.8 then
			local effGap = math.max(0, forwardDist - 4.5)
			if effGap < minGap then
				minGap = effGap
			end
		end
	end

	if minGap <= MIN_STOP_GAP then
		return 0
	elseif minGap < FORWARD_CHECK_DIST then
		return math.clamp((minGap - MIN_STOP_GAP) / (FORWARD_CHECK_DIST - MIN_STOP_GAP), 0, 1)
	end
	return 1.0
end

local function shouldStopForRedLight(car: AICar): boolean
	if car.panicTimer > 0 then
		return false -- Panicked drivers blow through red lights!
	end
	local phase = if car.axis == "NS" then nsPhase else ewPhase
	if phase == "Green" then
		return false
	end

	for _, interCoord in ipairs(roadCoords) do
		local distAhead = (interCoord - car.posAlong) * car.dir
		if distAhead > 18 and distAhead < 42 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- 3. 45 LIVELY CITY CHARACTERS (ROLES, AMBIENT CHATTER & COMICAL PANIC LEAPS)
--------------------------------------------------------------------------------
type NPCRoleSpec = {
	role: string,
	torsoColor: Color3,
	legsColor: Color3,
	hatColor: Color3?,
	walkSpeed: number,
	chatterLines: { string },
	panicLines: { string },
}

local NPC_ROLES: { NPCRoleSpec } = {
	{
		role = "HotdogChef",
		torsoColor = Color3.fromRGB(245, 245, 250),
		legsColor = Color3.fromRGB(48, 52, 64),
		hatColor = Color3.fromRGB(255, 255, 255),
		walkSpeed = 7.2,
		chatterLines = {
			"Best hotdogs in Leo City!",
			"Fresh street tacos, two bucks!",
			"Extra mustard on that!",
		},
		panicLines = {
			"MY TACOS!!",
			"NOT THE HOTDOG CART!!",
			"WATCH THE GRILL!",
		},
	},
	{
		role = "BusinessExecutive",
		torsoColor = Color3.fromRGB(38, 52, 82),
		legsColor = Color3.fromRGB(28, 36, 54),
		hatColor = nil,
		walkSpeed = 8.4,
		chatterLines = {
			"Late for my meeting at Leo Tower!",
			"MegaCorp stocks are through the roof!",
			"Where is my yellow cab?!",
		},
		panicLines = {
			"WATCH THE SUIT!",
			"CALL THE MAYOR!",
			"MY BRIEFCASE!!",
		},
	},
	{
		role = "ConstructionWorker",
		torsoColor = Color3.fromRGB(255, 145, 30),
		legsColor = Color3.fromRGB(52, 78, 128),
		hatColor = Color3.fromRGB(255, 210, 35),
		walkSpeed = 7.8,
		chatterLines = {
			"Careful around the blast zone!",
			"We just rebuilt that hydrant!",
			"Coffee break at Sunset Cafe!",
		},
		panicLines = {
			"HARD HAT ON!!",
			"WE JUST PAVED THAT!",
			"TIMBER!!",
		},
	},
	{
		role = "StreetSkater",
		torsoColor = Color3.fromRGB(195, 52, 235),
		legsColor = Color3.fromRGB(42, 46, 55),
		hatColor = Color3.fromRGB(45, 225, 210),
		walkSpeed = 11.2,
		chatterLines = {
			"Did you hear that V8?!",
			"Hit the Plaza Mega-Ramp!",
			"Leo City is wild today!",
		},
		panicLines = {
			"RADICAL JUMP!",
			"SICK DRIFT BRO!",
			"WHOA FULL SEND!!",
		},
	},
	{
		role = "Tourist",
		torsoColor = Color3.fromRGB(52, 198, 165),
		legsColor = Color3.fromRGB(225, 205, 168),
		hatColor = Color3.fromRGB(245, 215, 135),
		walkSpeed = 7.4,
		chatterLines = {
			"Look at the top of Leo Tower!",
			"The boardwalk beach is gorgeous!",
			"Smile for the vacation photo!",
		},
		panicLines = {
			"GET THAT ON CAMERA!",
			"CALL THE MAYOR!",
			"WHAT A STUNT!!",
		},
	},
	{
		role = "Jogger",
		torsoColor = Color3.fromRGB(245, 75, 115),
		legsColor = Color3.fromRGB(35, 38, 46),
		hatColor = Color3.fromRGB(255, 230, 55),
		walkSpeed = 10.6,
		chatterLines = {
			"Nothing beats a sunny Leo City run!",
			"Ten thousand steps before noon!",
			"Out of the way, hitting my stride!",
		},
		panicLines = {
			"CARDIO SAVED MY LIFE!",
			"WATCH THE CROSSWALK!",
			"LEAP OF FAITH!!",
		},
	},
}

type AIPed = {
	model: Model,
	root: BasePart,
	roleSpec: NPCRoleSpec,
	bubbleGui: BillboardGui,
	bubbleLabel: TextLabel,
	axis: string,
	dir: number,
	roadLine: number,
	side: number,
	posAlong: number,
	walkSpeed: number,
	dodgeCooldown: number,
	chatterTimer: number,
	leapOffset: Vector3,
	phase: number,
}

local aiPeds: { AIPed } = {}

local function buildPedestrian(idx: number): AIPed
	local roleSpec = NPC_ROLES[((idx - 1) % #NPC_ROLES) + 1]
	local m = Instance.new("Model")
	m.Name = "Citizen_" .. roleSpec.role
	m:SetAttribute("NPCRole", roleSpec.role)

	local root = Instance.new("Part")
	root.Name = "Torso"
	root.Size = Vector3.new(2.0, 2.6, 1.1)
	root.Color = roleSpec.torsoColor
	root.Material = Enum.Material.SmoothPlastic
	root.Anchored = true
	root.CanCollide = false
	root.Parent = m

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.5, 1.5, 1.5)
	head.CFrame = root.CFrame * CFrame.new(0, 2.0, 0)
	head.Color = Color3.fromRGB(240, 198, 160)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Anchored = false
	head.Parent = m

	local legs = Instance.new("Part")
	legs.Name = "Legs"
	legs.Size = Vector3.new(1.8, 2.2, 1.0)
	legs.CFrame = root.CFrame * CFrame.new(0, -2.4, 0)
	legs.Color = roleSpec.legsColor
	legs.Material = Enum.Material.SmoothPlastic
	legs.CanCollide = false
	legs.Anchored = false
	legs.Parent = m

	local partsToWeld: { BasePart } = { head, legs }

	if roleSpec.hatColor then
		local hat = Instance.new("Part")
		hat.Name = "AccessoryHat"
		hat.Size = if roleSpec.role == "HotdogChef"
			then Vector3.new(1.5, 1.2, 1.5)
			else Vector3.new(1.7, 0.55, 1.8)
		hat.CFrame = root.CFrame * CFrame.new(0, 2.85, 0)
		hat.Color = roleSpec.hatColor
		hat.Material = Enum.Material.SmoothPlastic
		hat.CanCollide = false
		hat.Anchored = false
		hat.Parent = m
		table.insert(partsToWeld, hat)
	end

	for _, part in ipairs(partsToWeld) do
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = root
		wc.Part1 = part
		wc.Parent = root
	end

	-- Speech & Panic Callout Bubble UI
	local bb = Instance.new("BillboardGui")
	bb.Name = "AlertBubble"
	bb.Size = UDim2.fromOffset(175, 42)
	bb.StudsOffset = Vector3.new(0, 3.8, 0)
	bb.MaxDistance = 165
	bb.AlwaysOnTop = false
	bb.Enabled = false
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(255, 240, 75)
	lbl.BackgroundTransparency = 0.08
	lbl.Text = "!"
	lbl.TextColor3 = Color3.fromRGB(28, 32, 42)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = lbl

	m.PrimaryPart = root
	CollectionService:AddTag(m, "NPCPedestrian")
	m.Parent = PedestriansFolder

	local axis = if idx % 2 == 0 then "NS" else "EW"
	local dir = if idx % 3 == 0 then 1 else -1
	local roadLine = roadCoords[((idx - 1) % #roadCoords) + 1]
	local side = if idx % 4 < 2 then 1 else -1
	local posAlong = -CITY_LIMIT + ((idx * 67) % (CITY_LIMIT * 2))

	return {
		model = m,
		root = root,
		roleSpec = roleSpec,
		bubbleGui = bb,
		bubbleLabel = lbl,
		axis = axis,
		dir = dir,
		roadLine = roadLine,
		side = side,
		posAlong = posAlong,
		walkSpeed = roleSpec.walkSpeed,
		dodgeCooldown = 0,
		chatterTimer = 3.0 + (idx % 9) * 1.6,
		leapOffset = Vector3.zero,
		phase = idx * 1.1,
	}
end

local function showPedestrianChatter(ped: AIPed)
	if ped.dodgeCooldown > 0 then
		return
	end
	local lines = ped.roleSpec.chatterLines
	local line = lines[math.random(1, #lines)]
	ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
	ped.bubbleLabel.TextColor3 = Color3.fromRGB(28, 36, 52)
	ped.bubbleLabel.Text = line
	ped.bubbleGui.Enabled = true

	task.delay(3.2, function()
		if ped.dodgeCooldown <= 0 and ped.bubbleGui then
			ped.bubbleGui.Enabled = false
		end
	end)
end

local function triggerPedestrianDodge(ped: AIPed, threatPos: Vector3)
	if ped.dodgeCooldown > 0 then
		return
	end
	ped.dodgeCooldown = 3.4
	local panicLines = ped.roleSpec.panicLines
	ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(255, 225, 55)
	ped.bubbleLabel.TextColor3 = Color3.fromRGB(215, 25, 25)
	ped.bubbleLabel.Text = panicLines[math.random(1, #panicLines)]
	ped.bubbleGui.Enabled = true

	local away = (ped.root.Position - threatPos)
	local flatAway = Vector3.new(away.X, 0, away.Z)
	local dodgeDir = if flatAway.Magnitude > 0.1 then flatAway.Unit else Vector3.new(1, 0, 0)
	ped.leapOffset = dodgeDir * 8.5 + Vector3.new(0, 4.4, 0)

	task.delay(2.2, function()
		if ped.bubbleGui then
			ped.bubbleGui.Enabled = false
		end
	end)
end

local function spawnPedestrians(count: number)
	for i = 1, count do
		table.insert(aiPeds, buildPedestrian(i))
	end
end

--------------------------------------------------------------------------------
-- CHAOS / DESTRUCTION PANIC HOOK
--------------------------------------------------------------------------------
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
local DestructionBindable = ServerEvents and ServerEvents:FindFirstChild("DestructionOccurred") :: BindableEvent?
if DestructionBindable then
	DestructionBindable.Event:Connect(function(payload: { [string]: any })
		local pos: Vector3? = payload and payload.position
		if not pos then
			return
		end
		for _, car in ipairs(aiCars) do
			if not car.smashed and (car.primary.Position - pos).Magnitude < 95 then
				car.panicTimer = 8.0
				car.swerveAngle = (math.random() - 0.5) * 0.42
			end
		end
		for _, ped in ipairs(aiPeds) do
			if (ped.root.Position - pos).Magnitude < 75 then
				triggerPedestrianDodge(ped, pos)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- MAIN HEARTBEAT AI UPDATE LOOP
--------------------------------------------------------------------------------
spawnTrafficCars(32)
spawnPedestrians(45)

RunService.Heartbeat:Connect(function(dt: number)
	local clampedDt = math.min(dt, 0.1)

	-- Gather active player vehicle & character positions for threat and spacing detection
	local playerRoots: { BasePart } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart then
				table.insert(playerRoots, hum.SeatPart)
			else
				local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					table.insert(playerRoots, hrp)
				end
			end
		end
	end
	for _, folderName in ipairs({ "PlayerVehicles", "Vehicles" }) do
		local vf = Workspace:FindFirstChild(folderName)
		if vf then
			for _, vModel in ipairs(vf:GetChildren()) do
				if vModel:IsA("Model") then
					local prim = vModel.PrimaryPart or vModel:FindFirstChildWhichIsA("BasePart")
					if prim then
						table.insert(playerRoots, prim)
					end
				end
			end
		end
	end

	-- Update 32 AI Traffic Vehicles
	for _, car in ipairs(aiCars) do
		if car.model:GetAttribute("Destroyed") == true then
			if not car.smashed then
				car.smashed = true
				task.delay(16.0, function()
					if car.model and car.model.Parent then
						car.model:SetAttribute("Destroyed", false)
						car.primary.Anchored = true
						car.primary.Transparency = 0
						car.primary.CanCollide = true
						for _, d in ipairs(car.model:GetDescendants()) do
							if d:IsA("BasePart") then
								d.Transparency = 0
							end
						end
						car.posAlong = -CITY_LIMIT
						car.panicTimer = 0
						car.swerveAngle = 0
						car.smashed = false
					end
				end)
			end
			continue
		end

		if car.panicTimer > 0 then
			car.panicTimer = math.max(0, car.panicTimer - clampedDt)
			car.swerveAngle = math.sin(os.clock() * 7) * 0.22
		else
			car.swerveAngle = car.swerveAngle * math.max(0, 1 - clampedDt * 5)
		end

		local stop = shouldStopForRedLight(car)
		local spacingFactor = computeForwardSpacingFactor(car, playerRoots)
		local desiredCruise = if stop then 0 elseif car.panicTimer > 0 then car.baseSpeed * 1.75 else car.baseSpeed
		local targetSpeed = desiredCruise * spacingFactor
		local accelRate = if targetSpeed < car.currentSpeed then 14.0 else 6.0
		car.currentSpeed += (targetSpeed - car.currentSpeed) * math.min(1, clampedDt * accelRate)

		car.posAlong += car.dir * car.currentSpeed * clampedDt
		if car.posAlong > CITY_LIMIT then
			car.posAlong = -CITY_LIMIT
		elseif car.posAlong < -CITY_LIMIT then
			car.posAlong = CITY_LIMIT
		end

		car.primary.CFrame = computeCarCFrame(car)
	end

	-- Update 45 Sidewalk Pedestrians
	for _, ped in ipairs(aiPeds) do
		ped.phase += clampedDt * 8
		if ped.dodgeCooldown > 0 then
			ped.dodgeCooldown = math.max(0, ped.dodgeCooldown - clampedDt)
		end
		ped.leapOffset = ped.leapOffset:Lerp(Vector3.zero, math.min(1, clampedDt * 6))

		-- Periodic ambient city chatter when players are nearby
		ped.chatterTimer -= clampedDt
		if ped.chatterTimer <= 0 then
			ped.chatterTimer = 9.0 + math.random() * 8.0
			for _, hrp in ipairs(playerRoots) do
				if (hrp.Position - ped.root.Position).Magnitude < 110 then
					showPedestrianChatter(ped)
					break
				end
			end
		end

		-- Check for approaching fast player vehicles
		for _, hrp in ipairs(playerRoots) do
			local d = (hrp.Position - ped.root.Position).Magnitude
			if d < 36 and hrp.AssemblyLinearVelocity.Magnitude > 18 then
				triggerPedestrianDodge(ped, hrp.Position)
			end
		end

		local speedMult = if ped.dodgeCooldown > 1.5 then 2.4 else 1.0
		ped.posAlong += ped.dir * ped.walkSpeed * speedMult * clampedDt
		if ped.posAlong > CITY_LIMIT then
			ped.posAlong = -CITY_LIMIT
		elseif ped.posAlong < -CITY_LIMIT then
			ped.posAlong = CITY_LIMIT
		end

		local bob = math.abs(math.sin(ped.phase)) * 0.45
		local sway = math.sin(ped.phase) * 0.08
		local basePos: Vector3
		local yaw: number
		if ped.axis == "NS" then
			basePos = Vector3.new(ped.roadLine + ped.side * SIDEWALK_OFFSET, 3.5 + bob, ped.posAlong)
			yaw = if ped.dir > 0 then math.pi else 0
		else
			basePos = Vector3.new(ped.posAlong, 3.5 + bob, ped.roadLine + ped.side * SIDEWALK_OFFSET)
			yaw = if ped.dir > 0 then -math.pi * 0.5 else math.pi * 0.5
		end

		ped.root.CFrame = CFrame.new(basePos + ped.leapOffset) * CFrame.Angles(0, yaw, sway)
	end
end)

print("[TrafficAndNPCAIService] 32 AI vehicles and 45 lively city NPCs active.")
