--!strict
-- TrafficAndNPCAIService.script.luau
-- Manages Leo City's living ambient world:
-- 1. Synchronized intersection traffic light cycling (Green -> Yellow -> Red) with orthogonal NS/EW phases.
-- 2. Autonomous AI traffic vehicles driving along road lanes, obeying traffic lights until hit or panicked
--    by nearby chaos/explosions, then swerving and fleeing at high speed!
-- 3. Animated NPC pedestrians walking along sidewalks who perform a compliance-friendly comical dodge leap
--    with a "!" exclamation bubble when a vehicle approaches rapidly or chaos erupts nearby.

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
local LANE_OFFSET = 10.5
local SIDEWALK_OFFSET = ROAD_WIDTH * 0.5 + 7.5

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
-- 2. AUTONOMOUS AI TRAFFIC VEHICLES
--------------------------------------------------------------------------------
type AICar = {
	model: Model,
	primary: BasePart,
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
local CAR_COLORS = {
	Color3.fromRGB(240, 190, 40), -- NYC Taxi Yellow
	Color3.fromRGB(210, 45, 45),
	Color3.fromRGB(45, 115, 220),
	Color3.fromRGB(230, 235, 245),
	Color3.fromRGB(55, 180, 95),
	Color3.fromRGB(65, 72, 88),
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

local function buildTrafficCarModel(color: Color3, isTaxi: boolean): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = if isTaxi then "AITaxiCab" else "AITrafficCar"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.0, 1.5, 12.6)
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = true
	chassis.CanCollide = true
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = m

	local baseCF = chassis.CFrame
	local trimColor = Color3.fromRGB(30, 34, 42)
	local glassColor = Color3.fromRGB(32, 44, 62)

	-- Sculpted Beltline & Trunk Deck
	addCarPart(m, "Part", "BodyBeltline", Vector3.new(6.1, 0.85, 7.6), baseCF * CFrame.new(0, 0.55, 0.15), color, Enum.Material.SmoothPlastic)
	addCarPart(m, "Part", "TrunkDeck", Vector3.new(5.8, 0.68, 2.4), baseCF * CFrame.new(0, 0.56, 4.95), color, Enum.Material.SmoothPlastic)

	-- Sloped Front Hood (WedgePart sloping down toward -Z front)
	addCarPart(m, "WedgePart", "SlopedHood", Vector3.new(5.8, 0.78, 3.6), baseCF * CFrame.new(0, 0.62, -4.30), color, Enum.Material.SmoothPlastic)

	-- Cabin Greenhouse, Painted Roof Cap, Sloped Front Windshield & Sloped Rear Window
	addCarPart(m, "Part", "Cabin", Vector3.new(5.3, 1.65, 4.4), baseCF * CFrame.new(0, 1.62, 0.10), glassColor, Enum.Material.Glass, 0.25)
	addCarPart(m, "Part", "RoofCap", Vector3.new(5.36, 0.22, 4.35), baseCF * CFrame.new(0, 2.50, 0.10), color, Enum.Material.SmoothPlastic)
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

	-- Front & Rear Metallic Bumpers + Textured Grille
	addCarPart(m, "Part", "FrontBumper", Vector3.new(6.22, 0.62, 0.62), baseCF * CFrame.new(0, -0.32, -6.40), trimColor, Enum.Material.Metal)
	addCarPart(m, "Part", "RearBumper", Vector3.new(6.22, 0.62, 0.62), baseCF * CFrame.new(0, -0.32, 6.40), trimColor, Enum.Material.Metal)
	addCarPart(m, "Part", "FrontGrille", Vector3.new(3.1, 0.58, 0.18), baseCF * CFrame.new(0, 0.20, -6.32), Color3.fromRGB(24, 26, 32), Enum.Material.DiamondPlate)

	-- Headlights & Taillights + Side Mirrors
	addCarPart(m, "Part", "Headlights", Vector3.new(5.2, 0.42, 0.18), baseCF * CFrame.new(0, 0.24, -6.34), Color3.fromRGB(255, 245, 200), Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		addCarPart(
			m,
			"Part",
			if sx < 0 then "HeadlightL" else "HeadlightR",
			Vector3.new(1.15, 0.48, 0.22),
			baseCF * CFrame.new(sx * 2.15, 0.24, -6.36),
			Color3.fromRGB(255, 248, 215),
			Enum.Material.Neon
		)
		addCarPart(
			m,
			"Part",
			if sx < 0 then "TaillightL" else "TaillightR",
			Vector3.new(1.25, 0.48, 0.22),
			baseCF * CFrame.new(sx * 2.10, 0.24, 6.36),
			Color3.fromRGB(255, 36, 36),
			Enum.Material.Neon
		)
		addCarPart(
			m,
			"Part",
			if sx < 0 then "MirrorL" else "MirrorR",
			Vector3.new(0.48, 0.30, 0.38),
			baseCF * CFrame.new(sx * 2.88, 1.22, -1.75),
			color,
			Enum.Material.SmoothPlastic
		)
	end
	addCarPart(m, "Part", "Taillights", Vector3.new(5.2, 0.36, 0.18), baseCF * CFrame.new(0, 0.24, 6.34), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)

	-- 4 Cylinder Tires (WheelFL, WheelFR, WheelRL, WheelRR) with Metallic Hubcaps
	local wheelSpecs = {
		{ Name = "WheelFL", X = -2.92, Z = -3.85 },
		{ Name = "WheelFR", X = 2.92, Z = -3.85 },
		{ Name = "WheelRL", X = -2.92, Z = 3.85 },
		{ Name = "WheelRR", X = 2.92, Z = 3.85 },
	}
	for _, ws in ipairs(wheelSpecs) do
		local wCF = baseCF * CFrame.new(ws.X, -0.55, ws.Z)
		addCarPart(
			m,
			"Part",
			ws.Name,
			Vector3.new(1.10, 2.50, 2.50),
			wCF,
			Color3.fromRGB(22, 24, 28),
			Enum.Material.SmoothPlastic,
			0,
			Enum.PartType.Cylinder
		)
		addCarPart(
			m,
			"Part",
			ws.Name .. "_Hubcap",
			Vector3.new(1.22, 1.44, 1.44),
			wCF,
			Color3.fromRGB(198, 206, 220),
			Enum.Material.Metal,
			0,
			Enum.PartType.Cylinder
		)
	end

	if isTaxi then
		addCarPart(m, "Part", "TaxiSign", Vector3.new(2.2, 0.65, 1.0), baseCF * CFrame.new(0, 2.92, -0.2), Color3.fromRGB(255, 225, 75), Enum.Material.Neon)
		addCarPart(m, "Part", "TaxiSideStripe", Vector3.new(6.16, 0.22, 7.4), baseCF * CFrame.new(0, 0.45, 0.15), Color3.fromRGB(24, 26, 32), Enum.Material.SmoothPlastic)
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
	m:SetAttribute("CashValue", 90)
	m:SetAttribute("ChaosPoints", 65)
	m:SetAttribute("BreakThreshold", 28)
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
		local isTaxi = (i % 4 == 1)
		local col = if isTaxi then CAR_COLORS[1] else CAR_COLORS[(i % #CAR_COLORS) + 1]
		local model, primary = buildTrafficCarModel(col, isTaxi)

		local axis = if i % 2 == 0 then "NS" else "EW"
		local dir = if (i % 4 < 2) then 1 else -1
		local roadLine = roadCoords[((i - 1) % #roadCoords) + 1]
		local posAlong = -CITY_LIMIT + ((i * 97) % (CITY_LIMIT * 2))

		local car: AICar = {
			model = model,
			primary = primary,
			axis = axis,
			dir = dir,
			roadLine = roadLine,
			posAlong = posAlong,
			baseSpeed = 34 + (i % 5) * 4,
			currentSpeed = 34,
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
	-- Cast 3 forward spacing rays across the front bumper (center, left, right)
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

	-- Analytic same-lane spacing check against other AI traffic cars
	for _, other in ipairs(aiCars) do
		if other ~= car and not other.smashed and other.axis == car.axis and other.roadLine == car.roadLine and other.dir == car.dir then
			local centerGap = (other.posAlong - car.posAlong) * car.dir
			if centerGap > 0 then
				local bumperGap = math.max(0, centerGap - 13.0)
				if bumperGap < minGap then
					minGap = bumperGap
				end
			end
		end
	end

	-- Analytic spacing check against player vehicles / characters ahead in lane
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

	-- Check distance to nearest intersection along travel direction
	for _, interCoord in ipairs(roadCoords) do
		local distAhead = (interCoord - car.posAlong) * car.dir
		if distAhead > 18 and distAhead < 42 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- 3. SIDEWALK NPC PEDESTRIANS (WITH ROLES, AMBIENT CHATTER & COMICAL DODGE)
--------------------------------------------------------------------------------
type AIPed = {
	model: Model,
	root: BasePart,
	bubbleGui: BillboardGui,
	bubbleLabel: TextLabel,
	roleName: string,
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
local NPC_ROLES = {
	{ Role = "HotdogChef", Color = Color3.fromRGB(235, 65, 55), Speed = 7.2 },
	{ Role = "BusinessExecutive", Color = Color3.fromRGB(42, 68, 128), Speed = 8.4 },
	{ Role = "ConstructionWorker", Color = Color3.fromRGB(245, 165, 35), Speed = 7.8 },
	{ Role = "StreetSkater", Color = Color3.fromRGB(50, 185, 115), Speed = 11.2 },
	{ Role = "Tourist", Color = Color3.fromRGB(165, 85, 215), Speed = 7.0 },
	{ Role = "Jogger", Color = Color3.fromRGB(35, 195, 235), Speed = 10.4 },
}

local AMBIENT_CHATTER_LINES = {
	"Best hotdogs in Leo City!",
	"Late for my meeting at Leo Tower!",
	"Did you hear that V8?!",
	"MegaCorp put barriers everywhere!",
	"Check out the Pier Stunt Jump!",
	"Sunny day in Leo City!",
}

local PANIC_CALLOUT_LINES = {
	"MY TACOS!!",
	"WATCH THE SUIT!",
	"RADICAL JUMP!",
	"CALL THE MAYOR!",
	"WHOA! CRAZY DRIVER!",
	"MY GELATO!!",
}

local function buildPedestrian(idx: number): AIPed
	local roleSpec = NPC_ROLES[((idx - 1) % #NPC_ROLES) + 1]
	local m = Instance.new("Model")
	m.Name = "CitizenNPC_" .. roleSpec.Role
	m:SetAttribute("NPCRole", roleSpec.Role)

	local root = Instance.new("Part")
	root.Name = "Torso"
	root.Size = Vector3.new(2.0, 2.6, 1.1)
	root.Color = roleSpec.Color
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
	legs.Color = Color3.fromRGB(38, 42, 54)
	legs.Material = Enum.Material.SmoothPlastic
	legs.CanCollide = false
	legs.Anchored = false
	legs.Parent = m

	for _, part in ipairs({ head, legs }) do
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = root
		wc.Part1 = part
		wc.Parent = root
	end

	-- Chatter & Panic Bubble UI
	local bb = Instance.new("BillboardGui")
	bb.Name = "AlertBubble"
	bb.Size = UDim2.fromOffset(145, 42)
	bb.StudsOffset = Vector3.new(0, 3.8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Enabled = false
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(255, 238, 75)
	lbl.BackgroundTransparency = 0.08
	lbl.Text = "!"
	lbl.TextColor3 = Color3.fromRGB(25, 28, 36)
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
		bubbleGui = bb,
		bubbleLabel = lbl,
		roleName = roleSpec.Role,
		axis = axis,
		dir = dir,
		roadLine = roadLine,
		side = side,
		posAlong = posAlong,
		walkSpeed = roleSpec.Speed,
		dodgeCooldown = 0,
		chatterTimer = 4.0 + (idx % 9) * 1.8,
		leapOffset = Vector3.zero,
		phase = idx * 1.1,
	}
end

local function triggerPedestrianDodge(ped: AIPed, threatPos: Vector3)
	if ped.dodgeCooldown > 0 then
		return
	end
	ped.dodgeCooldown = 3.2
	ped.bubbleGui.Enabled = true
	ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(255, 225, 55)
	ped.bubbleLabel.TextColor3 = Color3.fromRGB(215, 25, 25)
	ped.bubbleLabel.Text = PANIC_CALLOUT_LINES[math.random(1, #PANIC_CALLOUT_LINES)]

	local away = (ped.root.Position - threatPos)
	local flatAway = Vector3.new(away.X, 0, away.Z)
	local dodgeDir = if flatAway.Magnitude > 0.1 then flatAway.Unit else Vector3.new(1, 0, 0)
	ped.leapOffset = dodgeDir * 7.5 + Vector3.new(0, 3.6, 0)

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
			if not car.smashed and (car.primary.Position - pos).Magnitude < 85 then
				car.panicTimer = 8.0
				car.swerveAngle = (math.random() - 0.5) * 0.4
			end
		end
		for _, ped in ipairs(aiPeds) do
			if (ped.root.Position - pos).Magnitude < 65 then
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

	-- Update AI Traffic Vehicles
	for _, car in ipairs(aiCars) do
		if car.model:GetAttribute("Destroyed") == true then
			if not car.smashed then
				car.smashed = true
				-- Respawn traffic car onto road after 18s
				task.delay(18.0, function()
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

	-- Update Sidewalk Pedestrians
	for _, ped in ipairs(aiPeds) do
		ped.phase += clampedDt * 8
		if ped.dodgeCooldown > 0 then
			ped.dodgeCooldown = math.max(0, ped.dodgeCooldown - clampedDt)
		else
			ped.chatterTimer -= clampedDt
			if ped.chatterTimer <= 0 then
				ped.chatterTimer = 11.0 + math.random() * 9.0
				ped.bubbleGui.Enabled = true
				ped.bubbleLabel.BackgroundColor3 = Color3.fromRGB(248, 250, 255)
				ped.bubbleLabel.TextColor3 = Color3.fromRGB(22, 28, 42)
				ped.bubbleLabel.Text = AMBIENT_CHATTER_LINES[math.random(1, #AMBIENT_CHATTER_LINES)]
				task.delay(2.4, function()
					if ped.bubbleGui and ped.dodgeCooldown <= 0 then
						ped.bubbleGui.Enabled = false
					end
				end)
			end
		end
		ped.leapOffset = ped.leapOffset:Lerp(Vector3.zero, math.min(1, clampedDt * 6))

		-- Check for approaching fast player vehicles
		for _, hrp in ipairs(playerRoots) do
			local d = (hrp.Position - ped.root.Position).Magnitude
			if d < 32 and hrp.AssemblyLinearVelocity.Magnitude > 20 then
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

print("[TrafficAndNPCAIService] Synchronized traffic lights, AI vehicles, and sidewalk pedestrians active.")
