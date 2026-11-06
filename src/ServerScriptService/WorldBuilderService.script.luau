--!strict
-- WorldBuilderService.script.luau
-- Procedurally generates Leo City in Workspace.LeoCity with multi-block grid,
-- districts (Downtown, Industrial Construction Yard, Beachfront Boardwalk, Suburban Park),
-- interactive zones (Speed Shop, Mechanic Repair Bays, Stunt Ramps), and hundreds of
-- CollectionService-tagged "Destructible" props.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--------------------------------------------------------------------------------
-- SHARED EVENTS & FOLDERS
--------------------------------------------------------------------------------
local function ensureEvents()
	local serverEvents = ServerStorage:FindFirstChild("ServerEvents")
	if not serverEvents then
		serverEvents = Instance.new("Folder")
		serverEvents.Name = "ServerEvents"
		serverEvents.Parent = ServerStorage
	end
	if not serverEvents:FindFirstChild("DestructionOccurred") then
		local be = Instance.new("BindableEvent")
		be.Name = "DestructionOccurred"
		be.Parent = serverEvents
	end
	if not serverEvents:FindFirstChild("MechanicTriggered") then
		local be = Instance.new("BindableEvent")
		be.Name = "MechanicTriggered"
		be.Parent = serverEvents
	end
	if not serverEvents:FindFirstChild("SpeedShopTriggered") then
		local be = Instance.new("BindableEvent")
		be.Name = "SpeedShopTriggered"
		be.Parent = serverEvents
	end

	local repEvents = ReplicatedStorage:FindFirstChild("Remotes")
	if not repEvents then
		repEvents = Instance.new("Folder")
		repEvents.Name = "Remotes"
		repEvents.Parent = ReplicatedStorage
	end
	for _, name in ipairs({ "DestructionOccurred", "OpenSpeedShop", "VehicleRepaired", "StuntJumpTriggered" }) do
		if not repEvents:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = repEvents
		end
	end
	return serverEvents, repEvents
end

local ServerEvents, RemoteEvents = ensureEvents()

--------------------------------------------------------------------------------
-- CONSTANTS & GRID CONFIG
--------------------------------------------------------------------------------
local BLOCK_SIZE = 180 -- studs per city block (60m * 3 studs/m)
local ROAD_WIDTH = 36 -- 12m road
local SIDEWALK_WIDTH = 10 -- raised bluestone sidewalk
local GRID_RADIUS = 3 -- -3..3 = 7x7 city blocks (1260x1260 studs core + beachfront)

Workspace:SetAttribute("LeoCityBlockSize", BLOCK_SIZE)
Workspace:SetAttribute("LeoCityRoadWidth", ROAD_WIDTH)
Workspace:SetAttribute("LeoCityGridRadius", GRID_RADIUS)

local existingPreview = Workspace:FindFirstChild("LeoCity_EditPreview")
if existingPreview then
	existingPreview:Destroy()
end

local existingCity = Workspace:FindFirstChild("LeoCity")
if existingCity then
	existingCity:Destroy()
end

local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
if defaultSpawn and defaultSpawn:IsA("SpawnLocation") then
	defaultSpawn:Destroy()
end

local CityRoot = Instance.new("Folder")
CityRoot.Name = "LeoCity"
CityRoot.Parent = Workspace

local RoadsFolder = Instance.new("Folder")
RoadsFolder.Name = "Roads"
RoadsFolder.Parent = CityRoot

local BuildingsFolder = Instance.new("Folder")
BuildingsFolder.Name = "Buildings"
BuildingsFolder.Parent = CityRoot

local LandmarksFolder = Instance.new("Folder")
LandmarksFolder.Name = "Landmarks"
LandmarksFolder.Parent = CityRoot

local localZonesFolder = Instance.new("Folder")
localZonesFolder.Name = "InteractiveZones"
localZonesFolder.Parent = CityRoot

local PropsFolder = Instance.new("Folder")
PropsFolder.Name = "DestructibleProps"
PropsFolder.Parent = CityRoot

local TrafficLightsFolder = Instance.new("Folder")
TrafficLightsFolder.Name = "TrafficLights"
TrafficLightsFolder.Parent = CityRoot

--------------------------------------------------------------------------------
-- PART & SIGN HELPERS
--------------------------------------------------------------------------------
local function makePart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, anchored: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = if anchored == nil then true else anchored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function makeWedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = mat
	w.Anchored = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

local function addSurfaceSign(part: BasePart, text: string, textColor: Color3, face: Enum.NormalId?)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SignGui"
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 24
	sg.LightInfluence = 0
	sg.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0.2
	label.Parent = sg
end

local function weldChildrenToPrimary(model: Model, primary: BasePart)
	model.PrimaryPart = primary
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= primary then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = primary
			wc.Part1 = desc
			wc.Parent = primary
			desc.Anchored = false
		end
	end
end

local function tagDestructible(
	instance: Instance,
	propType: string,
	cashValue: number,
	chaosPoints: number,
	breakThreshold: number,
	explosive: boolean?
)
	instance:SetAttribute("PropType", propType)
	instance:SetAttribute("DestructibleType", propType)
	instance:SetAttribute("IsDestructible", true)
	instance:SetAttribute("CashValue", cashValue)
	instance:SetAttribute("CashReward", cashValue)
	instance:SetAttribute("ChaosPoints", chaosPoints)
	instance:SetAttribute("BreakThreshold", breakThreshold)
	instance:SetAttribute("Explosive", explosive == true)
	instance:SetAttribute("Destroyed", false)

	if instance:IsA("Model") and instance.PrimaryPart then
		instance:SetAttribute("OriginCFrame", instance.PrimaryPart.CFrame)
	elseif instance:IsA("BasePart") then
		instance:SetAttribute("OriginCFrame", instance.CFrame)
	end

	CollectionService:AddTag(instance, "Destructible")
end

--------------------------------------------------------------------------------
-- DESTRUCTIBLE PROP BUILDERS
--------------------------------------------------------------------------------

local function spawnFireHydrant(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "FireHydrant"

	local body = makePart(m, "Body", Vector3.new(1.6, 3.2, 1.6), CFrame.new(pos + Vector3.new(0, 1.6, 0)), Color3.fromRGB(220, 35, 35), Enum.Material.Metal, true)
	makePart(m, "Cap", Vector3.new(1.9, 0.6, 1.9), CFrame.new(pos + Vector3.new(0, 3.3, 0)), Color3.fromRGB(235, 235, 240), Enum.Material.Metal, false)
	makePart(m, "NozzleX", Vector3.new(2.2, 0.6, 0.6), CFrame.new(pos + Vector3.new(0, 2.2, 0)), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, false)

	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "FireHydrant", 25, 15, 18, false)
end

local function spawnStreetLight(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "StreetLight"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local pole = makePart(m, "Pole", Vector3.new(0.8, 16, 0.8), rot * CFrame.new(0, 8, 0), Color3.fromRGB(45, 50, 58), Enum.Material.Metal, true)
	makePart(m, "Base", Vector3.new(1.6, 2.2, 1.6), rot * CFrame.new(0, 1.1, 0), Color3.fromRGB(35, 40, 46), Enum.Material.Metal, false)
	makePart(m, "Arm", Vector3.new(0.5, 0.5, 5.5), rot * CFrame.new(0, 15.6, -2.5), Color3.fromRGB(45, 50, 58), Enum.Material.Metal, false)
	local bulb = makePart(m, "Bulb", Vector3.new(1.4, 0.4, 2.0), rot * CFrame.new(0, 15.2, -4.6), Color3.fromRGB(255, 215, 130), Enum.Material.Neon, false)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 140)
	light.Range = 36
	light.Brightness = 1.6
	light.Parent = bulb

	weldChildrenToPrimary(m, pole)
	m.Parent = PropsFolder
	tagDestructible(m, "StreetLight", 35, 20, 22, false)
end

local function spawnTrafficLight(intersectionPos: Vector3, cornerOffset: Vector3, yawDeg: number, axis: string)
	local m = Instance.new("Model")
	m.Name = "TrafficLight"
	local basePos = intersectionPos + cornerOffset
	local rot = CFrame.new(basePos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local pole = makePart(m, "Pole", Vector3.new(0.9, 17, 0.9), rot * CFrame.new(0, 8.5, 0), Color3.fromRGB(50, 54, 62), Enum.Material.Metal, true)
	makePart(m, "Arm", Vector3.new(9, 0.6, 0.6), rot * CFrame.new(4.2, 16, 0), Color3.fromRGB(50, 54, 62), Enum.Material.Metal, false)
	makePart(m, "Housing", Vector3.new(1.6, 4.2, 1.2), rot * CFrame.new(7.5, 15.2, 0), Color3.fromRGB(28, 30, 35), Enum.Material.Metal, false)

	local redLens = makePart(m, "RedLens", Vector3.new(0.9, 0.9, 0.3), rot * CFrame.new(7.5, 16.4, -0.55), Color3.fromRGB(255, 45, 45), Enum.Material.SmoothPlastic, false)
	local yellowLens = makePart(m, "YellowLens", Vector3.new(0.9, 0.9, 0.3), rot * CFrame.new(7.5, 15.2, -0.55), Color3.fromRGB(255, 200, 40), Enum.Material.SmoothPlastic, false)
	local greenLens = makePart(m, "GreenLens", Vector3.new(0.9, 0.9, 0.3), rot * CFrame.new(7.5, 14.0, -0.55), Color3.fromRGB(45, 255, 90), Enum.Material.Neon, false)
	redLens.CanCollide = false
	yellowLens.CanCollide = false
	greenLens.CanCollide = false

	weldChildrenToPrimary(m, pole)
	m:SetAttribute("IntersectionX", intersectionPos.X)
	m:SetAttribute("IntersectionZ", intersectionPos.Z)
	m:SetAttribute("TrafficAxis", axis) -- "NS" or "EW"
	m:SetAttribute("LightState", "Green")
	CollectionService:AddTag(m, "TrafficLight")

	m.Parent = TrafficLightsFolder
	tagDestructible(m, "TrafficLight", 45, 25, 25, false)
end

local function spawnCrateCluster(pos: Vector3, rows: number)
	local boxSize = 3.2
	for r = 0, rows - 1 do
		local count = math.max(1, rows - r)
		for c = 0, count - 1 do
			local offset = Vector3.new((c - (count - 1) * 0.5) * (boxSize + 0.2), r * boxSize + boxSize * 0.5, 0)
			local crate = makePart(
				PropsFolder,
				"WoodenCrate",
				Vector3.new(boxSize, boxSize, boxSize),
				CFrame.new(pos + offset) * CFrame.Angles(0, math.rad((r * 17 + c * 31) % 25 - 12), 0),
				Color3.fromRGB(145, 98, 56),
				Enum.Material.WoodPlanks,
				true
			)
			tagDestructible(crate, "WoodenCrate", 15, 10, 12, false)
		end
	end
end

local function spawnBench(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "ParkBench"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local seat = makePart(m, "Seat", Vector3.new(6, 0.5, 2.2), rot * CFrame.new(0, 1.6, 0), Color3.fromRGB(138, 88, 48), Enum.Material.Wood, true)
	makePart(m, "Backrest", Vector3.new(6, 1.8, 0.4), rot * CFrame.new(0, 2.6, -0.9), Color3.fromRGB(138, 88, 48), Enum.Material.Wood, false)
	makePart(m, "LegL", Vector3.new(0.5, 1.6, 2.0), rot * CFrame.new(-2.4, 0.8, 0), Color3.fromRGB(40, 42, 48), Enum.Material.Metal, false)
	makePart(m, "LegR", Vector3.new(0.5, 1.6, 2.0), rot * CFrame.new(2.4, 0.8, 0), Color3.fromRGB(40, 42, 48), Enum.Material.Metal, false)

	weldChildrenToPrimary(m, seat)
	m.Parent = PropsFolder
	tagDestructible(m, "Bench", 20, 12, 14, false)
end

local function spawnFenceRun(pos: Vector3, yawDeg: number, segments: number, color: Color3)
	local baseRot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for i = 1, segments do
		local segCF = baseRot * CFrame.new((i - (segments + 1) * 0.5) * 8, 1.8, 0)
		local fence = makePart(PropsFolder, "FencePanel", Vector3.new(7.6, 3.6, 0.5), segCF, color, Enum.Material.WoodPlanks, true)
		tagDestructible(fence, "Fence", 15, 8, 12, false)
	end
end

local function spawnBusStop(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "BusStop"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local backGlass = makePart(m, "GlassBack", Vector3.new(9, 7.5, 0.4), rot * CFrame.new(0, 3.75, -2.2), Color3.fromRGB(130, 200, 245), Enum.Material.Glass, true)
	backGlass.Transparency = 0.35
	makePart(m, "Roof", Vector3.new(9.8, 0.6, 5.2), rot * CFrame.new(0, 7.8, -0.2), Color3.fromRGB(48, 54, 66), Enum.Material.Metal, false)
	makePart(m, "PostL", Vector3.new(0.5, 7.6, 0.5), rot * CFrame.new(-4.3, 3.8, -2.2), Color3.fromRGB(70, 78, 90), Enum.Material.Metal, false)
	makePart(m, "PostR", Vector3.new(0.5, 7.6, 0.5), rot * CFrame.new(4.3, 3.8, -2.2), Color3.fromRGB(70, 78, 90), Enum.Material.Metal, false)
	local sign = makePart(m, "BusSign", Vector3.new(1.4, 2.2, 0.3), rot * CFrame.new(4.6, 6.2, 1.8), Color3.fromRGB(30, 140, 255), Enum.Material.Neon, false)
	addSurfaceSign(sign, "BUS", Color3.new(1, 1, 1), Enum.NormalId.Front)

	weldChildrenToPrimary(m, backGlass)
	m.Parent = PropsFolder
	tagDestructible(m, "BusStop", 60, 35, 24, false)
end

local function spawnBillboard(pos: Vector3, yawDeg: number, slogan: string, accentColor: Color3)
	local m = Instance.new("Model")
	m.Name = "Billboard"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local post = makePart(m, "SupportPost", Vector3.new(1.8, 16, 1.8), rot * CFrame.new(0, 8, 0), Color3.fromRGB(60, 64, 72), Enum.Material.Metal, true)
	local board = makePart(m, "Board", Vector3.new(18, 8, 1.2), rot * CFrame.new(0, 18, 0), Color3.fromRGB(24, 28, 38), Enum.Material.Metal, false)
	local trim = makePart(m, "NeonTrim", Vector3.new(18.6, 0.6, 1.4), rot * CFrame.new(0, 22.2, 0), accentColor, Enum.Material.Neon, false)
	trim.CanCollide = false
	addSurfaceSign(board, slogan, accentColor, Enum.NormalId.Front)
	addSurfaceSign(board, slogan, accentColor, Enum.NormalId.Back)

	weldChildrenToPrimary(m, post)
	m.Parent = PropsFolder
	tagDestructible(m, "Billboard", 85, 50, 32, false)
end

local function spawnConstructionBarrier(pos: Vector3, yawDeg: number)
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local barrier = makePart(PropsFolder, "ConstructionBarrier", Vector3.new(7.5, 3.0, 1.8), rot * CFrame.new(0, 1.5, 0), Color3.fromRGB(245, 125, 25), Enum.Material.Concrete, true)
	tagDestructible(barrier, "ConstructionBarrier", 25, 15, 20, false)
end

local function spawnExplosiveBarrel(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "ExplosiveBarrel"

	local drum = makePart(m, "Drum", Vector3.new(2.8, 4.0, 2.8), CFrame.new(pos + Vector3.new(0, 2.0, 0)), Color3.fromRGB(220, 28, 28), Enum.Material.Metal, true)
	local stripe = makePart(m, "HazardBand", Vector3.new(2.9, 0.8, 2.9), CFrame.new(pos + Vector3.new(0, 2.0, 0)), Color3.fromRGB(255, 210, 35), Enum.Material.Neon, false)
	stripe.CanCollide = false
	addSurfaceSign(drum, "TNT", Color3.fromRGB(255, 235, 80), Enum.NormalId.Front)

	weldChildrenToPrimary(m, drum)
	m.Parent = PropsFolder
	tagDestructible(m, "ExplosiveBarrel", 75, 60, 14, true)
end

local function spawnGasPump(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "GasPump"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local body = makePart(m, "PumpBody", Vector3.new(3.2, 6.5, 2.0), rot * CFrame.new(0, 3.25, 0), Color3.fromRGB(235, 45, 45), Enum.Material.Metal, true)
	local screen = makePart(m, "Display", Vector3.new(2.4, 1.8, 2.1), rot * CFrame.new(0, 4.8, 0), Color3.fromRGB(255, 215, 60), Enum.Material.Neon, false)
	screen.CanCollide = false
	addSurfaceSign(body, "FUEL", Color3.new(1, 1, 1), Enum.NormalId.Front)

	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "GasPump", 150, 110, 20, true)
end

local function spawnPalmTree(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "PalmTree"
	local trunk = makePart(m, "Trunk", Vector3.new(1.8, 16, 1.8), CFrame.new(pos + Vector3.new(0, 8, 0)), Color3.fromRGB(135, 95, 55), Enum.Material.Wood, true)
	for a = 0, 3 do
		local frondCF = CFrame.new(pos + Vector3.new(0, 16, 0)) * CFrame.Angles(math.rad(22), math.rad(a * 90), 0) * CFrame.new(0, 0, -3.8)
		makePart(m, "Frond", Vector3.new(2.8, 0.6, 7.5), frondCF, Color3.fromRGB(48, 165, 68), Enum.Material.Grass, false)
	end
	weldChildrenToPrimary(m, trunk)
	m.Parent = PropsFolder
	tagDestructible(m, "PalmTree", 35, 20, 24, false)
end

--------------------------------------------------------------------------------
-- INTERACTIVE ZONES: SPEED SHOP, MECHANIC BAYS, STUNT RAMPS
--------------------------------------------------------------------------------

local function buildStuntRamp(pos: Vector3, yawDeg: number, width: number, height: number, length: number, labelText: string)
	local m = Instance.new("Model")
	m.Name = labelText
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local wedge = makeWedge(
		m,
		"RampWedge",
		Vector3.new(width, height, length),
		rot * CFrame.new(0, height * 0.5, 0),
		Color3.fromRGB(50, 55, 68),
		Enum.Material.Concrete
	)
	-- Glowing neon launch rails
	makePart(m, "LeftRail", Vector3.new(0.8, height + 1, length), rot * CFrame.new(-width * 0.5 + 0.4, height * 0.5, 0), Color3.fromRGB(255, 145, 20), Enum.Material.Neon, true)
	makePart(m, "RightRail", Vector3.new(0.8, height + 1, length), rot * CFrame.new(width * 0.5 - 0.4, height * 0.5, 0), Color3.fromRGB(255, 145, 20), Enum.Material.Neon, true)

	local lipTrigger = makePart(m, "JumpTrigger", Vector3.new(width, 5, 4), rot * CFrame.new(0, height + 2.5, -length * 0.5 + 2), Color3.fromRGB(255, 220, 40), Enum.Material.Neon, true)
	lipTrigger.Transparency = 0.75
	lipTrigger.CanCollide = false
	CollectionService:AddTag(lipTrigger, "StuntRamp")

	local cooldowns: { [Player]: number } = {}
	lipTrigger.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then return end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local player = if hum then game:GetService("Players"):GetPlayerFromCharacter(model) else nil
		if not player then
			local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
			if seat and seat.Occupant then
				player = game:GetService("Players"):GetPlayerFromCharacter(seat.Occupant.Parent)
			end
		end
		if player and (os.clock() - (cooldowns[player] or 0) > 3.0) then
			cooldowns[player] = os.clock()
			if hit.AssemblyLinearVelocity.Magnitude > 35 then
				hit:ApplyImpulse(rot.LookVector * hit.AssemblyMass * 25 + Vector3.new(0, hit.AssemblyMass * 18, 0))
				local re = RemoteEvents:FindFirstChild("StuntJumpTriggered") :: RemoteEvent?
				if re then
					re:FireClient(player, labelText, pos)
				end
				local de = ServerEvents:FindFirstChild("DestructionOccurred") :: BindableEvent?
				if de then
					de:Fire({
						player = player,
						propType = "MegaStuntJump",
						cashEarned = 120,
						chaosPoints = 75,
						position = pos,
						isExplosion = false,
					})
				end
			end
		end
	end)

	m.Parent = localZonesFolder
end

local function buildSpeedShop(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "SpeedShop"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	makePart(m, "ShowroomFloor", Vector3.new(54, 0.8, 44), rot * CFrame.new(0, 0.4, 0), Color3.fromRGB(28, 32, 42), Enum.Material.Concrete, true)
	makePart(m, "BackWall", Vector3.new(52, 22, 2), rot * CFrame.new(0, 11, 16), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "LeftWall", Vector3.new(2, 22, 30), rot * CFrame.new(-25, 11, 2), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "RightWall", Vector3.new(2, 22, 30), rot * CFrame.new(25, 11, 2), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "Roof", Vector3.new(54, 1.6, 34), rot * CFrame.new(0, 22.5, 2), Color3.fromRGB(18, 20, 28), Enum.Material.Metal, true)

	local glass = makePart(m, "ShowroomGlass", Vector3.new(46, 16, 0.6), rot * CFrame.new(0, 8.5, -12), Color3.fromRGB(60, 210, 255), Enum.Material.Glass, true)
	glass.Transparency = 0.55

	local signBoard = makePart(m, "SignBoard", Vector3.new(38, 6.5, 1.5), rot * CFrame.new(0, 26.5, -11), Color3.fromRGB(16, 20, 30), Enum.Material.Metal, true)
	addSurfaceSign(signBoard, "LEO SPEED SHOP & DEALER", Color3.fromRGB(40, 240, 255), Enum.NormalId.Front)
	addSurfaceSign(signBoard, "LEO SPEED SHOP & DEALER", Color3.fromRGB(40, 240, 255), Enum.NormalId.Back)

	local pad = makePart(m, "SpeedShopPad", Vector3.new(20, 0.6, 16), rot * CFrame.new(0, 0.4, -22), Color3.fromRGB(25, 235, 255), Enum.Material.Neon, true)
	pad.CanCollide = false
	pad:SetAttribute("IsSpeedShop", true)
	CollectionService:AddTag(pad, "SpeedShopPad")
	CollectionService:AddTag(pad, "SpeedShop")

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Speed Shop"
	prompt.ObjectText = "Vehicle Dealer & Upgrades"
	prompt.MaxActivationDistance = 24
	prompt.HoldDuration = 0
	prompt.Parent = pad

	local touchCooldown: { [Player]: number } = {}
	local function triggerShop(player: Player)
		if os.clock() - (touchCooldown[player] or 0) < 3.0 then return end
		touchCooldown[player] = os.clock()
		local be = ServerEvents:FindFirstChild("SpeedShopTriggered") :: BindableEvent?
		if be then be:Fire(player) end
		local re = RemoteEvents:FindFirstChild("OpenSpeedShop") :: RemoteEvent?
		if re then re:FireClient(player) end
	end

	prompt.Triggered:Connect(triggerShop)
	pad.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then return end
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and seat.Occupant then
			local plr = game:GetService("Players"):GetPlayerFromCharacter(seat.Occupant.Parent)
			if plr then triggerShop(plr) end
		end
	end)

	m.Parent = localZonesFolder
end

local function buildMechanicRepairBay(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "MechanicRepairBay"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	makePart(m, "BayFloor", Vector3.new(36, 0.8, 36), rot * CFrame.new(0, 0.4, 0), Color3.fromRGB(34, 38, 46), Enum.Material.Concrete, true)
	makePart(m, "LeftWall", Vector3.new(2, 16, 28), rot * CFrame.new(-14, 8, 0), Color3.fromRGB(48, 52, 62), Enum.Material.Concrete, true)
	makePart(m, "RightWall", Vector3.new(2, 16, 28), rot * CFrame.new(14, 8, 0), Color3.fromRGB(48, 52, 62), Enum.Material.Concrete, true)
	makePart(m, "Roof", Vector3.new(32, 1.5, 30), rot * CFrame.new(0, 16.5, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, true)

	local sign = makePart(m, "MechanicSign", Vector3.new(28, 5, 1.4), rot * CFrame.new(0, 19.8, -13), Color3.fromRGB(20, 26, 32), Enum.Material.Metal, true)
	addSurfaceSign(sign, "INSTANT REPAIR & NITRO REFILL", Color3.fromRGB(60, 255, 120), Enum.NormalId.Front)
	addSurfaceSign(sign, "INSTANT REPAIR & NITRO REFILL", Color3.fromRGB(60, 255, 120), Enum.NormalId.Back)

	local pad = makePart(m, "RepairPad", Vector3.new(20, 0.6, 22), rot * CFrame.new(0, 0.5, 0), Color3.fromRGB(50, 255, 110), Enum.Material.Neon, true)
	pad.Transparency = 0.25
	pad.CanCollide = false
	pad:SetAttribute("IsMechanicSpot", true)
	CollectionService:AddTag(pad, "MechanicPad")
	CollectionService:AddTag(pad, "MechanicSpot")

	local cooldowns: { [Model]: number } = {}
	pad.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then return end
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		if not seat and not model:GetAttribute("VehicleHealth") and not model:GetAttribute("MaxHealth") then
			return
		end
		if os.clock() - (cooldowns[model] or 0) < 2.5 then return end
		cooldowns[model] = os.clock()

		-- Instant repair + nitro refill via attributes
		local maxHP = (model:GetAttribute("MaxHealth") :: number?) or 100
		model:SetAttribute("Health", maxHP)
		model:SetAttribute("VehicleHealth", maxHP)
		model:SetAttribute("Nitro", 100)
		model:SetAttribute("MaxNitro", 100)

		local player: Player? = nil
		if seat and seat.Occupant then
			player = game:GetService("Players"):GetPlayerFromCharacter(seat.Occupant.Parent)
		end
		local be = ServerEvents:FindFirstChild("MechanicTriggered") :: BindableEvent?
		if be then be:Fire(player, model) end
		if player then
			local re = RemoteEvents:FindFirstChild("VehicleRepaired") :: RemoteEvent?
			if re then re:FireClient(player, model) end
		end
	end)

	m.Parent = localZonesFolder
end

--------------------------------------------------------------------------------
-- DISTRICT & BLOCK ARCHITECTURES
--------------------------------------------------------------------------------

local function buildSkyscraper(center: Vector3, width: number, depth: number, height: number, tint: Color3, name: string, hasRooftopRamp: boolean?)
	local m = Instance.new("Model")
	m.Name = name

	-- 1. Granite Ground-Floor Podium & Colonnade Pillars
	local podiumH = 16
	local podiumColor = Color3.fromRGB(
		math.clamp(math.floor(tint.R * 255) + 18, 30, 220),
		math.clamp(math.floor(tint.G * 255) + 18, 30, 220),
		math.clamp(math.floor(tint.B * 255) + 22, 35, 230)
	)
	local podium = makePart(m, "PodiumBase", Vector3.new(width + 3.2, podiumH, depth + 3.2), CFrame.new(center + Vector3.new(0, podiumH * 0.5, 0)), podiumColor, Enum.Material.Granite, true)

	-- Recessed reflective glass lobby entrance + cantilevered canopy
	local lobbyGlass = makePart(m, "GlassLobby", Vector3.new(width * 0.84, podiumH - 2, depth + 3.5), CFrame.new(center + Vector3.new(0, (podiumH - 2) * 0.5, 0)), Color3.fromRGB(95, 175, 230), Enum.Material.Glass, true)
	lobbyGlass.Transparency = 0.28
	lobbyGlass.Reflectance = 0.25

	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(
				m,
				"CornerColonnade",
				Vector3.new(3.6, podiumH + 0.6, 3.6),
				CFrame.new(center + Vector3.new(sx * (width * 0.5), (podiumH + 0.6) * 0.5, sz * (depth * 0.5))),
				Color3.fromRGB(165, 172, 185),
				Enum.Material.Slate,
				true
			)
		end
	end

	-- Entrance Canopy Awning on Front & Back
	for _, sz in ipairs({ -1, 1 }) do
		makePart(
			m,
			"EntranceCanopy",
			Vector3.new(width * 0.52, 1.0, 5.2),
			CFrame.new(center + Vector3.new(0, 12.5, sz * (depth * 0.5 + 3.2))),
			Color3.fromRGB(32, 38, 48),
			Enum.Material.Metal,
			true
		)
	end

	-- 2. Main Architectural Tower Core with Reflective Glass Curtain Wall & Vertical Pilasters
	local shaft = makePart(m, "Shaft", Vector3.new(width - 1.6, height, depth - 1.6), CFrame.new(center + Vector3.new(0, height * 0.5, 0)), tint, Enum.Material.Concrete, true)

	local curtainZ = makePart(m, "GlassCurtainZ", Vector3.new(width - 3.2, height - podiumH - 6, depth + 0.2), CFrame.new(center + Vector3.new(0, podiumH + (height - podiumH - 6) * 0.5, 0)), Color3.fromRGB(68, 125, 175), Enum.Material.Glass, true)
	curtainZ.Reflectance = 0.28
	local curtainX = makePart(m, "GlassCurtainX", Vector3.new(width + 0.2, height - podiumH - 6, depth - 3.2), CFrame.new(center + Vector3.new(0, podiumH + (height - podiumH - 6) * 0.5, 0)), Color3.fromRGB(68, 125, 175), Enum.Material.Glass, true)
	curtainX.Reflectance = 0.28

	-- Vertical stone corner pilasters & center mullion ribs
	for _, sx in ipairs({ -1, 0, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local pilW = if sx == 0 then 1.8 else 2.8
			makePart(
				m,
				"VerticalPilasterZ",
				Vector3.new(pilW, height, 1.4),
				CFrame.new(center + Vector3.new(sx * (width * 0.46), height * 0.5, sz * (depth * 0.5))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
			makePart(
				m,
				"VerticalPilasterX",
				Vector3.new(1.4, height, pilW),
				CFrame.new(center + Vector3.new(sz * (width * 0.5), height * 0.5, sx * (depth * 0.46))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
		end
	end

	-- Horizontal spandrel ledges + warm recessed interior floor bands
	local floors = math.clamp(math.floor((height - podiumH) / 14), 3, 12)
	for f = 1, floors do
		local y = podiumH + (f - 0.5) * ((height - podiumH - 4) / floors)
		makePart(m, "SpandrelLedge", Vector3.new(width + 0.8, 1.1, depth + 0.8), CFrame.new(center + Vector3.new(0, y - 2.2, 0)), Color3.fromRGB(45, 52, 64), Enum.Material.Metal, true)
		if (f + math.floor(center.X)) % 2 == 0 then
			local warmLit = Color3.fromRGB(245, 222, 168)
			makePart(m, "LitOfficeFloor", Vector3.new(width - 2.4, 2.4, depth - 2.4), CFrame.new(center + Vector3.new(0, y, 0)), warmLit, Enum.Material.Neon, true)
		end
	end

	-- 3. Setback Crown, Mechanical Penthouse & Rooftop Helipad / Aviation Beacons
	local crownH = math.max(8, height * 0.14)
	local crown = makePart(m, "Crown", Vector3.new(width * 0.74, crownH, depth * 0.74), CFrame.new(center + Vector3.new(0, height + crownH * 0.5, 0)), podiumColor, Enum.Material.Metal, true)
	makePart(m, "RoofCornice", Vector3.new(width + 2.2, 1.6, depth + 2.2), CFrame.new(center + Vector3.new(0, height + 0.8, 0)), Color3.fromRGB(140, 148, 162), Enum.Material.Slate, true)

	local penthouseTopY = height + crownH
	makePart(m, "HelipadDeck", Vector3.new(width * 0.52, 0.6, depth * 0.52), CFrame.new(center + Vector3.new(0, penthouseTopY + 0.3, 0)), Color3.fromRGB(36, 40, 48), Enum.Material.Asphalt, true)

	-- Red aviation warning beacons on roof corners
	for _, sx in ipairs({ -1, 1 }) do
		local beacon = makePart(m, "AviationBeacon", Vector3.new(1.2, 1.2, 1.2), CFrame.new(center + Vector3.new(sx * (width * 0.34), penthouseTopY + 1.2, -depth * 0.34)), Color3.fromRGB(255, 45, 45), Enum.Material.Neon, true)
		beacon.Shape = Enum.PartType.Ball
		beacon.CanCollide = false
	end

	if name == "LeoTower" then
		local spire = makePart(m, "LeoSpire", Vector3.new(3.2, 34, 3.2), CFrame.new(center + Vector3.new(0, penthouseTopY + 17, 0)), Color3.fromRGB(255, 215, 65), Enum.Material.Neon, true)
		spire.CanCollide = false
		addSurfaceSign(crown, "LEO TOWER", Color3.fromRGB(255, 215, 65), Enum.NormalId.Front)
		addSurfaceSign(crown, "LEO TOWER", Color3.fromRGB(255, 215, 65), Enum.NormalId.Back)
	end

	if hasRooftopRamp then
		buildStuntRamp(center + Vector3.new(0, height, -depth * 0.3), 0, 18, 8, 24, "RooftopMegaJump")
	end

	m.PrimaryPart = podium
	m.Parent = BuildingsFolder
end

local function buildMidRiseCommercialBlock(origin: Vector3, variant: number)
	-- Varied mid-rise storefronts, awnings, outdoor cafe patio, and street trees
	local palettes = {
		{ wall = Color3.fromRGB(165, 92, 72), trim = Color3.fromRGB(235, 225, 210), sign = "LEO PIZZA & ARCADE", signCol = Color3.fromRGB(255, 195, 55) },
		{ wall = Color3.fromRGB(62, 84, 112), trim = Color3.fromRGB(215, 225, 238), sign = "METRO GRAND BANK", signCol = Color3.fromRGB(110, 225, 255) },
		{ wall = Color3.fromRGB(78, 92, 76), trim = Color3.fromRGB(230, 220, 195), sign = "SUNSET ESPRESSO CAFE", signCol = Color3.fromRGB(255, 160, 85) },
		{ wall = Color3.fromRGB(88, 72, 104), trim = Color3.fromRGB(220, 215, 235), sign = "TURBO AUTO PARTS", signCol = Color3.fromRGB(95, 245, 155) },
	}
	local p1 = palettes[(math.abs(variant) % #palettes) + 1]
	local p2 = palettes[((math.abs(variant) + 1) % #palettes) + 1]

	-- Building A (NW quadrant)
	local b1Center = origin + Vector3.new(-28, 0.3, -24)
	makePart(BuildingsFolder, "MidRiseStoreA", Vector3.new(44, 34, 38), CFrame.new(b1Center + Vector3.new(0, 17, 0)), p1.wall, Enum.Material.Brick, true)
	makePart(BuildingsFolder, "StoreCorniceA", Vector3.new(46, 2.2, 40), CFrame.new(b1Center + Vector3.new(0, 35, 0)), p1.trim, Enum.Material.Concrete, true)
	local glassA = makePart(BuildingsFolder, "StorefrontGlassA", Vector3.new(38, 10, 39.2), CFrame.new(b1Center + Vector3.new(0, 5.5, 0)), Color3.fromRGB(125, 195, 235), Enum.Material.Glass, true)
	glassA.Reflectance = 0.22
	local awningA = makePart(BuildingsFolder, "AwningA", Vector3.new(40, 1.2, 44), CFrame.new(b1Center + Vector3.new(0, 11.2, 0)), Color3.fromRGB(195, 48, 48), Enum.Material.Fabric, true)
	addSurfaceSign(awningA, p1.sign, p1.signCol, Enum.NormalId.Front)
	addSurfaceSign(awningA, p1.sign, p1.signCol, Enum.NormalId.Back)

	-- Building B (SE quadrant)
	local b2Center = origin + Vector3.new(28, 0.3, 24)
	makePart(BuildingsFolder, "MidRiseStoreB", Vector3.new(42, 42, 36), CFrame.new(b2Center + Vector3.new(0, 21, 0)), p2.wall, Enum.Material.Concrete, true)
	makePart(BuildingsFolder, "StoreCorniceB", Vector3.new(44, 2.2, 38), CFrame.new(b2Center + Vector3.new(0, 43, 0)), p2.trim, Enum.Material.Slate, true)
	local glassB = makePart(BuildingsFolder, "StorefrontGlassB", Vector3.new(36, 10, 37.2), CFrame.new(b2Center + Vector3.new(0, 5.5, 0)), Color3.fromRGB(125, 195, 235), Enum.Material.Glass, true)
	glassB.Reflectance = 0.22
	local signB = makePart(BuildingsFolder, "StoreSignB", Vector3.new(34, 4.2, 38), CFrame.new(b2Center + Vector3.new(0, 13.5, 0)), Color3.fromRGB(24, 28, 38), Enum.Material.Metal, true)
	addSurfaceSign(signB, p2.sign, p2.signCol, Enum.NormalId.Front)
	addSurfaceSign(signB, p2.sign, p2.signCol, Enum.NormalId.Back)

	-- Outdoor Cafe Patio & Trees in SW / NE plazas
	spawnPalmTree(origin + Vector3.new(-38, 0.3, 32))
	spawnPalmTree(origin + Vector3.new(38, 0.3, -32))
	spawnBench(origin + Vector3.new(-22, 0.3, 28), 0)
	spawnBench(origin + Vector3.new(22, 0.3, -28), 180)
	spawnFenceRun(origin + Vector3.new(24, 0.3, -48), 0, 3, Color3.fromRGB(215, 195, 165))
	spawnCrateCluster(origin + Vector3.new(-24, 0.3, 36), 2)
end

local function buildGasStation(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "LeoGasStation"
	makePart(m, "Canopy", Vector3.new(52, 2.2, 32), CFrame.new(origin + Vector3.new(0, 18, 0)), Color3.fromRGB(230, 45, 45), Enum.Material.Metal, true)
	local fascia = makePart(m, "Fascia", Vector3.new(52.6, 3.2, 32.6), CFrame.new(origin + Vector3.new(0, 19.5, 0)), Color3.fromRGB(255, 200, 40), Enum.Material.Neon, true)
	addSurfaceSign(fascia, "BOOM GAS & NITRO", Color3.fromRGB(30, 30, 35), Enum.NormalId.Front)
	addSurfaceSign(fascia, "BOOM GAS & NITRO", Color3.fromRGB(30, 30, 35), Enum.NormalId.Back)

	for _, sx in ipairs({ -18, 18 }) do
		for _, sz in ipairs({ -10, 10 }) do
			makePart(m, "Pillar", Vector3.new(2.2, 18, 2.2), CFrame.new(origin + Vector3.new(sx, 9, sz)), Color3.fromRGB(220, 225, 235), Enum.Material.Concrete, true)
		end
	end
	m.Parent = BuildingsFolder

	-- Explosive gas pumps & barrels!
	for _, px in ipairs({ -12, 0, 12 }) do
		spawnGasPump(origin + Vector3.new(px, 0, -4), 0)
		spawnGasPump(origin + Vector3.new(px, 0, 6), 180)
	end
	spawnExplosiveBarrel(origin + Vector3.new(-22, 0, 0))
	spawnExplosiveBarrel(origin + Vector3.new(22, 0, 0))
end

local function buildIndustrialYardBlock(origin: Vector3, seed: number)
	-- Crane centerpiece
	local crane = Instance.new("Model")
	crane.Name = "ConstructionCrane"
	local base = makePart(crane, "CraneBase", Vector3.new(12, 4, 12), CFrame.new(origin + Vector3.new(-35, 2, -35)), Color3.fromRGB(245, 185, 30), Enum.Material.Metal, true)
	makePart(crane, "Mast", Vector3.new(5, 85, 5), CFrame.new(origin + Vector3.new(-35, 44.5, -35)), Color3.fromRGB(245, 185, 30), Enum.Material.Metal, false)
	makePart(crane, "Jib", Vector3.new(75, 4, 4), CFrame.new(origin + Vector3.new(-10, 86, -35)), Color3.fromRGB(245, 185, 30), Enum.Material.Metal, false)
	weldChildrenToPrimary(crane, base)
	crane.Parent = PropsFolder
	tagDestructible(crane, "ConstructionCrane", 350, 250, 55, false)

	-- Warehouse
	makePart(BuildingsFolder, "Warehouse", Vector3.new(56, 26, 40), CFrame.new(origin + Vector3.new(28, 13, 25)), Color3.fromRGB(95, 65, 55), Enum.Material.CorrodedMetal, true)

	-- Explosive barrel clusters & crates
	for k = 1, 6 do
		local angle = (k / 6) * math.pi * 2 + seed
		local bPos = origin + Vector3.new(math.cos(angle) * 28, 0, math.sin(angle) * 28)
		spawnExplosiveBarrel(bPos)
		spawnExplosiveBarrel(bPos + Vector3.new(3.2, 0, 0))
	end
	spawnCrateCluster(origin + Vector3.new(-15, 0, 25), 3)
	spawnCrateCluster(origin + Vector3.new(10, 0, -25), 3)
	spawnConstructionBarrier(origin + Vector3.new(0, 0, -55), 0)
	spawnConstructionBarrier(origin + Vector3.new(-55, 0, 0), 90)
	spawnBillboard(origin + Vector3.new(-45, 0, 45), 45, "DANGER: BLAST ZONE", Color3.fromRGB(255, 90, 30))
end

local function buildSuburbanParkBlock(origin: Vector3)
	makePart(CityRoot, "ParkLawn", Vector3.new(BLOCK_SIZE - ROAD_WIDTH - 16, 0.8, BLOCK_SIZE - ROAD_WIDTH - 16), CFrame.new(origin + Vector3.new(0, 0.4, 0)), Color3.fromRGB(52, 135, 65), Enum.Material.Grass, true)
	makePart(CityRoot, "ParkPond", Vector3.new(46, 0.9, 34), CFrame.new(origin + Vector3.new(-22, 0.5, 18)), Color3.fromRGB(45, 155, 235), Enum.Material.Glass, true)

	-- Perimeter destructible white fences
	spawnFenceRun(origin + Vector3.new(0, 0, -56), 0, 5, Color3.fromRGB(240, 240, 245))
	spawnFenceRun(origin + Vector3.new(0, 0, 56), 0, 5, Color3.fromRGB(240, 240, 245))
	spawnBench(origin + Vector3.new(18, 0.8, 12), -45)
	spawnBench(origin + Vector3.new(18, 0.8, -12), -135)

	-- Park stunt jump over pond
	buildStuntRamp(origin + Vector3.new(-22, 0.8, -18), 180, 20, 9, 26, "ParkLakeMegaJump")
end

local function buildBeachfrontBoardwalk(origin: Vector3)
	-- Sandy beach + ocean water on East edge
	makePart(CityRoot, "BeachSand", Vector3.new(BLOCK_SIZE - ROAD_WIDTH, 0.7, BLOCK_SIZE - ROAD_WIDTH), CFrame.new(origin + Vector3.new(0, 0.35, 0)), Color3.fromRGB(235, 205, 145), Enum.Material.Sand, true)
	makePart(CityRoot, "BoardwalkDeck", Vector3.new(28, 1.0, BLOCK_SIZE - ROAD_WIDTH), CFrame.new(origin + Vector3.new(-38, 0.5, 0)), Color3.fromRGB(155, 108, 68), Enum.Material.WoodPlanks, true)

	-- Kiosks, palm trees, benches, and boardwalk stunt ramp
	for _, zOff in ipairs({ -42, 0, 42 }) do
		spawnPalmTree(origin + Vector3.new(-16, 0.6, zOff))
		spawnPalmTree(origin + Vector3.new(26, 0.6, zOff))
		spawnBench(origin + Vector3.new(-32, 1.0, zOff + 12), 90)
	end
	spawnCrateCluster(origin + Vector3.new(-36, 1.0, -20), 2)
	buildStuntRamp(origin + Vector3.new(10, 0.7, 0), 0, 18, 8, 24, "BoardwalkStuntJump")
end

--------------------------------------------------------------------------------
-- BUILD FULL LEO CITY
--------------------------------------------------------------------------------

local function buildLeoCity()
	local totalSpan = (GRID_RADIUS * 2 + 1) * BLOCK_SIZE + 240
	makePart(CityRoot, "CityBaseplate", Vector3.new(totalSpan, 4, totalSpan), CFrame.new(0, -2, 0), Color3.fromRGB(36, 40, 48), Enum.Material.Concrete, true)

	-- Ocean apron along the East beachfront (x > (GRID_RADIUS + 0.5) * BLOCK_SIZE)
	local oceanX = (GRID_RADIUS + 1.2) * BLOCK_SIZE
	makePart(CityRoot, "OceanWater", Vector3.new(360, 3.6, totalSpan), CFrame.new(oceanX, -1.6, 0), Color3.fromRGB(28, 125, 210), Enum.Material.Glass, true)

	-- SpawnLocation at Leo Plaza (0, 0, 0) — flush and invisible so there is no grey studded pad or curb step!
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "LeoPlazaSpawn"
	spawnLoc.Size = Vector3.new(12, 0.2, 12)
	spawnLoc.CFrame = CFrame.new(0, 0.15, 22)
	spawnLoc.Anchored = true
	spawnLoc.CanCollide = false
	spawnLoc.Transparency = 1
	spawnLoc.Neutral = true
	spawnLoc.Parent = CityRoot

	-- Grand Central Avenue straight through X = 0 and Z = 0 so the spawn area opens onto a dramatic boulevard vista
	local gridExtent = (GRID_RADIUS + 1) * BLOCK_SIZE
	makePart(RoadsFolder, "GrandCentralAveNS", Vector3.new(ROAD_WIDTH, 0.34, gridExtent * 2), CFrame.new(0, 0.17, 0), Color3.fromRGB(26, 28, 35), Enum.Material.Asphalt, true)
	for z = -gridExtent + 20, gridExtent - 20, 28 do
		makePart(RoadsFolder, "GrandAveDashNS", Vector3.new(0.8, 0.37, 12), CFrame.new(0, 0.185, z), Color3.fromRGB(245, 200, 55), Enum.Material.SmoothPlastic, true)
	end

	-- Build Road Grid & Intersections along block borders: (i + 0.5) * BLOCK_SIZE
	local roadLines = {}
	for i = -GRID_RADIUS - 1, GRID_RADIUS do
		table.insert(roadLines, (i + 0.5) * BLOCK_SIZE)
	end

	for _, rx in ipairs(roadLines) do
		makePart(RoadsFolder, "RoadNS", Vector3.new(ROAD_WIDTH, 0.3, gridExtent * 2), CFrame.new(rx, 0.15, 0), Color3.fromRGB(28, 30, 38), Enum.Material.Asphalt, true)
		-- Yellow center dashes
		for z = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashNS", Vector3.new(0.8, 0.34, 12), CFrame.new(rx, 0.17, z), Color3.fromRGB(240, 195, 50), Enum.Material.SmoothPlastic, true)
		end
	end

	for _, rz in ipairs(roadLines) do
		makePart(RoadsFolder, "RoadEW", Vector3.new(gridExtent * 2, 0.32, ROAD_WIDTH), CFrame.new(0, 0.16, rz), Color3.fromRGB(28, 30, 38), Enum.Material.Asphalt, true)
		for x = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashEW", Vector3.new(12, 0.35, 0.8), CFrame.new(x, 0.175, rz), Color3.fromRGB(240, 195, 50), Enum.Material.SmoothPlastic, true)
		end
	end

	-- Intersections: Crosswalks + Traffic Lights
	for _, rx in ipairs(roadLines) do
		for _, rz in ipairs(roadLines) do
			local interPos = Vector3.new(rx, 0, rz)
			for s = -2, 2 do
				if s ~= 0 then
					makePart(RoadsFolder, "CrosswalkN", Vector3.new(3.2, 0.36, 1.2), CFrame.new(rx + s * 5.5, 0.18, rz - ROAD_WIDTH * 0.5 - 2), Color3.fromRGB(220, 225, 235), Enum.Material.SmoothPlastic, true)
					makePart(RoadsFolder, "CrosswalkE", Vector3.new(1.2, 0.36, 3.2), CFrame.new(rx + ROAD_WIDTH * 0.5 + 2, 0.18, rz + s * 5.5), Color3.fromRGB(220, 225, 235), Enum.Material.SmoothPlastic, true)
				end
			end
			spawnTrafficLight(interPos, Vector3.new(-ROAD_WIDTH * 0.5 - 3, 0, -ROAD_WIDTH * 0.5 - 3), 0, "NS")
			spawnTrafficLight(interPos, Vector3.new(ROAD_WIDTH * 0.5 + 3, 0, ROAD_WIDTH * 0.5 + 3), 90, "EW")
		end
	end

	-- Populate each block (bx, bz) in -GRID_RADIUS..GRID_RADIUS
	for bx = -GRID_RADIUS, GRID_RADIUS do
		for bz = -GRID_RADIUS, GRID_RADIUS do
			local origin = Vector3.new(bx * BLOCK_SIZE, 0, bz * BLOCK_SIZE)
			local usable = BLOCK_SIZE - ROAD_WIDTH

			-- Low-profile smooth sidewalk framing block (0.26 studs tall so vehicles never snag on curbs)
			if bx ~= 0 then
				makePart(CityRoot, "SidewalkBlock", Vector3.new(usable, 0.26, usable), CFrame.new(origin + Vector3.new(0, 0.13, 0)), Color3.fromRGB(78, 84, 96), Enum.Material.Concrete, true)
			else
				-- Split sidewalk on left & right of Grand Central Avenue (X = -18..18 stays open asphalt!)
				local sideW = (usable - ROAD_WIDTH) * 0.5
				makePart(CityRoot, "SidewalkBlockW", Vector3.new(sideW, 0.26, usable), CFrame.new(origin + Vector3.new(-(ROAD_WIDTH * 0.5 + sideW * 0.5), 0.13, 0)), Color3.fromRGB(78, 84, 96), Enum.Material.Concrete, true)
				makePart(CityRoot, "SidewalkBlockE", Vector3.new(sideW, 0.26, usable), CFrame.new(origin + Vector3.new(ROAD_WIDTH * 0.5 + sideW * 0.5, 0.13, 0)), Color3.fromRGB(78, 84, 96), Enum.Material.Concrete, true)
			end

			-- Streetlights & Fire Hydrants on every block perimeter
			local edge = usable * 0.5 - 3.5
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, -edge), 45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, -edge), 135)
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, edge), -45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, edge), -135)
			spawnFireHydrant(origin + Vector3.new(-edge, 0.3, 0))
			spawnFireHydrant(origin + Vector3.new(edge, 0.3, 0))

			-- District & Landmark Assignment
			if bx == 0 and bz == 0 then
				-- LEO PLAZA & GRAND CENTRAL BOULEVARD:
				-- Central avenue (X = -18..18) is wide-open for driving straight ahead!
				-- Ornamental Circular Marble Fountain is placed in the West Plaza Courtyard (-42, 0, 12)
				local fCenter = origin + Vector3.new(-42, 0.3, 12)
				local fountain = makePart(LandmarksFolder, "LeoPlazaFountain", Vector3.new(3.2, 20, 20), CFrame.new(fCenter + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(215, 222, 232), Enum.Material.Marble, true)
				fountain.Shape = Enum.PartType.Cylinder
				local tier = makePart(LandmarksFolder, "FountainWaterTier", Vector3.new(1.4, 15, 15), CFrame.new(fCenter + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(65, 195, 245), Enum.Material.Glass, true)
				tier.Shape = Enum.PartType.Cylinder
				tier.Transparency = 0.25
				local spire = makePart(LandmarksFolder, "FountainWaterSpire", Vector3.new(8.5, 2.8, 2.8), CFrame.new(fCenter + Vector3.new(0, 7.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(185, 235, 255), Enum.Material.Marble, true)
				spire.Shape = Enum.PartType.Cylinder
				spire.CanCollide = false
				tagDestructible(fountain, "PlazaFountain", 500, 300, 75, false)

				spawnCrateCluster(origin + Vector3.new(-28, 0.3, -10), 3)
				spawnCrateCluster(origin + Vector3.new(28, 0.3, -10), 3)
				spawnBench(origin + Vector3.new(-26, 0.3, 12), 90)
				spawnBench(origin + Vector3.new(26, 0.3, 12), -90)
				spawnPalmTree(origin + Vector3.new(-26, 0.3, 34))
				spawnPalmTree(origin + Vector3.new(26, 0.3, 34))

				-- Stunt ramp down the North end of Grand Central Boulevard & Plaza Speed Shop / Mechanic Bay on East/West flanks
				buildStuntRamp(origin + Vector3.new(0, 0.3, -68), 0, 16, 7.5, 24, "LeoPlazaRamp")
				buildSpeedShop(origin + Vector3.new(54, 0.3, -24), -90)
				buildMechanicRepairBay(origin + Vector3.new(-54, 0.3, -24), 90)
			elseif bx == 1 and bz == 0 then
				buildSpeedShop(origin + Vector3.new(0, 0.3, 0), -90)
				spawnBusStop(origin + Vector3.new(0, 0.3, -edge + 2), 0)
			elseif bx == -1 and bz == 0 then
				buildMechanicRepairBay(origin + Vector3.new(0, 0.3, 0), 90)
				spawnBusStop(origin + Vector3.new(0, 0.3, edge - 2), 180)
			elseif bx == 0 and bz == -2 then
				buildGasStation(origin + Vector3.new(44, 0.3, 0))
				buildMechanicRepairBay(origin + Vector3.new(-44, 0.3, 0), 90)
			elseif bx == 2 and bz == 2 then
				buildSpeedShop(origin + Vector3.new(0, 0.3, 0), 180)
			elseif bx == -2 and bz == 2 then
				buildGasStation(origin + Vector3.new(0, 0.3, 0))
			elseif bx == GRID_RADIUS then
				-- East Coastline: Beachfront Boardwalk
				buildBeachfrontBoardwalk(origin)
			elseif bx <= -2 and bz <= -1 then
				-- NW Sector: Industrial Construction Yard with cranes & explosive barrels
				buildIndustrialYardBlock(origin + Vector3.new(0, 0.3, 0), bx * 7 + bz * 13)
			elseif bx <= -2 and bz >= 1 then
				-- SW Sector: Suburban Park & Lake
				buildSuburbanParkBlock(origin)
			elseif math.abs(bx) <= 1 and math.abs(bz) <= 1 then
				-- Downtown Skyscraper Core (placed outside X = -18..18 when bx == 0 so Grand Central Avenue stays clear!)
				local isLeoTower = (bx == 0 and bz == -1) or (bx == 1 and bz == -1)
				local h = if (bx == 0 and bz == -1) then 195 elseif (bx == 1 and bz == -1) then 175 else 115 + ((math.abs(bx * 3 + bz * 5) % 4) * 18)
				local col = if isLeoTower then Color3.fromRGB(32, 46, 72) else Color3.fromRGB(48, 56, 74)
				local towerName = if (bx == 0 and bz == -1) then "LeoTower" else "DowntownTower"
				local xOff = if bx == 0 then 44 else 28
				buildSkyscraper(origin + Vector3.new(-xOff, 0.3, -26), 38, 38, h, col, towerName, isLeoTower)
				buildSkyscraper(origin + Vector3.new(xOff, 0.3, 26), 36, 36, 96, Color3.fromRGB(58, 66, 82), "GlassOfficeTower", false)
				spawnBusStop(origin + Vector3.new(-edge + 2, 0.3, 0), 90)
				spawnCrateCluster(origin + Vector3.new(xOff, 0.3, -26), 3)
				spawnBillboard(origin + Vector3.new(-xOff, 0.3, 28), 0, "SMASH FOR CASH!", Color3.fromRGB(255, 200, 40))
			else
				-- Mixed Commercial / Midtown Storefront blocks
				buildMidRiseCommercialBlock(origin, bx * 5 + bz * 11)
			end
		end
	end
end

buildLeoCity()
Workspace:SetAttribute("LeoCityReady", true)
print(string.format("[WorldBuilderService] Leo City built with %d destructible props!", #CollectionService:GetTagged("Destructible")))
