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
local BLOCK_SIZE = 180 -- spacious 180-stud NYC blocks so buildings, plazas, and 4-lane avenues never overlap!
local ROAD_WIDTH = 38 -- 4-lane NYC avenues
local SIDEWALK_WIDTH = 10 -- bluestone sidewalk
local GRID_RADIUS = 4 -- -4..4 = 9x9 (81) full city blocks (1,800 x 1,800 studs of dense Manhattan + Harbor!)

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
			local w = Instance.new("Weld")
			w.Name = desc.Name .. "_Weld"
			w.Part0 = primary
			w.Part1 = desc
			w.C0 = primary.CFrame:Inverse() * desc.CFrame
			w.Parent = desc
			desc.Anchored = false
		end
	end
end

local PROP_DEFAULT_REQUIRED_TIER: { [string]: number } = {
	-- Tier 1: All Everyday Street Props, Hydrants, Streetlights, Bus Stops, Billboards & Taxis (Starter Car Smashes All!)
	Crate = 1,
	WoodenCrate = 1,
	JackpotCrate = 1,
	TrafficCone = 1,
	Fence = 1,
	Bench = 1,
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
	SnowyChristmasTree = 1,
	Snowman = 1,
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
	-- Tier 5: Ultra-Armored End-Game Bank Vaults & Boss (Unlocked by Goliath Bulldozer or Plow Lv.5)
	MegaCorpBankVault = 5,
	BossGoliath = 5,
}

local function tagDestructible(
	instance: Instance,
	propType: string,
	cashValue: number,
	chaosPoints: number,
	breakThreshold: number,
	explosive: boolean?,
	requiredTier: number?
)
	local reqTier = requiredTier or PROP_DEFAULT_REQUIRED_TIER[propType] or 1
	instance:SetAttribute("PropType", propType)
	instance:SetAttribute("DestructibleType", propType)
	instance:SetAttribute("IsDestructible", true)
	instance:SetAttribute("CashValue", cashValue)
	instance:SetAttribute("CashReward", cashValue)
	instance:SetAttribute("ChaosPoints", chaosPoints)
	instance:SetAttribute("BreakThreshold", breakThreshold)
	instance:SetAttribute("Explosive", explosive == true)
	instance:SetAttribute("RequiredTier", reqTier)
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

	-- Festive Holiday Gift Stack (crimson, emerald, and royal-gold wrapped present boxes with metallic ribbon bands — never blinding neon yellow!)
	local core = makePart(m, "CrimsonGiftBox", Vector3.new(3.6, 2.8, 3.6), CFrame.new(pos + Vector3.new(0, 1.4, 0)), Color3.fromRGB(186, 32, 38), Enum.Material.SmoothPlastic, true)
	local bandX = makePart(m, "GoldRibbonX", Vector3.new(3.75, 2.86, 0.55), CFrame.new(pos + Vector3.new(0, 1.4, 0)), Color3.fromRGB(214, 172, 68), Enum.Material.Metal, false)
	bandX.CanCollide = false
	local bandZ = makePart(m, "GoldRibbonZ", Vector3.new(0.55, 2.86, 3.75), CFrame.new(pos + Vector3.new(0, 1.4, 0)), Color3.fromRGB(214, 172, 68), Enum.Material.Metal, false)
	bandZ.CanCollide = false

	local topBoxCF = CFrame.new(pos + Vector3.new(-0.2, 3.8, 0.15)) * CFrame.Angles(0, math.rad(18), 0)
	local topBox = makePart(m, "EmeraldGiftBox", Vector3.new(2.5, 2.0, 2.5), topBoxCF, Color3.fromRGB(28, 118, 64), Enum.Material.SmoothPlastic, false)
	topBox.CanCollide = false
	local topRibbon = makePart(m, "TopGoldRibbon", Vector3.new(2.62, 2.06, 0.45), topBoxCF, Color3.fromRGB(224, 182, 76), Enum.Material.Metal, false)
	topRibbon.CanCollide = false
	local bowLoop = makePart(m, "HolidayGoldBow", Vector3.new(1.1, 0.45, 1.1), topBoxCF * CFrame.new(0, 1.15, 0), Color3.fromRGB(224, 182, 76), Enum.Material.Metal, false)
	bowLoop.CanCollide = false

	local sideBoxCF = CFrame.new(pos + Vector3.new(1.85, 0.95, -1.1)) * CFrame.Angles(0, math.rad(-14), 0)
	local sideBox = makePart(m, "GoldWrappedGiftBox", Vector3.new(2.0, 1.9, 2.0), sideBoxCF, Color3.fromRGB(198, 154, 56), Enum.Material.Metal, false)
	sideBox.CanCollide = false
	local sideRibbon = makePart(m, "CrimsonRibbon", Vector3.new(2.1, 1.96, 0.4), sideBoxCF, Color3.fromRGB(186, 32, 38), Enum.Material.SmoothPlastic, false)
	sideRibbon.CanCollide = false

	addSurfaceSign(core, "HOLIDAY GIFT", Color3.fromRGB(248, 232, 185), Enum.NormalId.Front)
	addSurfaceSign(core, "HOLIDAY GIFT", Color3.fromRGB(248, 232, 185), Enum.NormalId.Back)

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

-- Helper: Builds a tapered 8-sided conical pine tier out of 4 pairs of back-to-back WedgeParts (0, 45, 90, 135 deg)
local function addConicalPineFoliageTier(
	parent: Instance,
	tierPrefix: string,
	centerPos: Vector3,
	radius: number,
	tierHeight: number,
	pineColor: Color3,
	snowColor: Color3,
	anchored: boolean
)
	local boughThick = math.max(1.2, radius * 0.62)
	for a = 0, 3 do
		local yawRad = math.rad(a * 45)
		local baseRot = CFrame.new(centerPos) * CFrame.Angles(0, yawRad, 0)

		-- Pair of back-to-back WedgeParts sloping down-and-outward to form a true tapered pine cone!
		local wFront = makeWedge(
			parent,
			tierPrefix .. "_ConeWedgeA_" .. tostring(a),
			Vector3.new(boughThick, tierHeight, radius),
			baseRot * CFrame.new(0, 0, -radius * 0.5) * CFrame.Angles(0, math.rad(180), 0),
			pineColor,
			Enum.Material.Grass
		)
		wFront.Anchored = anchored

		local wBack = makeWedge(
			parent,
			tierPrefix .. "_ConeWedgeB_" .. tostring(a),
			Vector3.new(boughThick, tierHeight, radius),
			baseRot * CFrame.new(0, 0, radius * 0.5),
			pineColor,
			Enum.Material.Grass
		)
		wBack.Anchored = anchored

		-- Conical snow-frosted bough tips sloping down along the upper surface
		local snowH = math.max(0.45, tierHeight * 0.28)
		local snowR = radius * 0.92
		local sFront = makeWedge(
			parent,
			tierPrefix .. "_SnowConeA_" .. tostring(a),
			Vector3.new(boughThick * 0.88, snowH, snowR),
			baseRot * CFrame.new(0, tierHeight * 0.36, -snowR * 0.5) * CFrame.Angles(0, math.rad(180), 0),
			snowColor,
			Enum.Material.Snow
		)
		sFront.Anchored = anchored
		sFront.CanCollide = false

		local sBack = makeWedge(
			parent,
			tierPrefix .. "_SnowConeB_" .. tostring(a),
			Vector3.new(boughThick * 0.88, snowH, snowR),
			baseRot * CFrame.new(0, tierHeight * 0.36, snowR * 0.5),
			snowColor,
			Enum.Material.Snow
		)
		sBack.Anchored = anchored
		sBack.CanCollide = false
	end
end

local function spawnSnowyChristmasTree(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "SnowyChristmasTree"

	local pineColor = Color3.fromRGB(26, 86, 48)
	local snowColor = Color3.fromRGB(238, 244, 252)
	local trunk = makePart(m, "Trunk", Vector3.new(1.8, 5.2, 1.8), CFrame.new(pos + Vector3.new(0, 2.6, 0)), Color3.fromRGB(104, 68, 42), Enum.Material.Wood, true)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame = CFrame.new(pos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Size = Vector3.new(5.2, 1.8, 1.8)

	local tiers = {
		{ y = 6.2, r = 4.4, h = 4.8 },
		{ y = 10.0, r = 3.3, h = 4.4 },
		{ y = 13.4, r = 2.1, h = 4.0 },
	}
	local ornamentPalette = {
		Color3.fromRGB(255, 214, 92), -- warm gold
		Color3.fromRGB(235, 52, 52), -- holiday red
		Color3.fromRGB(58, 220, 98), -- christmas green
	}

	for idx, t in ipairs(tiers) do
		addConicalPineFoliageTier(
			m,
			"PineConeTier" .. idx,
			pos + Vector3.new(0, t.y, 0),
			t.r,
			t.h,
			pineColor,
			snowColor,
			false
		)

		for a = 0, 3 do
			local angle = math.rad(a * 90 + idx * 30)
			local radius = t.r * 0.72
			local ornPos = pos + Vector3.new(math.cos(angle) * radius, t.y - t.h * 0.22, math.sin(angle) * radius)
			local ornCol = ornamentPalette[((idx + a) % #ornamentPalette) + 1]
			local orn = makePart(m, "OrnamentLight", Vector3.new(0.65, 0.65, 0.65), CFrame.new(ornPos), ornCol, Enum.Material.Neon, false)
			orn.Shape = Enum.PartType.Ball
			orn.CanCollide = false
		end
	end

	local star = makePart(m, "TreeStarTopper", Vector3.new(1.3, 1.3, 0.5), CFrame.new(pos + Vector3.new(0, 16.0, 0)), Color3.fromRGB(255, 218, 82), Enum.Material.Neon, false)
	star.CanCollide = false

	weldChildrenToPrimary(m, trunk)
	m.Parent = PropsFolder
	tagDestructible(m, "PalmTree", 35, 20, 12, false, 1)
end

local spawnPalmTree = spawnSnowyChristmasTree

local function spawnSnowman(pos: Vector3, yawDeg: number?)
	local m = Instance.new("Model")
	m.Name = "HolidaySnowman"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg or 0), 0)
	local snowCol = Color3.fromRGB(240, 246, 254)

	local baseBall = makePart(m, "SnowBase", Vector3.new(3.4, 3.4, 3.4), rot * CFrame.new(0, 1.7, 0), snowCol, Enum.Material.Snow, true)
	baseBall.Shape = Enum.PartType.Ball
	local midBall = makePart(m, "SnowTorso", Vector3.new(2.5, 2.5, 2.5), rot * CFrame.new(0, 4.2, 0), snowCol, Enum.Material.Snow, false)
	midBall.Shape = Enum.PartType.Ball
	local headBall = makePart(m, "SnowHead", Vector3.new(1.8, 1.8, 1.8), rot * CFrame.new(0, 6.0, 0), snowCol, Enum.Material.Snow, false)
	headBall.Shape = Enum.PartType.Ball

	local scarf = makePart(m, "HolidayScarf", Vector3.new(2.0, 0.45, 2.0), rot * CFrame.new(0, 5.2, 0), Color3.fromRGB(196, 34, 42), Enum.Material.Fabric, false)
	scarf.CanCollide = false
	local nose = makePart(m, "CarrotNose", Vector3.new(0.35, 0.35, 1.0), rot * CFrame.new(0, 6.0, -1.1), Color3.fromRGB(242, 124, 32), Enum.Material.SmoothPlastic, false)
	nose.CanCollide = false
	local hatBrim = makePart(m, "TopHatBrim", Vector3.new(2.2, 0.25, 2.2), rot * CFrame.new(0, 6.85, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Fabric, false)
	hatBrim.CanCollide = false
	local hatCrown = makePart(m, "TopHatCrown", Vector3.new(1.4, 1.3, 1.4), rot * CFrame.new(0, 7.55, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Fabric, false)
	hatCrown.CanCollide = false

	weldChildrenToPrimary(m, baseBall)
	m.Parent = PropsFolder
	tagDestructible(m, "Snowman", 40, 25, 8, false, 1)
end

local function buildGiantChristmasTree(pos: Vector3, totalHeight: number, name: string)
	local m = Instance.new("Model")
	m.Name = name
	local pineColor = Color3.fromRGB(24, 82, 46)
	local snowColor = Color3.fromRGB(238, 244, 252)

	local trunkH = totalHeight * 0.16
	local trunk = makePart(
		m,
		"TreeTrunk",
		Vector3.new(trunkH, 4.2, 4.2),
		CFrame.new(pos + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(96, 62, 38),
		Enum.Material.Wood,
		true
	)
	trunk.Shape = Enum.PartType.Cylinder

	local tierSpecs = {
		{ yFrac = 0.28, rFrac = 0.25, hFrac = 0.26 },
		{ yFrac = 0.48, rFrac = 0.19, hFrac = 0.24 },
		{ yFrac = 0.66, rFrac = 0.14, hFrac = 0.22 },
		{ yFrac = 0.82, rFrac = 0.09, hFrac = 0.18 },
	}
	local ornamentColors = {
		Color3.fromRGB(255, 216, 88),
		Color3.fromRGB(235, 48, 52),
		Color3.fromRGB(54, 224, 96),
	}

	for idx, spec in ipairs(tierSpecs) do
		local tierR = totalHeight * spec.rFrac
		local tierH = totalHeight * spec.hFrac
		local tierY = totalHeight * spec.yFrac
		addConicalPineFoliageTier(
			m,
			"EvergreenConeTier" .. idx,
			pos + Vector3.new(0, tierY, 0),
			tierR,
			tierH,
			pineColor,
			snowColor,
			true
		)

		for a = 0, 5 do
			local ang = math.rad(a * 60 + idx * 25)
			local r = tierR * 0.78
			local oPos = pos + Vector3.new(math.cos(ang) * r, tierY - tierH * 0.22, math.sin(ang) * r)
			local oCol = ornamentColors[((idx + a) % #ornamentColors) + 1]
			local bulb = makePart(m, "HolidayOrnament", Vector3.new(1.2, 1.2, 1.2), CFrame.new(oPos), oCol, Enum.Material.Neon, true)
			bulb.Shape = Enum.PartType.Ball
			bulb.CanCollide = false
		end
	end

	local starY = totalHeight * 0.94
	local star = makePart(m, "GoldenStarTopper", Vector3.new(3.8, 3.8, 1.2), CFrame.new(pos + Vector3.new(0, starY, 0)), Color3.fromRGB(255, 222, 85), Enum.Material.Neon, true)
	star.CanCollide = false
	local starLight = Instance.new("PointLight")
	starLight.Color = Color3.fromRGB(255, 220, 130)
	starLight.Brightness = 3.2
	starLight.Range = 54
	starLight.Parent = star

	m.PrimaryPart = trunk
	m.Parent = LandmarksFolder
end

local VENDOR_VARIANTS = {
	{
		name = "RoastedChestnutCart",
		cartColor = Color3.fromRGB(118, 32, 38),
		umbrellaColor = Color3.fromRGB(28, 78, 48),
		menuText = "NYC ROASTED CHESTNUTS",
		signColor = Color3.fromRGB(248, 224, 168),
	},
	{
		name = "HotCocoaStreetCart",
		cartColor = Color3.fromRGB(28, 76, 48),
		umbrellaColor = Color3.fromRGB(136, 34, 40),
		menuText = "CENTRAL PARK HOT COCOA",
		signColor = Color3.fromRGB(248, 234, 195),
	},
	{
		name = "FifthAvePretzelCart",
		cartColor = Color3.fromRGB(72, 48, 36),
		umbrellaColor = Color3.fromRGB(122, 32, 38),
		menuText = "5TH AVE PRETZELS",
		signColor = Color3.fromRGB(248, 220, 152),
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
	addSurfaceSign(screen, "MEGACORP WATCHES YOU\n[TIER 3 TARGET]", Color3.fromRGB(255, 75, 75), Enum.NormalId.Front)
	addSurfaceSign(screen, "MEGACORP PROPERTY\n[TIER 3 TARGET]", Color3.fromRGB(255, 205, 55), Enum.NormalId.Back)

	weldChildrenToPrimary(m, pylon)
	m.Parent = PropsFolder
	tagDestructible(m, "MegaCorpTower", 140, 95, 20, true, 3)
end

local function spawnGoldATM(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "GoldATM"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	-- Sleek dark-slate & brushed-brass Manhattan Bank ATM Kiosk (never a giant yellow block!)
	local kiosk = makePart(m, "ATMKioskBody", Vector3.new(3.0, 5.4, 2.2), rot * CFrame.new(0, 2.7, 0), Color3.fromRGB(36, 42, 54), Enum.Material.Metal, true)
	makePart(m, "ATMTopHeader", Vector3.new(3.3, 1.0, 2.5), rot * CFrame.new(0, 5.7, 0), Color3.fromRGB(24, 28, 38), Enum.Material.Metal, false)
	local brassTrim = makePart(m, "BrassTrimBand", Vector3.new(3.15, 0.35, 2.35), rot * CFrame.new(0, 5.05, 0), Color3.fromRGB(196, 158, 68), Enum.Material.Metal, false)
	brassTrim.CanCollide = false
	local screen = makePart(m, "ATMScreen", Vector3.new(2.2, 1.6, 0.2), rot * CFrame.new(0, 3.4, -1.15), Color3.fromRGB(42, 148, 96), Enum.Material.SmoothPlastic, false)
	screen.CanCollide = false
	addSurfaceSign(screen, "MANHATTAN ATM\n[TIER 2]", Color3.fromRGB(238, 248, 242), Enum.NormalId.Front)
	addSurfaceSign(kiosk, "MANHATTAN BANK ATM", Color3.fromRGB(214, 178, 88), Enum.NormalId.Back)

	weldChildrenToPrimary(m, kiosk)
	m.Parent = PropsFolder
	tagDestructible(m, "GoldATM", 120, 80, 12, false, 2)
end

local function spawnArmoredCashTruck(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "ArmoredCashTruck"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local chassis = makePart(m, "Chassis", Vector3.new(6.8, 1.6, 15.6), rot * CFrame.new(0, 1.8, 0), Color3.fromRGB(34, 40, 52), Enum.Material.Metal, true)
	local vaultBox = makePart(m, "ArmoredCargoBox", Vector3.new(6.6, 4.4, 10.2), rot * CFrame.new(0, 4.6, 2.4), Color3.fromRGB(44, 52, 68), Enum.Material.Metal, false)
	makePart(m, "GoldArmorStripe", Vector3.new(6.8, 0.65, 10.0), rot * CFrame.new(0, 4.4, 2.4), Color3.fromRGB(198, 158, 64), Enum.Material.Metal, false)
	makePart(m, "CabFront", Vector3.new(6.4, 3.0, 4.6), rot * CFrame.new(0, 3.9, -5.0), Color3.fromRGB(34, 40, 52), Enum.Material.Metal, false)
	local ws = makePart(m, "ArmorWindshield", Vector3.new(5.8, 1.4, 0.35), rot * CFrame.new(0, 4.4, -7.25), Color3.fromRGB(24, 30, 38), Enum.Material.Glass, false)
	ws.Transparency = 0.25
	makePart(m, "FrontBullBar", Vector3.new(7.0, 1.4, 0.8), rot * CFrame.new(0, 2.1, -7.9), Color3.fromRGB(198, 158, 64), Enum.Material.DiamondPlate, false)

	for _, sx in ipairs({ -3.3, 3.3 }) do
		for _, sz in ipairs({ -4.8, 4.4 }) do
			local wheel = makePart(
				m,
				"Wheel",
				Vector3.new(1.2, 2.8, 2.8),
				rot * CFrame.new(sx, 1.4, sz),
				Color3.fromRGB(20, 22, 26),
				Enum.Material.SmoothPlastic,
				false
			)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.CanCollide = false
		end
	end

	addSurfaceSign(vaultBox, "ARMORED CASH VAN [TIER 3]", Color3.fromRGB(238, 202, 108), Enum.NormalId.Left)
	addSurfaceSign(vaultBox, "ARMORED CASH VAN [TIER 3]", Color3.fromRGB(238, 202, 108), Enum.NormalId.Right)

	weldChildrenToPrimary(m, chassis)
	m.Parent = PropsFolder
	tagDestructible(m, "ArmoredCashTruck", 450, 320, 24, false, 3)
end

local function spawnMegaCorpBankVault(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "MegaCorpBankVault"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local vaultBody = makePart(m, "VaultCore", Vector3.new(10.5, 8.2, 7.6), rot * CFrame.new(0, 4.1, 0), Color3.fromRGB(235, 185, 32), Enum.Material.Metal, true)
	makePart(m, "TitaniumFrame", Vector3.new(11.1, 8.6, 1.4), rot * CFrame.new(0, 4.3, -3.4), Color3.fromRGB(48, 54, 68), Enum.Material.DiamondPlate, false)
	local doorWheel = makePart(
		m,
		"VaultDoorDial",
		Vector3.new(0.8, 5.4, 5.4),
		rot * CFrame.new(0, 4.3, -4.1) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(255, 215, 55),
		Enum.Material.Metal,
		false
	)
	doorWheel.Shape = Enum.PartType.Cylinder
	local neonTrim = makePart(m, "VaultHeaderSign", Vector3.new(10.2, 1.6, 1.6), rot * CFrame.new(0, 9.0, -3.2), Color3.fromRGB(22, 26, 38), Enum.Material.Metal, false)
	addSurfaceSign(neonTrim, "GOLDEN BANK VAULT [TIER 5]", Color3.fromRGB(255, 220, 65), Enum.NormalId.Front)
	addSurfaceSign(vaultBody, "GOLDEN BANK VAULT [TIER 5]", Color3.fromRGB(30, 24, 12), Enum.NormalId.Back)

	weldChildrenToPrimary(m, vaultBody)
	m.Parent = PropsFolder
	tagDestructible(m, "MegaCorpBankVault", 2500, 1800, 35, true, 5)
end

--------------------------------------------------------------------------------
-- INTERACTIVE ZONES: SPEED SHOP, MECHANIC BAYS, 3-STAGE CURVED STUNT RAMPS
--------------------------------------------------------------------------------

local function buildStuntRamp(_pos: Vector3, _yawDeg: number, _width: number, _height: number, _length: number, _labelText: string)
	-- Standalone wedge ramps removed so plazas, parks, and waterfronts stay realistic and unobstructed!
end

local function buildSpeedShop(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "SpeedShop"
	local basePos = Vector3.new(pos.X, 0, pos.Z)
	local rot = CFrame.new(basePos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	-- ShowroomFloor at Y = 0.26 (top Y = 0.46) — strictly above SidewalkBlock (top Y = 0.30) for zero Z-fighting!
	makePart(m, "ShowroomFloor", Vector3.new(44, 0.40, 36), rot * CFrame.new(0, 0.26, 0), Color3.fromRGB(28, 32, 42), Enum.Material.Concrete, true)
	makePart(m, "BackWall", Vector3.new(42, 22, 2), rot * CFrame.new(0, 11.4, 14), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "LeftWall", Vector3.new(2, 22, 26), rot * CFrame.new(-20, 11.4, 2), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "RightWall", Vector3.new(2, 22, 26), rot * CFrame.new(20, 11.4, 2), Color3.fromRGB(22, 26, 36), Enum.Material.Metal, true)
	makePart(m, "Roof", Vector3.new(44, 1.6, 30), rot * CFrame.new(0, 22.8, 2), Color3.fromRGB(18, 20, 28), Enum.Material.Metal, true)

	local glass = makePart(m, "ShowroomGlass", Vector3.new(38, 16, 0.6), rot * CFrame.new(0, 8.8, -10.4), Color3.fromRGB(60, 210, 255), Enum.Material.Glass, true)
	glass.Transparency = 0.55

	local signBoard = makePart(m, "SignBoard", Vector3.new(34, 6.0, 1.5), rot * CFrame.new(0, 26.8, -9.5), Color3.fromRGB(16, 20, 30), Enum.Material.Metal, true)
	addSurfaceSign(signBoard, "LEO SPEED SHOP & DEALER", Color3.fromRGB(40, 240, 255), Enum.NormalId.Front)
	addSurfaceSign(signBoard, "LEO SPEED SHOP & DEALER", Color3.fromRGB(40, 240, 255), Enum.NormalId.Back)

	-- SpeedShopPad at Y = 0.58 (top Y = 0.70) — strictly above ShowroomFloor (top Y = 0.46) for zero Z-fighting!
	local pad = makePart(m, "SpeedShopPad", Vector3.new(18, 0.24, 14), rot * CFrame.new(0, 0.58, -16), Color3.fromRGB(25, 235, 255), Enum.Material.Neon, true)
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
	local basePos = Vector3.new(pos.X, 0, pos.Z)
	local rot = CFrame.new(basePos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	-- BayFloor at Y = 0.26 (top Y = 0.46) — strictly above SidewalkBlock (top Y = 0.30)
	makePart(m, "BayFloor", Vector3.new(32, 0.40, 32), rot * CFrame.new(0, 0.26, 0), Color3.fromRGB(34, 38, 46), Enum.Material.Concrete, true)
	makePart(m, "LeftWall", Vector3.new(2, 16, 26), rot * CFrame.new(-13, 8.4, 0), Color3.fromRGB(48, 52, 62), Enum.Material.Concrete, true)
	makePart(m, "RightWall", Vector3.new(2, 16, 26), rot * CFrame.new(13, 8.4, 0), Color3.fromRGB(48, 52, 62), Enum.Material.Concrete, true)
	makePart(m, "Roof", Vector3.new(30, 1.5, 28), rot * CFrame.new(0, 16.8, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, true)

	local sign = makePart(m, "MechanicSign", Vector3.new(26, 5, 1.4), rot * CFrame.new(0, 20.1, -12), Color3.fromRGB(20, 26, 32), Enum.Material.Metal, true)
	addSurfaceSign(sign, "INSTANT REPAIR & NITRO REFILL", Color3.fromRGB(60, 255, 120), Enum.NormalId.Front)
	addSurfaceSign(sign, "INSTANT REPAIR & NITRO REFILL", Color3.fromRGB(60, 255, 120), Enum.NormalId.Back)

	-- RepairPad at Y = 0.58 (top Y = 0.70) — strictly above BayFloor (top Y = 0.46) so green pad NEVER flickers!
	local pad = makePart(m, "RepairPad", Vector3.new(18, 0.24, 20), rot * CFrame.new(0, 0.58, 0), Color3.fromRGB(50, 255, 110), Enum.Material.Neon, true)
	pad.Transparency = 0.20
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

	-- 2. Main Art Deco Stepped Tower Core with Reflective Glass Curtain Wall & Vertical Pilasters (0.4+ stud offsets for zero Z-fighting!)
	local lowerH = height * 0.72
	local midSetbackH = height * 0.28
	makePart(m, "Shaft", Vector3.new(width - 2.0, lowerH, depth - 2.0), CFrame.new(center + Vector3.new(0, lowerH * 0.5, 0)), tint, Enum.Material.Concrete, true)
	makePart(m, "ArtDecoSetbackTier", Vector3.new((width - 2.0) * 0.80, midSetbackH, (depth - 2.0) * 0.80), CFrame.new(center + Vector3.new(0, lowerH + midSetbackH * 0.5, 0)), tint, Enum.Material.Concrete, true)

	local curtainZ = makePart(m, "GlassCurtainZ", Vector3.new(width - 4.0, lowerH - podiumH - 4, depth - 0.8), CFrame.new(center + Vector3.new(0, podiumH + (lowerH - podiumH - 4) * 0.5, 0)), glassTint, Enum.Material.Glass, true)
	curtainZ.Reflectance = 0.32
	local curtainX = makePart(m, "GlassCurtainX", Vector3.new(width - 0.8, lowerH - podiumH - 4, depth - 4.0), CFrame.new(center + Vector3.new(0, podiumH + (lowerH - podiumH - 4) * 0.5, 0)), glassTint, Enum.Material.Glass, true)
	curtainX.Reflectance = 0.32

	-- Vertical stone corner pilasters & center mullion ribs (offset +0.6 studs outside glass so faces never co-plane)
	for _, sx in ipairs({ -1, 0, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local pilW = if sx == 0 then 1.8 else 2.8
			makePart(
				m,
				"VerticalPilasterZ",
				Vector3.new(pilW, lowerH, 1.4),
				CFrame.new(center + Vector3.new(sx * (width * 0.44), lowerH * 0.5, sz * (depth * 0.5 + 0.45))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
			makePart(
				m,
				"VerticalPilasterX",
				Vector3.new(1.4, lowerH, pilW),
				CFrame.new(center + Vector3.new(sz * (width * 0.5 + 0.45), lowerH * 0.5, sx * (depth * 0.44))),
				podiumColor,
				Enum.Material.Concrete,
				true
			)
		end
	end

	-- Horizontal spandrel ledges + subtle recessed warm golden apartment/office window mullions & white snow-dusted ledges
	local floors = math.clamp(math.floor((height - podiumH) / 16), 4, 12)
	local warmMullionColor = Color3.fromRGB(235, 202, 145)
	local snowLedgeColor = Color3.fromRGB(236, 242, 250)
	for f = 1, floors do
		local y = podiumH + (f - 0.5) * ((height - podiumH - 4) / floors)
		local tierScale = if y > lowerH then 0.80 else 1.0
		makePart(m, "SpandrelLedge", Vector3.new(width * tierScale + 1.8, 1.1, depth * tierScale + 1.8), CFrame.new(center + Vector3.new(0, y - 2.2, 0)), Color3.fromRGB(58, 64, 76), Enum.Material.Metal, true)
		local snowLedge = makePart(m, "SnowDustedLedge", Vector3.new(width * tierScale + 2.0, 0.35, depth * tierScale + 2.0), CFrame.new(center + Vector3.new(0, y - 1.5, 0)), snowLedgeColor, Enum.Material.Snow, true)
		snowLedge.CanCollide = false

		local winZ = makePart(m, "LitOfficeFloorZ", Vector3.new((width - 4.4) * tierScale, 2.2, (depth - 0.2) * tierScale), CFrame.new(center + Vector3.new(0, y, 0)), warmMullionColor, Enum.Material.SmoothPlastic, true)
		winZ.Reflectance = 0.15
		local winX = makePart(m, "LitOfficeFloorX", Vector3.new((width - 0.2) * tierScale, 2.2, (depth - 4.4) * tierScale), CFrame.new(center + Vector3.new(0, y, 0)), warmMullionColor, Enum.Material.SmoothPlastic, true)
		winX.Reflectance = 0.15
	end

	-- 3. Setback Crown, Snow-Dusted Cornice, Mechanical Penthouse & Rooftop Helipad / Aviation Beacons
	local crownH = math.max(10, height * 0.14)
	local crown = makePart(m, "Crown", Vector3.new(width * 0.64, crownH, depth * 0.64), CFrame.new(center + Vector3.new(0, height + crownH * 0.5, 0)), Color3.fromRGB(148, 128, 84), Enum.Material.Metal, true)
	makePart(m, "RoofCornice", Vector3.new(width * 0.84 + 2.0, 1.6, depth * 0.84 + 2.0), CFrame.new(center + Vector3.new(0, height + 0.8, 0)), Color3.fromRGB(132, 114, 74), Enum.Material.Metal, true)
	local roofSnow = makePart(m, "RoofSnowCap", Vector3.new(width * 0.84 + 2.2, 0.45, depth * 0.84 + 2.2), CFrame.new(center + Vector3.new(0, height + 1.8, 0)), snowLedgeColor, Enum.Material.Snow, true)
	roofSnow.CanCollide = false

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
	-- Dense 4-Tower Manhattan Midtown / Upper East Side Skyscraper Block (135 to 230 studs tall)
	-- with ground-floor holiday storefronts, red velvet awnings, and snow-frosted Christmas trees!
	local storefrontSigns = {
		"PLAZA GRAND HOTEL",
		"FIFTH AVE JEWELERS",
		"ROCKEFELLER TOY EMPORIUM",
		"MANHATTAN TRUST BANK",
		"CENTRAL PARK BISTRO",
	}
	local towerTints = {
		Color3.fromRGB(74, 80, 92),
		Color3.fromRGB(88, 76, 68),
		Color3.fromRGB(62, 70, 84),
		Color3.fromRGB(94, 86, 76),
	}
	local quadrants = {
		{ x = -34, z = -34, w = 36, d = 36, baseH = 140 },
		{ x = 34, z = -34, w = 34, d = 34, baseH = 175 },
		{ x = -34, z = 34, w = 34, d = 34, baseH = 195 },
		{ x = 34, z = 34, w = 36, d = 36, baseH = 225 },
	}

	local seed = math.abs(variant)
	for qIdx, q in ipairs(quadrants) do
		local tCenter = origin + Vector3.new(q.x, 0.3, q.z)
		local h = math.clamp(q.baseH + ((seed * 13 + qIdx * 29) % 35) - 10, 135, 230)
		local tint = towerTints[((seed + qIdx) % #towerTints) + 1]
		local signText = storefrontSigns[((seed + qIdx) % #storefrontSigns) + 1]

		buildSkyscraper(tCenter, q.w, q.d, h, tint, "ManhattanMidtownTower_" .. qIdx, false)

		-- Red velvet holiday awning & storefront sign on the street-facing side of each tower
		local awningZ = if q.z < 0 then -(q.d * 0.5 + 3.4) else (q.d * 0.5 + 3.4)
		local awning = makePart(
			BuildingsFolder,
			"HolidayVelvetAwning",
			Vector3.new(q.w * 0.72, 1.3, 4.8),
			CFrame.new(tCenter + Vector3.new(0, 11.4, awningZ)),
			Color3.fromRGB(156, 26, 34),
			Enum.Material.Fabric,
			true
		)
		local snowAwning = makePart(
			BuildingsFolder,
			"AwningSnowTrim",
			Vector3.new(q.w * 0.72 + 0.3, 0.35, 5.0),
			CFrame.new(tCenter + Vector3.new(0, 12.2, awningZ)),
			Color3.fromRGB(238, 244, 252),
			Enum.Material.Snow,
			true
		)
		snowAwning.CanCollide = false
		addSurfaceSign(awning, signText, Color3.fromRGB(252, 226, 164), Enum.NormalId.Front)
		addSurfaceSign(awning, signText, Color3.fromRGB(252, 226, 164), Enum.NormalId.Back)
	end

	-- Snow-frosted Christmas trees, holiday gift stacks, snowmen, and 5th Ave vendor carts on the sidewalks
	spawnSnowyChristmasTree(origin + Vector3.new(-58, 0.3, 0))
	spawnSnowyChristmasTree(origin + Vector3.new(58, 0.3, 0))
	spawnSnowyChristmasTree(origin + Vector3.new(0, 0.3, -58))
	spawnSnowyChristmasTree(origin + Vector3.new(0, 0.3, 58))
	spawnSnowman(origin + Vector3.new(-14, 0.3, 0), 90)
	spawnCafePatio(origin + Vector3.new(0, 0.3, 18), 0)
	spawnFoodVendorCart(origin + Vector3.new(0, 0.3, -22), 180, variant)
	spawnGoldATM(origin + Vector3.new(-14, 0.3, -56), 0)
	spawnJackpotCrate(origin + Vector3.new(14, 0.3, -56))
	spawnCrateCluster(origin + Vector3.new(-14, 0.3, 56), 2)
	if seed % 2 == 0 then
		spawnBillboard(origin + Vector3.new(-56, 0.3, 56), 45, "HAPPY HOLIDAYS FROM 5TH AVE!", Color3.fromRGB(245, 205, 95))
		spawnArmoredCashTruck(origin + Vector3.new(0, 0.3, 42), 0)
	else
		spawnMegaCorpSurveillanceTower(origin + Vector3.new(56, 0.3, -56), -45)
	end
end

local function buildGasStation(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "LeoGasStation"
	makePart(m, "Canopy", Vector3.new(44, 2.2, 28), CFrame.new(origin + Vector3.new(0, 18, 0)), Color3.fromRGB(230, 45, 45), Enum.Material.Metal, true)
	local fascia = makePart(m, "Fascia", Vector3.new(44.8, 3.2, 28.8), CFrame.new(origin + Vector3.new(0, 19.5, 0)), Color3.fromRGB(255, 200, 40), Enum.Material.Neon, true)
	addSurfaceSign(fascia, "BOOM GAS & NITRO", Color3.fromRGB(30, 30, 35), Enum.NormalId.Front)
	addSurfaceSign(fascia, "BOOM GAS & NITRO", Color3.fromRGB(30, 30, 35), Enum.NormalId.Back)

	for _, sx in ipairs({ -16, 16 }) do
		for _, sz in ipairs({ -9, 9 }) do
			makePart(m, "Pillar", Vector3.new(2.2, 18, 2.2), CFrame.new(origin + Vector3.new(sx, 9, sz)), Color3.fromRGB(220, 225, 235), Enum.Material.Concrete, true)
		end
	end
	m.Parent = BuildingsFolder

	-- Explosive gas pumps & barrels!
	for _, px in ipairs({ -10, 0, 10 }) do
		spawnGasPump(origin + Vector3.new(px, 0.3, -4), 0)
		spawnGasPump(origin + Vector3.new(px, 0.3, 6), 180)
	end
	spawnExplosiveBarrel(origin + Vector3.new(-18, 0.3, 0))
	spawnExplosiveBarrel(origin + Vector3.new(18, 0.3, 0))
end

local function buildShippingContainerStack(origin: Vector3, offset: Vector3, yawDeg: number)
	local containerColors = {
		{ col = Color3.fromRGB(195, 48, 38), label = "RED HOOK PORT" },
		{ col = Color3.fromRGB(34, 96, 178), label = "ATLANTIC CARGO" },
		{ col = Color3.fromRGB(228, 162, 32), label = "MEGACORP FREIGHT" },
		{ col = Color3.fromRGB(38, 138, 86), label = "HUDSON SHIPPING" },
	}
	local baseRot = CFrame.new(origin + offset) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for row = 0, 1 do
		for tier = 0, 1 do
			if not (row == 1 and tier == 1) then
				local spec = containerColors[((row * 2 + tier) % #containerColors) + 1]
				local cPos = baseRot * CFrame.new((row - 0.5) * 9.2, 4.4 + tier * 8.8, 0)
				local box = makePart(BuildingsFolder, "ShippingContainer", Vector3.new(8.4, 8.6, 22.0), cPos, spec.col, Enum.Material.Metal, true)
				makePart(BuildingsFolder, "ContainerCornerFrame", Vector3.new(8.8, 8.8, 1.2), cPos * CFrame.new(0, 0, -10.5), Color3.fromRGB(38, 42, 50), Enum.Material.Metal, true)
				makePart(BuildingsFolder, "ContainerRearDoors", Vector3.new(8.8, 8.8, 1.2), cPos * CFrame.new(0, 0, 10.5), Color3.fromRGB(38, 42, 50), Enum.Material.Metal, true)
				addSurfaceSign(box, spec.label, Color3.fromRGB(245, 248, 255), Enum.NormalId.Left)
				addSurfaceSign(box, spec.label, Color3.fromRGB(245, 248, 255), Enum.NormalId.Right)
			end
		end
	end
end

local function buildIndustrialYardBlock(origin: Vector3, seed: number)
	-- Compact Hudson River Cargo Container Dock (NO stick cranes cluttering the Manhattan skyline!)
	buildShippingContainerStack(origin, Vector3.new(-18, 0, -18), 0)
	buildShippingContainerStack(origin, Vector3.new(18, 0, 14), 0)

	-- Explosive barrel clusters & crates
	for k = 1, 5 do
		local angle = (k / 5) * math.pi * 2 + seed
		local bPos = origin + Vector3.new(math.cos(angle) * 22, 0, math.sin(angle) * 22)
		spawnExplosiveBarrel(bPos)
		spawnExplosiveBarrel(bPos + Vector3.new(3.2, 0, 0))
	end
	spawnCrateCluster(origin + Vector3.new(-14, 0, 18), 3)
	spawnCrateCluster(origin + Vector3.new(8, 0, -18), 3)
	spawnConstructionBarrier(origin + Vector3.new(0, 0, -38), 0)
	spawnConstructionBarrier(origin + Vector3.new(-38, 0, 0), 90)
	spawnBillboard(origin + Vector3.new(-32, 0, 32), 45, "HUDSON CARGO DOCKS", Color3.fromRGB(255, 165, 50))
end

local function buildSuburbanParkBlock(origin: Vector3)
	-- Snowy Christmas Central Park: white snow lawn (Enum.Material.Snow), Wollman Ice Skating Rink (54x40 Enum.Material.Ice),
	-- 48-stud Illuminated Central Park Christmas Tree with golden star topper, snowmen, and park benches!
	local parkSpan = BLOCK_SIZE - ROAD_WIDTH - 12
	makePart(CityRoot, "ParkLawn", Vector3.new(parkSpan, 0.24, parkSpan), CFrame.new(origin + Vector3.new(0, 0.24, 0)), Color3.fromRGB(238, 244, 252), Enum.Material.Snow, true)

	local rink = makePart(CityRoot, "WollmanIceSkatingRink", Vector3.new(54, 0.24, 40), CFrame.new(origin + Vector3.new(-14, 0.34, 16)), Color3.fromRGB(168, 214, 248), Enum.Material.Ice, true)
	rink.Reflectance = 0.32

	-- 48-stud Illuminated Central Park Christmas Tree with golden star topper
	buildGiantChristmasTree(origin + Vector3.new(28, 0.36, -18), 48, "CentralParkChristmasTree")

	-- Snowy evergreen groves & holiday snowmen around the park paths
	for _, treeOff in ipairs({
		Vector3.new(-46, 0.36, -38),
		Vector3.new(-46, 0.36, 42),
		Vector3.new(44, 0.36, 36),
		Vector3.new(46, 0.36, -42),
		Vector3.new(-8, 0.36, -42),
	}) do
		spawnSnowyChristmasTree(origin + treeOff)
	end

	spawnSnowman(origin + Vector3.new(18, 0.36, 12), -45)
	spawnSnowman(origin + Vector3.new(-44, 0.36, 4), 60)
	spawnSnowman(origin + Vector3.new(12, 0.36, -32), 180)

	-- Perimeter destructible fences, park benches & holiday gift stacks
	spawnFenceRun(origin + Vector3.new(0, 0.3, -52), 0, 4, Color3.fromRGB(230, 236, 246))
	spawnFenceRun(origin + Vector3.new(0, 0.3, 52), 0, 4, Color3.fromRGB(230, 236, 246))
	spawnBench(origin + Vector3.new(18, 0.36, 22), -45)
	spawnBench(origin + Vector3.new(18, 0.36, -4), -135)
	spawnJackpotCrate(origin + Vector3.new(28, 0.36, -4))
	spawnJackpotCrate(origin + Vector3.new(18, 0.36, -18))
	spawnFoodVendorCart(origin + Vector3.new(38, 0.36, 14), -90, 2)
end

-- 1. Holiday Market Chalet & Golden Prometheus Monument for Rockefeller Christmas Party
local function buildHolidayChalet(pos: Vector3, yawDeg: number, boothTitle: string)
	local m = Instance.new("Model")
	m.Name = "HolidayMarketChalet"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local body = makePart(m, "ChaletCabin", Vector3.new(9.5, 6.2, 7.2), rot * CFrame.new(0, 3.1, 0), Color3.fromRGB(118, 72, 42), Enum.Material.WoodPlanks, true)
	makeWedge(m, "RoofLeft", Vector3.new(10.5, 3.0, 4.4), rot * CFrame.new(0, 7.6, -2.2) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(238, 244, 252), Enum.Material.Snow)
	makeWedge(m, "RoofRight", Vector3.new(10.5, 3.0, 4.4), rot * CFrame.new(0, 7.6, 2.2), Color3.fromRGB(238, 244, 252), Enum.Material.Snow)
	local garland = makePart(m, "FairyLightGarland", Vector3.new(10.2, 0.45, 7.8), rot * CFrame.new(0, 6.2, 0), Color3.fromRGB(255, 220, 85), Enum.Material.Neon, false)
	garland.CanCollide = false
	addSurfaceSign(body, boothTitle, Color3.fromRGB(255, 232, 145), Enum.NormalId.Front)
	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "Crate", 120, 85, 10, false, 1)
end

local function buildPrometheusMonument(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "GoldenPrometheusMonument"
	local ped = makePart(m, "GranitePedestal", Vector3.new(8.5, 4.8, 8.5), CFrame.new(pos + Vector3.new(0, 2.4, 0)), Color3.fromRGB(64, 70, 82), Enum.Material.Marble, true)
	local ring = makePart(m, "GoldenZodiacRing", Vector3.new(1.2, 9.5, 9.5), CFrame.new(pos + Vector3.new(0, 9.6, 0)) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(245, 198, 48), Enum.Material.Metal, true)
	ring.Shape = Enum.PartType.Cylinder
	ring.Reflectance = 0.45
	local figure = makePart(m, "GoldenStatueCore", Vector3.new(2.6, 7.2, 2.2), CFrame.new(pos + Vector3.new(0, 9.4, 0)) * CFrame.Angles(math.rad(-18), 0, math.rad(12)), Color3.fromRGB(255, 212, 55), Enum.Material.Neon, true)
	figure.CanCollide = false
	addSurfaceSign(ped, "ROCKEFELLER PROMETHEUS MONUMENT", Color3.fromRGB(255, 220, 95), Enum.NormalId.Front)
	m.PrimaryPart = ped
	m.Parent = LandmarksFolder
end

-- 2. Times Square Live Outdoor Concert Stage & Block Party (`buildConcertStage`)
local function buildConcertStage(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "TimesSquareConcertStage"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	local deck = makePart(m, "ConcertStageDeck", Vector3.new(42, 2.8, 24), rot * CFrame.new(0, 1.4, 0), Color3.fromRGB(24, 28, 40), Enum.Material.Metal, true)
	makePart(m, "NeonStageTrim", Vector3.new(42.6, 0.5, 24.6), rot * CFrame.new(0, 2.75, 0), Color3.fromRGB(255, 65, 215), Enum.Material.Neon, true)

	-- Giant LED Backdrop Screen + Steel Truss Arch with Colored Stage SpotLights
	local screen = makePart(m, "GiantLEDBackdrop", Vector3.new(36, 18, 1.8), rot * CFrame.new(0, 11.8, 10.5), Color3.fromRGB(16, 20, 34), Enum.Material.Metal, true)
	local screenGlow = makePart(m, "LEDScreenBorder", Vector3.new(37.2, 19.2, 1.4), rot * CFrame.new(0, 11.8, 10.6), Color3.fromRGB(55, 235, 255), Enum.Material.Neon, true)
	screenGlow.CanCollide = false
	addSurfaceSign(screen, "LIVE IN MANHATTAN • NEW YEAR CONCERT", Color3.fromRGB(255, 235, 85), Enum.NormalId.Front)
	addSurfaceSign(screen, "LIVE IN MANHATTAN • NEW YEAR CONCERT", Color3.fromRGB(255, 235, 85), Enum.NormalId.Back)

	for _, sx in ipairs({ -19, 19 }) do
		makePart(m, "SteelTrussPillar", Vector3.new(2.2, 24, 2.2), rot * CFrame.new(sx, 12, -2), Color3.fromRGB(48, 56, 70), Enum.Material.DiamondPlate, true)
		-- Giant Stacked Concert Subwoofers
		local sub = makePart(m, "ConcertSubwooferStack", Vector3.new(6.2, 11.5, 5.6), rot * CFrame.new(sx, 7.2, 3), Color3.fromRGB(20, 22, 28), Enum.Material.Metal, true)
		makePart(m, "SubwooferNeonCone", Vector3.new(4.2, 4.2, 0.4), rot * CFrame.new(sx, 9.2, 0.1), Color3.fromRGB(55, 235, 255), Enum.Material.Neon, true)
		addSurfaceSign(sub, "BASS 10,000W", Color3.fromRGB(255, 95, 225), Enum.NormalId.Front)
	end
	local topTruss = makePart(m, "OverheadLightTruss", Vector3.new(42, 2.0, 2.2), rot * CFrame.new(0, 23.5, -2), Color3.fromRGB(48, 56, 70), Enum.Material.DiamondPlate, true)

	local beamColors = {
		Color3.fromRGB(255, 65, 220),
		Color3.fromRGB(55, 235, 255),
		Color3.fromRGB(255, 225, 55),
		Color3.fromRGB(85, 255, 130),
	}
	for i = 1, 4 do
		local lx = -15 + (i - 1) * 10
		local lamp = makePart(m, "StageSpotLamp_" .. i, Vector3.new(2.0, 1.6, 2.0), rot * CFrame.new(lx, 22.0, -2), beamColors[i], Enum.Material.Neon, true)
		local spot = Instance.new("SpotLight")
		spot.Color = beamColors[i]
		spot.Brightness = 4.5
		spot.Range = 48
		spot.Angle = 55
		spot.Face = Enum.NormalId.Bottom
		spot.Parent = lamp
	end

	-- Illuminated DJ Booth & Neon Dance Floor in front of stage
	local djBooth = makePart(m, "DJBooth", Vector3.new(11.0, 3.8, 4.2), rot * CFrame.new(0, 4.7, 2.0), Color3.fromRGB(255, 75, 215), Enum.Material.Neon, true)
	addSurfaceSign(djBooth, "DJ LEO LIVE", Color3.fromRGB(255, 255, 255), Enum.NormalId.Front)
	local danceFloor = makePart(m, "NeonDanceFloor", Vector3.new(34, 0.22, 22), rot * CFrame.new(0, 0.34, -24), Color3.fromRGB(45, 195, 255), Enum.Material.Neon, true)
	danceFloor.Transparency = 0.25

	-- Smashable VIP Party Tables around the dance floor
	for _, tx in ipairs({ -14, 0, 14 }) do
		spawnJackpotCrate((rot * CFrame.new(tx, 0.3, -18)).Position)
		spawnCafePatio((rot * CFrame.new(tx, 0.3, -30)).Position, yawDeg)
	end

	m.PrimaryPart = deck
	m.Parent = LandmarksFolder
end

-- 3. Wall Street Federal Reserve Gold Bank & Charging Bull Monument (`buildGrandBankBlock`)
local function buildGrandBankBlock(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "ManhattanFederalGoldReserve"
	local bankCenter = origin + Vector3.new(0, 0.3, 24)

	-- Neoclassical Marble & Granite Bank Hall + Soaring Wall Street Financial Skyscraper behind it
	local hall = makePart(m, "NeoclassicalBankHall", Vector3.new(78, 46, 52), CFrame.new(bankCenter + Vector3.new(0, 23, 0)), Color3.fromRGB(224, 220, 210), Enum.Material.Marble, true)
	makePart(m, "GraniteSteps", Vector3.new(84, 2.4, 62), CFrame.new(bankCenter + Vector3.new(0, 1.2, -4)), Color3.fromRGB(168, 164, 156), Enum.Material.Limestone, true)

	-- 8 Tall Fluted Marble Columns along the front portico
	for i = 1, 8 do
		local cx = -31.5 + (i - 1) * 9.0
		local col = makePart(
			m,
			"FlutedMarbleColumn_" .. i,
			Vector3.new(38, 3.4, 3.4),
			CFrame.new(bankCenter + Vector3.new(cx, 21.4, -28.5)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(238, 235, 226),
			Enum.Material.Marble,
			true
		)
		col.Shape = Enum.PartType.Cylinder
	end

	local pediment = makePart(m, "BankPedimentFrieze", Vector3.new(80, 6.5, 8.0), CFrame.new(bankCenter + Vector3.new(0, 43.5, -26.5)), Color3.fromRGB(214, 182, 96), Enum.Material.Metal, true)
	addSurfaceSign(pediment, "MANHATTAN FEDERAL GOLD RESERVE", Color3.fromRGB(28, 24, 14), Enum.NormalId.Front)
	addSurfaceSign(pediment, "MANHATTAN FEDERAL GOLD RESERVE", Color3.fromRGB(28, 24, 14), Enum.NormalId.Back)

	-- Charging Bull / Golden Bullion Monument in the forecourt
	local bullPed = makePart(m, "BullMonumentPedestal", Vector3.new(9.0, 3.2, 14.0), CFrame.new(origin + Vector3.new(-32, 1.9, -22)), Color3.fromRGB(58, 62, 72), Enum.Material.Marble, true)
	local bullBody = makePart(m, "BronzeChargingBull", Vector3.new(4.8, 4.6, 9.5), CFrame.new(origin + Vector3.new(-32, 5.6, -22)), Color3.fromRGB(205, 152, 54), Enum.Material.Metal, true)
	bullBody.Reflectance = 0.38
	addSurfaceSign(bullPed, "WALL ST CHARGING BULL", Color3.fromRGB(255, 215, 85), Enum.NormalId.Front)

	m.PrimaryPart = hall
	m.Parent = BuildingsFolder

	-- Towering Financial Center Skyscrapers flanking the Reserve
	buildSkyscraper(origin + Vector3.new(-42, 0.3, 38), 32, 32, 225, Color3.fromRGB(68, 76, 90), "WallStreetTowerWest", false)
	buildSkyscraper(origin + Vector3.new(42, 0.3, 38), 32, 32, 255, Color3.fromRGB(84, 76, 68), "WallStreetTowerEast", false)
	buildSpeedShop(origin + Vector3.new(26, 0, -28), -90)

	-- Smashable Gold ATMs, Armored Cash Trucks & Golden Bank Vaults out front!
	for _, gx in ipairs({ -22, -8, 8, 22 }) do
		spawnGoldATM(origin + Vector3.new(gx, 0.3, -6), 0)
	end
	spawnArmoredCashTruck(origin + Vector3.new(-18, 0.3, -38), 90)
	spawnMegaCorpBankVault(origin + Vector3.new(0, 0.3, -18), 0)
	spawnJackpotCrate(origin + Vector3.new(-14, 0.3, -18))
	spawnJackpotCrate(origin + Vector3.new(14, 0.3, -18))
end

-- 4. Manhattan General Hospital Complex (`buildHospitalBlock`)
local function spawnParkedAmbulanceProp(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "NYC_EMS_Ambulance"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local body = makePart(m, "AmbulanceBody", Vector3.new(6.4, 5.2, 14.4), rot * CFrame.new(0, 2.8, 0), Color3.fromRGB(246, 248, 252), Enum.Material.SmoothPlastic, true)
	makePart(m, "RedCrossStripe", Vector3.new(6.55, 0.85, 14.5), rot * CFrame.new(0, 2.6, 0), Color3.fromRGB(235, 38, 45), Enum.Material.SmoothPlastic, false)
	local bar = makePart(m, "EmergencyLightbar", Vector3.new(4.8, 0.55, 1.1), rot * CFrame.new(0, 5.65, -4.5), Color3.fromRGB(255, 45, 55), Enum.Material.Neon, false)
	bar.CanCollide = false
	addSurfaceSign(body, "+ NYC EMS AMBULANCE +", Color3.fromRGB(225, 32, 38), Enum.NormalId.Left)
	addSurfaceSign(body, "+ NYC EMS AMBULANCE +", Color3.fromRGB(225, 32, 38), Enum.NormalId.Right)
	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "TrafficVehicle", 300, 200, 12, false, 1)
end

local function buildHospitalBlock(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "ManhattanGeneralHospital"

	local mainTowerPos = origin + Vector3.new(-24, 0.3, 20)
	local eastWingPos = origin + Vector3.new(28, 0.3, 20)

	-- Crisp White & Sky-Blue Glass Medical Towers (165 studs tall)
	local towerA = makePart(m, "MedicalTowerMain", Vector3.new(44, 165, 42), CFrame.new(mainTowerPos + Vector3.new(0, 82.5, 0)), Color3.fromRGB(238, 244, 252), Enum.Material.SmoothPlastic, true)
	local glassA = makePart(m, "MedicalGlassCurtain", Vector3.new(40, 150, 42.6), CFrame.new(mainTowerPos + Vector3.new(0, 82, 0)), Color3.fromRGB(115, 195, 245), Enum.Material.Glass, true)
	glassA.Reflectance = 0.28

	makePart(m, "MedicalTowerEastWing", Vector3.new(38, 125, 38), CFrame.new(eastWingPos + Vector3.new(0, 62.5, 0)), Color3.fromRGB(232, 238, 248), Enum.Material.SmoothPlastic, true)
	makePart(m, "Skybridge", Vector3.new(24, 10, 14), CFrame.new(origin + Vector3.new(4, 58, 20)), Color3.fromRGB(135, 205, 250), Enum.Material.Glass, true)

	-- Glowing Red Cross Emblems on Rooftop & Facade
	makePart(m, "RedCrossVert", Vector3.new(4.5, 18, 1.4), CFrame.new(mainTowerPos + Vector3.new(0, 138, -21.6)), Color3.fromRGB(255, 42, 52), Enum.Material.Neon, true)
	makePart(m, "RedCrossHoriz", Vector3.new(18, 4.5, 1.4), CFrame.new(mainTowerPos + Vector3.new(0, 138, -21.6)), Color3.fromRGB(255, 42, 52), Enum.Material.Neon, true)

	-- Emergency Ambulance Canopy
	local canopy = makePart(m, "EmergencyBayCanopy", Vector3.new(48, 2.2, 22), CFrame.new(origin + Vector3.new(-16, 16, -18)), Color3.fromRGB(225, 38, 48), Enum.Material.Metal, true)
	addSurfaceSign(canopy, "MANHATTAN GENERAL HOSPITAL • EMERGENCY", Color3.fromRGB(255, 255, 255), Enum.NormalId.Front)
	addSurfaceSign(canopy, "MANHATTAN GENERAL HOSPITAL • EMERGENCY", Color3.fromRGB(255, 255, 255), Enum.NormalId.Back)

	m.PrimaryPart = towerA
	m.Parent = BuildingsFolder

	-- 2 Parked NYC EMS Ambulances + Drive-Through Instant Medical Triage & Repair Bay!
	spawnParkedAmbulanceProp(origin + Vector3.new(-28, 0.3, -24), 0)
	spawnParkedAmbulanceProp(origin + Vector3.new(-6, 0.3, -24), 0)
	buildMechanicRepairBay(origin + Vector3.new(34, 0, -24), 0)
	spawnCrateCluster(origin + Vector3.new(-18, 0.3, -44), 3)
	spawnJackpotCrate(origin + Vector3.new(0, 0.3, -44))
end

-- 5. Manhattan University & Public School District (`buildUniversityBlock` & `buildSchoolBlock`)
local function buildUniversityBlock(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "ManhattanUniversityCampus"

	local hallCenter = origin + Vector3.new(0, 0.3, 28)
	local mainHall = makePart(m, "CollegiateMainHall", Vector3.new(82, 44, 38), CFrame.new(hallCenter + Vector3.new(0, 22, 0)), Color3.fromRGB(148, 56, 48), Enum.Material.Concrete, true)
	makePart(m, "LimestoneColonnade", Vector3.new(74, 36, 4.0), CFrame.new(hallCenter + Vector3.new(0, 18, -19.5)), Color3.fromRGB(218, 212, 198), Enum.Material.Limestone, true)

	-- Classical Rotunda Dome & 150-Stud Collegiate Clock Tower
	local dome = makePart(m, "ClassicalDome", Vector3.new(32, 24, 32), CFrame.new(hallCenter + Vector3.new(0, 50, 0)), Color3.fromRGB(72, 145, 118), Enum.Material.Metal, true)
	dome.Shape = Enum.PartType.Ball
	local clockTower = makePart(m, "UniversityClockTower", Vector3.new(22, 150, 22), CFrame.new(origin + Vector3.new(-44, 75.3, 28)), Color3.fromRGB(212, 204, 188), Enum.Material.Limestone, true)
	local clockFace = makePart(m, "ClockFaceNeon", Vector3.new(12, 12, 1.4), CFrame.new(origin + Vector3.new(-44, 126, 16.8)), Color3.fromRGB(255, 232, 145), Enum.Material.Neon, true)
	addSurfaceSign(clockFace, "XII", Color3.fromRGB(24, 28, 38), Enum.NormalId.Front)

	local gateSign = makePart(m, "UniversityGateArch", Vector3.new(44, 4.2, 2.4), CFrame.new(origin + Vector3.new(0, 18, -42)), Color3.fromRGB(36, 58, 108), Enum.Material.Metal, true)
	addSurfaceSign(gateSign, "MANHATTAN UNIVERSITY • EST. 1754", Color3.fromRGB(255, 220, 85), Enum.NormalId.Front)
	addSurfaceSign(gateSign, "MANHATTAN UNIVERSITY • EST. 1754", Color3.fromRGB(255, 220, 85), Enum.NormalId.Back)

	-- Bronze Founder Statue in Campus Quad
	local statuePed = makePart(m, "FounderStatuePedestal", Vector3.new(7, 4.5, 7), CFrame.new(origin + Vector3.new(0, 2.5, -12)), Color3.fromRGB(185, 180, 170), Enum.Material.Marble, true)
	makePart(m, "BronzeFounderStatue", Vector3.new(3.2, 7.5, 3.2), CFrame.new(origin + Vector3.new(0, 8.5, -12)), Color3.fromRGB(168, 128, 64), Enum.Material.Metal, true)
	addSurfaceSign(statuePed, "ALMA MATER MONUMENT", Color3.fromRGB(255, 225, 120), Enum.NormalId.Front)

	m.PrimaryPart = mainHall
	m.Parent = BuildingsFolder

	spawnCafePatio(origin + Vector3.new(-22, 0.3, -18), 0)
	spawnCafePatio(origin + Vector3.new(22, 0.3, -18), 0)
	spawnJackpotCrate(origin + Vector3.new(-14, 0.3, -32))
	spawnJackpotCrate(origin + Vector3.new(14, 0.3, -32))
	spawnSnowyChristmasTree(origin + Vector3.new(-36, 0.3, -24))
	spawnSnowyChristmasTree(origin + Vector3.new(36, 0.3, -24))
end

local function spawnParkedSchoolBusProp(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "NYC_SchoolBus"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local body = makePart(m, "BusBody", Vector3.new(6.8, 5.6, 18.2), rot * CFrame.new(0, 3.0, 0), Color3.fromRGB(252, 185, 22), Enum.Material.SmoothPlastic, true)
	makePart(m, "BlackSafetyStripe", Vector3.new(6.95, 0.65, 18.3), rot * CFrame.new(0, 2.6, 0), Color3.fromRGB(22, 24, 28), Enum.Material.SmoothPlastic, false)
	addSurfaceSign(body, "NYC SCHOOL BUS • P.S. 101", Color3.fromRGB(18, 20, 24), Enum.NormalId.Left)
	addSurfaceSign(body, "NYC SCHOOL BUS • P.S. 101", Color3.fromRGB(18, 20, 24), Enum.NormalId.Right)
	weldChildrenToPrimary(m, body)
	m.Parent = PropsFolder
	tagDestructible(m, "CityBus", 420, 260, 14, false, 1)
end

local function buildSchoolBlock(origin: Vector3)
	local m = Instance.new("Model")
	m.Name = "ManhattanPublicSchoolPS101"

	local schoolBuilding = makePart(m, "SchoolRedBrickMain", Vector3.new(76, 42, 38), CFrame.new(origin + Vector3.new(0, 21.3, 24)), Color3.fromRGB(162, 58, 46), Enum.Material.Concrete, true)
	local signHeader = makePart(m, "SchoolBannerSign", Vector3.new(58, 4.5, 1.8), CFrame.new(origin + Vector3.new(0, 38, 4.2)), Color3.fromRGB(252, 192, 32), Enum.Material.Metal, true)
	addSurfaceSign(signHeader, "MANHATTAN PUBLIC SCHOOL P.S. 101", Color3.fromRGB(20, 24, 34), Enum.NormalId.Front)
	addSurfaceSign(signHeader, "MANHATTAN PUBLIC SCHOOL P.S. 101", Color3.fromRGB(20, 24, 34), Enum.NormalId.Back)

	-- Schoolyard Basketball Court & Hoops
	makePart(m, "SchoolyardCourt", Vector3.new(54, 0.22, 36), CFrame.new(origin + Vector3.new(0, 0.34, -22)), Color3.fromRGB(58, 86, 128), Enum.Material.Asphalt, true)
	for _, sx in ipairs({ -24, 24 }) do
		makePart(m, "HoopPost", Vector3.new(0.8, 11, 0.8), CFrame.new(origin + Vector3.new(sx, 5.8, -22)), Color3.fromRGB(220, 225, 235), Enum.Material.Metal, true)
		makePart(m, "Backboard", Vector3.new(0.4, 3.6, 5.2), CFrame.new(origin + Vector3.new(sx, 10.5, -22)), Color3.fromRGB(245, 248, 255), Enum.Material.SmoothPlastic, true)
	end

	m.PrimaryPart = schoolBuilding
	m.Parent = BuildingsFolder

	spawnParkedSchoolBusProp(origin + Vector3.new(-38, 0.3, -46), 90)
	spawnParkedSchoolBusProp(origin + Vector3.new(38, 0.3, -46), 90)
	spawnFenceRun(origin + Vector3.new(0, 0.3, -42), 0, 4, Color3.fromRGB(252, 195, 38))
	spawnSnowman(origin + Vector3.new(-18, 0.3, -18), 45)
	spawnSnowman(origin + Vector3.new(18, 0.3, -18), -45)
	spawnJackpotCrate(origin + Vector3.new(0, 0.3, -22))
end

-- 6. Washington Square & Central Park Grand Marble Triumphal Arch (`buildMonumentArch`)
local function buildMonumentArch(pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "WashingtonSquareTriumphalArch"
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local marbleCol = Color3.fromRGB(236, 234, 226)

	local leftPillar = makePart(m, "ArchPillarLeft", Vector3.new(11, 34, 12), rot * CFrame.new(-15, 17, 0), marbleCol, Enum.Material.Marble, true)
	makePart(m, "ArchPillarRight", Vector3.new(11, 34, 12), rot * CFrame.new(15, 17, 0), marbleCol, Enum.Material.Marble, true)
	local attic = makePart(m, "ArchAtticEntablature", Vector3.new(44, 14, 13.5), rot * CFrame.new(0, 41, 0), marbleCol, Enum.Material.Marble, true)
	makePart(m, "ArchSnowCornice", Vector3.new(45.5, 0.8, 14.5), rot * CFrame.new(0, 48.4, 0), Color3.fromRGB(240, 246, 255), Enum.Material.Snow, true)
	addSurfaceSign(attic, "MANHATTAN CENTENNIAL TRIUMPHAL ARCH", Color3.fromRGB(95, 86, 68), Enum.NormalId.Front)
	addSurfaceSign(attic, "MANHATTAN CENTENNIAL TRIUMPHAL ARCH", Color3.fromRGB(95, 86, 68), Enum.NormalId.Back)

	m.PrimaryPart = leftPillar
	m.Parent = LandmarksFolder
end

-- 7. Hudson & East River Maritime Port, Piers & 3D Boats (`buildBoatModel` & `buildHarborPortAndBoats`)
local function buildBoatModel(pos: Vector3, yawDeg: number, boatStyle: string)
	local m = Instance.new("Model")
	m.Name = "HarborBoat_" .. boatStyle
	local rot = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

	if boatStyle == "HolidayYacht" then
		local hull = makePart(m, "YachtHull", Vector3.new(16, 5.5, 68), rot * CFrame.new(0, 1.2, 0), Color3.fromRGB(244, 248, 255), Enum.Material.Metal, true)
		makeWedge(m, "YachtBow", Vector3.new(16, 5.5, 16), rot * CFrame.new(0, 1.2, -42) * CFrame.Angles(0, 0, 0), Color3.fromRGB(244, 248, 255), Enum.Material.Metal)
		makePart(m, "DeckTier1", Vector3.new(13.5, 5.2, 46), rot * CFrame.new(0, 6.5, 4), Color3.fromRGB(238, 244, 252), Enum.Material.SmoothPlastic, true)
		makePart(m, "BridgeDeck", Vector3.new(11.5, 4.4, 28), rot * CFrame.new(0, 11.2, 8), Color3.fromRGB(85, 205, 255), Enum.Material.Glass, true)
		makePart(m, "FestiveStringLights", Vector3.new(14.2, 0.5, 48), rot * CFrame.new(0, 9.2, 4), Color3.fromRGB(255, 215, 65), Enum.Material.Neon, true)
		addSurfaceSign(hull, "MANHATTAN HOLIDAY CRUISE YACHT", Color3.fromRGB(24, 48, 92), Enum.NormalId.Left)
		addSurfaceSign(hull, "MANHATTAN HOLIDAY CRUISE YACHT", Color3.fromRGB(24, 48, 92), Enum.NormalId.Right)
		m.PrimaryPart = hull
	elseif boatStyle == "StatenIslandFerry" then
		local hull = makePart(m, "FerryHull", Vector3.new(18, 6.0, 62), rot * CFrame.new(0, 1.4, 0), Color3.fromRGB(235, 112, 24), Enum.Material.Metal, true)
		local upper = makePart(m, "PassengerDeck", Vector3.new(16.5, 7.5, 52), rot * CFrame.new(0, 8.0, 0), Color3.fromRGB(242, 124, 32), Enum.Material.SmoothPlastic, true)
		makePart(m, "Wheelhouse", Vector3.new(10, 5.0, 14), rot * CFrame.new(0, 14.2, 0), Color3.fromRGB(244, 248, 252), Enum.Material.Metal, true)
		addSurfaceSign(upper, "MANHATTAN FERRY", Color3.fromRGB(255, 255, 255), Enum.NormalId.Left)
		addSurfaceSign(upper, "MANHATTAN FERRY", Color3.fromRGB(255, 255, 255), Enum.NormalId.Right)
		m.PrimaryPart = hull
	else
		-- Red & Black NYC Harbor Tugboat & Cargo Barge loaded with smashable cargo!
		local hull = makePart(m, "TugBargeHull", Vector3.new(15, 4.2, 48), rot * CFrame.new(0, 0.8, 0), Color3.fromRGB(188, 34, 38), Enum.Material.Metal, true)
		makePart(m, "TugWheelhouse", Vector3.new(9.5, 7.2, 12), rot * CFrame.new(0, 6.4, -12), Color3.fromRGB(32, 36, 44), Enum.Material.Metal, true)
		makePart(m, "TugSmokestack", Vector3.new(2.8, 6.5, 2.8), rot * CFrame.new(0, 12.2, -10), Color3.fromRGB(235, 185, 38), Enum.Material.Metal, true)
		spawnJackpotCrate((rot * CFrame.new(0, 2.9, 6)).Position)
		spawnCrateCluster((rot * CFrame.new(0, 2.9, 15)).Position, 3)
		m.PrimaryPart = hull
	end

	m.Parent = LandmarksFolder
end

local function buildHarborPortAndBoats(origin: Vector3, isEastSide: boolean, bz: number)
	local usable = BLOCK_SIZE - ROAD_WIDTH
	local outDir = if isEastSide then 1 else -1

	-- Inland Half of Block: Tall Port Terminal Warehouse & Maritime Authority Skyscraper so the horizon is never empty!
	local inlandX = -outDir * 32
	local towerH = 125 + (math.abs(bz) * 22)
	buildSkyscraper(
		origin + Vector3.new(inlandX, 0.3, -28),
		34,
		34,
		towerH,
		Color3.fromRGB(64, 76, 94),
		if isEastSide then "EastRiverPortTower" else "HudsonPortTower",
		false
	)

	local terminal = makePart(
		BuildingsFolder,
		"MaritimeCruiseTerminal",
		Vector3.new(42, 28, 56),
		CFrame.new(origin + Vector3.new(inlandX, 14.3, 28)),
		Color3.fromRGB(48, 58, 74),
		Enum.Material.Metal,
		true
	)
	local termSign = makePart(
		BuildingsFolder,
		"TerminalRoofSign",
		Vector3.new(2.2, 5.5, 48),
		CFrame.new(origin + Vector3.new(inlandX + outDir * 21.5, 31, 28)),
		Color3.fromRGB(22, 28, 40),
		Enum.Material.Metal,
		true
	)
	addSurfaceSign(
		termSign,
		if isEastSide then "EAST RIVER CRUISE & CARGO PORT" else "HUDSON RIVER MARITIME PIER",
		Color3.fromRGB(65, 225, 255),
		if isEastSide then Enum.NormalId.Right else Enum.NormalId.Left
	)
	local _ = terminal

	-- Waterfront Half + Heavy Wooden & Concrete Harbor Pier extending 95 studs out over the river water!
	makePart(CityRoot, "WaterfrontQuayWall", Vector3.new(usable, 0.24, usable), CFrame.new(origin + Vector3.new(0, 0.24, 0)), Color3.fromRGB(82, 88, 100), Enum.Material.Concrete, true)
	local pierCenter = origin + Vector3.new(outDir * 68, 0.36, 0)
	makePart(CityRoot, "HarborWoodenPierDeck", Vector3.new(98, 0.8, 48), CFrame.new(pierCenter), Color3.fromRGB(108, 78, 52), Enum.Material.WoodPlanks, true)

	-- Shipping containers, festive trees, and smashable cargo crates right on the pier deck
	buildShippingContainerStack(origin, Vector3.new(outDir * 22, 0.3, -34), 0)
	spawnJackpotCrate(pierCenter + Vector3.new(outDir * 18, 0.4, -10))
	spawnJackpotCrate(pierCenter + Vector3.new(outDir * 18, 0.4, 10))
	spawnCrateCluster(pierCenter + Vector3.new(0, 0.4, -14), 3)
	spawnCrateCluster(pierCenter + Vector3.new(0, 0.4, 14), 3)
	spawnExplosiveBarrel(pierCenter + Vector3.new(outDir * 28, 0.4, 0))
	spawnSnowyChristmasTree(origin + Vector3.new(outDir * 18, 0.36, 36))

	-- Docked 3D Boats floating beside the pier in the river water!
	local boatStyles = { "HolidayYacht", "StatenIslandFerry", "TugBarge" }
	local chosenStyle = boatStyles[((math.abs(bz)) % #boatStyles) + 1]
	buildBoatModel(origin + Vector3.new(outDir * 128, -0.4, 0), if isEastSide then 0 else 180, chosenStyle)
end

--------------------------------------------------------------------------------
-- BUILD FULL LEO CITY (MOODY DARK CLOUDY, SNOWY, RAINY NYC WINTER EDITION)
--------------------------------------------------------------------------------

local function buildLeoCity()
	local totalSpan = (GRID_RADIUS * 2 + 1) * BLOCK_SIZE + 240
	-- CityBaseplate at Y = -2.2, Size Y = 4.0 -> top Y = -0.20 (strictly below Road top Y = 0.16!)
	makePart(CityRoot, "CityBaseplate", Vector3.new(totalSpan, 4, totalSpan), CFrame.new(0, -2.2, 0), Color3.fromRGB(34, 38, 46), Enum.Material.Concrete, true)

	-- Expose Landmark Coordinates on Workspace.LeoCity for the Map & Mission System
	CityRoot:SetAttribute("ChristmasPartyPos", Vector3.new(-36, 0, 18))
	CityRoot:SetAttribute("ConcertStagePos", Vector3.new(0, 0, -180))
	CityRoot:SetAttribute("WallStreetBankPos", Vector3.new(180, 0, 0))
	CityRoot:SetAttribute("UniversityPos", Vector3.new(-360, 0, 0))
	CityRoot:SetAttribute("HospitalPos", Vector3.new(-180, 0, -180))
	CityRoot:SetAttribute("HarborPortPos", Vector3.new(720, 0, 0))
	CityRoot:SetAttribute("CentralParkMonumentPos", Vector3.new(-180, 0, 180))

	-- East River & Hudson River dark icy water along BOTH East and West waterfronts!
	local oceanX = (GRID_RADIUS + 1.1) * BLOCK_SIZE
	local eastRiver = makePart(CityRoot, "OceanWater", Vector3.new(380, 3.6, totalSpan), CFrame.new(oceanX, -1.8, 0), Color3.fromRGB(24, 48, 72), Enum.Material.Glass, true)
	eastRiver.Reflectance = 0.22
	local westRiver = makePart(CityRoot, "HudsonRiverWater", Vector3.new(380, 3.6, totalSpan), CFrame.new(-oceanX, -1.8, 0), Color3.fromRGB(24, 48, 72), Enum.Material.Glass, true)
	westRiver.Reflectance = 0.22

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
	-- Road Y = 0.0, Size Y = 0.32 -> top Y = 0.16
	-- LaneDash Y = 0.21, Size Y = 0.08 -> top Y = 0.25 (strictly above Road top Y = 0.16!)
	local gridExtent = (GRID_RADIUS + 1) * BLOCK_SIZE
	local grandAve = makePart(RoadsFolder, "GrandCentralAveNS", Vector3.new(ROAD_WIDTH, 0.32, gridExtent * 2), CFrame.new(0, 0.0, 0), Color3.fromRGB(26, 30, 38), Enum.Material.Asphalt, true)
	grandAve.Reflectance = 0.14
	for z = -gridExtent + 20, gridExtent - 20, 28 do
		makePart(RoadsFolder, "GrandAveDashNS", Vector3.new(0.8, 0.08, 12), CFrame.new(0, 0.21, z), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
		makePart(RoadsFolder, "GrandAveWhiteLaneW", Vector3.new(0.45, 0.08, 9), CFrame.new(-ROAD_WIDTH * 0.25, 0.21, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		makePart(RoadsFolder, "GrandAveWhiteLaneE", Vector3.new(0.45, 0.08, 9), CFrame.new(ROAD_WIDTH * 0.25, 0.21, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
	end

	-- Steaming NYC Manholes along Grand Central Avenue
	for z = -280, 280, 140 do
		spawnSteamingManhole(Vector3.new(8, 0.2, z + 35))
	end

	-- Build Road Grid & Intersections along block borders: (i + 0.5) * BLOCK_SIZE
	local roadLines = {}
	for i = -GRID_RADIUS - 1, GRID_RADIUS do
		table.insert(roadLines, (i + 0.5) * BLOCK_SIZE)
	end

	for _, rx in ipairs(roadLines) do
		local rns = makePart(RoadsFolder, "RoadNS", Vector3.new(ROAD_WIDTH, 0.32, gridExtent * 2), CFrame.new(rx, 0.0, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Asphalt, true)
		rns.Reflectance = 0.14
		for z = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashNS", Vector3.new(0.8, 0.08, 12), CFrame.new(rx, 0.21, z), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneNS_W", Vector3.new(0.45, 0.08, 9), CFrame.new(rx - ROAD_WIDTH * 0.25, 0.21, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneNS_E", Vector3.new(0.45, 0.08, 9), CFrame.new(rx + ROAD_WIDTH * 0.25, 0.21, z), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		end
	end

	for _, rz in ipairs(roadLines) do
		-- RoadEW at Y = 0.01 (top Y = 0.17) so NS/EW intersections never Z-fight; LaneDashEW at Y = 0.21 (top Y = 0.25)
		local rew = makePart(RoadsFolder, "RoadEW", Vector3.new(gridExtent * 2, 0.32, ROAD_WIDTH), CFrame.new(0, 0.01, rz), Color3.fromRGB(28, 32, 40), Enum.Material.Asphalt, true)
		rew.Reflectance = 0.14
		for x = -gridExtent + 20, gridExtent - 20, 28 do
			makePart(RoadsFolder, "LaneDashEW", Vector3.new(12, 0.08, 0.8), CFrame.new(x, 0.21, rz), Color3.fromRGB(235, 190, 50), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneEW_N", Vector3.new(9, 0.08, 0.45), CFrame.new(x, 0.21, rz - ROAD_WIDTH * 0.25), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
			makePart(RoadsFolder, "WhiteLaneEW_S", Vector3.new(9, 0.08, 0.45), CFrame.new(x, 0.21, rz + ROAD_WIDTH * 0.25), Color3.fromRGB(215, 222, 235), Enum.Material.SmoothPlastic, true)
		end
	end

	-- Intersections: Crosswalks (Y = 0.22, top Y = 0.26) + Traffic Lights + Steaming Manholes
	for _, rx in ipairs(roadLines) do
		for _, rz in ipairs(roadLines) do
			local interPos = Vector3.new(rx, 0, rz)
			for s = -2, 2 do
				if s ~= 0 then
					makePart(RoadsFolder, "CrosswalkN", Vector3.new(3.2, 0.08, 1.2), CFrame.new(rx + s * 5.5, 0.22, rz - ROAD_WIDTH * 0.5 - 2), Color3.fromRGB(212, 218, 230), Enum.Material.SmoothPlastic, true)
					makePart(RoadsFolder, "CrosswalkE", Vector3.new(1.2, 0.08, 3.2), CFrame.new(rx + ROAD_WIDTH * 0.5 + 2, 0.22, rz + s * 5.5), Color3.fromRGB(212, 218, 230), Enum.Material.SmoothPlastic, true)
				end
			end
			spawnTrafficLight(interPos, Vector3.new(-ROAD_WIDTH * 0.5 - 3, 0, -ROAD_WIDTH * 0.5 - 3), 0, "NS")
			spawnTrafficLight(interPos, Vector3.new(ROAD_WIDTH * 0.5 + 3, 0, ROAD_WIDTH * 0.5 + 3), 90, "EW")
			if math.abs(rx) <= 240 and math.abs(rz) <= 240 then
				spawnSteamingManhole(Vector3.new(rx - 9, 0.2, rz + 9))
			end
		end
	end

	-- Populate each block (bx, bz) in -GRID_RADIUS..GRID_RADIUS
	for bx = -GRID_RADIUS, GRID_RADIUS do
		for bz = -GRID_RADIUS, GRID_RADIUS do
			local origin = Vector3.new(bx * BLOCK_SIZE, 0, bz * BLOCK_SIZE)
			local usable = BLOCK_SIZE - ROAD_WIDTH

			-- Dark wet Manhattan bluestone granite sidewalk framing block at Y = 0.20 (Size Y = 0.20 -> top Y = 0.30)
			if bx ~= 0 then
				makePart(CityRoot, "SidewalkBlock", Vector3.new(usable, 0.20, usable), CFrame.new(origin + Vector3.new(0, 0.20, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
			else
				local sideW = (usable - ROAD_WIDTH) * 0.5
				makePart(CityRoot, "SidewalkBlockW", Vector3.new(sideW, 0.20, usable), CFrame.new(origin + Vector3.new(-(ROAD_WIDTH * 0.5 + sideW * 0.5), 0.20, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
				makePart(CityRoot, "SidewalkBlockE", Vector3.new(sideW, 0.20, usable), CFrame.new(origin + Vector3.new(ROAD_WIDTH * 0.5 + sideW * 0.5, 0.20, 0)), Color3.fromRGB(68, 74, 84), Enum.Material.Concrete, true)
			end

			-- Streetlights, Fire Hydrants & Easy-Smash Street Clutter Rows on every block perimeter
			local edge = usable * 0.5 - 3.5
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, -edge), 45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, -edge), 135)
			spawnStreetLight(origin + Vector3.new(-edge, 0.3, edge), -45)
			spawnStreetLight(origin + Vector3.new(edge, 0.3, edge), -135)
			spawnFireHydrant(origin + Vector3.new(-edge, 0.3, 0))
			spawnFireHydrant(origin + Vector3.new(edge, 0.3, 0))
			spawnStreetClutterRow(origin + Vector3.new(-edge + 2.5, 0.3, -18), 90)
			spawnStreetClutterRow(origin + Vector3.new(edge - 2.5, 0.3, 18), -90)

			-- District & Landmark Assignment
			if bx == 0 and bz == 0 then
				-- 5TH AVENUE & CENTRAL PARK SOUTH PLAZA (180x180 Block):
				-- Central 5th Avenue driving lanes (X = -19..19) are 100% wide-open so the player looks straight down the towering Manhattan skyscraper canyon!
				-- Holiday Gift Stacks, snowmen, and crates are placed along the curb/plaza edges (never blocking the center driving lane of 5th Avenue!).
				spawnJackpotCrate(origin + Vector3.new(-22, 0.3, 8))
				spawnJackpotCrate(origin + Vector3.new(22, 0.3, 8))
				spawnJackpotCrate(origin + Vector3.new(-22, 0.3, -18))
				spawnJackpotCrate(origin + Vector3.new(22, 0.3, -18))
				spawnCrateCluster(origin + Vector3.new(-24, 0.3, -32), 2)
				spawnCrateCluster(origin + Vector3.new(24, 0.3, -32), 2)
				spawnFireHydrant(origin + Vector3.new(-21, 0.3, -24))
				spawnFireHydrant(origin + Vector3.new(21, 0.3, -24))

				-- 52-stud Rockefeller / Plaza Christmas Tree at (-46, 0.3, 18) surrounded by Holiday Market Chalet Booths, Golden Prometheus Statue, and Gift Stacks!
				buildGiantChristmasTree(origin + Vector3.new(-46, 0.3, 18), 52, "RockefellerPlazaChristmasTree")
				buildPrometheusMonument(origin + Vector3.new(-46, 0.3, -4))
				buildHolidayChalet(origin + Vector3.new(-58, 0.3, 28), 90, "HOLIDAY HOT COCOA")
				buildHolidayChalet(origin + Vector3.new(-32, 0.3, 32), -45, "NYC TOYS & GIFTS")
				spawnJackpotCrate(origin + Vector3.new(-36, 0.3, 18))
				spawnJackpotCrate(origin + Vector3.new(-46, 0.3, 8))
				spawnSnowman(origin + Vector3.new(-36, 0.3, 26), 135)
				spawnSnowman(origin + Vector3.new(-54, 0.3, 10), 45)
				spawnSnowyChristmasTree(origin + Vector3.new(-58, 0.3, 42))
				spawnSnowyChristmasTree(origin + Vector3.new(58, 0.3, 42))

				-- Ornamental Circular Marble Fountain in the West Courtyard (-46, 0.3, 42) — clear of buildings and tree!
				local fCenter = origin + Vector3.new(-46, 0.3, 42)
				local fountain = makePart(LandmarksFolder, "LeoPlazaFountain", Vector3.new(3.2, 16, 16), CFrame.new(fCenter + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(235, 238, 245), Enum.Material.Marble, true)
				fountain.Shape = Enum.PartType.Cylinder
				local tier = makePart(LandmarksFolder, "FountainWaterTier", Vector3.new(1.4, 12, 12), CFrame.new(fCenter + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(165, 215, 248), Enum.Material.Ice, true)
				tier.Shape = Enum.PartType.Cylinder
				tier.Transparency = 0.15
				local spire = makePart(LandmarksFolder, "FountainWaterSpire", Vector3.new(7.5, 2.4, 2.4), CFrame.new(fCenter + Vector3.new(0, 6.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(215, 238, 255), Enum.Material.Ice, true)
				spire.Shape = Enum.PartType.Cylinder
				spire.CanCollide = false
				tagDestructible(fountain, "PlazaFountain", 500, 300, 75, false, 4)

				-- Tiered Heist Targets neatly arranged along the East & West Plaza Walkways (well clear of SpeedShop at (52, 0, -22)!)
				spawnFoodVendorCart(origin + Vector3.new(-26, 0.3, 14), 90, 1)
				spawnFoodVendorCart(origin + Vector3.new(26, 0.3, 14), -90, 2)
				spawnGoldATM(origin + Vector3.new(-26, 0.3, -2), 90)
				spawnGoldATM(origin + Vector3.new(26, 0.3, -2), -90)
				spawnArmoredCashTruck(origin + Vector3.new(26, 0.3, 44), 0)
				spawnMegaCorpBankVault(origin + Vector3.new(48, 0.3, 44), -25)

				buildSpeedShop(origin + Vector3.new(52, 0, -22), -90)
				buildMechanicRepairBay(origin + Vector3.new(-52, 0, -22), 90)
			elseif bx == 1 and bz == 0 then
				-- Wall Street Grand Federal Gold Reserve Bank & Charging Bull Monument
				buildGrandBankBlock(origin)
			elseif bx == -1 and bz == 0 then
				-- Central Park South Entrance + Holiday Market Chalets + West Plaza Mechanic Bay
				buildSuburbanParkBlock(origin)
				buildHolidayChalet(origin + Vector3.new(-32, 0.36, -18), 0, "CENTRAL PARK WAFFLES")
				buildMechanicRepairBay(origin + Vector3.new(38, 0, -36), 90)
				spawnBusStop(origin + Vector3.new(0, 0.3, edge - 2), 180)
				spawnGoldATM(origin + Vector3.new(28, 0.3, 24), -90)
				spawnFoodVendorCart(origin + Vector3.new(32, 0.3, 32), 180, 1)
			elseif bx == -1 and bz == -1 then
				-- Mount Sinai / Bellevue Manhattan General Hospital Complex
				buildHospitalBlock(origin)
			elseif bx == -2 and bz == 0 then
				-- Columbia / NYU Manhattan University Campus + Clock Tower
				buildUniversityBlock(origin)
			elseif bx == -2 and bz == 1 then
				-- P.S. 101 Manhattan Public School + School Buses & Basketball Court
				buildSchoolBlock(origin)
			elseif bx == -1 and bz == 1 then
				-- Washington Square Triumphal Arch & Central Park Monuments
				buildSuburbanParkBlock(origin)
				buildMonumentArch(origin + Vector3.new(0, 0.36, -34), 0)
			elseif bx == 0 and bz ~= 0 then
				-- 5TH AVENUE SKYSCRAPER CANYON & TIMES SQUARE CONCERT STAGE (bz == -1)
				local isLeoBlock = (bz == -1)
				local seed = math.abs(bz * 19)
				local hNW = if isLeoBlock then 310 else 185 + (seed % 95)
				local hNE = if isLeoBlock then 265 else 170 + ((seed + 37) % 105)
				local hSW = if isLeoBlock then 240 else 160 + ((seed + 61) % 110)
				local hSE = if isLeoBlock then 280 else 195 + ((seed + 83) % 95)

				buildSkyscraper(origin + Vector3.new(-44, 0.3, -32), 36, 36, hNW, Color3.fromRGB(58, 68, 86), if isLeoBlock then "LeoTower" else "FifthAveTowerNW", false)
				buildSkyscraper(origin + Vector3.new(44, 0.3, -32), 36, 36, hNE, Color3.fromRGB(76, 82, 96), "FifthAveTowerNE", false)
				buildSkyscraper(origin + Vector3.new(-44, 0.3, 32), 36, 36, hSW, Color3.fromRGB(88, 78, 70), "FifthAveTowerSW", false)
				buildSkyscraper(origin + Vector3.new(44, 0.3, 32), 36, 36, hSE, Color3.fromRGB(64, 72, 86), "FifthAveTowerSE", false)

				spawnSnowyChristmasTree(origin + Vector3.new(-24, 0.3, 0))
				spawnSnowyChristmasTree(origin + Vector3.new(24, 0.3, 0))
				spawnBusStop(origin + Vector3.new(-24, 0.3, -52), 90)
				spawnJackpotCrate(origin + Vector3.new(24, 0.3, -14))
				spawnGoldATM(origin + Vector3.new(-24, 0.3, 14), 90)
				spawnFoodVendorCart(origin + Vector3.new(24, 0.3, 18), -90, bz)
				if isLeoBlock then
					-- Times Square Live Concert Stage & Neon Dance Floor at (0, 0, -180)!
					buildConcertStage(origin + Vector3.new(0, 0.3, 0), 0)
					spawnBillboard(origin + Vector3.new(-26, 0.3, -48), 25, "TIMES SQUARE NEW YEAR LIVE!", Color3.fromRGB(255, 85, 220))
					spawnBillboard(origin + Vector3.new(26, 0.3, -48), -25, "BROADWAY & 5TH AVE CONCERT", Color3.fromRGB(55, 235, 255))
					spawnMegaCorpBankVault(origin + Vector3.new(44, 0.3, 0), -90)
					spawnArmoredCashTruck(origin + Vector3.new(26, 0.3, 48), 0)
				elseif bz == -2 then
					buildMechanicRepairBay(origin + Vector3.new(-44, 0, 0), 90)
					buildGasStation(origin + Vector3.new(44, 0, 0))
				end
			elseif bx == GRID_RADIUS or bx == -GRID_RADIUS then
				-- East & West Waterfronts: Maritime Port Terminals, Wooden Piers & Docked 3D Boats (zero empty slabs!)
				buildHarborPortAndBoats(origin, bx == GRID_RADIUS, bz)
			elseif bx == 2 and bz == 2 then
				buildMidRiseCommercialBlock(origin, bx * 5 + bz * 11)
				buildSpeedShop(origin + Vector3.new(0, 0, -32), 180)
			elseif bx == -2 and bz == 2 then
				buildSuburbanParkBlock(origin)
				buildMonumentArch(origin + Vector3.new(0, 0.36, 0), 45)
				buildGasStation(origin + Vector3.new(32, 0, -34))
			elseif bx == -3 and bz == -3 then
				-- Hudson Cargo Terminal + Backdrop Towers so no block is ever a flat empty slab!
				buildMidRiseCommercialBlock(origin, bx * 5 + bz * 11)
				buildIndustrialYardBlock(origin + Vector3.new(0, 0.3, 0), bx * 7 + bz * 13)
			elseif bx <= -1 and bz >= 1 then
				-- Snowy Christmas Central Park (expanded across the Southwest sector facing Central Park South & 5th Ave!)
				buildSuburbanParkBlock(origin)
			elseif math.abs(bx) <= 1 and math.abs(bz) <= 1 then
				-- Dense 4-Tower Downtown Manhattan Skyscraper Core (165 to 285 studs tall)
				local isEastCrown = (bx == 1 and bz == -1)
				local baseH = if isEastCrown then 235 else 175
				buildSkyscraper(origin + Vector3.new(-34, 0.3, -34), 36, 36, baseH + 45, Color3.fromRGB(58, 68, 86), "DowntownTowerNW", false)
				buildSkyscraper(origin + Vector3.new(34, 0.3, -34), 36, 36, baseH + 15, Color3.fromRGB(74, 82, 96), "DowntownTowerNE", false)
				buildSkyscraper(origin + Vector3.new(-34, 0.3, 34), 36, 36, baseH, Color3.fromRGB(86, 78, 72), "DowntownTowerSW", false)
				buildSkyscraper(origin + Vector3.new(34, 0.3, 34), 36, 36, baseH + 30, Color3.fromRGB(64, 72, 84), "DowntownTowerSE", false)
				if isEastCrown then
					buildConcertStage(origin + Vector3.new(0, 0.3, -12), 180)
				end

				spawnSnowyChristmasTree(origin + Vector3.new(-58, 0.3, 0))
				spawnSnowyChristmasTree(origin + Vector3.new(58, 0.3, 0))
				spawnBusStop(origin + Vector3.new(-edge + 2, 0.3, 0), 90)
				spawnCrateCluster(origin + Vector3.new(0, 0.3, -54), 3)
				spawnJackpotCrate(origin + Vector3.new(0, 0.3, -16))
				spawnGoldATM(origin + Vector3.new(-16, 0.3, 0), 0)
				spawnArmoredCashTruck(origin + Vector3.new(0, 0.3, 52), 90)
				spawnFoodVendorCart(origin + Vector3.new(-54, 0.3, 24), 0, bx + bz)
				spawnMegaCorpSurveillanceTower(origin + Vector3.new(54, 0.3, -54), 180)
				spawnBillboard(origin + Vector3.new(-54, 0.3, 54), 0, "FIFTH AVENUE HOLIDAYS", Color3.fromRGB(245, 205, 95))
			else
				-- Dense 4-Tower Manhattan Midtown / West-Side Skyscraper & Holiday Storefront Blocks
				buildMidRiseCommercialBlock(origin, bx * 5 + bz * 11)
			end
		end
	end
end

buildLeoCity()
Workspace:SetAttribute("LeoCityReady", true)
print(string.format("[WorldBuilderService] Leo City built with %d destructible props!", #CollectionService:GetTagged("Destructible")))
