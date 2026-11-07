--!strict
--[[
	VehicleCatalog.luau
	Shared definition & procedural 3D model builder for all 8 playable & traffic vehicle archetypes
	in World of Destruction (Leo City).

	Archetypes:
	  1. Compact      - Starter nimble hatchback ("TURBO POCKET")
	  2. Sedan        - Balanced city cruiser ("CRUISER V8")
	  3. Muscle       - High-torque drift machine with blower hood ("HELLFIRE GT")
	  4. SUV          - Heavy off-road rammer ("TITAN 4x4")
	  5. Pickup       - Utility truck with open bed ("RANCH RAMMER")
	  6. Sports       - Superfast aerodynamic coupe with spoiler & neon accents ("APEX GT")
	  7. MonsterTruck - Massive tires, high suspension, crushes smaller objects ("CRUSHER XL")
	  8. Bulldozer    - Ultimate destruction vehicle with heavy front blade ("GOLIATH DOZER" / ArmoredTank)
]]

local CollectionService = game:GetService("CollectionService")

export type VehicleArchetypeConfig = {
	Id: string,
	DisplayName: string,
	Tagline: string,
	Category: string,
	UnlockCost: number,
	CoinReward: number,
	SpawnWeight: number,

	-- Core performance & physics attributes
	MaxHealth: number,
	Mass: number,
	MaxSpeed: number,        -- studs/sec forward top speed
	ReverseSpeed: number,    -- studs/sec reverse top speed
	Acceleration: number,    -- studs/sec^2
	BrakeDecel: number,      -- studs/sec^2
	TurnSpeed: number,       -- rad/sec base steering authority
	DriftFactor: number,     -- lateral slip & drift boost multiplier
	RamMultiplier: number,   -- destruction damage multiplier on impact
	NitroCapacity: number,   -- seconds of full nitro burn
	HoverHeight: number,     -- chassis height above ground

	-- Dimensions (studs)
	Size: Vector3,           -- Chassis bounding size (Width, Height, Length)
	WheelRadius: number,
	WheelWidth: number,
	WheelbaseOffsetZ: number,
	TrackOffsetX: number,

	-- Default styling
	PrimaryColor: Color3,
	SecondaryColor: Color3,
	AccentColor: Color3,
	HasBlower: boolean?,
	HasSpoiler: boolean?,
	HasNeonAccents: boolean?,
	HasTruckBed: boolean?,
	HasRoofRails: boolean?,
	HasMonsterSuspension: boolean?,
	HasBulldozerBlade: boolean?,
}

export type BuildOptions = {
	PrimaryColor: Color3?,
	SecondaryColor: Color3?,
	AccentColor: Color3?,
	OwnerUserId: number?,
	IsTraffic: boolean?,
	EngineLevel: number?,
	ArmorLevel: number?,
	NitroLevel: number?,
	PlowLevel: number?,
	BulkScale: number?,
	HasRamPlow: boolean?,
	CFrame: CFrame?,
}

local VehicleCatalog = {}

-- Ordered list of canonical archetype IDs
VehicleCatalog.OrderedIds = {
	"Compact",
	"Sedan",
	"Muscle",
	"SUV",
	"Pickup",
	"Sports",
	"MonsterTruck",
	"Bulldozer",
}

-- Color palettes for player & traffic vehicles
VehicleCatalog.PlayerPalette = {
	CrimsonRed = Color3.fromRGB(220, 32, 32),
	ElectricBlue = Color3.fromRGB(28, 120, 245),
	SolarOrange = Color3.fromRGB(250, 125, 20),
	ToxicGreen = Color3.fromRGB(50, 225, 85),
	CyberPurple = Color3.fromRGB(150, 45, 240),
	GoldRush = Color3.fromRGB(245, 195, 35),
	StealthBlack = Color3.fromRGB(26, 29, 36),
	PearlWhite = Color3.fromRGB(238, 242, 248),
}

VehicleCatalog.TrafficPalette = {
	Color3.fromRGB(28, 33, 41),   -- Obsidian Black
	Color3.fromRGB(48, 54, 66),   -- Shadow Charcoal
	Color3.fromRGB(72, 78, 92),   -- Dark Gunmetal
	Color3.fromRGB(115, 122, 134),-- Smoked Pewter
	Color3.fromRGB(32, 52, 96),   -- Midnight Blue
	Color3.fromRGB(110, 32, 38),  -- Dark Oxblood
	Color3.fromRGB(38, 66, 56),   -- Dark Pine
	Color3.fromRGB(210, 215, 222),-- City Silver
	Color3.fromRGB(195, 150, 42), -- Taxi Ochre
}

VehicleCatalog.Archetypes = {
	Compact = {
		Id = "Compact",
		DisplayName = "TURBO POCKET",
		Tagline = "Nimble starter hatchback + drift pro",
		Category = "Starter",
		UnlockCost = 0,
		CoinReward = 16,
		SpawnWeight = 5,

		MaxHealth = 100,
		Mass = 950,
		MaxSpeed = 58,
		ReverseSpeed = 26,
		Acceleration = 26,
		BrakeDecel = 95,
		TurnSpeed = 2.5,
		DriftFactor = 1.35,
		RamMultiplier = 0.95,
		NitroCapacity = 4.0,
		HoverHeight = 2.0,

		Size = Vector3.new(6.2, 2.2, 12.6),
		WheelRadius = 1.4,
		WheelWidth = 0.95,
		WheelbaseOffsetZ = 4.0,
		TrackOffsetX = 3.15,

		PrimaryColor = Color3.fromRGB(225, 42, 42),
		SecondaryColor = Color3.fromRGB(30, 34, 42),
		AccentColor = Color3.fromRGB(255, 195, 45),
	},

	Sedan = {
		Id = "Sedan",
		DisplayName = "CRUISER V8",
		Tagline = "Balanced city cruiser all-rounder",
		Category = "Street",
		UnlockCost = 250,
		CoinReward = 18,
		SpawnWeight = 6,

		MaxHealth = 125,
		Mass = 1150,
		MaxSpeed = 64,
		ReverseSpeed = 28,
		Acceleration = 28,
		BrakeDecel = 95,
		TurnSpeed = 2.4,
		DriftFactor = 1.20,
		RamMultiplier = 1.08,
		NitroCapacity = 4.2,
		HoverHeight = 2.1,

		Size = Vector3.new(6.6, 2.2, 14.8),
		WheelRadius = 1.45,
		WheelWidth = 1.0,
		WheelbaseOffsetZ = 4.8,
		TrackOffsetX = 3.35,

		PrimaryColor = Color3.fromRGB(36, 118, 235),
		SecondaryColor = Color3.fromRGB(24, 28, 36),
		AccentColor = Color3.fromRGB(220, 230, 245),
	},

	Muscle = {
		Id = "Muscle",
		DisplayName = "HELLFIRE GT",
		Tagline = "High-torque drift machine with supercharger blower",
		Category = "Muscle",
		UnlockCost = 650,
		CoinReward = 24,
		SpawnWeight = 3,

		MaxHealth = 140,
		Mass = 1350,
		MaxSpeed = 72,
		ReverseSpeed = 28,
		Acceleration = 32,
		BrakeDecel = 98,
		TurnSpeed = 2.35,
		DriftFactor = 1.55,
		RamMultiplier = 1.25,
		NitroCapacity = 4.8,
		HoverHeight = 2.1,

		Size = Vector3.new(7.0, 2.2, 15.4),
		WheelRadius = 1.5,
		WheelWidth = 1.15,
		WheelbaseOffsetZ = 5.0,
		TrackOffsetX = 3.55,

		PrimaryColor = Color3.fromRGB(245, 110, 20),
		SecondaryColor = Color3.fromRGB(20, 22, 26),
		AccentColor = Color3.fromRGB(235, 235, 240),
		HasBlower = true,
		HasSpoiler = true,
	},

	SUV = {
		Id = "SUV",
		DisplayName = "TITAN 4x4",
		Tagline = "Heavy off-road armor + strong impact",
		Category = "Heavy",
		UnlockCost = 900,
		CoinReward = 24,
		SpawnWeight = 4,

		MaxHealth = 175,
		Mass = 1650,
		MaxSpeed = 62,
		ReverseSpeed = 26,
		Acceleration = 27,
		BrakeDecel = 92,
		TurnSpeed = 2.2,
		DriftFactor = 1.10,
		RamMultiplier = 1.40,
		NitroCapacity = 4.5,
		HoverHeight = 2.5,

		Size = Vector3.new(7.2, 2.8, 16.0),
		WheelRadius = 1.7,
		WheelWidth = 1.2,
		WheelbaseOffsetZ = 5.2,
		TrackOffsetX = 3.65,

		PrimaryColor = Color3.fromRGB(42, 85, 68),
		SecondaryColor = Color3.fromRGB(26, 30, 34),
		AccentColor = Color3.fromRGB(200, 208, 215),
		HasRoofRails = true,
	},

	Pickup = {
		Id = "Pickup",
		DisplayName = "RANCH RAMMER",
		Tagline = "High-torque utility ramming truck",
		Category = "Heavy",
		UnlockCost = 1200,
		CoinReward = 26,
		SpawnWeight = 4,

		MaxHealth = 185,
		Mass = 1750,
		MaxSpeed = 64,
		ReverseSpeed = 26,
		Acceleration = 28,
		BrakeDecel = 94,
		TurnSpeed = 2.2,
		DriftFactor = 1.18,
		RamMultiplier = 1.50,
		NitroCapacity = 4.6,
		HoverHeight = 2.55,

		Size = Vector3.new(7.2, 2.6, 17.2),
		WheelRadius = 1.72,
		WheelWidth = 1.22,
		WheelbaseOffsetZ = 5.6,
		TrackOffsetX = 3.65,

		PrimaryColor = Color3.fromRGB(185, 38, 42),
		SecondaryColor = Color3.fromRGB(32, 35, 42),
		AccentColor = Color3.fromRGB(235, 190, 50),
		HasTruckBed = true,
	},

	Sports = {
		Id = "Sports",
		DisplayName = "APEX GT",
		Tagline = "Superfast aerodynamic coupe with neon accents",
		Category = "Super",
		UnlockCost = 2000,
		CoinReward = 32,
		SpawnWeight = 2,

		MaxHealth = 130,
		Mass = 1100,
		MaxSpeed = 82,
		ReverseSpeed = 30,
		Acceleration = 36,
		BrakeDecel = 110,
		TurnSpeed = 2.6,
		DriftFactor = 1.42,
		RamMultiplier = 1.15,
		NitroCapacity = 5.5,
		HoverHeight = 1.85,

		Size = Vector3.new(7.0, 1.9, 15.2),
		WheelRadius = 1.45,
		WheelWidth = 1.15,
		WheelbaseOffsetZ = 4.9,
		TrackOffsetX = 3.55,

		PrimaryColor = Color3.fromRGB(22, 25, 34),
		SecondaryColor = Color3.fromRGB(15, 17, 22),
		AccentColor = Color3.fromRGB(0, 235, 255),
		HasSpoiler = true,
		HasNeonAccents = true,
	},

	MonsterTruck = {
		Id = "MonsterTruck",
		DisplayName = "CRUSHER XL",
		Tagline = "Massive tires, high suspension, crushes obstacles",
		Category = "Demolition",
		UnlockCost = 3500,
		CoinReward = 42,
		SpawnWeight = 1,

		MaxHealth = 250,
		Mass = 2600,
		MaxSpeed = 60,
		ReverseSpeed = 26,
		Acceleration = 29,
		BrakeDecel = 92,
		TurnSpeed = 2.1,
		DriftFactor = 1.15,
		RamMultiplier = 2.10,
		NitroCapacity = 5.2,
		HoverHeight = 4.2,

		Size = Vector3.new(8.2, 2.8, 16.8),
		WheelRadius = 2.85,
		WheelWidth = 2.1,
		WheelbaseOffsetZ = 5.4,
		TrackOffsetX = 4.5,

		PrimaryColor = Color3.fromRGB(130, 35, 225),
		SecondaryColor = Color3.fromRGB(28, 30, 38),
		AccentColor = Color3.fromRGB(65, 255, 110),
		HasTruckBed = true,
		HasMonsterSuspension = true,
	},

	Bulldozer = {
		Id = "Bulldozer",
		DisplayName = "GOLIATH DOZER",
		Tagline = "Ultimate armored destruction vehicle with heavy front plow",
		Category = "Demolition",
		UnlockCost = 5500,
		CoinReward = 60,
		SpawnWeight = 1,

		MaxHealth = 380,
		Mass = 4200,
		MaxSpeed = 50,
		ReverseSpeed = 22,
		Acceleration = 24,
		BrakeDecel = 105,
		TurnSpeed = 1.95,
		DriftFactor = 0.95,
		RamMultiplier = 3.00,
		NitroCapacity = 5.0,
		HoverHeight = 2.9,

		Size = Vector3.new(8.8, 3.4, 17.6),
		WheelRadius = 2.1,
		WheelWidth = 1.65,
		WheelbaseOffsetZ = 5.6,
		TrackOffsetX = 4.4,

		PrimaryColor = Color3.fromRGB(235, 175, 25),
		SecondaryColor = Color3.fromRGB(32, 34, 38),
		AccentColor = Color3.fromRGB(255, 85, 20),
		HasBulldozerBlade = true,
	},
}

-- Alias support so `ArmoredTank`, `Hatchback`, `BoxTruck`, etc. resolve cleanly
local ALIAS_MAP: { [string]: string } = {
	compact = "Compact",
	hatchback = "Compact",
	sedan = "Sedan",
	muscle = "Muscle",
	suv = "SUV",
	pickup = "Pickup",
	sports = "Sports",
	monstertruck = "MonsterTruck",
	monster = "MonsterTruck",
	bulldozer = "Bulldozer",
	armoredtank = "Bulldozer",
	tank = "Bulldozer",
	boxtruck = "Bulldozer",
	van = "SUV",
}

-- Also expose ArmoredTank and Tank directly in Archetypes table for direct indexing
VehicleCatalog.Archetypes.ArmoredTank = VehicleCatalog.Archetypes.Bulldozer
VehicleCatalog.Archetypes.Tank = VehicleCatalog.Archetypes.Bulldozer
VehicleCatalog.Vehicles = VehicleCatalog.Archetypes

function VehicleCatalog.ResolveArchetypeId(vehicleType: string?): string
	if not vehicleType or vehicleType == "" then
		return "Compact"
	end
	if VehicleCatalog.Archetypes[vehicleType] then
		return VehicleCatalog.Archetypes[vehicleType].Id
	end
	local lowered = string.lower(vehicleType)
	if ALIAS_MAP[lowered] then
		return ALIAS_MAP[lowered]
	end
	return "Compact"
end

function VehicleCatalog.GetConfig(vehicleType: string?): VehicleArchetypeConfig
	local resolved = VehicleCatalog.ResolveArchetypeId(vehicleType)
	return VehicleCatalog.Archetypes[resolved] or VehicleCatalog.Archetypes.Compact
end

function VehicleCatalog.GetRandomTrafficArchetype(rng: Random?): string
	local r = rng or Random.new()
	local totalWeight = 0
	for _, id in ipairs(VehicleCatalog.OrderedIds) do
		local cfg = VehicleCatalog.Archetypes[id]
		-- Keep MonsterTruck & Bulldozer rare in regular traffic
		totalWeight += cfg.SpawnWeight
	end
	local pick = r:NextInteger(1, totalWeight)
	for _, id in ipairs(VehicleCatalog.OrderedIds) do
		local cfg = VehicleCatalog.Archetypes[id]
		if pick <= cfg.SpawnWeight then
			return id
		end
		pick -= cfg.SpawnWeight
	end
	return "Sedan"
end

function VehicleCatalog.GetRandomTrafficColor(rng: Random?): Color3
	local r = rng or Random.new()
	local palette = VehicleCatalog.TrafficPalette
	return palette[r:NextInteger(1, #palette)]
end

-- Internal helper: create a base Part with zero velocity & smooth surfaces
local function makePart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	canCollide: boolean?,
	massless: boolean?,
	transparency: number?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = if canCollide ~= nil then canCollide else false
	p.Massless = if massless ~= nil then massless else true
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function makeWedge(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	transparency: number?
): WedgePart
	local wp = Instance.new("WedgePart")
	wp.Name = name
	wp.Size = size
	wp.Color = color
	wp.Material = material
	wp.TopSurface = Enum.SurfaceType.Smooth
	wp.BottomSurface = Enum.SurfaceType.Smooth
	wp.CanCollide = false
	wp.Massless = true
	wp.Transparency = transparency or 0
	wp.Parent = parent
	return wp
end

local function weldParts(part0: BasePart, part1: BasePart, c0: CFrame?, c1: CFrame?): Weld
	local w = Instance.new("Weld")
	w.Name = part1.Name .. "_Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0 or part0.CFrame:ToObjectSpace(part1.CFrame)
	w.C1 = c1 or CFrame.identity
	w.Parent = part1
	return w
end

local function placeAndWeld(chassis: BasePart, part: BasePart, offsetCFrame: CFrame): Weld
	part.CFrame = chassis.CFrame * offsetCFrame
	part:SetAttribute("BaseC0", offsetCFrame)
	return weldParts(chassis, part, offsetCFrame, CFrame.identity)
end

-- Builds or upgrades the front Ramming Plow / Dozer Blade on a vehicle model
function VehicleCatalog.AttachRamPlow(model: Model, plowLevel: number, accentColor: Color3?)
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end

	-- Remove any existing plow first
	local existing = model:FindFirstChild("RamPlow")
	if existing then
		existing:Destroy()
	end

	if plowLevel <= 0 then
		model:SetAttribute("PlowLevel", 0)
		return
	end

	model:SetAttribute("PlowLevel", plowLevel)

	local plowModel = Instance.new("Model")
	plowModel.Name = "RamPlow"
	plowModel.Parent = model

	local size = chassis.Size
	local w = size.X * (1.08 + math.min(plowLevel, 5) * 0.04)
	local h = math.clamp(size.Y * 0.85, 2.0, 3.6)
	local frontZ = -(size.Z * 0.5) - 0.85

	local bladeColor = accentColor or Color3.fromRGB(235, 175, 25)
	local steelColor = Color3.fromRGB(45, 48, 55)

	-- Main heavy curved plow blade (lower angled scoop + upper deflector)
	local mainBlade = makePart(
		"PlowBlade",
		Vector3.new(w, h * 0.68, 0.75),
		steelColor,
		Enum.Material.DiamondPlate,
		plowModel,
		false,
		true
	)
	placeAndWeld(chassis, mainBlade, CFrame.new(0, -size.Y * 0.12, frontZ) * CFrame.Angles(math.rad(14), 0, 0))

	local lowerScoop = makePart(
		"PlowScoop",
		Vector3.new(w * 1.02, h * 0.42, 0.85),
		bladeColor,
		Enum.Material.Metal,
		plowModel,
		false,
		true
	)
	placeAndWeld(chassis, lowerScoop, CFrame.new(0, -size.Y * 0.42, frontZ - 0.45) * CFrame.Angles(math.rad(-28), 0, 0))

	-- Side cheek plates to funnel debris outward
	for _, sx in ipairs({ -1, 1 }) do
		local cheek = makePart(
			"PlowCheek",
			Vector3.new(0.45, h * 0.75, 1.8),
			bladeColor,
			Enum.Material.Metal,
			plowModel,
			false,
			true
		)
		placeAndWeld(
			chassis,
			cheek,
			CFrame.new(sx * (w * 0.5 - 0.15), -size.Y * 0.15, frontZ + 0.1) * CFrame.Angles(0, math.rad(-sx * 18), 0)
		)

		-- Support push-beams connecting chassis frame to blade
		local strut = makePart(
			"PlowStrut",
			Vector3.new(0.55, 0.55, 2.2),
			steelColor,
			Enum.Material.Metal,
			plowModel,
			false,
			true
		)
		placeAndWeld(chassis, strut, CFrame.new(sx * (size.X * 0.32), -size.Y * 0.2, frontZ + 0.8))
	end

	-- Hazard teeth along the bottom edge for higher levels
	local numTeeth = math.clamp(3 + plowLevel, 4, 8)
	for i = 1, numTeeth do
		local frac = (i - 0.5) / numTeeth - 0.5
		local tooth = makePart(
			"PlowTooth",
			Vector3.new((w / numTeeth) * 0.55, 0.45, 0.9),
			Color3.fromRGB(240, 240, 245),
			Enum.Material.Metal,
			plowModel,
			false,
			true
		)
		placeAndWeld(
			chassis,
			tooth,
			CFrame.new(frac * (w * 0.88), -size.Y * 0.54, frontZ - 0.75) * CFrame.Angles(math.rad(-20), 0, 0)
		)
	end
end

-- Attaches or updates all 5 3D visual upgrade tracks (Engine, Armor, Nitro, Plow, Magnet) on a vehicle Model
function VehicleCatalog.AttachVisualUpgrades(
	model: Model,
	upgrades: {
		Engine: number?,
		Armor: number?,
		Nitro: number?,
		Plow: number?,
		Magnet: number?,
		AccentColor: Color3?,
	}?
)
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end

	local upg = upgrades or {}
	local engineLvl = math.clamp(tonumber(upg.Engine or model:GetAttribute("EngineLevel")) or 0, 0, 5)
	local armorLvl = math.clamp(tonumber(upg.Armor or model:GetAttribute("ArmorLevel")) or 0, 0, 5)
	local nitroLvl = math.clamp(tonumber(upg.Nitro or model:GetAttribute("NitroLevel")) or 0, 0, 5)
	local plowLvl = math.clamp(tonumber(upg.Plow or model:GetAttribute("PlowLevel")) or 0, 0, 5)
	local magnetLvl = math.clamp(tonumber(upg.Magnet or model:GetAttribute("MagnetLevel")) or 0, 0, 5)

	local oldContainer = model:FindFirstChild("VisualUpgradesContainer")
	if oldContainer then
		oldContainer:Destroy()
	end

	local container = Instance.new("Model")
	container.Name = "VisualUpgradesContainer"
	container.Parent = model

	local size = chassis.Size
	local w = size.X
	local h = size.Y
	local len = size.Z
	local accentColor = upg.AccentColor or Color3.fromRGB(255, 195, 45)

	-- 1. ENGINE TRACK (Twin-Turbo Supercharger Scoop & Chrome Intake Manifold on Hood)
	if engineLvl >= 1 then
		local boostScale = 0.85 + engineLvl * 0.08
		local blowerBase = makePart(
			"EngineSuperchargerBlock",
			Vector3.new(w * 0.34 * boostScale, h * 0.28 * boostScale, len * 0.16),
			Color3.fromRGB(195, 204, 218),
			Enum.Material.Metal,
			container,
			false,
			true
		)
		placeAndWeld(chassis, blowerBase, CFrame.new(0, h * 0.58, -len * 0.24))

		local intakeScoop = makePart(
			"EngineIntakeScoop",
			Vector3.new(w * 0.38 * boostScale, h * 0.16 * boostScale, len * 0.14),
			Color3.fromRGB(255, 115, 35),
			Enum.Material.Neon,
			container,
			false,
			true
		)
		placeAndWeld(chassis, intakeScoop, CFrame.new(0, h * 0.74, -len * 0.26))
	end

	-- 2. ARMOR TRACK (Heavy Steel Exo-Rollcage & Side Impact Bull-Bars)
	local roofTopY = h * 0.5 + h * 0.62
	if armorLvl >= 1 then
		local armorColor = if armorLvl >= 4 then Color3.fromRGB(235, 190, 50) else Color3.fromRGB(95, 108, 128)
		for _, sx in ipairs({ -1, 1 }) do
			local sidePlate = makePart(
				"ArmorSideBar_" .. tostring(sx),
				Vector3.new(0.38, h * 0.45, len * 0.58),
				armorColor,
				Enum.Material.DiamondPlate,
				container,
				false,
				true
			)
			placeAndWeld(chassis, sidePlate, CFrame.new(sx * (w * 0.52), 0.1, 0))

			local roofRail = makePart(
				"ArmorRoofCage_" .. tostring(sx),
				Vector3.new(0.24, 0.24, len * 0.34),
				armorColor,
				Enum.Material.Metal,
				container,
				false,
				true
			)
			placeAndWeld(chassis, roofRail, CFrame.new(sx * (w * 0.34), roofTopY + 0.14, 0.0))
		end
	end

	-- 3. NITRO TRACK (Dual Glowing Liquid-Nitrous Bottles Mounted on Rear Deck)
	if nitroLvl >= 1 then
		for _, sx in ipairs({ -1, 1 }) do
			local bottle = makePart(
				"NitroBottle_" .. tostring(sx),
				Vector3.new(2.2, 0.85, 0.85),
				Color3.fromRGB(35, 165, 255),
				Enum.Material.Metal,
				container,
				false,
				true,
				0,
				Enum.PartType.Cylinder
			)
			placeAndWeld(
				chassis,
				bottle,
				CFrame.new(sx * (w * 0.24), h * 0.66, len * 0.32) * CFrame.Angles(0, math.rad(90), math.rad(12))
			)

			local glowBand = makePart(
				"NitroGlowBand_" .. tostring(sx),
				Vector3.new(0.55, 0.92, 0.92),
				Color3.fromRGB(95, 230, 255),
				Enum.Material.Neon,
				container,
				false,
				true,
				0,
				Enum.PartType.Cylinder
			)
			placeAndWeld(
				chassis,
				glowBand,
				CFrame.new(sx * (w * 0.24), h * 0.66, len * 0.32) * CFrame.Angles(0, math.rad(90), math.rad(12))
			)
		end
	end

	-- 4. PLOW TRACK (Heavy Demolition Wedge Ram Plow on Front Bumper)
	VehicleCatalog.AttachRamPlow(model, plowLvl, accentColor)

	-- 5. MAGNET TRACK (Golden Electromagnetic Cash-Attractor Coil & Halo on Roof)
	if magnetLvl >= 1 then
		local magPedestal = makePart(
			"MagnetPedestal",
			Vector3.new(0.85, 0.36, 0.85),
			Color3.fromRGB(45, 52, 65),
			Enum.Material.Metal,
			container,
			false,
			true
		)
		placeAndWeld(chassis, magPedestal, CFrame.new(0, roofTopY + 0.18, 0.2))

		local magHalo = makePart(
			"MagnetGoldCoil",
			Vector3.new(0.26, 1.85, 1.85),
			Color3.fromRGB(255, 215, 40),
			Enum.Material.Neon,
			container,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		placeAndWeld(chassis, magHalo, CFrame.new(0, roofTopY + 0.38, 0.2) * CFrame.Angles(0, 0, math.rad(90)))
	end
end

-- Builds a standalone 3D preview model for any of the 5 upgrade tracks (Engine, Armor, Nitro, Plow, Magnet)
-- or a full upgraded vehicle preview if passed a vehicle archetype + upgrades table.
function VehicleCatalog.BuildUpgradePreviewModel(
	trackOrVehicle: string?,
	levelOrOptions: any,
	accentColorOpt: Color3?
): Model
	if type(levelOrOptions) == "table" then
		return VehicleCatalog.BuildVehicle(trackOrVehicle, levelOrOptions)
	end

	local track = tostring(trackOrVehicle or "Engine")
	local lowered = string.lower(track)
	local level = math.clamp(tonumber(levelOrOptions) or 1, 1, 5)
	local accent = accentColorOpt or Color3.fromRGB(255, 195, 45)

	local model = Instance.new("Model")
	model.Name = "UpgradePreview_" .. track

	local root = makePart(
		"PreviewRoot",
		Vector3.new(3.2, 0.35, 3.2),
		Color3.fromRGB(28, 32, 42),
		Enum.Material.Metal,
		model,
		false,
		true
	)
	root.Anchored = true
	root.CFrame = CFrame.identity
	model.PrimaryPart = root

	local function addPreviewPart(
		name: string,
		size: Vector3,
		color: Color3,
		mat: Enum.Material,
		offset: CFrame,
		shape: Enum.PartType?
	): Part
		local p = makePart(name, size, color, mat, model, false, true, 0, shape)
		p.Anchored = true
		p.CFrame = root.CFrame * offset
		return p
	end

	if lowered == "engine" then
		addPreviewPart(
			"EngineBlock",
			Vector3.new(2.2, 1.2, 2.6),
			Color3.fromRGB(185, 195, 210),
			Enum.Material.Metal,
			CFrame.new(0, 0.75, 0)
		)
		addPreviewPart(
			"SuperchargerBlower",
			Vector3.new(1.6, 0.65, 1.8),
			Color3.fromRGB(220, 226, 236),
			Enum.Material.Metal,
			CFrame.new(0, 1.65, 0)
		)
		addPreviewPart(
			"TurboIntakeGlow",
			Vector3.new(1.4, 0.32, 0.35),
			Color3.fromRGB(255, 110, 30),
			Enum.Material.Neon,
			CFrame.new(0, 1.68, -0.82)
		)
	elseif lowered == "armor" then
		local armorColor = if level >= 4 then Color3.fromRGB(235, 190, 50) else Color3.fromRGB(95, 108, 128)
		addPreviewPart(
			"ArmorCenterShield",
			Vector3.new(2.8, 1.5, 0.45),
			armorColor,
			Enum.Material.DiamondPlate,
			CFrame.new(0, 0.95, 0)
		)
		for _, sx in ipairs({ -1, 1 }) do
			addPreviewPart(
				"ArmorBullBar_" .. tostring(sx),
				Vector3.new(0.35, 1.7, 2.2),
				armorColor,
				Enum.Material.Metal,
				CFrame.new(sx * 1.35, 1.0, 0)
			)
		end
	elseif lowered == "nitro" then
		for _, sx in ipairs({ -1, 1 }) do
			addPreviewPart(
				"NitroCylinder_" .. tostring(sx),
				Vector3.new(2.6, 0.95, 0.95),
				Color3.fromRGB(35, 165, 255),
				Enum.Material.Metal,
				CFrame.new(sx * 0.72, 0.85, 0) * CFrame.Angles(0, math.rad(90), math.rad(14)),
				Enum.PartType.Cylinder
			)
			addPreviewPart(
				"NitroBand_" .. tostring(sx),
				Vector3.new(0.6, 1.02, 1.02),
				Color3.fromRGB(95, 235, 255),
				Enum.Material.Neon,
				CFrame.new(sx * 0.72, 0.85, 0) * CFrame.Angles(0, math.rad(90), math.rad(14)),
				Enum.PartType.Cylinder
			)
		end
	elseif lowered == "plow" then
		addPreviewPart(
			"PlowMainBlade",
			Vector3.new(3.4, 1.4, 0.65),
			Color3.fromRGB(48, 52, 60),
			Enum.Material.DiamondPlate,
			CFrame.new(0, 0.95, -0.2) * CFrame.Angles(math.rad(14), 0, 0)
		)
		addPreviewPart(
			"PlowLowerScoop",
			Vector3.new(3.5, 0.75, 0.75),
			accent,
			Enum.Material.Metal,
			CFrame.new(0, 0.45, -0.55) * CFrame.Angles(math.rad(-26), 0, 0)
		)
	elseif lowered == "magnet" then
		addPreviewPart(
			"MagnetBasePedestal",
			Vector3.new(1.2, 0.55, 1.2),
			Color3.fromRGB(45, 52, 65),
			Enum.Material.Metal,
			CFrame.new(0, 0.45, 0)
		)
		addPreviewPart(
			"MagnetGoldenCoil",
			Vector3.new(0.38, 2.3, 2.3),
			Color3.fromRGB(255, 215, 40),
			Enum.Material.Neon,
			CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Enum.PartType.Cylinder
		)
	end

	return model
end

-- Creates particle emitters used for Nitro, Drift Tire Smoke, and Low-Health Engine Damage
local function attachVehicleVFX(model: Model, chassis: BasePart, cfg: VehicleArchetypeConfig)
	local halfL = cfg.Size.Z * 0.5
	local halfW = cfg.Size.X * 0.5

	-- Engine bay attachment (front hood) for smoke & fire when damaged
	local engineAttachment = Instance.new("Attachment")
	engineAttachment.Name = "EngineVFXAttachment"
	engineAttachment.Position = Vector3.new(0, cfg.Size.Y * 0.45, -halfL * 0.65)
	engineAttachment.Parent = chassis

	local damageSmoke = Instance.new("ParticleEmitter")
	damageSmoke.Name = "DamageSmoke"
	damageSmoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 90, 95)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 35)),
	})
	damageSmoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	damageSmoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	damageSmoke.Lifetime = NumberRange.new(1.0, 1.8)
	damageSmoke.Rate = 28
	damageSmoke.Speed = NumberRange.new(4, 9)
	damageSmoke.SpreadAngle = Vector2.new(25, 25)
	damageSmoke.Enabled = false
	damageSmoke.Parent = engineAttachment

	local damageFire = Instance.new("ParticleEmitter")
	damageFire.Name = "DamageFire"
	damageFire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 95, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 20, 10)),
	})
	damageFire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	damageFire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	damageFire.LightEmission = 1
	damageFire.Lifetime = NumberRange.new(0.3, 0.6)
	damageFire.Rate = 35
	damageFire.Speed = NumberRange.new(5, 10)
	damageFire.SpreadAngle = Vector2.new(18, 18)
	damageFire.Enabled = false
	damageFire.Parent = engineAttachment

	-- Dual rear exhaust attachments for Nitro flames & exhaust puffs
	for _, sx in ipairs({ -1, 1 }) do
		local exhaustAtt = Instance.new("Attachment")
		exhaustAtt.Name = if sx < 0 then "ExhaustAttachmentL" else "ExhaustAttachmentR"
		exhaustAtt.Position = Vector3.new(sx * (halfW * 0.52), -cfg.Size.Y * 0.28, halfL + 0.3)
		exhaustAtt.Parent = chassis

		local nitroFlame = Instance.new("ParticleEmitter")
		nitroFlame.Name = "NitroFlame"
		nitroFlame.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 220, 255)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(40, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 20)),
		})
		nitroFlame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.95),
			NumberSequenceKeypoint.new(0.5, 1.35),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		nitroFlame.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		nitroFlame.LightEmission = 1
		nitroFlame.Lifetime = NumberRange.new(0.12, 0.24)
		nitroFlame.Rate = 65
		nitroFlame.Speed = NumberRange.new(22, 36)
		nitroFlame.EmissionDirection = Enum.NormalId.Back
		nitroFlame.SpreadAngle = Vector2.new(8, 8)
		nitroFlame.Enabled = false
		nitroFlame.Parent = exhaustAtt
	end

	-- Rear tire drift smoke & skid trail attachments
	for _, sx in ipairs({ -1, 1 }) do
		local tireAtt = Instance.new("Attachment")
		tireAtt.Name = if sx < 0 then "DriftAttachmentL" else "DriftAttachmentR"
		tireAtt.Position = Vector3.new(sx * cfg.TrackOffsetX, -cfg.HoverHeight + 0.25, cfg.WheelbaseOffsetZ)
		tireAtt.Parent = chassis

		local trailAtt0 = Instance.new("Attachment")
		trailAtt0.Name = if sx < 0 then "SkidAttL0" else "SkidAttR0"
		trailAtt0.Position = Vector3.new(sx * cfg.TrackOffsetX - 0.35, -cfg.HoverHeight + 0.12, cfg.WheelbaseOffsetZ)
		trailAtt0.Parent = chassis

		local trailAtt1 = Instance.new("Attachment")
		trailAtt1.Name = if sx < 0 then "SkidAttL1" else "SkidAttR1"
		trailAtt1.Position = Vector3.new(sx * cfg.TrackOffsetX + 0.35, -cfg.HoverHeight + 0.12, cfg.WheelbaseOffsetZ)
		trailAtt1.Parent = chassis

		local skidTrail = Instance.new("Trail")
		skidTrail.Name = if sx < 0 then "SkidTrailL" else "SkidTrailR"
		skidTrail.Attachment0 = trailAtt0
		skidTrail.Attachment1 = trailAtt1
		skidTrail.Color = ColorSequence.new(Color3.fromRGB(20, 20, 24))
		skidTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.8, 0.65),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		skidTrail.Lifetime = 2.2
		skidTrail.MinLength = 0.2
		skidTrail.FaceCamera = false
		skidTrail.Enabled = false
		skidTrail.Parent = chassis

		local driftSmoke = Instance.new("ParticleEmitter")
		driftSmoke.Name = "DriftSmoke"
		driftSmoke.Color = ColorSequence.new(Color3.fromRGB(230, 232, 238))
		driftSmoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 3.2),
		})
		driftSmoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		driftSmoke.Lifetime = NumberRange.new(0.45, 0.85)
		driftSmoke.Rate = 45
		driftSmoke.Speed = NumberRange.new(3, 8)
		driftSmoke.SpreadAngle = Vector2.new(35, 20)
		driftSmoke.Enabled = false
		driftSmoke.Parent = tireAtt
	end
end

-- Main procedural 3D vehicle builder
function VehicleCatalog.BuildVehicle(vehicleType: string?, options: BuildOptions?): Model
	local opts: BuildOptions = options or {}
	local cfg = VehicleCatalog.GetConfig(vehicleType)

	local scale = math.clamp(opts.BulkScale or 1.0, 0.75, 2.0)
	local engineLevel = math.max(0, opts.EngineLevel or 0)
	local armorLevel = math.max(0, opts.ArmorLevel or 0)
	local nitroLevel = math.max(0, opts.NitroLevel or 0)
	local plowLevel = math.max(0, opts.PlowLevel or (if opts.HasRamPlow then 1 else 0))
	if cfg.HasBulldozerBlade and plowLevel < 2 then
		plowLevel = 2
	end

	local primaryColor = opts.PrimaryColor or cfg.PrimaryColor
	local secondaryColor = opts.SecondaryColor or cfg.SecondaryColor
	local accentColor = opts.AccentColor or cfg.AccentColor

	local model = Instance.new("Model")
	model.Name = cfg.Id

	local chassisSize = cfg.Size * scale
	local w = chassisSize.X
	local h = chassisSize.Y
	local len = chassisSize.Z

	-- 1. Main Chassis slab (PrimaryPart, ONLY part with CanCollide = true)
	local chassis = makePart(
		"Chassis",
		chassisSize,
		primaryColor,
		Enum.Material.SmoothPlastic,
		model,
		true,
		false
	)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.85, 0.01, 0.0, 100, 100)
	model.PrimaryPart = chassis

	local spawnCF = opts.CFrame or CFrame.new(0, cfg.HoverHeight * scale + h * 0.5, 0)
	chassis.CFrame = spawnCF

	-- 2. DriveSeat (VehicleSeat) inside the cabin (MaxSpeed = 0, Torque = 0 so legacy solver never fights custom velocity)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(2.2, 0.7, 2.2)
	seat.Color = Color3.fromRGB(26, 28, 34)
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false

	-- Effective upgraded stats
	local effectiveMaxSpeed = cfg.MaxSpeed * (1 + engineLevel * 0.09)
	local effectiveAccel = cfg.Acceleration * (1 + engineLevel * 0.10)
	local effectiveMaxHealth = math.round(cfg.MaxHealth * (1 + armorLevel * 0.22))
	local effectiveNitroCap = cfg.NitroCapacity * (1 + nitroLevel * 0.18)
	local effectiveRamMult = cfg.RamMultiplier + plowLevel * 0.35

	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = cfg.TurnSpeed
	seat.Parent = model

	local seatZ = if cfg.HasTruckBed then -len * 0.08 elseif cfg.HasBulldozerBlade then len * 0.06 else -len * 0.02
	placeAndWeld(chassis, seat, CFrame.new(0, -h * 0.45, seatZ))

	-- ProximityPrompt on DriveSeat for quick E enter / hijack on foot
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterVehiclePrompt"
	prompt.ActionText = if opts.IsTraffic then "Hijack " .. cfg.DisplayName else "Drive " .. cfg.DisplayName
	prompt.ObjectText = cfg.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	-- 3. Sculpted Aerodynamic Front Hood Nose (WedgePart) & Hood Deck + Front Splitter/Air Dam
	local hoodLen = len * (if cfg.Id == "Sports" or cfg.Id == "Muscle" then 0.34 else 0.28)
	local hoodW = w * 0.94
	local hoodH = h * 0.36
	local hoodDeckLen = hoodLen * 0.62
	local hoodSlopeLen = hoodLen * 0.38

	local hood = makePart(
		"Hood",
		Vector3.new(hoodW, hoodH, hoodDeckLen),
		primaryColor,
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(
		chassis,
		hood,
		CFrame.new(0, h * 0.48, -len * 0.5 + hoodSlopeLen + hoodDeckLen * 0.5 + 0.15 * scale)
	)

	-- Sloped aerodynamic front hood nose (WedgePart sloping down toward -Z)
	local hoodNose = makeWedge(
		"HoodNoseWedge",
		Vector3.new(hoodW, hoodH, hoodSlopeLen),
		primaryColor,
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(
		chassis,
		hoodNose,
		CFrame.new(0, h * 0.48, -len * 0.5 + hoodSlopeLen * 0.5 + 0.15 * scale)
	)

	-- Sculpted hood power-dome / center crease
	local hoodCrease = makePart(
		"HoodPowerDome",
		Vector3.new(w * 0.42, 0.14 * scale, hoodDeckLen * 0.88),
		primaryColor,
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(
		chassis,
		hoodCrease,
		CFrame.new(0, h * 0.48 + hoodH * 0.5 + 0.04 * scale, -len * 0.5 + hoodSlopeLen + hoodDeckLen * 0.5 + 0.15 * scale)
	)

	-- Muscle car racing stripe & supercharger blower on hood
	if cfg.HasBlower then
		local stripe = makePart(
			"RacingStripe",
			Vector3.new(w * 0.28, 0.08 * scale, len * 0.94),
			secondaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(chassis, stripe, CFrame.new(0, h * 0.68, 0))

		local blowerBase = makePart(
			"BlowerBase",
			Vector3.new(w * 0.32, h * 0.38, hoodLen * 0.45),
			Color3.fromRGB(205, 210, 220),
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, blowerBase, CFrame.new(0, h * 0.82, -len * 0.24))

		local blowerScoop = makePart(
			"BlowerScoop",
			Vector3.new(w * 0.36, h * 0.26, hoodLen * 0.38),
			Color3.fromRGB(225, 230, 238),
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, blowerScoop, CFrame.new(0, h * 1.06, -len * 0.26))

		for _, intakeX in ipairs({ -0.35, 0, 0.35 }) do
			local butterfly = makePart(
				"IntakeValve",
				Vector3.new(w * 0.08, h * 0.16, 0.12 * scale),
				Color3.fromRGB(220, 45, 35),
				Enum.Material.Neon,
				model
			)
			placeAndWeld(chassis, butterfly, CFrame.new(intakeX * w * 0.28, h * 1.08, -len * 0.26 - hoodLen * 0.19))
		end
	end

	-- 3b. Sculpted Side Body Doors, Lower Rocker Side Skirts, Flared Wheel-Arch Fenders & Side Mirrors
	local darkTrimColor = Color3.fromRGB(24, 27, 34)
	for _, sx in ipairs({ -1, 1 }) do
		local sideTag = if sx < 0 then "L" else "R"

		-- Sculpted side door panel with beltline contour
		local sideDoor = makePart(
			"SideDoor" .. sideTag,
			Vector3.new(0.24 * scale, h * 0.72, len * 0.42),
			primaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(chassis, sideDoor, CFrame.new(sx * (w * 0.50), h * 0.14, 0))

		-- Door handle & side character crease
		local doorHandle = makePart(
			"DoorHandle" .. sideTag,
			Vector3.new(0.14 * scale, 0.14 * scale, 0.65 * scale),
			secondaryColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, doorHandle, CFrame.new(sx * (w * 0.525), h * 0.32, 0.35 * scale))

		-- Lower aerodynamic carbon/dark-metallic rocker side skirt
		local sideSkirt = makePart(
			"SideSkirt" .. sideTag,
			Vector3.new(0.36 * scale, h * 0.24, len * 0.52),
			darkTrimColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, sideSkirt, CFrame.new(sx * (w * 0.51), -h * 0.38, 0))

		-- Flared Wheel-Arch Fenders over front & rear tires
		for _, fz in ipairs({ -cfg.WheelbaseOffsetZ * scale, cfg.WheelbaseOffsetZ * scale }) do
			local archTag = if fz < 0 then "Front" else "Rear"
			local fenderFlare = makePart(
				"FenderFlare" .. sideTag .. "_" .. archTag,
				Vector3.new(0.42 * scale, h * 0.34, cfg.WheelRadius * 2.15 * scale),
				primaryColor,
				Enum.Material.SmoothPlastic,
				model
			)
			placeAndWeld(chassis, fenderFlare, CFrame.new(sx * (w * 0.515), h * 0.08, fz))

			local archLip = makePart(
				"FenderArchLip" .. sideTag .. "_" .. archTag,
				Vector3.new(0.46 * scale, 0.18 * scale, cfg.WheelRadius * 2.05 * scale),
				darkTrimColor,
				Enum.Material.Metal,
				model
			)
			placeAndWeld(chassis, archLip, CFrame.new(sx * (w * 0.52), -h * 0.08, fz))
		end
	end

	-- 4. Low-Profile Sleek Aerodynamic Greenhouse (Cabin), 38° Raked Front WedgePart Windshield,
	--    Thin Flush Roof Panel (0.18 studs thick), and 32° Long Fastback WedgePart Rear Window
	local glassColor = Color3.fromRGB(24, 30, 38)
	local cabW = w * 0.78
	local cabH = h * 0.62
	local cabLen = if cfg.HasTruckBed then len * 0.24 elseif cfg.Id == "SUV" then len * 0.34 else len * 0.26
	local cabCenterZ = if cfg.HasTruckBed then -len * 0.08 elseif cfg.Id == "SUV" then 0.0 else -len * 0.02
	local cabBaseY = h * 0.5 + cabH * 0.5 - 0.04 * scale

	local cabin = makePart(
		"Cabin",
		Vector3.new(cabW, cabH, cabLen),
		glassColor,
		Enum.Material.Glass,
		model,
		false,
		true,
		0.25
	)
	cabin.Reflectance = 0.25
	placeAndWeld(chassis, cabin, CFrame.new(0, cabBaseY, cabCenterZ))

	-- Sleek low-profile dark-tinted Driver Silhouette inside the smoked glass greenhouse (never pokes above roof)
	local silhouetteColor = Color3.fromRGB(18, 22, 28)
	local headrest = makePart(
		"DriverHeadrest",
		Vector3.new(1.35 * scale, cabH * 0.52, 0.34 * scale),
		Color3.fromRGB(24, 28, 36),
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(
		chassis,
		headrest,
		CFrame.new(0, h * 0.5 + cabH * 0.28, seatZ + 0.62 * scale) * CFrame.Angles(math.rad(-10), 0, 0)
	)

	local driverTorso = makePart(
		"DriverSilhouetteTorso",
		Vector3.new(1.45 * scale, cabH * 0.42, 0.72 * scale),
		silhouetteColor,
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(
		chassis,
		driverTorso,
		CFrame.new(0, h * 0.5 + cabH * 0.22, seatZ + 0.06 * scale) * CFrame.Angles(math.rad(-8), 0, 0)
	)

	local driverHelmet = makePart(
		"DriverSilhouetteHelmet",
		Vector3.new(cabH * 0.56, cabH * 0.56, cabH * 0.60),
		silhouetteColor,
		Enum.Material.SmoothPlastic,
		model,
		false,
		true,
		0,
		Enum.PartType.Ball
	)
	placeAndWeld(
		chassis,
		driverHelmet,
		CFrame.new(0, h * 0.5 + cabH * 0.50, seatZ + 0.04 * scale)
	)

	local driverVisor = makePart(
		"DriverHelmetVisor",
		Vector3.new(cabH * 0.48, cabH * 0.18, cabH * 0.20),
		accentColor,
		Enum.Material.Neon,
		model
	)
	placeAndWeld(
		chassis,
		driverVisor,
		CFrame.new(0, h * 0.5 + cabH * 0.52, seatZ - 0.26 * scale)
	)

	-- Thin flush roof panel (0.18 studs thick)
	local roofCap = makePart(
		"RoofCap",
		Vector3.new(cabW * 0.98, 0.18 * scale, cabLen * 0.98),
		if cfg.Id == "Sports" or cfg.Id == "Muscle" then secondaryColor else primaryColor,
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(chassis, roofCap, CFrame.new(0, h * 0.5 + cabH - 0.04 * scale, cabCenterZ))

	-- Steeply raked front WedgePart windshield (38° angle) with left/right sculpted A-pillars
	local wsSlopeLen = cabH / math.tan(math.rad(38))
	local windshield = makeWedge(
		"Windshield",
		Vector3.new(cabW * 0.98, cabH, wsSlopeLen),
		glassColor,
		Enum.Material.Glass,
		model,
		0.25
	)
	windshield.Reflectance = 0.25
	placeAndWeld(
		chassis,
		windshield,
		CFrame.new(0, cabBaseY, cabCenterZ - cabLen * 0.5 - wsSlopeLen * 0.5)
	)

	for _, sx in ipairs({ -1, 1 }) do
		local pillarTag = if sx < 0 then "L" else "R"
		local aPillar = makePart(
			"APillar" .. pillarTag,
			Vector3.new(0.18 * scale, math.sqrt(cabH * cabH + wsSlopeLen * wsSlopeLen), 0.20 * scale),
			primaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(
			chassis,
			aPillar,
			CFrame.new(sx * (cabW * 0.48), cabBaseY, cabCenterZ - cabLen * 0.5 - wsSlopeLen * 0.5)
				* CFrame.Angles(math.atan2(wsSlopeLen, cabH), 0, 0)
		)

		-- Left/Right aerodynamic side-view mirrors + mirror glass
		local mirrorArm = makePart(
			"SideMirrorArm" .. pillarTag,
			Vector3.new(0.45 * scale, 0.14 * scale, 0.22 * scale),
			darkTrimColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(
			chassis,
			mirrorArm,
			CFrame.new(sx * (w * 0.51), h * 0.54, cabCenterZ - cabLen * 0.5 - wsSlopeLen * 0.35)
		)

		local mirrorCap = makePart(
			"SideMirror" .. pillarTag,
			Vector3.new(0.52 * scale, 0.32 * scale, 0.36 * scale),
			primaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(
			chassis,
			mirrorCap,
			CFrame.new(sx * (w * 0.56), h * 0.58, cabCenterZ - cabLen * 0.5 - wsSlopeLen * 0.35)
				* CFrame.Angles(0, math.rad(-sx * 12), 0)
		)
	end

	-- Long fastback WedgePart rear window (32° angle) that slopes smoothly into the rear decklid
	local rwSlopeLen = if cfg.HasTruckBed
		then cabH * 0.55
		else (cabH / math.tan(math.rad(32)))
	local rearWindow = makeWedge(
		"RearWindow",
		Vector3.new(cabW * 0.96, cabH, rwSlopeLen),
		glassColor,
		Enum.Material.Glass,
		model,
		0.25
	)
	rearWindow.Reflectance = 0.25
	placeAndWeld(
		chassis,
		rearWindow,
		CFrame.new(0, cabBaseY, cabCenterZ + cabLen * 0.5 + rwSlopeLen * 0.5)
			* CFrame.Angles(0, math.rad(180), 0)
	)

	-- Rear trunk decklid (sloping fastback transitions smoothly into decklid)
	if not cfg.HasTruckBed then
		local rearGlassEndZ = cabCenterZ + cabLen * 0.5 + rwSlopeLen
		local trunkLen = math.max(1.1 * scale, (len * 0.5) - rearGlassEndZ + 0.35 * scale)
		local trunkDeck = makePart(
			"TrunkDeck",
			Vector3.new(w * 0.92, h * 0.34, trunkLen),
			primaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(chassis, trunkDeck, CFrame.new(0, h * 0.44, len * 0.5 - trunkLen * 0.5 - 0.12 * scale))
	end

	-- 5. Truck Bed (Pickup & MonsterTruck)
	if cfg.HasTruckBed then
		local bedLen = len * 0.38
		local bedZ = len * 0.5 - bedLen * 0.5 - 0.2 * scale
		local bedFloor = makePart(
			"TruckBedFloor",
			Vector3.new(w * 0.88, 0.25 * scale, bedLen),
			secondaryColor,
			Enum.Material.DiamondPlate,
			model
		)
		placeAndWeld(chassis, bedFloor, CFrame.new(0, h * 0.38, bedZ))

		for _, sx in ipairs({ -1, 1 }) do
			local bedWall = makePart(
				"TruckBedWall",
				Vector3.new(0.42 * scale, h * 0.48, bedLen),
				primaryColor,
				Enum.Material.SmoothPlastic,
				model
			)
			placeAndWeld(chassis, bedWall, CFrame.new(sx * (w * 0.46), h * 0.58, bedZ))
		end

		local tailgate = makePart(
			"Tailgate",
			Vector3.new(w * 0.92, h * 0.48, 0.38 * scale),
			primaryColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(chassis, tailgate, CFrame.new(0, h * 0.58, len * 0.5 - 0.25 * scale))

		-- Sport rollbar behind cab with overhead floodlights
		local rollbar = makePart(
			"RollBar",
			Vector3.new(cabW * 0.94, cabH * 0.95, 0.38 * scale),
			secondaryColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, rollbar, CFrame.new(0, h * 0.5 + cabH * 0.48, cabCenterZ + cabLen * 0.5 + 0.45 * scale))
	end

	-- 6. Roof Rails (SUV)
	if cfg.HasRoofRails then
		for _, sx in ipairs({ -1, 1 }) do
			local rail = makePart(
				"RoofRail",
				Vector3.new(0.24 * scale, 0.26 * scale, cabLen * 0.86),
				secondaryColor,
				Enum.Material.Metal,
				model
			)
			placeAndWeld(chassis, rail, CFrame.new(sx * (cabW * 0.42), h * 0.5 + cabH + 0.2 * scale, cabCenterZ))
		end
	end

	-- 7. Rear Spoiler & Splitter (Sports & Muscle)
	if cfg.HasSpoiler then
		for _, sx in ipairs({ -1, 1 }) do
			local strut = makePart(
				"SpoilerStrut",
				Vector3.new(0.25 * scale, 0.75 * scale, 0.45 * scale),
				secondaryColor,
				Enum.Material.Metal,
				model
			)
			placeAndWeld(chassis, strut, CFrame.new(sx * (w * 0.30), h * 0.72, len * 0.44))
		end
		local wing = makePart(
			"SpoilerWing",
			Vector3.new(w * 0.94, 0.22 * scale, 1.35 * scale),
			accentColor,
			Enum.Material.SmoothPlastic,
			model
		)
		placeAndWeld(chassis, wing, CFrame.new(0, h * 1.12, len * 0.45) * CFrame.Angles(math.rad(-8), 0, 0))
	end

	-- 8. Neon Accents (Sports coupe underglow & side blades)
	if cfg.HasNeonAccents then
		for _, sx in ipairs({ -1, 1 }) do
			local sideNeon = makePart(
				"NeonSideStrip",
				Vector3.new(0.16 * scale, 0.18 * scale, len * 0.68),
				accentColor,
				Enum.Material.Neon,
				model
			)
			placeAndWeld(chassis, sideNeon, CFrame.new(sx * (w * 0.51), -h * 0.36, 0))
		end
		local frontSplitterNeon = makePart(
			"NeonFrontStrip",
			Vector3.new(w * 0.86, 0.14 * scale, 0.22 * scale),
			accentColor,
			Enum.Material.Neon,
			model
		)
		placeAndWeld(chassis, frontSplitterNeon, CFrame.new(0, -h * 0.38, -len * 0.5 - 0.18 * scale))
	end

	-- 9. Monster Truck high-travel suspension struts & shock coils
	if cfg.HasMonsterSuspension then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local shock = makePart(
					"SuspensionShock",
					Vector3.new(0.55 * scale, cfg.HoverHeight * 0.85 * scale, 0.55 * scale),
					accentColor,
					Enum.Material.Metal,
					model
				)
				placeAndWeld(
					chassis,
					shock,
					CFrame.new(sx * (w * 0.38), -cfg.HoverHeight * 0.42 * scale, sz * cfg.WheelbaseOffsetZ * scale)
						* CFrame.Angles(0, 0, math.rad(sx * 12))
				)
			end
		end
	end

	-- 10. Bulldozer / ArmoredTank turret cage & hazard beacons
	if cfg.HasBulldozerBlade then
		for _, sx in ipairs({ -1, 1 }) do
			local beacon = makePart(
				"HazardBeacon",
				Vector3.new(0.55 * scale, 0.65 * scale, 0.55 * scale),
				Color3.fromRGB(255, 140, 10),
				Enum.Material.Neon,
				model,
				false,
				true,
				0,
				Enum.PartType.Cylinder
			)
			placeAndWeld(
				chassis,
				beacon,
				CFrame.new(sx * (cabW * 0.35), h * 0.5 + cabH + 0.38 * scale, cabCenterZ)
					* CFrame.Angles(0, 0, math.rad(90))
			)

			-- Side armored track skirts
			local trackSkirt = makePart(
				"ArmoredTrackSkirt",
				Vector3.new(0.75 * scale, h * 0.85, len * 0.88),
				secondaryColor,
				Enum.Material.DiamondPlate,
				model
			)
			placeAndWeld(chassis, trackSkirt, CFrame.new(sx * (w * 0.52), -h * 0.25, 0))
		end
	end

	-- 11. Front & Rear Bumpers, Splitter/Air Dam, Honeycomb Grille, Projector Headlights, Rear Diffuser, License Plate & Twin Exhaust
	for _, sz in ipairs({ -1, 1 }) do
		local bumper = makePart(
			if sz < 0 then "FrontBumper" else "RearBumper",
			Vector3.new(w * 1.03, h * 0.34, 0.58 * scale),
			secondaryColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, bumper, CFrame.new(0, -h * 0.24, sz * (len * 0.5 + 0.18 * scale)))
	end

	-- Sculpted Front Splitter / Air Dam with carbon/dark-metallic trim
	local frontSplitter = makePart(
		"FrontSplitter",
		Vector3.new(w * 1.06, 0.16 * scale, 0.85 * scale),
		darkTrimColor,
		Enum.Material.Metal,
		model
	)
	placeAndWeld(chassis, frontSplitter, CFrame.new(0, -h * 0.44, -len * 0.5 - 0.26 * scale))

	local frontAirDam = makePart(
		"FrontAirDam",
		Vector3.new(w * 0.62, h * 0.22, 0.32 * scale),
		Color3.fromRGB(16, 18, 22),
		Enum.Material.DiamondPlate,
		model
	)
	placeAndWeld(chassis, frontAirDam, CFrame.new(0, -h * 0.32, -len * 0.5 - 0.22 * scale))

	-- Recessed Honeycomb / Mesh Front Grille + Surround Trim
	local grilleSurround = makePart(
		"FrontGrilleTrim",
		Vector3.new(w * 0.52, h * 0.40, 0.16 * scale),
		secondaryColor,
		Enum.Material.Metal,
		model
	)
	placeAndWeld(chassis, grilleSurround, CFrame.new(0, 0.06 * scale, -len * 0.5 - 0.06 * scale))

	local grille = makePart(
		"FrontGrille",
		Vector3.new(w * 0.48, h * 0.34, 0.18 * scale),
		Color3.fromRGB(22, 25, 30),
		Enum.Material.DiamondPlate,
		model
	)
	placeAndWeld(chassis, grille, CFrame.new(0, 0.06 * scale, -len * 0.5 - 0.09 * scale))

	-- Dual Angled Projector Headlights (Front = -Z) with Inner LED Rings & SpotLights
	for _, sx in ipairs({ -1, 1 }) do
		local hlSide = if sx < 0 then "L" else "R"

		local hlHousing = makePart(
			"HeadlightHousing" .. hlSide,
			Vector3.new(w * 0.21, h * 0.25, 0.20 * scale),
			Color3.fromRGB(18, 20, 26),
			Enum.Material.Metal,
			model
		)
		placeAndWeld(
			chassis,
			hlHousing,
			CFrame.new(sx * (w * 0.35), h * 0.12, -len * 0.5 - 0.06 * scale)
				* CFrame.Angles(0, math.rad(-sx * 8), math.rad(-sx * 4))
		)

		local headlight = makePart(
			"Headlight" .. hlSide,
			Vector3.new(w * 0.18, h * 0.20, 0.22 * scale),
			Color3.fromRGB(245, 250, 255),
			Enum.Material.Neon,
			model
		)
		placeAndWeld(
			chassis,
			headlight,
			CFrame.new(sx * (w * 0.35), h * 0.12, -len * 0.5 - 0.09 * scale)
				* CFrame.Angles(0, math.rad(-sx * 8), math.rad(-sx * 4))
		)

		local ledRing = makePart(
			"HeadlightLEDRing" .. hlSide,
			Vector3.new(w * 0.19, 0.07 * scale, 0.24 * scale),
			accentColor,
			Enum.Material.Neon,
			model
		)
		placeAndWeld(
			chassis,
			ledRing,
			CFrame.new(sx * (w * 0.35), h * 0.04, -len * 0.5 - 0.11 * scale)
				* CFrame.Angles(0, math.rad(-sx * 8), math.rad(-sx * 6))
		)

		local spot = Instance.new("SpotLight")
		spot.Name = "HeadlightBeam"
		spot.Face = Enum.NormalId.Front
		spot.Brightness = 2.8
		spot.Range = 58
		spot.Angle = 55
		spot.Color = Color3.fromRGB(255, 248, 230)
		spot.Enabled = true
		spot.Parent = headlight
	end

	-- Detailed Rear Fascia: Recessed dark-red LED taillight strips inside a black rear diffuser housing (no giant pink neon slab!)
	local taillightLedColor = Color3.fromRGB(185, 24, 30)
	local rearHousingColor = Color3.fromRGB(16, 18, 24)

	local taillightHousing = makePart(
		"RearTaillightHousing",
		Vector3.new(w * 0.88, h * 0.22, 0.18 * scale),
		rearHousingColor,
		Enum.Material.Metal,
		model
	)
	placeAndWeld(chassis, taillightHousing, CFrame.new(0, h * 0.14, len * 0.5 + 0.05 * scale))

	local taillight = makePart(
		"TaillightBar",
		Vector3.new(w * 0.74, 0.08 * scale, 0.14 * scale),
		taillightLedColor,
		Enum.Material.SmoothPlastic,
		model
	)
	taillight.Reflectance = 0.15
	placeAndWeld(chassis, taillight, CFrame.new(0, h * 0.15, len * 0.5 + 0.08 * scale))

	for _, sx in ipairs({ -1, 1 }) do
		local tlSide = if sx < 0 then "L" else "R"
		local tlBezel = makePart(
			"TaillightBezel" .. tlSide,
			Vector3.new(w * 0.23, h * 0.20, 0.18 * scale),
			rearHousingColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, tlBezel, CFrame.new(sx * (w * 0.34), h * 0.14, len * 0.5 + 0.06 * scale))

		local tlCluster = makePart(
			"TaillightCluster" .. tlSide,
			Vector3.new(w * 0.19, 0.12 * scale, 0.16 * scale),
			taillightLedColor,
			Enum.Material.SmoothPlastic,
			model
		)
		tlCluster.Reflectance = 0.15
		placeAndWeld(chassis, tlCluster, CFrame.new(sx * (w * 0.34), h * 0.14, len * 0.5 + 0.09 * scale))
	end

	-- License Plate Badge ("LEO-01")
	local plateBacking = makePart(
		"LicensePlate",
		Vector3.new(1.55 * scale, 0.72 * scale, 0.14 * scale),
		Color3.fromRGB(240, 200, 45),
		Enum.Material.SmoothPlastic,
		model
	)
	placeAndWeld(chassis, plateBacking, CFrame.new(0, -h * 0.16, len * 0.5 + 0.24 * scale))

	local plateGui = Instance.new("SurfaceGui")
	plateGui.Name = "PlateGui"
	plateGui.Face = Enum.NormalId.Back
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.PixelsPerStud = 48
	plateGui.Parent = plateBacking

	local plateLabel = Instance.new("TextLabel")
	plateLabel.Size = UDim2.fromScale(1, 1)
	plateLabel.BackgroundTransparency = 1
	plateLabel.Text = "LEO-01"
	plateLabel.TextColor3 = Color3.fromRGB(20, 24, 32)
	plateLabel.Font = Enum.Font.GothamBlack
	plateLabel.TextScaled = true
	plateLabel.Parent = plateGui

	-- Rear Diffuser Fins along the lower rear bumper
	local diffuserBase = makePart(
		"RearDiffuser",
		Vector3.new(w * 0.84, 0.18 * scale, 0.55 * scale),
		darkTrimColor,
		Enum.Material.Metal,
		model
	)
	placeAndWeld(chassis, diffuserBase, CFrame.new(0, -h * 0.42, len * 0.5 + 0.18 * scale))

	for finIdx = -2, 2 do
		local fin = makePart(
			"DiffuserFin",
			Vector3.new(0.10 * scale, 0.32 * scale, 0.58 * scale),
			darkTrimColor,
			Enum.Material.Metal,
			model
		)
		placeAndWeld(chassis, fin, CFrame.new(finIdx * (w * 0.12), -h * 0.40, len * 0.5 + 0.24 * scale))
	end

	-- Twin Chrome / Titanium Exhaust Tips (Rear = +Z)
	for _, sx in ipairs({ -1, 1 }) do
		local exhaustSide = if sx < 0 then "L" else "R"
		local exhaust = makePart(
			"Exhaust" .. exhaustSide,
			Vector3.new(0.58 * scale, 0.38 * scale, 0.38 * scale),
			Color3.fromRGB(190, 198, 210),
			Enum.Material.Metal,
			model,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		placeAndWeld(
			chassis,
			exhaust,
			CFrame.new(sx * (w * 0.30), -h * 0.35, len * 0.5 + 0.26 * scale)
				* CFrame.Angles(0, math.rad(90), 0)
		)

		local exhaustInner = makePart(
			"ExhaustTipInner" .. exhaustSide,
			Vector3.new(0.60 * scale, 0.26 * scale, 0.26 * scale),
			Color3.fromRGB(25, 28, 34),
			Enum.Material.Metal,
			model,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		placeAndWeld(
			chassis,
			exhaustInner,
			CFrame.new(sx * (w * 0.30), -h * 0.35, len * 0.5 + 0.27 * scale)
				* CFrame.Angles(0, math.rad(90), 0)
		)
	end

	-- 12. 4 Detailed 3D Wheels (FL, FR, RL, RR): dark rubber tire cylinder, metallic alloy rim, inner brake rotor disc, and painted red brake caliper!
	local wheelDiameter = cfg.WheelRadius * 2 * scale
	local wheelWidth = cfg.WheelWidth * scale
	local wheelY = -(cfg.HoverHeight * scale) + cfg.WheelRadius * scale - h * 0.15
	local wheelSpecs = {
		{ Name = "WheelFL", X = -cfg.TrackOffsetX * scale, Z = -cfg.WheelbaseOffsetZ * scale, IsFront = true, Side = -1 },
		{ Name = "WheelFR", X = cfg.TrackOffsetX * scale, Z = -cfg.WheelbaseOffsetZ * scale, IsFront = true, Side = 1 },
		{ Name = "WheelRL", X = -cfg.TrackOffsetX * scale, Z = cfg.WheelbaseOffsetZ * scale, IsFront = false, Side = -1 },
		{ Name = "WheelRR", X = cfg.TrackOffsetX * scale, Z = cfg.WheelbaseOffsetZ * scale, IsFront = false, Side = 1 },
	}

	for _, ws in ipairs(wheelSpecs) do
		-- Roblox Cylinder axis is local X, so Size = (width, diameter, diameter) aligns axle with X!
		local tire = makePart(
			ws.Name,
			Vector3.new(wheelWidth, wheelDiameter, wheelDiameter),
			Color3.fromRGB(20, 22, 26),
			Enum.Material.SmoothPlastic,
			model,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		tire:SetAttribute("IsFrontWheel", ws.IsFront)
		local baseOffset = CFrame.new(ws.X, wheelY, ws.Z)
		local weld = placeAndWeld(chassis, tire, baseOffset)
		weld.Name = "WheelWeld"
		tire:SetAttribute("BaseX", ws.X)
		tire:SetAttribute("BaseY", wheelY)
		tire:SetAttribute("BaseZ", ws.Z)

		-- Metallic alloy rim
		local rim = makePart(
			ws.Name .. "_Rim",
			Vector3.new(wheelWidth + 0.10 * scale, wheelDiameter * 0.62, wheelDiameter * 0.62),
			Color3.fromRGB(195, 202, 214),
			Enum.Material.Metal,
			model,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		placeAndWeld(tire, rim, CFrame.identity)

		-- Center alloy hub & spoke bar so wheel spin is visually unmistakable
		local spokeBar = makePart(
			ws.Name .. "_Spoke",
			Vector3.new(wheelWidth + 0.14 * scale, wheelDiameter * 0.56, wheelDiameter * 0.14),
			accentColor,
			Enum.Material.Metal,
			model,
			false,
			true
		)
		placeAndWeld(tire, spokeBar, CFrame.identity)

		-- Inner brake rotor disc
		local rotor = makePart(
			ws.Name .. "_BrakeRotor",
			Vector3.new(wheelWidth * 0.45, wheelDiameter * 0.46, wheelDiameter * 0.46),
			Color3.fromRGB(130, 136, 146),
			Enum.Material.Metal,
			model,
			false,
			true,
			0,
			Enum.PartType.Cylinder
		)
		placeAndWeld(tire, rotor, CFrame.new(-ws.Side * (wheelWidth * 0.18), 0, 0))

		-- Painted red performance brake caliper (welded to chassis inside the wheel hub so it stays stationary while rotor spins!)
		local caliper = makePart(
			ws.Name .. "_BrakeCaliper",
			Vector3.new(wheelWidth * 0.55, wheelDiameter * 0.22, wheelDiameter * 0.16),
			Color3.fromRGB(225, 32, 32),
			Enum.Material.Metal,
			model,
			false,
			true
		)
		placeAndWeld(
			chassis,
			caliper,
			CFrame.new(
				ws.X + ws.Side * (wheelWidth * 0.15),
				wheelY + wheelDiameter * 0.12,
				ws.Z - (if ws.IsFront then -wheelDiameter * 0.14 else wheelDiameter * 0.14)
			)
		)
	end

	-- 13. Attach VFX Emitters (Nitro, Drift Smoke, Skid Trails, Damage Smoke/Fire)
	attachVehicleVFX(model, chassis, cfg)

	-- 14. Attach 3D Visual Upgrades (Engine, Armor, Nitro, Plow, Magnet)
	local magnetLevel = math.max(0, tonumber((opts :: any).MagnetLevel) or 0)
	VehicleCatalog.AttachVisualUpgrades(model, {
		Engine = engineLevel,
		Armor = armorLevel,
		Nitro = nitroLevel,
		Plow = plowLevel,
		Magnet = magnetLevel,
		AccentColor = accentColor,
	})

	-- 15. Set Vehicle Attributes on Model & DriveSeat
	model:SetAttribute("VehicleType", cfg.Id)
	model:SetAttribute("DisplayName", cfg.DisplayName)
	model:SetAttribute("MaxHealth", effectiveMaxHealth)
	model:SetAttribute("Health", effectiveMaxHealth)
	model:SetAttribute("Mass", math.round(cfg.Mass * scale))
	model:SetAttribute("MaxSpeed", effectiveMaxSpeed)
	model:SetAttribute("ReverseSpeed", cfg.ReverseSpeed)
	model:SetAttribute("Acceleration", effectiveAccel)
	model:SetAttribute("BrakeDecel", cfg.BrakeDecel)
	model:SetAttribute("TurnSpeed", cfg.TurnSpeed)
	model:SetAttribute("DriftFactor", cfg.DriftFactor)
	model:SetAttribute("RamMultiplier", effectiveRamMult)
	model:SetAttribute("NitroCapacity", effectiveNitroCap)
	model:SetAttribute("HoverHeight", cfg.HoverHeight * scale)
	model:SetAttribute("CoinReward", cfg.CoinReward)
	model:SetAttribute("UnlockCost", cfg.UnlockCost)
	model:SetAttribute("EngineLevel", engineLevel)
	model:SetAttribute("ArmorLevel", armorLevel)
	model:SetAttribute("NitroLevel", nitroLevel)
	model:SetAttribute("PlowLevel", plowLevel)
	model:SetAttribute("MagnetLevel", magnetLevel)
	model:SetAttribute("BaseSmashTier", VehicleCatalog.GetBaseSmashTier(cfg.Id))
	model:SetAttribute("BulkScale", scale)
	model:SetAttribute("IsTraffic", opts.IsTraffic == true)
	model:SetAttribute("OwnerUserId", opts.OwnerUserId or 0)
	model:SetAttribute("HeadlightsOn", true)
	model:SetAttribute("IsWrecked", false)

	CollectionService:AddTag(model, "Vehicle")
	if opts.IsTraffic then
		CollectionService:AddTag(model, "TrafficVehicle")
	end

	return model
end

local BASE_SMASH_TIER_BY_CLASS: { [string]: number } = {
	Compact = 1,
	Sedan = 2,
	Muscle = 2,
	SUV = 3,
	Pickup = 3,
	Sports = 3,
	MonsterTruck = 4,
	Bulldozer = 5,
	Tank = 5,
	ArmoredTank = 5,
}

function VehicleCatalog.GetBaseSmashTier(vehicleType: string?): number
	local resolved = VehicleCatalog.ResolveArchetypeId(vehicleType)
	return BASE_SMASH_TIER_BY_CLASS[resolved] or 1
end

-- Alias for compatibility with other scripts
VehicleCatalog.Build = VehicleCatalog.BuildVehicle
VehicleCatalog.CreateVehicle = VehicleCatalog.BuildVehicle

return VehicleCatalog
