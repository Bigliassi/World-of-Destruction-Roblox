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
local BLOCK_SIZE = (Workspace:GetAttribute("LeoCityBlockSize") :: number?) or 180
local ROAD_WIDTH = (Workspace:GetAttribute("LeoCityRoadWidth") :: number?) or 36
local GRID_RADIUS = (Workspace:GetAttribute("LeoCityGridRadius") :: number?) or 3
local LANE_OFFSET = 8.5
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

local function buildTrafficCarModel(color: Color3, isTaxi: boolean): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = if isTaxi then "AITaxiCab" else "AITrafficCar"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.2, 2.4, 12.5)
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Anchored = true
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = m

	local cabin = Instance.new("Part")
	cabin.Name = "Cabin"
	cabin.Size = Vector3.new(5.4, 2.0, 6.4)
	cabin.CFrame = chassis.CFrame * CFrame.new(0, 2.1, -0.4)
	cabin.Color = Color3.fromRGB(30, 38, 52)
	cabin.Material = Enum.Material.Glass
	cabin.CanCollide = false
	cabin.Parent = m

	local headlights = Instance.new("Part")
	headlights.Name = "Headlights"
	headlights.Size = Vector3.new(5.2, 0.6, 0.2)
	headlights.CFrame = chassis.CFrame * CFrame.new(0, 0.2, -6.3)
	headlights.Color = Color3.fromRGB(255, 245, 200)
	headlights.Material = Enum.Material.Neon
	headlights.CanCollide = false
	headlights.Parent = m

	local taillights = Instance.new("Part")
	taillights.Name = "Taillights"
	taillights.Size = Vector3.new(5.2, 0.6, 0.2)
	taillights.CFrame = chassis.CFrame * CFrame.new(0, 0.2, 6.3)
	taillights.Color = Color3.fromRGB(255, 40, 40)
	taillights.Material = Enum.Material.Neon
	taillights.CanCollide = false
	taillights.Parent = m

	if isTaxi then
		local sign = Instance.new("Part")
		sign.Name = "TaxiSign"
		sign.Size = Vector3.new(2.2, 0.7, 1.0)
		sign.CFrame = chassis.CFrame * CFrame.new(0, 3.4, -0.4)
		sign.Color = Color3.fromRGB(255, 225, 75)
		sign.Material = Enum.Material.Neon
		sign.CanCollide = false
		sign.Parent = m
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
-- 3. SIDEWALK NPC PEDESTRIANS (WITH COMICAL DODGE & EXCLAMATION BUBBLE)
--------------------------------------------------------------------------------
type AIPed = {
	model: Model,
	root: BasePart,
	bubbleGui: BillboardGui,
	bubbleLabel: TextLabel,
	axis: string,
	dir: number,
	roadLine: number,
	side: number,
	posAlong: number,
	walkSpeed: number,
	dodgeCooldown: number,
	leapOffset: Vector3,
	phase: number,
}

local aiPeds: { AIPed } = {}
local OUTFIT_COLORS = {
	Color3.fromRGB(45, 95, 185),
	Color3.fromRGB(190, 55, 65),
	Color3.fromRGB(50, 150, 95),
	Color3.fromRGB(145, 90, 190),
	Color3.fromRGB(220, 135, 45),
}

local function buildPedestrian(idx: number): AIPed
	local m = Instance.new("Model")
	m.Name = "CitizenNPC"

	local root = Instance.new("Part")
	root.Name = "Torso"
	root.Size = Vector3.new(2.0, 2.6, 1.1)
	root.Color = OUTFIT_COLORS[(idx % #OUTFIT_COLORS) + 1]
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

	-- Exclamation Bubble UI (hidden until startled)
	local bb = Instance.new("BillboardGui")
	bb.Name = "AlertBubble"
	bb.Size = UDim2.fromOffset(52, 52)
	bb.StudsOffset = Vector3.new(0, 3.8, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(255, 235, 60)
	lbl.BackgroundTransparency = 0.1
	lbl.Text = "!"
	lbl.TextColor3 = Color3.fromRGB(220, 25, 25)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
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
		axis = axis,
		dir = dir,
		roadLine = roadLine,
		side = side,
		posAlong = posAlong,
		walkSpeed = 7.5 + (idx % 4) * 1.2,
		dodgeCooldown = 0,
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
	ped.bubbleLabel.Text = if math.random() < 0.5 then "!" else "WHOA!"

	local away = (ped.root.Position - threatPos)
	local flatAway = Vector3.new(away.X, 0, away.Z)
	local dodgeDir = if flatAway.Magnitude > 0.1 then flatAway.Unit else Vector3.new(1, 0, 0)
	ped.leapOffset = dodgeDir * 7.5 + Vector3.new(0, 3.6, 0)

	task.delay(1.8, function()
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
spawnTrafficCars(18)
spawnPedestrians(28)

RunService.Heartbeat:Connect(function(dt: number)
	local clampedDt = math.min(dt, 0.1)

	-- Gather active player positions & velocities for threat detection
	local playerRoots: { BasePart } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			table.insert(playerRoots, hrp)
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
		local targetSpeed = if stop then 0 elseif car.panicTimer > 0 then car.baseSpeed * 1.75 else car.baseSpeed
		car.currentSpeed += (targetSpeed - car.currentSpeed) * math.min(1, clampedDt * 6)

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
