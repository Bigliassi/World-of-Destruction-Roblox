--!strict
-- TrafficAndNPCAIService.script.luau
-- Manages Leo City's living, chaotic New York traffic and pedestrian world:
-- 1. Synchronized intersection traffic light cycling (Green -> Yellow -> Red) with orthogonal NS/EW phases.
-- 2. 36 Autonomous AI traffic vehicles (NYC Yellow Taxis, MTA City Buses, Delivery Vans, Fuel Tankers,
--    NYPD Patrols, and Sports Cars) welded with rigid C0/C1 Welds so they NEVER separate into planks!
-- 3. 48 Articulated NYC pedestrians with animated walking arm/leg swing cycles, chatter bubbles, and comical dodge leaps!

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- CITY GRID CONFIG (Standardized on 180-stud blocks)
--------------------------------------------------------------------------------
local BLOCK_SIZE = (Workspace:GetAttribute("LeoCityBlockSize") :: number?) or 180
local ROAD_WIDTH = (Workspace:GetAttribute("LeoCityRoadWidth") :: number?) or 38
local GRID_RADIUS = (Workspace:GetAttribute("LeoCityGridRadius") :: number?) or 3
local LANE_OFFSET = 9.0
local SIDEWALK_OFFSET = ROAD_WIDTH * 0.5 + 6.0

local existingAI = Workspace:FindFirstChild("LeoCityAI")
if existingAI then
	existingAI:Destroy()
end

local AIFolder = Instance.new("Folder")
AIFolder.Name = "LeoCityAI"
AIFolder.Parent = Workspace

local TrafficFolder = Instance.new("Folder")
TrafficFolder.Name = "AITraffic"
TrafficFolder.Parent = AIFolder

local PedestriansFolder = Instance.new("Folder")
PedestriansFolder.Name = "AIPedestrians"
PedestriansFolder.Parent = AIFolder

local roadCoords: { number } = { 0 }
for i = -GRID_RADIUS - 1, GRID_RADIUS do
	table.insert(roadCoords, (i + 0.5) * BLOCK_SIZE)
end
local CITY_LIMIT = (GRID_RADIUS + 1) * BLOCK_SIZE - 20

--------------------------------------------------------------------------------
-- RIGID WELD HELPER (Uses classic Weld C0 so moving PrimaryPart.CFrame ALWAYS moves all children!)
--------------------------------------------------------------------------------
local function weldToPrimary(primary: BasePart, child: BasePart, offsetCF: CFrame): Weld
	child.Anchored = false
	child.Massless = true
	child.CFrame = primary.CFrame * offsetCF
	local w = Instance.new("Weld")
	w.Name = child.Name .. "_Weld"
	w.Part0 = primary
	w.Part1 = child
	w.C0 = offsetCF
	w.Parent = child
	return w
end

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
-- 2. AUTONOMOUS AI TRAFFIC VEHICLES (36 NYC VEHICLES WITH RIGID WELDS)
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
	"YellowTaxi",
	"SportsCar",
	"DeliveryVan",
	"CityTransitBus",
	"FuelTanker",
}

local SPORTS_CAR_COLORS = {
	Color3.fromRGB(220, 38, 48),
	Color3.fromRGB(38, 135, 245),
	Color3.fromRGB(245, 135, 28),
	Color3.fromRGB(46, 195, 98),
	Color3.fromRGB(155, 65, 235),
}

local function addWeldedCarPart(
	parentModel: Model,
	primary: BasePart,
	className: string,
	name: string,
	size: Vector3,
	offsetCF: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape and p:IsA("Part") then
		p.Shape = shape
	end
	p.Parent = parentModel
	weldToPrimary(primary, p, offsetCF)
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

local function buildTrafficVehicleByType(vehicleType: string, idx: number, initialCF: CFrame): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "AI_" .. vehicleType

	local color = Color3.fromRGB(245, 192, 32)
	local chassisLen = 12.6
	local chassisWidth = 6.0
	local cashVal = 110
	local chaosPts = 75
	local breakThresh = 5
	local explosive = false
	local reqTier = 1

	if vehicleType == "YellowTaxi" then
		color = Color3.fromRGB(248, 196, 34)
		cashVal = 120
		reqTier = 1
	elseif vehicleType == "CityTransitBus" then
		color = Color3.fromRGB(42, 118, 215)
		chassisLen = 18.5
		chassisWidth = 6.8
		cashVal = 400
		chaosPts = 220
		reqTier = 3
	elseif vehicleType == "DeliveryVan" then
		color = Color3.fromRGB(238, 242, 248)
		chassisLen = 14.2
		chassisWidth = 6.2
		cashVal = 160
		chaosPts = 110
		reqTier = 1
	elseif vehicleType == "FuelTanker" then
		color = Color3.fromRGB(215, 48, 38)
		chassisLen = 17.5
		chassisWidth = 6.6
		cashVal = 350
		chaosPts = 240
		explosive = true
		reqTier = 2
	else
		color = SPORTS_CAR_COLORS[(idx % #SPORTS_CAR_COLORS) + 1]
		cashVal = 150
		chaosPts = 95
		reqTier = 1
	end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(chassisWidth, 1.4, chassisLen)
	chassis.CFrame = initialCF
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = true
	chassis.CanCollide = true
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = m
	m.PrimaryPart = chassis

	local trimColor = Color3.fromRGB(28, 32, 40)
	local glassColor = Color3.fromRGB(28, 36, 48)
	local halfZ = chassisLen * 0.5

	if vehicleType == "CityTransitBus" then
		local busBody = addWeldedCarPart(m, chassis, "Part", "BusCoachBody", Vector3.new(chassisWidth, 5.2, chassisLen - 0.4), CFrame.new(0, 3.0, 0), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "Part", "BusRoofStripe", Vector3.new(chassisWidth + 0.1, 0.8, chassisLen - 0.6), CFrame.new(0, 5.2, 0), Color3.fromRGB(242, 246, 252), Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "Part", "BusWindows", Vector3.new(chassisWidth + 0.16, 2.0, chassisLen - 3.2), CFrame.new(0, 3.5, 0.2), glassColor, Enum.Material.Glass, 0.2)
		addWeldedCarPart(m, chassis, "Part", "BusWindshield", Vector3.new(chassisWidth - 0.6, 2.3, 0.3), CFrame.new(0, 3.4, -halfZ + 0.15), glassColor, Enum.Material.Glass, 0.18)
		addSurfaceLabel(busBody, "NYC METRO BUS", Color3.fromRGB(255, 235, 85), Enum.NormalId.Left)
		addSurfaceLabel(busBody, "NYC METRO BUS", Color3.fromRGB(255, 235, 85), Enum.NormalId.Right)
	elseif vehicleType == "DeliveryVan" then
		addWeldedCarPart(m, chassis, "Part", "CabFront", Vector3.new(chassisWidth - 0.2, 2.6, 4.4), CFrame.new(0, 1.7, -halfZ + 2.4), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "WedgePart", "Windshield", Vector3.new(chassisWidth - 0.6, 1.7, 1.6), CFrame.new(0, 2.0, -halfZ + 1.0), glassColor, Enum.Material.Glass, 0.2)
		local cargoBox = addWeldedCarPart(m, chassis, "Part", "CargoBox", Vector3.new(chassisWidth + 0.2, 4.2, chassisLen - 4.8), CFrame.new(0, 2.6, 2.1), Color3.fromRGB(244, 246, 250), Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "Part", "AccentStripe", Vector3.new(chassisWidth + 0.28, 0.6, chassisLen - 5.0), CFrame.new(0, 2.3, 2.1), Color3.fromRGB(245, 138, 32), Enum.Material.SmoothPlastic)
		addSurfaceLabel(cargoBox, "NYC EXPRESS PARCEL", Color3.fromRGB(32, 42, 64), Enum.NormalId.Left)
		addSurfaceLabel(cargoBox, "NYC EXPRESS PARCEL", Color3.fromRGB(32, 42, 64), Enum.NormalId.Right)
	elseif vehicleType == "FuelTanker" then
		addWeldedCarPart(m, chassis, "Part", "TruckCab", Vector3.new(chassisWidth - 0.2, 3.4, 4.8), CFrame.new(0, 2.1, -halfZ + 2.6), Color3.fromRGB(220, 48, 38), Enum.Material.Metal)
		addWeldedCarPart(m, chassis, "Part", "CabWindshield", Vector3.new(chassisWidth - 0.8, 1.5, 0.3), CFrame.new(0, 2.7, -halfZ + 0.25), glassColor, Enum.Material.Glass, 0.2)
		local tank = addWeldedCarPart(
			m,
			chassis,
			"Part",
			"FuelTankCylinder",
			Vector3.new(chassisLen - 5.6, 5.0, 5.0),
			CFrame.new(0, 2.9, 2.4) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(228, 232, 240),
			Enum.Material.Metal,
			0,
			Enum.PartType.Cylinder
		)
		addWeldedCarPart(m, chassis, "Part", "HazardStripe", Vector3.new(chassisWidth + 0.1, 0.8, chassisLen - 5.8), CFrame.new(0, 2.9, 2.4), Color3.fromRGB(255, 195, 35), Enum.Material.Neon)
		addSurfaceLabel(tank, "FLAMMABLE FUEL", Color3.fromRGB(225, 35, 35), Enum.NormalId.Top)
	else
		-- Sleek Low-Profile Sedan / YellowTaxi / SportsCar
		addWeldedCarPart(m, chassis, "Part", "BodyBeltline", Vector3.new(6.0, 0.85, 7.6), CFrame.new(0, 0.55, 0.15), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "Part", "TrunkDeck", Vector3.new(5.8, 0.65, 2.4), CFrame.new(0, 0.52, 4.95), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "WedgePart", "SlopedHood", Vector3.new(5.8, 0.75, 3.6), CFrame.new(0, 0.58, -4.30), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "Part", "Cabin", Vector3.new(5.1, 1.32, 4.0), CFrame.new(0, 1.38, 0.10), glassColor, Enum.Material.Glass, 0.22)
		addWeldedCarPart(m, chassis, "Part", "RoofCap", Vector3.new(5.15, 0.18, 3.95), CFrame.new(0, 2.08, 0.10), color, Enum.Material.SmoothPlastic)
		addWeldedCarPart(m, chassis, "WedgePart", "Windshield", Vector3.new(5.0, 1.30, 1.85), CFrame.new(0, 1.36, -2.82), glassColor, Enum.Material.Glass, 0.20)
		addWeldedCarPart(
			m,
			chassis,
			"WedgePart",
			"RearWindow",
			Vector3.new(4.95, 1.25, 1.65),
			CFrame.new(0, 1.34, 2.92) * CFrame.Angles(0, math.rad(180), 0),
			glassColor,
			Enum.Material.Glass,
			0.22
		)

		if vehicleType == "YellowTaxi" then
			addWeldedCarPart(m, chassis, "Part", "TaxiSign", Vector3.new(2.0, 0.55, 0.9), CFrame.new(0, 2.42, -0.1), Color3.fromRGB(255, 225, 75), Enum.Material.Neon)
			addWeldedCarPart(m, chassis, "Part", "TaxiSideStripe", Vector3.new(6.10, 0.22, 7.2), CFrame.new(0, 0.45, 0.15), Color3.fromRGB(22, 24, 30), Enum.Material.SmoothPlastic)
		elseif vehicleType == "SportsCar" then
			addWeldedCarPart(m, chassis, "Part", "RearSpoilerWing", Vector3.new(5.5, 0.22, 1.0), CFrame.new(0, 1.25, 5.75), Color3.fromRGB(28, 32, 40), Enum.Material.Metal)
			addWeldedCarPart(m, chassis, "Part", "RacingStripe", Vector3.new(1.0, 0.88, 12.0), CFrame.new(0, 0.58, 0), Color3.fromRGB(245, 248, 255), Enum.Material.SmoothPlastic)
		end
	end

	-- Bumpers, Headlights, Taillights & 4 Wheels
	addWeldedCarPart(m, chassis, "Part", "FrontBumper", Vector3.new(chassisWidth + 0.16, 0.58, 0.58), CFrame.new(0, -0.28, -halfZ - 0.1), trimColor, Enum.Material.Metal)
	addWeldedCarPart(m, chassis, "Part", "RearBumper", Vector3.new(chassisWidth + 0.16, 0.58, 0.58), CFrame.new(0, -0.28, halfZ + 0.1), trimColor, Enum.Material.Metal)
	addWeldedCarPart(m, chassis, "Part", "Headlights", Vector3.new(chassisWidth - 0.8, 0.36, 0.16), CFrame.new(0, 0.22, -halfZ - 0.05), Color3.fromRGB(255, 245, 205), Enum.Material.Neon)
	addWeldedCarPart(m, chassis, "Part", "Taillights", Vector3.new(chassisWidth - 0.8, 0.28, 0.16), CFrame.new(0, 0.22, halfZ + 0.05), Color3.fromRGB(195, 28, 34), Enum.Material.SmoothPlastic)

	local wheelZ = halfZ - 2.45
	local wheelX = chassisWidth * 0.5 - 0.08
	local wheelSpecs = {
		{ Name = "WheelFL", X = -wheelX, Z = -wheelZ },
		{ Name = "WheelFR", X = wheelX, Z = -wheelZ },
		{ Name = "WheelRL", X = -wheelX, Z = wheelZ },
		{ Name = "WheelRR", X = wheelX, Z = wheelZ },
	}
	for _, ws in ipairs(wheelSpecs) do
		local wOffset = CFrame.new(ws.X, -0.52, ws.Z)
		addWeldedCarPart(m, chassis, "Part", ws.Name, Vector3.new(1.05, 2.45, 2.45), wOffset, Color3.fromRGB(20, 22, 26), Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
		addWeldedCarPart(m, chassis, "Part", ws.Name .. "_Hubcap", Vector3.new(1.16, 1.40, 1.40), wOffset, Color3.fromRGB(192, 200, 215), Enum.Material.Metal, 0, Enum.PartType.Cylinder)
	end

	m:SetAttribute("PropType", if vehicleType == "CityTransitBus" then "CityBus" else "TrafficVehicle")
	m:SetAttribute("DestructibleType", vehicleType)
	m:SetAttribute("IsDestructible", true)
	m:SetAttribute("RequiredTier", reqTier)
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
		return CFrame.new(x, 1.85, z) * CFrame.Angles(0, yaw + car.swerveAngle, 0)
	else
		local z = car.roadLine + laneShift
		local x = car.posAlong
		local yaw = if car.dir > 0 then -math.pi * 0.5 else math.pi * 0.5
		return CFrame.new(x, 1.85, z) * CFrame.Angles(0, yaw + car.swerveAngle, 0)
	end
end

local function spawnTrafficCars(count: number)
	for i = 1, count do
		local vType = VEHICLE_TYPES[((i - 1) % #VEHICLE_TYPES) + 1]
		local axis = if i % 2 == 0 then "NS" else "EW"
		local dir = if (i % 4 < 2) then 1 else -1
		local roadLine = roadCoords[((i - 1) % #roadCoords) + 1]
		local posAlong = -CITY_LIMIT + ((i * 89) % (CITY_LIMIT * 2))

		local speedByRole = if vType == "SportsCar"
			then 44
			elseif vType == "CityTransitBus" or vType == "FuelTanker" then 28
			else 34

		local dummyCar: AICar = {
			model = nil :: any,
			primary = nil :: any,
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
		local initialCF = computeCarCFrame(dummyCar)
		local model, primary = buildTrafficVehicleByType(vType, i, initialCF)
		dummyCar.model = model
		dummyCar.primary = primary

		primary.Touched:Connect(function(hit: BasePart)
			if not hit.Anchored and hit.AssemblyLinearVelocity.Magnitude > 18 and not hit:IsDescendantOf(model) then
				dummyCar.panicTimer = 7.0
				dummyCar.swerveAngle = (math.random() - 0.5) * 0.35
			end
		end)

		table.insert(aiCars, dummyCar)
	end
end

local trafficRayParams = RaycastParams.new()
trafficRayParams.FilterType = Enum.RaycastFilterType.Exclude
trafficRayParams.IgnoreWater = true
trafficRayParams.RespectCanCollide = true

local FORWARD_CHECK_DIST = 32.0
local MIN_STOP_GAP = 8.0

local function computeForwardSpacingFactor(car: AICar, playerRoots: { BasePart }): number
	local cf = car.primary.CFrame
	local forwardVec = cf.LookVector
	local rightVec = cf.RightVector
	local frontBumperPos = cf.Position + forwardVec * 6.5 + Vector3.new(0, 0.35, 0)

	local minGap = FORWARD_CHECK_DIST
	for _, other in ipairs(aiCars) do
		if other ~= car and not other.smashed and other.axis == car.axis and other.roadLine == car.roadLine and other.dir == car.dir then
			local centerGap = (other.posAlong - car.posAlong) * car.dir
			if centerGap > 0 then
				local bumperGap = math.max(0, centerGap - 16.0)
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
		return false
	end
	local phase = if car.axis == "NS" then nsPhase else ewPhase
	if phase == "Green" then
		return false
	end

	for _, interCoord in ipairs(roadCoords) do
		local distAhead = (interCoord - car.posAlong) * car.dir
		if distAhead > 18 and distAhead < 40 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- 3. 48 ARTICULATED NYC PEDESTRIANS (RIGID WELDS + ANIMATED WALK SWING)
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

local SKIN_TONES = {
	Color3.fromRGB(240, 198, 160),
	Color3.fromRGB(217, 160, 115),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(245, 205, 174),
}

local NPC_ROLES: { NPCRoleSpec } = {
	{
		role = "HotdogChef",
		torsoColor = Color3.fromRGB(235, 238, 245),
		legsColor = Color3.fromRGB(44, 48, 58),
		hatColor = Color3.fromRGB(245, 245, 250),
		walkSpeed = 7.5,
		chatterLines = { "Hot pretzels & dogs!", "Fresh NYC street dogs!" },
		panicLines = { "MY PRETZEL CART!!", "WATCH THE GRILL!" },
	},
	{
		role = "BusinessExecutive",
		torsoColor = Color3.fromRGB(32, 42, 64),
		legsColor = Color3.fromRGB(24, 30, 44),
		hatColor = Color3.fromRGB(38, 44, 56),
		walkSpeed = 8.5,
		chatterLines = { "Late for Wall Street!", "Where is my yellow cab?!" },
		panicLines = { "HEY! I'M WALKIN' HERE!", "WATCH THE SUIT!" },
	},
	{
		role = "ConstructionWorker",
		torsoColor = Color3.fromRGB(215, 128, 28),
		legsColor = Color3.fromRGB(48, 68, 108),
		hatColor = Color3.fromRGB(235, 185, 32),
		walkSpeed = 8.0,
		chatterLines = { "We just rebuilt that hydrant!", "Cold day in Manhattan!" },
		panicLines = { "HARD HAT ON!!", "TIMBER!!" },
	},
	{
		role = "StreetSkater",
		torsoColor = Color3.fromRGB(58, 72, 96),
		legsColor = Color3.fromRGB(36, 40, 48),
		hatColor = Color3.fromRGB(165, 42, 48),
		walkSpeed = 10.5,
		chatterLines = { "Hit the Grand Ave Ramp!", "Did you hear that V8?!" },
		panicLines = { "SICK DRIFT BRO!", "WHOA FULL SEND!!" },
	},
	{
		role = "Tourist",
		torsoColor = Color3.fromRGB(46, 118, 98),
		legsColor = Color3.fromRGB(82, 74, 64),
		hatColor = Color3.fromRGB(195, 165, 110),
		walkSpeed = 7.5,
		chatterLines = { "Look at Leo Tower!", "New York is wild!" },
		panicLines = { "GET THAT ON CAMERA!", "ONLY IN NEW YORK!" },
	},
	{
		role = "Jogger",
		torsoColor = Color3.fromRGB(178, 48, 58),
		legsColor = Color3.fromRGB(32, 36, 44),
		hatColor = Color3.fromRGB(48, 56, 72),
		walkSpeed = 10.2,
		chatterLines = { "Morning Central Park run!", "Out of the way!" },
		panicLines = { "CARDIO SAVED MY LIFE!", "WATCH THE CROSSWALK!" },
	},
}

type AIPed = {
	model: Model,
	root: BasePart,
	leftArmWeld: Weld,
	rightArmWeld: Weld,
	leftLegWeld: Weld,
	rightLegWeld: Weld,
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

local function makeWeldedPedLimb(
	parent: Instance,
	primary: BasePart,
	name: string,
	size: Vector3,
	offsetCF: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): (Part, Weld)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	local w = weldToPrimary(primary, p, offsetCF)
	return p, w
end

local function buildPedestrian(idx: number): AIPed
	local roleSpec = NPC_ROLES[((idx - 1) % #NPC_ROLES) + 1]
	local skinTone = SKIN_TONES[((idx - 1) % #SKIN_TONES) + 1]

	local axis = if idx % 2 == 0 then "NS" else "EW"
	local dir = if idx % 3 == 0 then 1 else -1
	local roadLine = roadCoords[((idx - 1) % #roadCoords) + 1]
	local side = if idx % 4 < 2 then 1 else -1
	local posAlong = -CITY_LIMIT + ((idx * 67) % (CITY_LIMIT * 2))

	local initPos = if axis == "NS"
		then Vector3.new(roadLine + side * SIDEWALK_OFFSET, 3.5, posAlong)
		else Vector3.new(posAlong, 3.5, roadLine + side * SIDEWALK_OFFSET)

	local m = Instance.new("Model")
	m.Name = "Citizen_" .. roleSpec.role
	m:SetAttribute("NPCRole", roleSpec.role)

	local root = Instance.new("Part")
	root.Name = "Torso"
	root.Size = Vector3.new(1.7, 2.1, 0.95)
	root.CFrame = CFrame.new(initPos)
	root.Color = roleSpec.torsoColor
	root.Material = Enum.Material.Fabric
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Anchored = true
	root.CanCollide = false
	root.Parent = m
	m.PrimaryPart = root

	makeWeldedPedLimb(m, root, "WinterScarf", Vector3.new(1.45, 0.34, 1.08), CFrame.new(0, 1.0, 0), Color3.fromRGB(36, 40, 50), Enum.Material.Fabric, nil)
	local head, _ = makeWeldedPedLimb(m, root, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.72, 0), skinTone, Enum.Material.SmoothPlastic, Enum.PartType.Ball)

	local _, leftArmWeld = makeWeldedPedLimb(m, root, "LeftArm", Vector3.new(0.58, 1.85, 0.58), CFrame.new(-1.16, 0.06, 0), roleSpec.torsoColor, Enum.Material.Fabric, nil)
	local _, rightArmWeld = makeWeldedPedLimb(m, root, "RightArm", Vector3.new(0.58, 1.85, 0.58), CFrame.new(1.16, 0.06, 0), roleSpec.torsoColor, Enum.Material.Fabric, nil)
	local _, leftLegWeld = makeWeldedPedLimb(m, root, "LeftLeg", Vector3.new(0.72, 1.95, 0.72), CFrame.new(-0.44, -2.0, 0), roleSpec.legsColor, Enum.Material.Fabric, nil)
	local _, rightLegWeld = makeWeldedPedLimb(m, root, "RightLeg", Vector3.new(0.72, 1.95, 0.72), CFrame.new(0.44, -2.0, 0), roleSpec.legsColor, Enum.Material.Fabric, nil)

	if roleSpec.hatColor then
		makeWeldedPedLimb(
			m,
			root,
			"AccessoryHat",
			if roleSpec.role == "HotdogChef" then Vector3.new(1.22, 0.85, 1.22) else Vector3.new(1.32, 0.45, 1.38),
			CFrame.new(0, 2.36, 0),
			roleSpec.hatColor,
			Enum.Material.SmoothPlastic,
			nil
		)
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "AlertBubble"
	bb.Size = UDim2.fromOffset(155, 36)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = 120
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
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)

	CollectionService:AddTag(m, "NPCPedestrian")
	m.Parent = PedestriansFolder

	return {
		model = m,
		root = root,
		leftArmWeld = leftArmWeld,
		rightArmWeld = rightArmWeld,
		leftLegWeld = leftLegWeld,
		rightLegWeld = rightLegWeld,
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
		chatterTimer = 4.0 + (idx % 9) * 1.8,
		leapOffset = Vector3.zero,
		phase = idx * 1.1,
	}
end

local function showPedestrianChatter(ped: AIPed)
	if ped.dodgeCooldown > 0 then
		return
	end
	local lines = ped.roleSpec.chatterLines
	ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
	ped.bubbleLabel.TextColor3 = Color3.fromRGB(28, 36, 52)
	ped.bubbleLabel.Text = lines[math.random(1, #lines)]
	ped.bubbleGui.Enabled = true

	task.delay(2.8, function()
		if ped.dodgeCooldown <= 0 and ped.bubbleGui then
			ped.bubbleGui.Enabled = false
		end
	end)
end

local function triggerPedestrianDodge(ped: AIPed, threatPos: Vector3)
	if ped.dodgeCooldown > 0 then
		return
	end
	ped.dodgeCooldown = 3.2
	local panicLines = ped.roleSpec.panicLines
	ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(255, 225, 55)
	ped.bubbleLabel.TextColor3 = Color3.fromRGB(215, 25, 25)
	ped.bubbleLabel.Text = panicLines[math.random(1, #panicLines)]
	ped.bubbleGui.Enabled = true

	local away = (ped.root.Position - threatPos)
	local flatAway = Vector3.new(away.X, 0, away.Z)
	local dodgeDir = if flatAway.Magnitude > 0.1 then flatAway.Unit else Vector3.new(1, 0, 0)
	ped.leapOffset = dodgeDir * 7.5 + Vector3.new(0, 3.8, 0)

	task.delay(2.0, function()
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
				car.swerveAngle = (math.random() - 0.5) * 0.35
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
spawnTrafficCars(36)
spawnPedestrians(48)

RunService.Heartbeat:Connect(function(dt: number)
	local clampedDt = math.min(dt, 0.1)

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

	-- Update 36 AI Traffic Vehicles
	for _, car in ipairs(aiCars) do
		if car.model:GetAttribute("Destroyed") == true then
			if not car.smashed then
				car.smashed = true
				task.delay(12.0, function()
					if car.model and car.model.Parent then
						car.model:SetAttribute("Destroyed", false)
						car.primary.AssemblyLinearVelocity = Vector3.zero
						car.primary.AssemblyAngularVelocity = Vector3.zero
						car.primary.Anchored = true
						car.primary.CanCollide = true
						for _, d in ipairs(car.model:GetDescendants()) do
							if d:IsA("BasePart") and d ~= car.primary then
								d.Anchored = false
								d.CanCollide = false
							end
						end
						car.posAlong = -CITY_LIMIT
						car.panicTimer = 0
						car.swerveAngle = 0
						car.smashed = false
						car.primary.CFrame = computeCarCFrame(car)
					end
				end)
			end
			continue
		end

		-- Ensure primary stays anchored while cruising so C0/C1 Welds carry all body parts in lockstep
		if not car.primary.Anchored then
			car.primary.Anchored = true
		end

		if car.panicTimer > 0 then
			car.panicTimer = math.max(0, car.panicTimer - clampedDt)
			car.swerveAngle = math.sin(os.clock() * 7) * 0.18
		else
			car.swerveAngle = car.swerveAngle * math.max(0, 1 - clampedDt * 5)
		end

		local stop = shouldStopForRedLight(car)
		local spacingFactor = computeForwardSpacingFactor(car, playerRoots)
		local desiredCruise = if stop then 0 elseif car.panicTimer > 0 then car.baseSpeed * 1.65 else car.baseSpeed
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

	-- Update 48 Sidewalk Pedestrians with Animated Arm & Leg Swing
	for _, ped in ipairs(aiPeds) do
		ped.phase += clampedDt * 8.5
		if ped.dodgeCooldown > 0 then
			ped.dodgeCooldown = math.max(0, ped.dodgeCooldown - clampedDt)
		end
		ped.leapOffset = ped.leapOffset:Lerp(Vector3.zero, math.min(1, clampedDt * 6))

		ped.chatterTimer -= clampedDt
		if ped.chatterTimer <= 0 then
			ped.chatterTimer = 10.0 + math.random() * 8.0
			for _, hrp in ipairs(playerRoots) do
				if (hrp.Position - ped.root.Position).Magnitude < 95 then
					showPedestrianChatter(ped)
					break
				end
			end
		end

		for _, hrp in ipairs(playerRoots) do
			local d = (hrp.Position - ped.root.Position).Magnitude
			if d < 32 and hrp.AssemblyLinearVelocity.Magnitude > 18 then
				triggerPedestrianDodge(ped, hrp.Position)
			end
		end

		local speedMult = if ped.dodgeCooldown > 1.5 then 2.2 else 1.0
		ped.posAlong += ped.dir * ped.walkSpeed * speedMult * clampedDt
		if ped.posAlong > CITY_LIMIT then
			ped.posAlong = -CITY_LIMIT
		elseif ped.posAlong < -CITY_LIMIT then
			ped.posAlong = CITY_LIMIT
		end

		local swing = math.sin(ped.phase) * math.rad(28)
		ped.leftArmWeld.C0 = CFrame.new(-1.16, 0.06, 0) * CFrame.Angles(swing, 0, 0)
		ped.rightArmWeld.C0 = CFrame.new(1.16, 0.06, 0) * CFrame.Angles(-swing, 0, 0)
		ped.leftLegWeld.C0 = CFrame.new(-0.44, -2.0, 0) * CFrame.Angles(-swing, 0, 0)
		ped.rightLegWeld.C0 = CFrame.new(0.44, -2.0, 0) * CFrame.Angles(swing, 0, 0)

		local bob = math.abs(math.sin(ped.phase)) * 0.25
		local basePos: Vector3
		local yaw: number
		if ped.axis == "NS" then
			basePos = Vector3.new(ped.roadLine + ped.side * SIDEWALK_OFFSET, 3.35 + bob, ped.posAlong)
			yaw = if ped.dir > 0 then math.pi else 0
		else
			basePos = Vector3.new(ped.posAlong, 3.35 + bob, ped.roadLine + ped.side * SIDEWALK_OFFSET)
			yaw = if ped.dir > 0 then -math.pi * 0.5 else math.pi * 0.5
		end

		ped.root.CFrame = CFrame.new(basePos + ped.leapOffset) * CFrame.Angles(0, yaw, 0)
	end
end)

print("[TrafficAndNPCAIService] 36 intact AI vehicles and 48 animated NYC pedestrians active.")
