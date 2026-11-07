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
local BLOCK_SIZE = 200 -- studs per city block (expanded 2,200 x 2,200 stud metropolitan map!)
local ROAD_WIDTH = 42 -- wide 4-lane sunlit avenues
local SIDEWALK_WIDTH = 10 -- bright warm limestone sidewalk
local GRID_RADIUS = 4 -- -4..4 = 9x9 full city blocks (2,200 x 2,200 studs total span)

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

	local body = makePart(m, "Body", Vector3.new(1.6, 3.2, 1.6), CFrame.new(pos + Vector3.new(0, 1.6, 0)), Color3.fromRGB(215, 38, 35), Enum.Material.Metal, true)
	makePart(m, "Cap", Vector3.new(1.9, 0.6, 1.9), CFrame.new(pos + Vector3.new(0, 3.3, 0)), Color3.fromRGB(225, 228, 236), Enum.Material.Metal, false)
	makePart(m, "NozzleX", Vector3.new(2.2, 0.6, 0.6), CFrame.new(pos + Vector3.new(0, 2.2, 0)), Color3.fromRGB(195, 200, 208), Enum.Material.Metal, false)

	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "FireHydrant", 35, 20, 4, false)
end

local function spawnStreetLight(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "StreetLight"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local pole = makePart(m, "Pole", Vector3.new(0.8, 16, 0.8), rot * CFrame.new(0, 8, 0), Color3.fromRGB(38, 42, 50), Enum.Material.Metal, true)
	makePart(m, "Base", Vector3.new(1.6, 2.2, 1.6), rot * CFrame.new(0, 1.1, 0), Color3.fromRGB(30, 34, 42), Enum.Material.Metal, false)
	makePart(m, "Arm", Vector3.new(0.5, 0.5, 5.5), rot * CFrame.new(0, 15.6, -2.5), Color3.fromRGB(38, 42, 50), Enum.Material.Metal, false)
	local bulb = makePart(m, "Bulb", Vector3.new(1.4, 0.4, 2.0), rot * CFrame.new(0, 15.2, -4.6), Color3.fromRGB(255, 212, 135), Enum.Material.Neon, false)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 212, 145)
	light.Range = 38
	light.Brightness = 1.75
	light.Parent = bulb

	weldChildrenToPrimary(m, pole)
	m.Parent = PropsFolder
	tagDestructible(m, "StreetLight", 45, 25, 4, false)
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

	-- Support post stops cleanly at Y = 14 (below the board at Y = 14..22) so no pole ever slices through sign text!
	local post = makePart(m, "SupportPost", Vector3.new(1.8, 14, 1.8), rot * CFrame.new(0, 7, 0), Color3.fromRGB(48, 52, 62), Enum.Material.Metal, true)
	makePart(m, "Crossbeam", Vector3.new(12, 0.8, 2.0), rot * CFrame.new(0, 13.8, 0), Color3.fromRGB(42, 46, 56), Enum.Material.Metal, false)
	local board = makePart(m, "Board", Vector3.new(18, 8, 1.2), rot * CFrame.new(0, 18, 0), Color3.fromRGB(18, 22, 32), Enum.Material.Metal, false)
	local trim = makePart(m, "NeonTrim", Vector3.new(18.6, 0.6, 1.4), rot * CFrame.new(0, 22.3, 0), accentColor, Enum.Material.Neon, false)
	trim.CanCollide = false
	addSurfaceSign(board, slogan, accentColor, Enum.NormalId.Front)
	addSurfaceSign(board, slogan, accentColor, Enum.NormalId.Back)

	weldChildrenToPrimary(m, post)
	m.Parent = PropsFolder
	tagDestructible(m, "Billboard", 85, 50, 12, false)
end

local function spawnJackpotCrate(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "JackpotCrate"

	local core = makePart(m, "GoldCore", Vector3.new(4.2, 4.2, 4.2), CFrame.new(pos + Vector3.new(0, 2.1, 0)), Color3.fromRGB(255, 205, 35), Enum.Material.Metal, true)
	local bandH = makePart(m, "NeonBandH", Vector3.new(4.4, 0.9, 4.4), CFrame.new(pos + Vector3.new(0, 2.1, 0)), Color3.fromRGB(255, 235, 90), Enum.Material.Neon, false)
	bandH.CanCollide = false
	local bandV = makePart(m, "NeonBandV", Vector3.new(0.9, 4.4, 4.4), CFrame.new(pos + Vector3.new(0, 2.1, 0)), Color3.fromRGB(255, 235, 90), Enum.Material.Neon, false)
	bandV.CanCollide = false

	addSurfaceSign(core, "777 JACKPOT", Color3.fromRGB(255, 250, 210), Enum.NormalId.Front)
	addSurfaceSign(core, "777 JACKPOT", Color3.fromRGB(255, 250, 210), Enum.NormalId.Back)

	weldChildrenToPrimary(m, core)
	m:SetAttribute("IsJackpotCrate", true)
	m.Parent = PropsFolder
	tagDestructible(m, "JackpotCrate", 250, 180, 5, false)
end

local function spawnSteamingManhole(pos: Vector3)
	local cover = makePart(
		RoadsFolder,
		"SteamingManhole",
		Vector3.new(0.18, 3.6, 3.6),
		CFrame.new(pos.X, 0.22, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(44, 48, 56),
		Enum.Material.DiamondPlate,
		true
	)
	cover.Shape = Enum.PartType.Cylinder
	cover.CanCollide = false

	local steam = Instance.new("ParticleEmitter")
	steam.Name = "NYCSteamVent"
	steam.Color = ColorSequence.new(Color3.fromRGB(215, 225, 240))
	steam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 2.4),
		NumberSequenceKeypoint.new(1, 4.2),
	})
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.6, 0.72),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	steam.Lifetime = NumberRange.new(1.8, 2.8)
	steam.Rate = 14
	steam.Speed = NumberRange.new(3.5, 6.5)
	steam.SpreadAngle = Vector2.new(14, 14)
	steam.EmissionDirection = Enum.NormalId.Right
	steam.Parent = cover
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
	local trunk = makePart(m, "Trunk", Vector3.new(1.8, 16, 1.8), CFrame.new(pos + Vector3.new(0, 8, 0)), Color3.fromRGB(148, 108, 65), Enum.Material.Wood, true)
	for a = 0, 3 do
		local frondCF = CFrame.new(pos + Vector3.new(0, 16, 0)) * CFrame.Angles(math.rad(22), math.rad(a * 90), 0) * CFrame.new(0, 0, -3.8)
		makePart(m, "Frond", Vector3.new(2.8, 0.6, 7.5), frondCF, Color3.fromRGB(58, 182, 78), Enum.Material.Grass, false)
	end
	weldChildrenToPrimary(m, trunk)
	m.Parent = PropsFolder
	tagDestructible(m, "PalmTree", 35, 20, 24, false)
end

local VENDOR_VARIANTS = {
	{
		name = "HotdogVendorCart",
		cartColor = Color3.fromRGB(235, 58, 45),
		umbrellaColor = Color3.fromRGB(255, 205, 45),
		menuText = "LEO HOTDOGS $2",
		signColor = Color3.fromRGB(255, 235, 85),
	},
	{
		name = "TacoStreetCart",
		cartColor = Color3.fromRGB(245, 145, 38),
		umbrellaColor = Color3.fromRGB(52, 195, 125),
		menuText = "EL SOL TACOS",
		signColor = Color3.fromRGB(255, 245, 155),
	},
	{
		name = "IceCreamGelatoCart",
		cartColor = Color3.fromRGB(85, 195, 245),
		umbrellaColor = Color3.fromRGB(255, 115, 165),
		menuText = "SUNSET GELATO",
		signColor = Color3.fromRGB(255, 255, 255),
	},
}

local function spawnFoodVendorCart(pos: Vector3, yawDeg: number, variant: number?)
	local v = VENDOR_VARIANTS[((math.abs(variant or 1)) % #VENDOR_VARIANTS) + 1]
	local m = Instance.new("Model")
	m.Name = v.name
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local body = makePart(m, "CartBody", Vector3.new(5.6, 3.4, 3.2), rot * CFrame.new(0, 2.1, 0), v.cartColor, Enum.Material.SmoothPlastic, true)
	makePart(m, "CounterTop", Vector3.new(6.0, 0.35, 3.5), rot * CFrame.new(0, 3.95, 0), Color3.fromRGB(230, 235, 242), Enum.Material.Metal, false)
	makePart(m, "SneezeGuard", Vector3.new(5.4, 1.4, 0.25), rot * CFrame.new(0, 4.8, -1.4), Color3.fromRGB(175, 228, 255), Enum.Material.Glass, false)
	makePart(m, "UmbrellaPole", Vector3.new(0.35, 5.2, 0.35), rot * CFrame.new(0, 6.4, 0), Color3.fromRGB(220, 225, 235), Enum.Material.Metal, false)
	makePart(m, "UmbrellaCanopy", Vector3.new(7.4, 0.9, 6.2), rot * CFrame.new(0, 8.9, 0), v.umbrellaColor, Enum.Material.Fabric, false)
	makePart(m, "UmbrellaStripe", Vector3.new(7.6, 0.4, 2.2), rot * CFrame.new(0, 9.0, 0), Color3.fromRGB(250, 250, 252), Enum.Material.Fabric, false)

	local menuBoard = makePart(m, "MenuSign", Vector3.new(4.8, 1.3, 0.35), rot * CFrame.new(0, 7.6, -1.6), Color3.fromRGB(28, 32, 42), Enum.Material.Metal, false)
	addSurfaceSign(menuBoard, v.menuText, v.signColor, Enum.NormalId.Front)
	addSurfaceSign(menuBoard, v.menuText, v.signColor, Enum.NormalId.Back)

	for _, sx in ipairs({ -2.1, 2.1 }) do
		local wheel = makePart(m, "CartWheel", Vector3.new(0.45, 1.6, 1.6), rot * CFrame.new(sx, 0.8, 1.65) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(35, 38, 45), Enum.Material.SmoothPlastic, false)
		wheel.Shape = Enum.PartType.Cylinder
	end

	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "FoodVendorCart", 85, 55, 12, false)
end

local function spawnCafePatio(pos: Vector3, yawDeg: number)
	local baseRot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local umbrellaColors = {
		Color3.fromRGB(240, 82, 68),
		Color3.fromRGB(48, 175, 235),
		Color3.fromRGB(245, 185, 45),
	}

	for i = 1, 2 do
		local offsetX = (i - 1.5) * 9.5
		local tableRot = baseRot * CFrame.new(offsetX, 0, 0)
		local m = Instance.new("Model")
		m.Name = "CafePatioSet"

		local top = makePart(m, "CafeTable", Vector3.new(0.35, 3.8, 3.8), tableRot * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(245, 242, 235), Enum.Material.Marble, true)
		top.Shape = Enum.PartType.Cylinder
		makePart(m, "TablePedestal", Vector3.new(0.45, 2.6, 0.45), tableRot * CFrame.new(0, 1.3, 0), Color3.fromRGB(55, 60, 70), Enum.Material.Metal, false)
		makePart(m, "UmbrellaMast", Vector3.new(0.3, 5.4, 0.3), tableRot * CFrame.new(0, 5.3, 0), Color3.fromRGB(235, 235, 240), Enum.Material.Metal, false)
		local uCol = umbrellaColors[((i + math.floor(math.abs(pos.X))) % #umbrellaColors) + 1]
		makePart(m, "CafeUmbrella", Vector3.new(6.2, 0.8, 6.2), tableRot * CFrame.new(0, 7.8, 0), uCol, Enum.Material.Fabric, false)

		for _, cx in ipairs({ -2.7, 2.7 }) do
			makePart(m, "CafeChairSeat", Vector3.new(1.6, 0.3, 1.6), tableRot * CFrame.new(cx, 1.5, 0), Color3.fromRGB(215, 155, 95), Enum.Material.Wood, false)
			makePart(m, "CafeChairBack", Vector3.new(0.25, 1.6, 1.6), tableRot * CFrame.new(cx + (if cx > 0 then 0.7 else -0.7), 2.3, 0), Color3.fromRGB(215, 155, 95), Enum.Material.Wood, false)
		end

		weldChildrenToPrimary(m, top)
		m.Parent = PropsFolder
		tagDestructible(m, "CafePatio", 45, 30, 10, false)
	end
end

local function spawnStreetClutterRow(pos: Vector3, yawDeg: number)
	local baseRot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	-- 1. Red & Yellow Newspaper Boxes (BreakThreshold = 8 for effortless sidewalk combo chains!)
	local newsRed = makePart(PropsFolder, "NewspaperBox", Vector3.new(1.8, 3.2, 1.6), baseRot * CFrame.new(-4.8, 1.6, 0), Color3.fromRGB(228, 48, 42), Enum.Material.Metal, true)
	addSurfaceSign(newsRed, "DAILY NEWS", Color3.fromRGB(255, 255, 255), Enum.NormalId.Front)
	tagDestructible(newsRed, "NewspaperBox", 20, 12, 8, false)

	local newsYellow = makePart(PropsFolder, "NewspaperBox", Vector3.new(1.8, 3.2, 1.6), baseRot * CFrame.new(-2.4, 1.6, 0), Color3.fromRGB(248, 198, 38), Enum.Material.Metal, true)
	addSurfaceSign(newsYellow, "METRO TIMES", Color3.fromRGB(25, 28, 35), Enum.NormalId.Front)
	tagDestructible(newsYellow, "NewspaperBox", 20, 12, 8, false)

	-- 2. Classic Blue City Mailbox
	local mailbox = makePart(PropsFolder, "CityMailbox", Vector3.new(2.0, 3.8, 1.8), baseRot * CFrame.new(0.2, 1.9, 0), Color3.fromRGB(38, 108, 215), Enum.Material.Metal, true)
	addSurfaceSign(mailbox, "US MAIL", Color3.fromRGB(255, 255, 255), Enum.NormalId.Front)
	tagDestructible(mailbox, "Mailbox", 25, 16, 8, false)

	-- 3. Green Trash Can & Blue Recycling Bin
	local trashCan = makePart(PropsFolder, "TrashCan", Vector3.new(1.9, 3.0, 1.9), baseRot * CFrame.new(2.8, 1.5, 0), Color3.fromRGB(48, 152, 78), Enum.Material.SmoothPlastic, true)
	tagDestructible(trashCan, "TrashCan", 18, 12, 8, false)

	local recycleBin = makePart(PropsFolder, "RecyclingBin", Vector3.new(1.9, 3.0, 1.9), baseRot * CFrame.new(5.1, 1.5, 0), Color3.fromRGB(42, 145, 235), Enum.Material.SmoothPlastic, true)
	addSurfaceSign(recycleBin, "RECYCLE", Color3.fromRGB(255, 255, 255), Enum.NormalId.Front)
	tagDestructible(recycleBin, "RecyclingBin", 18, 12, 8, false)
end

local function spawnMegaCorpSurveillanceTower(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "MegaCorpSurveillanceTower"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local pylon = makePart(m, "TowerPylon", Vector3.new(2.6, 20, 2.6), rot * CFrame.new(0, 10, 0), Color3.fromRGB(38, 42, 54), Enum.Material.Metal, true)
	local screen = makePart(m, "PropagandaScreen", Vector3.new(9.5, 5.5, 1.0), rot * CFrame.new(0, 14.5, 0), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, false)
	local scanner = makePart(m, "ScannerBeacon", Vector3.new(3.2, 1.8, 3.2), rot * CFrame.new(0, 20.8, 0), Color3.fromRGB(255, 48, 65), Enum.Material.Neon, false)
	addSurfaceSign(screen, "MEGACORP WATCHES YOU\n[SMASH FOR BONUS!]", Color3.fromRGB(255, 75, 75), Enum.NormalId.Front)
	addSurfaceSign(screen, "MEGACORP PROPERTY\n[TARGET]", Color3.fromRGB(255, 205, 55), Enum.NormalId.Back)

	weldChildrenToPrimary(m, pylon)
	m.Parent = PropsFolder
	tagDestructible(m, "MegaCorpTower", 140, 95, 20, true)
end

--------------------------------------------------------------------------------
-- INTERACTIVE ZONES: SPEED SHOP, MECHANIC BAYS, 3-STAGE CURVED STUNT RAMPS
--------------------------------------------------------------------------------

local function buildStuntRamp(pos: Vector3, yawDeg: number, width: number, height: number, length: number, labelText: string)
	local m = Instance.new("Model")
	m.Name = labelText
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	-- Seamless 1-piece low-angle steel ramp (NO stepped grey blocks, NO giant yellow walls!)
	local rampWidth = math.max(width, 26)
	local totalLen = math.max(length, 38)
	local rampHeight = math.clamp(height, 5.2, 6.8)
	local y0 = -0.22 -- Sunk slightly below road surface so approach is 100% flush

	local rampPhysProps = PhysicalProperties.new(0.7, 0.3, 0.0, 1.0, 1.0)
	local steelDeckColor = Color3.fromRGB(42, 48, 58)
	local trimGlowColor = Color3.fromRGB(85, 220, 255)

	-- Single continuous 1-piece steel WedgePart deck
	local wedge1 = makeWedge(
		m,
		"RampWedge",
		Vector3.new(rampWidth, rampHeight, totalLen),
		rot * CFrame.new(0, y0 + rampHeight * 0.5, 0),
		steelDeckColor,
		Enum.Material.Metal
	)
	wedge1.CustomPhysicalProperties = rampPhysProps
	CollectionService:AddTag(wedge1, "StuntRampSurface")
	CollectionService:AddTag(wedge1, "StuntRamp")

	-- Flush steel approach transition plate at the toe of the ramp
	local approachPlate = makePart(
		m,
		"ApproachTransitionPlate",
		Vector3.new(rampWidth, 0.24, 4.5),
		rot * CFrame.new(0, 0.04, totalLen * 0.5 + 1.8),
		Color3.fromRGB(54, 60, 72),
		Enum.Material.DiamondPlate,
		true
	)
	approachPlate.CustomPhysicalProperties = rampPhysProps
	CollectionService:AddTag(approachPlate, "StuntRampSurface")

	-- Slope-aligned low-profile side guide strips (CanCollide = false, no giant walls!)
	local slopePitchRad = math.atan2(rampHeight, totalLen)
	local slopeHyp = math.sqrt(totalLen * totalLen + rampHeight * rampHeight)
	for _, sx in ipairs({ -1, 1 }) do
		local rail = makePart(
			m,
			if sx < 0 then "LeftEdgeTrim" else "RightEdgeTrim",
			Vector3.new(0.45, 0.32, slopeHyp),
			rot * CFrame.new(sx * (rampWidth * 0.5 - 0.25), y0 + rampHeight * 0.5 + 0.12, 0) * CFrame.Angles(slopePitchRad, 0, 0),
			trimGlowColor,
			Enum.Material.Neon,
			true
		)
		rail.CanCollide = false
		rail.CanTouch = false
		rail.CanQuery = false
	end

	-- Invisible launch trigger at the top lip (Transparency = 1, no giant yellow wall!)
	local lipTrigger = makePart(
		m,
		"JumpTrigger",
		Vector3.new(rampWidth, 5, 4),
		rot * CFrame.new(0, rampHeight + 2.0, -totalLen * 0.5 + 1.5),
		trimGlowColor,
		Enum.Material.SmoothPlastic,
		true
	)
	lipTrigger.Transparency = 1.0
	lipTrigger.CanCollide = false
	CollectionService:AddTag(lipTrigger, "StuntRamp")
	CollectionService:AddTag(m, "StuntRamp")

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
		if player and (os.clock() - (cooldowns[player] or 0) > 2.5) then
			if hit.AssemblyLinearVelocity.Magnitude > 22 then
				cooldowns[player] = os.clock()
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

	m.PrimaryPart = wedge1
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

local SKYSCRAPER_GLASS_PALETTES = {
	Color3.fromRGB(68, 96, 128), -- Moody NYC steel-blue glass
	Color3.fromRGB(54, 78, 108), -- Gotham midnight slate glass
	Color3.fromRGB(92, 112, 138), -- Overcast Hudson reflection glass
	Color3.fromRGB(78, 88, 112), -- Dark granite reflection glass
}

local SKYSCRAPER_STONE_PALETTES = {
	Color3.fromRGB(72, 78, 90), -- Dark Gotham limestone
	Color3.fromRGB(58, 64, 76), -- Charcoal Manhattan granite
	Color3.fromRGB(88, 72, 64), -- NYC brownstone masonry
	Color3.fromRGB(64, 70, 82), -- Wet slate stone
	Color3.fromRGB(96, 86, 74), -- Aged Art Deco travertine
}

local function buildSkyscraper(center: Vector3, width: number, depth: number, height: number, tint: Color3, name: string, hasRooftopRamp: boolean?)
	local m = Instance.new("Model")
	m.Name = name

	local paletteSeed = math.abs(math.floor(center.X * 0.13 + center.Z * 0.17))
	local glassTint = SKYSCRAPER_GLASS_PALETTES[(paletteSeed % #SKYSCRAPER_GLASS_PALETTES) + 1]
	local stoneTint = SKYSCRAPER_STONE_PALETTES[(paletteSeed % #SKYSCRAPER_STONE_PALETTES) + 1]

	-- 1. Gotham Art Deco Limestone & Granite Podium
	local podiumH = 16
	local podiumColor = stoneTint
	local podium = makePart(m, "PodiumBase", Vector3.new(width + 3.2, podiumH, depth + 3.2), CFrame.new(center + Vector3.new(0, podiumH * 0.5, 0)), podiumColor, Enum.Material.Limestone, true)

	-- Recessed warm amber/brass lobby entrance + cantilevered canopy
	local lobbyGlass = makePart(m, "GlassLobby", Vector3.new(width * 0.84, podiumH - 2, depth + 3.5), CFrame.new(center + Vector3.new(0, (podiumH - 2) * 0.5, 0)), Color3.fromRGB(255, 205, 125), Enum.Material.Glass, true)
	lobbyGlass.Transparency = 0.25
	lobbyGlass.Reflectance = 0.32

	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(
				m,
				"CornerColonnade",
				Vector3.new(3.6, podiumH + 0.6, 3.6),
				CFrame.new(center + Vector3.new(sx * (width * 0.5), (podiumH + 0.6) * 0.5, sz * (depth * 0.5))),
				Color3.fromRGB(52, 58, 70),
				Enum.Material.Limestone,
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
			Color3.fromRGB(44, 48, 58),
			Enum.Material.Metal,
			true
		)
	end

	-- 2. Main Art Deco Stepped Tower Core with Reflective Glass Curtain Wall & Vertical Pilasters
	local lowerH = height * 0.72
	local midSetbackH = height * 0.28
	makePart(m, "Shaft", Vector3.new(width - 1.6, lowerH, depth - 1.6), CFrame.new(center + Vector3.new(0, lowerH * 0.5, 0)), tint, Enum.Material.Concrete, true)
	makePart(m, "ArtDecoSetbackTier", Vector3.new((width - 1.6) * 0.82, midSetbackH, (depth - 1.6) * 0.82), CFrame.new(center + Vector3.new(0, lowerH + midSetbackH * 0.5, 0)), tint, Enum.Material.Concrete, true)

	local curtainZ = makePart(m, "GlassCurtainZ", Vector3.new(width - 3.2, lowerH - podiumH - 4, depth + 0.2), CFrame.new(center + Vector3.new(0, podiumH + (lowerH - podiumH - 4) * 0.5, 0)), glassTint, Enum.Material.Glass, true)
	curtainZ.Reflectance = 0.32
	local curtainX = makePart(m, "GlassCurtainX", Vector3.new(width + 0.2, lowerH - podiumH - 4, depth - 3.2), CFrame.new(center + Vector3.new(0, podiumH + (lowerH - podiumH - 4) * 0.5, 0)), glassTint, Enum.Material.Glass, true)
	curtainX.Reflectance = 0.32

	-- Vertical stone corner pilasters & center mullion ribs
	for _, sx in ipairs({ -1, 0, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local pilW = if sx == 0 then 1.8 else 2.8
			makePart(
				m,
				"VerticalPilasterZ",
				Vector3.new(pilW, lowerH, 1.4),
				CFrame.new(center + Vector3.new(sx * (width * 0.46), lowerH * 0.5, sz * (depth * 0.5))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
			makePart(
				m,
				"VerticalPilasterX",
				Vector3.new(1.4, lowerH, pilW),
				CFrame.new(center + Vector3.new(sz * (width * 0.5), lowerH * 0.5, sx * (depth * 0.46))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
		end
	end

	-- Horizontal spandrel ledges + warm amber & cool ice-cyan NYC night office floor bands
	local floors = math.clamp(math.floor((height - podiumH) / 14), 3, 12)
	for f = 1, floors do
		local y = podiumH + (f - 0.5) * ((height - podiumH - 4) / floors)
		local tierScale = if y > lowerH then 0.82 else 1.0
		makePart(m, "SpandrelLedge", Vector3.new(width * tierScale + 0.8, 1.1, depth * tierScale + 0.8), CFrame.new(center + Vector3.new(0, y - 2.2, 0)), Color3.fromRGB(58, 64, 76), Enum.Material.Metal, true)
		local winColor = if (f + math.floor(center.X)) % 2 == 0 then Color3.fromRGB(255, 204, 118) else Color3.fromRGB(135, 192, 248)
		makePart(m, "LitOfficeFloor", Vector3.new((width - 2.2) * tierScale, 2.5, (depth - 2.2) * tierScale), CFrame.new(center + Vector3.new(0, y, 0)), winColor, Enum.Material.Neon, true)
	end

	-- 3. Setback Crown, Mechanical Penthouse & Rooftop Helipad / Aviation Beacons
	local crownH = math.max(8, height * 0.14)
	local crown = makePart(m, "Crown", Vector3.new(width * 0.64, crownH, depth * 0.64), CFrame.new(center + Vector3.new(0, height + crownH * 0.5, 0)), Color3.fromRGB(165, 138, 78), Enum.Material.Metal, true)
	makePart(m, "RoofCornice", Vector3.new(width * 0.84 + 2.0, 1.6, depth * 0.84 + 2.0), CFrame.new(center + Vector3.new(0, height + 0.8, 0)), Color3.fromRGB(145, 122, 68), Enum.Material.Metal, true)

	local penthouseTopY = height + crownH
	makePart(m, "HelipadDeck", Vector3.new(width * 0.52, 0.6, depth * 0.52), CFrame.new(center + Vector3.new(0, penthouseTopY + 0.3, 0)), Color3.fromRGB(82, 86, 96), Enum.Material.Asphalt, true)

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
		buildStuntRamp(center + Vector3.new(0, height, -depth * 0.3), 0, 26, 8, 32, "RooftopMegaJump")
	end

	m.PrimaryPart = podium
	m.Parent = BuildingsFolder
end

local function buildMidRiseCommercialBlock(origin: Vector3, variant: number)
	-- Gotham / NYC Midtown Brick Brownstones, Art Deco Storefronts, Neon Signs, and Winter Street Clutter
	local palettes = {
		{ wall = Color3.fromRGB(108, 62, 52), trim = Color3.fromRGB(64, 68, 78), sign = "BROADWAY PIZZA & ARCADE", signCol = Color3.fromRGB(255, 215, 65) },
		{ wall = Color3.fromRGB(58, 66, 80), trim = Color3.fromRGB(168, 142, 82), sign = "MANHATTAN TRUST BANK", signCol = Color3.fromRGB(255, 230, 115) },
		{ wall = Color3.fromRGB(88, 68, 56), trim = Color3.fromRGB(72, 76, 86), sign = "SOHO ROASTERS CAFE", signCol = Color3.fromRGB(255, 195, 95) },
		{ wall = Color3.fromRGB(68, 74, 86), trim = Color3.fromRGB(92, 102, 118), sign = "GOTHAM TURBO CUSTOMS", signCol = Color3.fromRGB(95, 235, 255) },
		{ wall = Color3.fromRGB(94, 58, 54), trim = Color3.fromRGB(158, 134, 78), sign = "EMPIRE GRAND HOTEL", signCol = Color3.fromRGB(255, 195, 85) },
	}
	local p1 = palettes[(math.abs(variant) % #palettes) + 1]
	local p2 = palettes[((math.abs(variant) + 1) % #palettes) + 1]

	-- Building A (NW quadrant)
	local b1Center = origin + Vector3.new(-28, 0.3, -24)
	makePart(BuildingsFolder, "MidRiseStoreA", Vector3.new(44, 34, 38), CFrame.new(b1Center + Vector3.new(0, 17, 0)), p1.wall, Enum.Material.SmoothPlastic, true)
	makePart(BuildingsFolder, "StoreCorniceA", Vector3.new(46, 2.2, 40), CFrame.new(b1Center + Vector3.new(0, 35, 0)), p1.trim, Enum.Material.Concrete, true)
	local glassA = makePart(BuildingsFolder, "StorefrontGlassA", Vector3.new(38, 10, 39.2), CFrame.new(b1Center + Vector3.new(0, 5.5, 0)), Color3.fromRGB(135, 210, 250), Enum.Material.Glass, true)
	glassA.Reflectance = 0.25
	local awningA = makePart(BuildingsFolder, "AwningA", Vector3.new(40, 1.2, 44), CFrame.new(b1Center + Vector3.new(0, 11.2, 0)), Color3.fromRGB(225, 62, 58), Enum.Material.Fabric, true)
	addSurfaceSign(awningA, p1.sign, p1.signCol, Enum.NormalId.Front)
	addSurfaceSign(awningA, p1.sign, p1.signCol, Enum.NormalId.Back)

	-- Building B (SE quadrant)
	local b2Center = origin + Vector3.new(28, 0.3, 24)
	makePart(BuildingsFolder, "MidRiseStoreB", Vector3.new(42, 42, 36), CFrame.new(b2Center + Vector3.new(0, 21, 0)), p2.wall, Enum.Material.SmoothPlastic, true)
	makePart(BuildingsFolder, "StoreCorniceB", Vector3.new(44, 2.2, 38), CFrame.new(b2Center + Vector3.new(0, 43, 0)), p2.trim, Enum.Material.Concrete, true)
	local glassB = makePart(BuildingsFolder, "StorefrontGlassB", Vector3.new(36, 10, 37.2), CFrame.new(b2Center + Vector3.new(0, 5.5, 0)), Color3.fromRGB(135, 210, 250), Enum.Material.Glass, true)
	glassB.Reflectance = 0.25
	local signB = makePart(BuildingsFolder, "StoreSignB", Vector3.new(34, 4.2, 38), CFrame.new(b2Center + Vector3.new(0, 13.5, 0)), Color3.fromRGB(32, 38, 52), Enum.Material.Metal, true)
	addSurfaceSign(signB, p2.sign, p2.signCol, Enum.NormalId.Front)
	addSurfaceSign(signB, p2.sign, p2.signCol, Enum.NormalId.Back)

	-- Outdoor Cafe Patio, Food Vendor Carts, MegaCorp Targets & Trees in SW / NE plazas
	spawnPalmTree(origin + Vector3.new(-38, 0.3, 32))
	spawnPalmTree(origin + Vector3.new(38, 0.3, -32))
	spawnCafePatio(origin + Vector3.new(-22, 0.3, 24), 0)
	spawnFoodVendorCart(origin + Vector3.new(26, 0.3, -26), 180, variant)
	spawnFenceRun(origin + Vector3.new(24, 0.3, -48), 0, 3, Color3.fromRGB(235, 222, 198))
	spawnCrateCluster(origin + Vector3.new(-24, 0.3, 42), 2)
	if math.abs(variant) % 2 == 0 then
		spawnBillboard(origin + Vector3.new(-42, 0.3, 46), 45, "SMASH MEGACORP PROPERTY!", Color3.fromRGB(255, 85, 85))
	else
		spawnMegaCorpSurveillanceTower(origin + Vector3.new(42, 0.3, -46), -45)
	end
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
	-- Snowy Central Park winter lawn & frozen ice pond
	makePart(CityRoot, "ParkLawn", Vector3.new(BLOCK_SIZE - ROAD_WIDTH - 16, 0.8, BLOCK_SIZE - ROAD_WIDTH - 16), CFrame.new(origin + Vector3.new(0, 0.4, 0)), Color3.fromRGB(218, 228, 242), Enum.Material.Sand, true)
	local pond = makePart(CityRoot, "ParkPond", Vector3.new(46, 0.9, 34), CFrame.new(origin + Vector3.new(-22, 0.5, 18)), Color3.fromRGB(145, 192, 232), Enum.Material.Glass, true)
	pond.Reflectance = 0.28

	-- Perimeter destructible fences
	spawnFenceRun(origin + Vector3.new(0, 0, -56), 0, 5, Color3.fromRGB(220, 226, 238))
	spawnFenceRun(origin + Vector3.new(0, 0, 56), 0, 5, Color3.fromRGB(220, 226, 238))
	spawnBench(origin + Vector3.new(18, 0.8, 12), -45)
	spawnBench(origin + Vector3.new(18, 0.8, -12), -135)
	spawnJackpotCrate(origin + Vector3.new(24, 0.8, 0))

	-- Park seamless steel stunt jump over frozen pond
	buildStuntRamp(origin + Vector3.new(-22, 0.8, -18), 180, 26, 6.2, 38, "ParkLakeMegaJump")
end

local function buildBeachfrontBoardwalk(origin: Vector3)
	-- Frosty Hudson River Pier & Winter Boardwalk on East edge
	makePart(CityRoot, "BeachSand", Vector3.new(BLOCK_SIZE - ROAD_WIDTH, 0.7, BLOCK_SIZE - ROAD_WIDTH), CFrame.new(origin + Vector3.new(0, 0.35, 0)), Color3.fromRGB(82, 88, 100), Enum.Material.Concrete, true)
	makePart(CityRoot, "BoardwalkDeck", Vector3.new(28, 1.0, BLOCK_SIZE - ROAD_WIDTH), CFrame.new(origin + Vector3.new(-38, 0.5, 0)), Color3.fromRGB(102, 74, 52), Enum.Material.WoodPlanks, true)

	for _, zOff in ipairs({ -42, 0, 42 }) do
		spawnPalmTree(origin + Vector3.new(-16, 0.6, zOff))
		spawnPalmTree(origin + Vector3.new(26, 0.6, zOff))
		spawnBench(origin + Vector3.new(-32, 1.0, zOff + 12), 90)
	end
	spawnCrateCluster(origin + Vector3.new(-36, 1.0, -20), 2)
	spawnJackpotCrate(origin + Vector3.new(-28, 1.0, 22))
	buildStuntRamp(origin + Vector3.new(10, 0.7, 0), 0, 26, 6.2, 38, "BoardwalkStuntJump")
end

--------------------------------------------------------------------------------
-- BUILD FULL LEO CITY (MOODY DARK CLOUDY, SNOWY, RAINY NYC WINTER EDITION)
--------------------------------------------------------------------------------

local function buildLeoCity()
	local totalSpan = (GRID_RADIUS * 2 + 1) * BLOCK_SIZE + 240
	makePart(CityRoot, "CityBaseplate", Vector3.new(totalSpan, 4, totalSpan), CFrame.new(0, -2, 0), Color3.fromRGB(34, 38, 46), Enum.Material.Concrete, true)

	-- Hudson River dark icy water along the East waterfront
	local oceanX = (GRID_RADIUS + 1.2) * BLOCK_SIZE
	local river = makePart(CityRoot, "OceanWater", Vector3.new(360, 3.6, totalSpan), CFrame.new(oceanX, -1.6, 0), Color3.fromRGB(24, 48, 72), Enum.Material.Glass, true)
	river.Reflectance = 0.22

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

	-- Grand Central Avenue straight through X = 0 and Z = 0 with wet reflective dark NYC slate asphalt
	local gridExtent = (GRID_RADIUS + 1) * BLOCK_SIZE
	local grandAve = makePart(RoadsFolder, "GrandCentralAveNS", Vector3.new(ROAD_WIDTH, 0.34, gridExtent * 2), CFrame.new(0, 0.17, 0), Color3.fromRGB(26, 30, 38), Enum.Material.Asphalt, true)
	grandAve.Reflectance = 0.14
	for z = -gridExtent + 20, gridExtent - 20, 28 do
		makePart(RoadsFolder, "GrandAveDashNS", Vector3.new(0.8, 0.37, 12), CFrame.new(0, 0.185, z), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
		makePart(RoadsFolder, "GrandAveWhiteLaneW", Vector3.new(0.45, 0.36, 9), CFrame.new(-ROAD_WIDTH * 0.25, 0.18, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		makePart(RoadsFolder, "GrandAveWhiteLaneE", Vector3.new(0.45, 0.36, 9), CFrame.new(ROAD_WIDTH * 0.25, 0.18, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
	end

	-- Steaming NYC Manholes along Grand Central Avenue
	for z = -320, 320, 160 do
		spawnSteamingManhole(Vector3.new(8, 0.2, z + 35))
	end

	-- Build Road Grid & Intersections along block borders: (i + 0.5) * BLOCK_SIZE
	local roadLines = {}
	for i = -GRID_RADIUS - 1, GRID_RADIUS do
		table.insert(roadLines, (i + 0.5) * BLOCK_SIZE)
	end

	for _, rx in ipairs(roadLines) do
		local rns = makePart(RoadsFolder, "RoadNS", Vector3.new(ROAD_WIDTH, 0.3, gridExtent * 2), CFrame.new(rx, 0.15, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Asphalt, true)
		rns.Reflectance = 0.14
		for z = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashNS", Vector3.new(0.8, 0.34, 12), CFrame.new(rx, 0.17, z), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneNS_W", Vector3.new(0.45, 0.33, 9), CFrame.new(rx - ROAD_WIDTH * 0.25, 0.165, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneNS_E", Vector3.new(0.45, 0.33, 9), CFrame.new(rx + ROAD_WIDTH * 0.25, 0.165, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		end
	end

	for _, rz in ipairs(roadLines) do
		local rew = makePart(RoadsFolder, "RoadEW", Vector3.new(gridExtent * 2, 0.32, ROAD_WIDTH), CFrame.new(0, 0.16, rz), Color3.fromRGB(28, 32, 40), Enum.Material.Asphalt, true)
		rew.Reflectance = 0.14
		for x = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashEW", Vector3.new(12, 0.35, 0.8), CFrame.new(x, 0.175, rz), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneEW_N", Vector3.new(9, 0.34, 0.45), CFrame.new(x, 0.17, rz - ROAD_WIDTH * 0.25), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneEW_S", Vector3.new(9, 0.34, 0.45), CFrame.new(x, 0.17, rz + ROAD_WIDTH * 0.25), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		end
	end

	-- Intersections: Crosswalks + Traffic Lights + Steaming Manholes
	for _, rx in ipairs(roadLines) do
		for _, rz in ipairs(roadLines) do
			local interPos = Vector3.new(rx, 0, rz)
			for s = -2, 2 do
				if s ~= 0 then
					makePart(RoadsFolder, "CrosswalkN", Vector3.new(3.2, 0.36, 1.2), CFrame.new(rx + s * 5.5, 0.18, rz - ROAD_WIDTH * 0.5 - 2), Color3.fromRGB(212, 218, 230), Enum.Material.SmoothPlastic, true)
					makePart(RoadsFolder, "CrosswalkE", Vector3.new(1.2, 0.36, 3.2), CFrame.new(rx + ROAD_WIDTH * 0.5 + 2, 0.18, rz + s * 5.5), Color3.fromRGB(212, 218, 230), Enum.Material.SmoothPlastic, true)
				end
			end
			spawnTrafficLight(interPos, Vector3.new(-ROAD_WIDTH * 0.5 - 3, 0, -ROAD_WIDTH * 0.5 - 3), 0, "NS")
			spawnTrafficLight(interPos, Vector3.new(ROAD_WIDTH * 0.5 + 3, 0, ROAD_WIDTH * 0.5 + 3), 90, "EW")
			if math.abs(rx) <= 300 and math.abs(rz) <= 300 then
				spawnSteamingManhole(Vector3.new(rx - 9, 0.2, rz + 9))
			end
		end
	end

	-- Populate each block (bx, bz) in -GRID_RADIUS..GRID_RADIUS
	for bx = -GRID_RADIUS, GRID_RADIUS do
		for bz = -GRID_RADIUS, GRID_RADIUS do
			local origin = Vector3.new(bx * BLOCK_SIZE, 0, bz * BLOCK_SIZE)
			local usable = BLOCK_SIZE - ROAD_WIDTH

			-- Dark wet Manhattan bluestone granite sidewalk framing block (0.26 studs tall so vehicles never snag on curbs)
			if bx ~= 0 then
				makePart(CityRoot, "SidewalkBlock", Vector3.new(usable, 0.26, usable), CFrame.new(origin + Vector3.new(0, 0.13, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
			else
				local sideW = (usable - ROAD_WIDTH) * 0.5
				makePart(CityRoot, "SidewalkBlockW", Vector3.new(sideW, 0.26, usable), CFrame.new(origin + Vector3.new(-(ROAD_WIDTH * 0.5 + sideW * 0.5), 0.13, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
				makePart(CityRoot, "SidewalkBlockE", Vector3.new(sideW, 0.26, usable), CFrame.new(origin + Vector3.new(ROAD_WIDTH * 0.5 + sideW * 0.5, 0.13, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
			end

			-- Streetlights, Fire Hydrants & Easy-Smash Street Clutter Rows on every block perimeter
			local edge = usable * 0.5 - 3.5
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, -edge), 45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, -edge), 135)
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, edge), -45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, edge), -135)
			spawnFireHydrant(origin + Vector3.new(-edge, 0.3, 0))
			spawnFireHydrant(origin + Vector3.new(edge, 0.3, 0))
			spawnStreetClutterRow(origin + Vector3.new(-edge + 2.5, 0.3, -24), 90)
			spawnStreetClutterRow(origin + Vector3.new(edge - 2.5, 0.3, 24), -90)

			-- District & Landmark Assignment
			if bx == 0 and bz == 0 then
				-- LEO PLAZA & GRAND CENTRAL BOULEVARD:
				-- Central avenue (X = -21..21) is wide-open for driving straight ahead!
				-- Ornamental Circular Marble Fountain is placed in the West Plaza Courtyard (-42, 0, 12)
				local fCenter = origin + Vector3.new(-42, 0.3, 12)
				local fountain = makePart(LandmarksFolder, "LeoPlazaFountain", Vector3.new(3.2, 20, 20), CFrame.new(fCenter + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(235, 238, 245), Enum.Material.Marble, true)
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
				spawnJackpotCrate(origin + Vector3.new(-14, 0.3, -18))
				spawnJackpotCrate(origin + Vector3.new(14, 0.3, -18))
				spawnFoodVendorCart(origin + Vector3.new(-32, 0.3, 28), 90, 1)
				spawnFoodVendorCart(origin + Vector3.new(32, 0.3, 28), -90, 2)
				spawnCafePatio(origin + Vector3.new(38, 0.3, 8), -90)
				spawnMegaCorpSurveillanceTower(origin + Vector3.new(-36, 0.3, -38), 35)
				spawnMegaCorpSurveillanceTower(origin + Vector3.new(36, 0.3, -38), -35)
				spawnBench(origin + Vector3.new(-26, 0.3, 12), 90)
				spawnBench(origin + Vector3.new(26, 0.3, 12), -90)
				spawnPalmTree(origin + Vector3.new(-26, 0.3, 34))
				spawnPalmTree(origin + Vector3.new(26, 0.3, 34))

				-- Seamless 1-piece low-angle steel Stunt Ramp down the North end of Grand Central Boulevard & Plaza Speed Shop / Mechanic Bay on East/West flanks
				buildStuntRamp(origin + Vector3.new(0, 0.3, -68), 0, 26, 6.2, 38, "LeoPlazaRamp")
				buildSpeedShop(origin + Vector3.new(54, 0.3, -24), -90)
				buildMechanicRepairBay(origin + Vector3.new(-54, 0.3, -24), 90)
			elseif bx == 1 and bz == 0 then
				buildSpeedShop(origin + Vector3.new(0, 0.3, 0), -90)
				spawnBusStop(origin + Vector3.new(0, 0.3, -edge + 2), 0)
				spawnFoodVendorCart(origin + Vector3.new(-36, 0.3, 32), 0, 3)
			elseif bx == -1 and bz == 0 then
				buildMechanicRepairBay(origin + Vector3.new(0, 0.3, 0), 90)
				spawnBusStop(origin + Vector3.new(0, 0.3, edge - 2), 180)
				spawnFoodVendorCart(origin + Vector3.new(36, 0.3, -32), 180, 1)
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
				-- Downtown Gotham / NYC Skyscraper Core
				local isLeoTower = (bx == 0 and bz == -1) or (bx == 1 and bz == -1)
				local h = if (bx == 0 and bz == -1) then 195 elseif (bx == 1 and bz == -1) then 175 else 115 + ((math.abs(bx * 3 + bz * 5) % 4) * 18)
				local col = if isLeoTower then Color3.fromRGB(48, 56, 70) else Color3.fromRGB(62, 68, 82)
				local towerName = if (bx == 0 and bz == -1) then "LeoTower" else "DowntownTower"
				local xOff = if bx == 0 then 44 else 28
				buildSkyscraper(origin + Vector3.new(-xOff, 0.3, -26), 38, 38, h, col, towerName, isLeoTower)
				buildSkyscraper(origin + Vector3.new(xOff, 0.3, 26), 36, 36, 96, Color3.fromRGB(76, 68, 62), "GlassOfficeTower", false)
				spawnBusStop(origin + Vector3.new(-edge + 2, 0.3, 0), 90)
				spawnCrateCluster(origin + Vector3.new(xOff, 0.3, -26), 3)
				spawnJackpotCrate(origin + Vector3.new(xOff - 8, 0.3, -18))
				spawnFoodVendorCart(origin + Vector3.new(-xOff, 0.3, 18), 0, bx + bz)
				spawnMegaCorpSurveillanceTower(origin + Vector3.new(xOff, 0.3, -46), 180)
				spawnBillboard(origin + Vector3.new(-xOff, 0.3, 38), 0, "SMASH MEGACORP PROPERTY!", Color3.fromRGB(255, 200, 40))
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
