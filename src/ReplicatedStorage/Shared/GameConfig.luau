--!strict
--[[
	GameConfig.luau
	Central tuning & balance configuration for World of Destruction (Roblox Edition).
	Covers:
	  1. All 8 vehicle classes (Compact, Sedan, Muscle, SUV, Sports, Pickup, MonsterTruck, Tank)
	  2. All 8 core destructible object tiers (Hydrant, Fence, StreetLight, Crate, Billboard, BusStop, GasPump, Kiosk)
	  3. Combo window & multiplier thresholds
	  4. 5-star police heat thresholds & unit configs
	  5. Garage upgrade levels & costs (Engine, Armor, Nitro, Plow, CashMagnet)
	  6. Leo City layout constants, districts, and landmarks
]]

local Types = require(script.Parent:WaitForChild("Types"))

local GameConfig = {}

--------------------------------------------------------------------------------
-- 1. VEHICLE CLASSES
--------------------------------------------------------------------------------

GameConfig.StarterVehicle = "Compact" :: Types.VehicleClass
GameConfig.DefaultVehicle = "Compact" :: Types.VehicleClass

GameConfig.VehicleOrder = {
	"Compact",
	"Sedan",
	"Pickup",
	"Muscle",
	"SUV",
	"Sports",
	"MonsterTruck",
	"Tank",
} :: { Types.VehicleClass }

GameConfig.Vehicles = {
	Compact = {
		Id = "Compact",
		Class = "Compact",
		Name = "Compact Hatch",
		DisplayName = "Leo Hatch",
		Description = "Nimble city hatchback. Quick cornering and free to drive from the start!",
		Order = 1,
		Tier = 1,
		Cost = 0,
		Price = 0,
		UnlockCost = 0,
		TopSpeed = 58,
		MaxSpeed = 58,
		ReverseSpeed = 26,
		Acceleration = 26,
		Accel = 26,
		Braking = 85,
		BrakeForce = 85,
		TurnSpeed = 2.5,
		SteerSpeed = 2.5,
		Handling = 0.92,
		DriftFactor = 0.85,
		Grip = 0.88,
		Mass = 1050,
		Weight = 1050,
		MaxHealth = 100,
		Health = 100,
		Armor = 1.0,
		DamageMultiplier = 1.0,
		SmashPower = 1.0,
		RamDamage = 18,
		NitroMultiplier = 1.55,
		BoostMultiplier = 1.55,
		NitroDuration = 2.6,
		BoostDuration = 2.6,
		NitroCooldown = 4.5,
		BoostCooldown = 4.5,
		Size = Vector3.new(6.4, 4.2, 11.5),
		WheelRadius = 1.4,
		WheelWidth = 0.85,
		SuspensionHeight = 1.2,
		PrimaryColor = Color3.fromRGB(255, 75, 55),
		Color = Color3.fromRGB(255, 75, 55),
		SecondaryColor = Color3.fromRGB(245, 245, 250),
		AccentColor = Color3.fromRGB(255, 210, 60),
	},

	Sedan = {
		Id = "Sedan",
		Class = "Sedan",
		Name = "Street Sedan",
		DisplayName = "Metro Cruiser",
		Description = "Balanced four-door street cruiser with solid speed and heavier bumper impact.",
		Order = 2,
		Tier = 2,
		Cost = 600,
		Price = 600,
		UnlockCost = 600,
		TopSpeed = 64,
		MaxSpeed = 64,
		ReverseSpeed = 28,
		Acceleration = 28,
		Accel = 28,
		Braking = 88,
		BrakeForce = 88,
		TurnSpeed = 2.4,
		SteerSpeed = 2.4,
		Handling = 0.86,
		DriftFactor = 0.82,
		Grip = 0.86,
		Mass = 1380,
		Weight = 1380,
		MaxHealth = 130,
		Health = 130,
		Armor = 1.12,
		DamageMultiplier = 1.2,
		SmashPower = 1.2,
		RamDamage = 24,
		NitroMultiplier = 1.60,
		BoostMultiplier = 1.60,
		NitroDuration = 2.8,
		BoostDuration = 2.8,
		NitroCooldown = 4.5,
		BoostCooldown = 4.5,
		Size = Vector3.new(6.8, 4.3, 13.8),
		WheelRadius = 1.5,
		WheelWidth = 0.9,
		SuspensionHeight = 1.25,
		PrimaryColor = Color3.fromRGB(45, 135, 255),
		Color = Color3.fromRGB(45, 135, 255),
		SecondaryColor = Color3.fromRGB(220, 230, 245),
		AccentColor = Color3.fromRGB(90, 200, 255),
	},

	Pickup = {
		Id = "Pickup",
		Class = "Pickup",
		Name = "Heavy Pickup",
		DisplayName = "Brawler 4x4",
		Description = "Rugged utility truck built for smashing crates, fences, and roadside stalls.",
		Order = 3,
		Tier = 3,
		Cost = 1500,
		Price = 1500,
		UnlockCost = 1500,
		TopSpeed = 64,
		MaxSpeed = 64,
		ReverseSpeed = 26,
		Acceleration = 28,
		Accel = 28,
		Braking = 80,
		BrakeForce = 80,
		TurnSpeed = 2.2,
		SteerSpeed = 2.2,
		Handling = 0.80,
		DriftFactor = 0.78,
		Grip = 0.84,
		Mass = 1950,
		Weight = 1950,
		MaxHealth = 175,
		Health = 175,
		Armor = 1.30,
		DamageMultiplier = 1.50,
		SmashPower = 1.50,
		RamDamage = 34,
		NitroMultiplier = 1.58,
		BoostMultiplier = 1.58,
		NitroDuration = 3.0,
		BoostDuration = 3.0,
		NitroCooldown = 4.8,
		BoostCooldown = 4.8,
		Size = Vector3.new(7.4, 5.2, 15.2),
		WheelRadius = 1.75,
		WheelWidth = 1.05,
		SuspensionHeight = 1.55,
		PrimaryColor = Color3.fromRGB(235, 140, 30),
		Color = Color3.fromRGB(235, 140, 30),
		SecondaryColor = Color3.fromRGB(40, 42, 48),
		AccentColor = Color3.fromRGB(255, 200, 70),
	},

	Muscle = {
		Id = "Muscle",
		Class = "Muscle",
		Name = "V8 Muscle",
		DisplayName = "Thunder V8",
		Description = "Roaring V8 muscle car with aggressive launch, wide power-slides, and heavy steel bumpers.",
		Order = 4,
		Tier = 4,
		Cost = 3200,
		Price = 3200,
		UnlockCost = 3200,
		TopSpeed = 72,
		MaxSpeed = 72,
		ReverseSpeed = 28,
		Acceleration = 32,
		Accel = 32,
		Braking = 86,
		BrakeForce = 86,
		TurnSpeed = 2.35,
		SteerSpeed = 2.35,
		Handling = 0.82,
		DriftFactor = 0.96,
		Grip = 0.78,
		Mass = 1650,
		Weight = 1650,
		MaxHealth = 160,
		Health = 160,
		Armor = 1.25,
		DamageMultiplier = 1.65,
		SmashPower = 1.65,
		RamDamage = 38,
		NitroMultiplier = 1.72,
		BoostMultiplier = 1.72,
		NitroDuration = 3.2,
		BoostDuration = 3.2,
		NitroCooldown = 4.2,
		BoostCooldown = 4.2,
		Size = Vector3.new(7.2, 4.1, 14.6),
		WheelRadius = 1.55,
		WheelWidth = 1.0,
		SuspensionHeight = 1.2,
		PrimaryColor = Color3.fromRGB(220, 35, 45),
		Color = Color3.fromRGB(220, 35, 45),
		SecondaryColor = Color3.fromRGB(25, 25, 30),
		AccentColor = Color3.fromRGB(255, 220, 80),
	},

	SUV = {
		Id = "SUV",
		Class = "SUV",
		Name = "Armored SUV",
		DisplayName = "Titan Trail",
		Description = "Reinforced off-road SUV that shrugs off police roadblocks and plows through bus stops.",
		Order = 5,
		Tier = 5,
		Cost = 5500,
		Price = 5500,
		UnlockCost = 5500,
		TopSpeed = 62,
		MaxSpeed = 62,
		ReverseSpeed = 26,
		Acceleration = 27,
		Accel = 27,
		Braking = 84,
		BrakeForce = 84,
		TurnSpeed = 2.2,
		SteerSpeed = 2.2,
		Handling = 0.84,
		DriftFactor = 0.75,
		Grip = 0.88,
		Mass = 2350,
		Weight = 2350,
		MaxHealth = 225,
		Health = 225,
		Armor = 1.48,
		DamageMultiplier = 1.85,
		SmashPower = 1.85,
		RamDamage = 46,
		NitroMultiplier = 1.62,
		BoostMultiplier = 1.62,
		NitroDuration = 3.2,
		BoostDuration = 3.2,
		NitroCooldown = 4.5,
		BoostCooldown = 4.5,
		Size = Vector3.new(7.8, 5.6, 15.8),
		WheelRadius = 1.8,
		WheelWidth = 1.1,
		SuspensionHeight = 1.6,
		PrimaryColor = Color3.fromRGB(40, 175, 95),
		Color = Color3.fromRGB(40, 175, 95),
		SecondaryColor = Color3.fromRGB(30, 35, 40),
		AccentColor = Color3.fromRGB(140, 245, 170),
	},

	Sports = {
		Id = "Sports",
		Class = "Sports",
		Name = "Supercar",
		DisplayName = "Apex GT",
		Description = "Low-slung twin-turbo supercar. Blistering top speed for massive high-velocity impact multipliers!",
		Order = 6,
		Tier = 6,
		Cost = 9500,
		Price = 9500,
		UnlockCost = 9500,
		TopSpeed = 82,
		MaxSpeed = 82,
		ReverseSpeed = 30,
		Acceleration = 36,
		Accel = 36,
		Braking = 98,
		BrakeForce = 98,
		TurnSpeed = 2.6,
		SteerSpeed = 2.6,
		Handling = 0.95,
		DriftFactor = 0.90,
		Grip = 0.92,
		Mass = 1420,
		Weight = 1420,
		MaxHealth = 150,
		Health = 150,
		Armor = 1.15,
		DamageMultiplier = 1.75,
		SmashPower = 1.75,
		RamDamage = 42,
		NitroMultiplier = 1.80,
		BoostMultiplier = 1.80,
		NitroDuration = 3.5,
		BoostDuration = 3.5,
		NitroCooldown = 3.8,
		BoostCooldown = 3.8,
		Size = Vector3.new(7.4, 3.6, 14.8),
		WheelRadius = 1.5,
		WheelWidth = 1.05,
		SuspensionHeight = 1.0,
		PrimaryColor = Color3.fromRGB(255, 205, 25),
		Color = Color3.fromRGB(255, 205, 25),
		SecondaryColor = Color3.fromRGB(20, 22, 28),
		AccentColor = Color3.fromRGB(255, 95, 35),
	},

	MonsterTruck = {
		Id = "MonsterTruck",
		Class = "MonsterTruck",
		Name = "Monster Truck",
		DisplayName = "Crusher XL",
		Description = "Towering monster truck on giant tires. Crushes kiosks, billboards, and police interceptors with ease!",
		Order = 7,
		Tier = 7,
		Cost = 18000,
		Price = 18000,
		UnlockCost = 18000,
		TopSpeed = 60,
		MaxSpeed = 60,
		ReverseSpeed = 26,
		Acceleration = 29,
		Accel = 29,
		Braking = 82,
		BrakeForce = 82,
		TurnSpeed = 2.1,
		SteerSpeed = 2.1,
		Handling = 0.78,
		DriftFactor = 0.72,
		Grip = 0.85,
		Mass = 3800,
		Weight = 3800,
		MaxHealth = 320,
		Health = 320,
		Armor = 1.85,
		DamageMultiplier = 2.60,
		SmashPower = 2.60,
		RamDamage = 75,
		NitroMultiplier = 1.68,
		BoostMultiplier = 1.68,
		NitroDuration = 3.6,
		BoostDuration = 3.6,
		NitroCooldown = 4.2,
		BoostCooldown = 4.2,
		Size = Vector3.new(10.2, 8.2, 17.5),
		WheelRadius = 3.1,
		WheelWidth = 2.2,
		SuspensionHeight = 2.8,
		PrimaryColor = Color3.fromRGB(165, 55, 255),
		Color = Color3.fromRGB(165, 55, 255),
		SecondaryColor = Color3.fromRGB(35, 255, 130),
		AccentColor = Color3.fromRGB(255, 230, 50),
	},

	Tank = {
		Id = "Tank",
		Class = "Tank",
		Name = "Demolition Tank",
		DisplayName = "Rampage Dozer",
		Description = "Ultimate armored juggernaut. Unstoppable mass that flattens anything standing in Leo City!",
		Order = 8,
		Tier = 8,
		Cost = 40000,
		Price = 40000,
		UnlockCost = 40000,
		TopSpeed = 50,
		MaxSpeed = 50,
		ReverseSpeed = 22,
		Acceleration = 24,
		Accel = 24,
		Braking = 95,
		BrakeForce = 95,
		TurnSpeed = 1.95,
		SteerSpeed = 1.95,
		Handling = 0.82,
		DriftFactor = 0.50,
		Grip = 0.96,
		Mass = 6500,
		Weight = 6500,
		MaxHealth = 500,
		Health = 500,
		Armor = 2.50,
		DamageMultiplier = 4.00,
		SmashPower = 4.00,
		RamDamage = 120,
		NitroMultiplier = 1.55,
		BoostMultiplier = 1.55,
		NitroDuration = 4.0,
		BoostDuration = 4.0,
		NitroCooldown = 4.5,
		BoostCooldown = 4.5,
		Size = Vector3.new(11.0, 7.6, 19.5),
		WheelRadius = 2.2,
		WheelWidth = 1.8,
		SuspensionHeight = 1.6,
		PrimaryColor = Color3.fromRGB(75, 95, 65),
		Color = Color3.fromRGB(75, 95, 65),
		SecondaryColor = Color3.fromRGB(45, 52, 42),
		AccentColor = Color3.fromRGB(255, 185, 40),
	},
} :: { [string]: Types.VehicleConfigData }

-- Convenient cross-module aliases
GameConfig.Vehicles.Bulldozer = GameConfig.Vehicles.Tank
GameConfig.Vehicles.ArmoredTank = GameConfig.Vehicles.Tank
GameConfig.Vehicles.Hatchback = GameConfig.Vehicles.Compact
GameConfig.VehicleClasses = GameConfig.Vehicles

function GameConfig.GetVehicle(arg1: any, arg2: any): Types.VehicleConfigData
	local classId = if type(arg1) == "table" then tostring(arg2 or "Compact") else tostring(arg1 or "Compact")
	return GameConfig.Vehicles[classId] or GameConfig.Vehicles.Compact
end

--------------------------------------------------------------------------------
-- 2. DESTRUCTIBLE OBJECT TIERS
--------------------------------------------------------------------------------

GameConfig.DestructibleOrder = {
	"Hydrant",
	"Fence",
	"StreetLight",
	"Crate",
	"BusStop",
	"Kiosk",
	"Billboard",
	"GasPump",
} :: { Types.DestructibleTierId }

GameConfig.Destructibles = {
	Hydrant = {
		Id = "Hydrant",
		Type = "Hydrant",
		Name = "Fire Hydrant",
		DisplayName = "Fire Hydrant",
		Tier = 1,
		MaxHealth = 20,
		Health = 20,
		HP = 20,
		MinImpactSpeed = 12,
		SmashSpeed = 12,
		CashReward = 25,
		CoinReward = 25,
		Reward = 25,
		BaseReward = 25,
		Points = 25,
		HeatGenerated = 6,
		Heat = 6,
		VehicleDamage = 2,
		CarDamage = 2,
		RespawnTime = 20,
		DebrisCount = 5,
		FragmentCount = 5,
		DebrisColor = Color3.fromRGB(220, 40, 40),
		Color = Color3.fromRGB(220, 40, 40),
		AccentColor = Color3.fromRGB(230, 230, 235),
		Material = Enum.Material.Metal,
		Size = Vector3.new(1.8, 3.2, 1.8),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = true,
	},

	Fence = {
		Id = "Fence",
		Type = "Fence",
		Name = "Wooden Fence",
		DisplayName = "Perimeter Fence",
		Tier = 1,
		MaxHealth = 18,
		Health = 18,
		HP = 18,
		MinImpactSpeed = 10,
		SmashSpeed = 10,
		CashReward = 20,
		CoinReward = 20,
		Reward = 20,
		BaseReward = 20,
		Points = 20,
		HeatGenerated = 4,
		Heat = 4,
		VehicleDamage = 1,
		CarDamage = 1,
		RespawnTime = 18,
		DebrisCount = 6,
		FragmentCount = 6,
		DebrisColor = Color3.fromRGB(175, 125, 75),
		Color = Color3.fromRGB(175, 125, 75),
		AccentColor = Color3.fromRGB(140, 95, 55),
		Material = Enum.Material.WoodPlanks,
		Size = Vector3.new(8.0, 3.6, 1.0),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	Crate = {
		Id = "Crate",
		Type = "Crate",
		Name = "Supply Crate",
		DisplayName = "Supply Crate",
		Tier = 1,
		MaxHealth = 25,
		Health = 25,
		HP = 25,
		MinImpactSpeed = 10,
		SmashSpeed = 10,
		CashReward = 30,
		CoinReward = 30,
		Reward = 30,
		BaseReward = 30,
		Points = 30,
		HeatGenerated = 5,
		Heat = 5,
		VehicleDamage = 2,
		CarDamage = 2,
		RespawnTime = 20,
		DebrisCount = 7,
		FragmentCount = 7,
		DebrisColor = Color3.fromRGB(205, 145, 70),
		Color = Color3.fromRGB(205, 145, 70),
		AccentColor = Color3.fromRGB(155, 100, 45),
		Material = Enum.Material.Wood,
		Size = Vector3.new(3.8, 3.8, 3.8),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	StreetLight = {
		Id = "StreetLight",
		Type = "StreetLight",
		Name = "Street Light",
		DisplayName = "Street Lamp Post",
		Tier = 2,
		MaxHealth = 45,
		Health = 45,
		HP = 45,
		MinImpactSpeed = 18,
		SmashSpeed = 18,
		CashReward = 45,
		CoinReward = 45,
		Reward = 45,
		BaseReward = 45,
		Points = 45,
		HeatGenerated = 10,
		Heat = 10,
		VehicleDamage = 4,
		CarDamage = 4,
		RespawnTime = 25,
		DebrisCount = 6,
		FragmentCount = 6,
		DebrisColor = Color3.fromRGB(85, 92, 102),
		Color = Color3.fromRGB(85, 92, 102),
		AccentColor = Color3.fromRGB(255, 240, 175),
		Material = Enum.Material.Metal,
		Size = Vector3.new(2.2, 16.0, 4.0),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	BusStop = {
		Id = "BusStop",
		Type = "BusStop",
		Name = "Bus Stop Shelter",
		DisplayName = "Transit Shelter",
		Tier = 2,
		MaxHealth = 75,
		Health = 75,
		HP = 75,
		MinImpactSpeed = 24,
		SmashSpeed = 24,
		CashReward = 80,
		CoinReward = 80,
		Reward = 80,
		BaseReward = 80,
		Points = 80,
		HeatGenerated = 16,
		Heat = 16,
		VehicleDamage = 7,
		CarDamage = 7,
		RespawnTime = 30,
		DebrisCount = 10,
		FragmentCount = 10,
		DebrisColor = Color3.fromRGB(145, 210, 245),
		Color = Color3.fromRGB(65, 130, 195),
		AccentColor = Color3.fromRGB(180, 230, 255),
		Material = Enum.Material.Glass,
		Size = Vector3.new(10.0, 8.0, 5.0),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	Kiosk = {
		Id = "Kiosk",
		Type = "Kiosk",
		Name = "Street Kiosk",
		DisplayName = "Snack Kiosk",
		Tier = 3,
		MaxHealth = 110,
		Health = 110,
		HP = 110,
		MinImpactSpeed = 28,
		SmashSpeed = 28,
		CashReward = 120,
		CoinReward = 120,
		Reward = 120,
		BaseReward = 120,
		Points = 120,
		HeatGenerated = 22,
		Heat = 22,
		VehicleDamage = 10,
		CarDamage = 10,
		RespawnTime = 35,
		DebrisCount = 12,
		FragmentCount = 12,
		DebrisColor = Color3.fromRGB(245, 115, 45),
		Color = Color3.fromRGB(245, 115, 45),
		AccentColor = Color3.fromRGB(255, 225, 95),
		Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(8.5, 9.5, 8.5),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	Billboard = {
		Id = "Billboard",
		Type = "Billboard",
		Name = "Roadside Billboard",
		DisplayName = "Mega Billboard",
		Tier = 3,
		MaxHealth = 140,
		Health = 140,
		HP = 140,
		MinImpactSpeed = 34,
		SmashSpeed = 34,
		CashReward = 160,
		CoinReward = 160,
		Reward = 160,
		BaseReward = 160,
		Points = 160,
		HeatGenerated = 28,
		Heat = 28,
		VehicleDamage = 13,
		CarDamage = 13,
		RespawnTime = 40,
		DebrisCount = 14,
		FragmentCount = 14,
		DebrisColor = Color3.fromRGB(240, 200, 50),
		Color = Color3.fromRGB(55, 60, 72),
		AccentColor = Color3.fromRGB(255, 85, 145),
		Material = Enum.Material.Metal,
		Size = Vector3.new(16.0, 18.0, 3.5),
		Explosive = false,
		IsExplosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		WaterGeyser = false,
	},

	GasPump = {
		Id = "GasPump",
		Type = "GasPump",
		Name = "Fuel Pump",
		DisplayName = "Fuel Station Pump",
		Tier = 4,
		MaxHealth = 60,
		Health = 60,
		HP = 60,
		MinImpactSpeed = 20,
		SmashSpeed = 20,
		CashReward = 200,
		CoinReward = 200,
		Reward = 200,
		BaseReward = 200,
		Points = 200,
		HeatGenerated = 40,
		Heat = 40,
		VehicleDamage = 18,
		CarDamage = 18,
		RespawnTime = 45,
		DebrisCount = 14,
		FragmentCount = 14,
		DebrisColor = Color3.fromRGB(240, 60, 40),
		Color = Color3.fromRGB(240, 60, 40),
		AccentColor = Color3.fromRGB(255, 215, 55),
		Material = Enum.Material.Metal,
		Size = Vector3.new(4.2, 7.2, 2.8),
		Explosive = true,
		IsExplosive = true,
		ExplosionRadius = 32,
		ExplosionDamage = 85,
		WaterGeyser = false,
	},
} :: { [string]: Types.DestructibleConfigData }

GameConfig.DestructibleTiers = GameConfig.Destructibles
GameConfig.DestructibleObjects = GameConfig.Destructibles

function GameConfig.GetDestructible(arg1: any, arg2: any): Types.DestructibleConfigData
	local tierId = if type(arg1) == "table" then tostring(arg2 or "Crate") else tostring(arg1 or "Crate")
	return GameConfig.Destructibles[tierId] or GameConfig.Destructibles.Crate
end

--------------------------------------------------------------------------------
-- 3. COMBO WINDOW & MULTIPLIER THRESHOLDS
--------------------------------------------------------------------------------

GameConfig.Combo = {
	Window = 3.5,
	TimeWindow = 3.5,
	DecayTime = 3.5,
	Duration = 3.5,
	MaxMultiplier = 20,
	CompletionBonusRatio = 0.25,
	CompletionBonus = 0.25,
	Thresholds = {
		{
			MinHits = 1,
			Hits = 1,
			Chain = 1,
			Multiplier = 1,
			Label = "SMASH!",
			Name = "SMASH!",
			Color = Color3.fromRGB(255, 255, 255),
		},
		{
			MinHits = 3,
			Hits = 3,
			Chain = 3,
			Multiplier = 2,
			Label = "DOUBLE SMASH!",
			Name = "DOUBLE SMASH!",
			Color = Color3.fromRGB(255, 230, 80),
		},
		{
			MinHits = 5,
			Hits = 5,
			Chain = 5,
			Multiplier = 3,
			Label = "RAMPAGE!",
			Name = "RAMPAGE!",
			Color = Color3.fromRGB(255, 175, 45),
		},
		{
			MinHits = 8,
			Hits = 8,
			Chain = 8,
			Multiplier = 5,
			Label = "DESTRUCTION SPREE!",
			Name = "DESTRUCTION SPREE!",
			Color = Color3.fromRGB(255, 110, 40),
		},
		{
			MinHits = 12,
			Hits = 12,
			Chain = 12,
			Multiplier = 8,
			Label = "UNSTOPPABLE!",
			Name = "UNSTOPPABLE!",
			Color = Color3.fromRGB(255, 60, 60),
		},
		{
			MinHits = 18,
			Hits = 18,
			Chain = 18,
			Multiplier = 12,
			Label = "MEGA CHAOS!",
			Name = "MEGA CHAOS!",
			Color = Color3.fromRGB(240, 55, 185),
		},
		{
			MinHits = 25,
			Hits = 25,
			Chain = 25,
			Multiplier = 20,
			Label = "WORLD OF DESTRUCTION!",
			Name = "WORLD OF DESTRUCTION!",
			Color = Color3.fromRGB(175, 85, 255),
		},
	} :: { Types.ComboThreshold },
}

GameConfig.ComboWindow = GameConfig.Combo.Window

function GameConfig.GetComboThreshold(arg1: any, arg2: any): Types.ComboThreshold
	local chain = if type(arg1) == "table" then (tonumber(arg2) or 0) else (tonumber(arg1) or 0)
	local active = GameConfig.Combo.Thresholds[1]
	for _, entry in ipairs(GameConfig.Combo.Thresholds) do
		if chain >= entry.MinHits then
			active = entry
		else
			break
		end
	end
	return active
end

function GameConfig.GetComboMultiplier(arg1: any, arg2: any): number
	local chain = if type(arg1) == "table" then (tonumber(arg2) or 0) else (tonumber(arg1) or 0)
	if chain <= 0 then
		return 1
	end
	return GameConfig.GetComboThreshold(chain).Multiplier
end

--------------------------------------------------------------------------------
-- 4. 5-STAR POLICE HEAT THRESHOLDS & UNIT CONFIGS
--------------------------------------------------------------------------------

GameConfig.Police = {
	MaxStars = 5,
	MaxWantedLevel = 5,
	MaxHeat = 1000,
	DecayDelay = 6.0,
	CooldownDelay = 6.0,
	GracePeriod = 6.0,
	DecayRate = 18.0,
	EscapeDistance = 220,
	EscapeTime = 7.5,
	BustDistance = 14.0,
	CatchDistance = 14.0,
	BustSpeedThreshold = 20.0,
	BustTime = 1.6,
	CatchFillTime = 1.6,
	BustDecayRate = 2.0,
	BustPenaltyRatio = 0.20,
	FineRatio = 0.20,
	MaxBustFine = 2500,
	SpawnMinDistance = 140,
	SpawnMaxDistance = 220,
	DespawnDistance = 380,
	WarningDelay = 1.5,
	CopWreckReward = 250,
	CopWreckHeatRelief = 45,

	StarThresholds = {
		[1] = 50,
		[2] = 160,
		[3] = 340,
		[4] = 580,
		[5] = 850,
	},

	Stars = {
		[1] = {
			Star = 1,
			Level = 1,
			Threshold = 50,
			HeatRequired = 50,
			Name = "Patrol Alert",
			MaxUnits = 1,
			SpawnInterval = 6.0,
			UnitTypes = { "Cruiser" },
			SpeedMultiplier = 1.00,
			Aggression = 0.50,
		},
		[2] = {
			Star = 2,
			Level = 2,
			Threshold = 160,
			HeatRequired = 160,
			Name = "Active Pursuit",
			MaxUnits = 2,
			SpawnInterval = 5.0,
			UnitTypes = { "Cruiser" },
			SpeedMultiplier = 1.06,
			Aggression = 0.65,
		},
		[3] = {
			Star = 3,
			Level = 3,
			Threshold = 340,
			HeatRequired = 340,
			Name = "Highway Interceptors",
			MaxUnits = 3,
			SpawnInterval = 4.2,
			UnitTypes = { "Cruiser", "Interceptor" },
			SpeedMultiplier = 1.12,
			Aggression = 0.80,
		},
		[4] = {
			Star = 4,
			Level = 4,
			Threshold = 580,
			HeatRequired = 580,
			Name = "SWAT Tactical Response",
			MaxUnits = 4,
			SpawnInterval = 3.5,
			UnitTypes = { "Interceptor", "SWATVan" },
			SpeedMultiplier = 1.18,
			Aggression = 0.92,
		},
		[5] = {
			Star = 5,
			Level = 5,
			Threshold = 850,
			HeatRequired = 850,
			Name = "Maximum Wanted",
			MaxUnits = 5,
			SpawnInterval = 2.8,
			UnitTypes = { "Interceptor", "SWATVan", "Enforcer" },
			SpeedMultiplier = 1.25,
			Aggression = 1.00,
		},
	} :: { [number]: Types.PoliceStarConfig },

	Units = {
		Cruiser = {
			Id = "Cruiser",
			Name = "Police Cruiser",
			TopSpeed = 92,
			MaxSpeed = 92,
			Acceleration = 54,
			TurnSpeed = 2.35,
			MaxHealth = 110,
			Health = 110,
			Mass = 1450,
			RamDamage = 14,
			CashReward = 200,
			HeatRelief = 35,
			Size = Vector3.new(6.8, 4.4, 14.0),
			Color = Color3.fromRGB(240, 244, 250),
			StripeColor = Color3.fromRGB(25, 55, 145),
		},
		Interceptor = {
			Id = "Interceptor",
			Name = "Police Interceptor",
			TopSpeed = 116,
			MaxSpeed = 116,
			Acceleration = 70,
			TurnSpeed = 2.75,
			MaxHealth = 135,
			Health = 135,
			Mass = 1550,
			RamDamage = 20,
			CashReward = 325,
			HeatRelief = 45,
			Size = Vector3.new(7.2, 4.0, 14.6),
			Color = Color3.fromRGB(22, 28, 42),
			StripeColor = Color3.fromRGB(65, 145, 255),
		},
		SWATVan = {
			Id = "SWATVan",
			Name = "SWAT Armored Van",
			TopSpeed = 84,
			MaxSpeed = 84,
			Acceleration = 46,
			TurnSpeed = 1.90,
			MaxHealth = 260,
			Health = 260,
			Mass = 3200,
			RamDamage = 34,
			CashReward = 500,
			HeatRelief = 60,
			Size = Vector3.new(8.4, 7.2, 17.5),
			Color = Color3.fromRGB(28, 36, 52),
			StripeColor = Color3.fromRGB(180, 195, 215),
		},
		Enforcer = {
			Id = "Enforcer",
			Name = "Heavy Enforcer",
			TopSpeed = 98,
			MaxSpeed = 98,
			Acceleration = 58,
			TurnSpeed = 2.05,
			MaxHealth = 380,
			Health = 380,
			Mass = 4600,
			RamDamage = 48,
			CashReward = 750,
			HeatRelief = 80,
			Size = Vector3.new(9.4, 6.8, 18.8),
			Color = Color3.fromRGB(18, 20, 26),
			StripeColor = Color3.fromRGB(235, 50, 50),
		},
	} :: { [string]: Types.PoliceUnitConfig },
}

GameConfig.Police.UnitConfigs = GameConfig.Police.Units
GameConfig.Heat = GameConfig.Police

function GameConfig.GetStarsForHeat(arg1: any, arg2: any): number
	local heat = if type(arg1) == "table" then (tonumber(arg2) or 0) else (tonumber(arg1) or 0)
	local stars = 0
	for level = 1, GameConfig.Police.MaxStars do
		local threshold = GameConfig.Police.StarThresholds[level]
		if heat >= threshold then
			stars = level
		else
			break
		end
	end
	return stars
end

--------------------------------------------------------------------------------
-- 5. GARAGE UPGRADE LEVELS & COSTS
--------------------------------------------------------------------------------

GameConfig.UpgradeOrder = {
	"Engine",
	"Armor",
	"Nitro",
	"Plow",
	"CashMagnet",
} :: { Types.UpgradeTrackId }

GameConfig.Upgrades = {
	MaxLevel = 5,
	DefaultCosts = { 400, 900, 1800, 3200, 5500 },

	Engine = {
		Id = "Engine",
		Name = "Engine Tune",
		DisplayName = "Twin-Turbo Engine",
		Description = "Increases top speed and acceleration by +8% per level.",
		StatLabel = "Top Speed & Accel",
		Icon = "⚡",
		MaxLevel = 5,
		Costs = { 400, 900, 1800, 3200, 5500 },
		BonusPerLevel = 0.08,
		Multipliers = { [0] = 1.0, [1] = 1.08, [2] = 1.16, [3] = 1.24, [4] = 1.32, [5] = 1.40 },
		Values = { 1.08, 1.16, 1.24, 1.32, 1.40 },
	},

	Armor = {
		Id = "Armor",
		Name = "Reinforced Chassis",
		DisplayName = "Heavy Rollcage & Armor",
		Description = "Increases max vehicle health and reduces crash damage by +12% per level.",
		StatLabel = "Chassis Durability",
		Icon = "🛡️",
		MaxLevel = 5,
		Costs = { 400, 900, 1800, 3200, 5500 },
		BonusPerLevel = 0.12,
		Multipliers = { [0] = 1.0, [1] = 1.12, [2] = 1.24, [3] = 1.36, [4] = 1.48, [5] = 1.60 },
		Values = { 1.12, 1.24, 1.36, 1.48, 1.60 },
	},

	Nitro = {
		Id = "Nitro",
		Name = "Nitro Boost",
		DisplayName = "Nitrous Oxide System",
		Description = "Increases boost power and duration by +12% per level.",
		StatLabel = "Boost Power & Time",
		Icon = "🔥",
		MaxLevel = 5,
		Costs = { 400, 900, 1800, 3200, 5500 },
		BonusPerLevel = 0.12,
		Multipliers = { [0] = 1.0, [1] = 1.12, [2] = 1.24, [3] = 1.36, [4] = 1.48, [5] = 1.60 },
		Values = { 1.12, 1.24, 1.36, 1.48, 1.60 },
	},

	Plow = {
		Id = "Plow",
		Name = "Demolition Plow",
		DisplayName = "Wrecking Ram Bumper",
		Description = "Increases impact damage dealt to destructibles and police by +15% per level.",
		StatLabel = "Smash Damage",
		Icon = "💥",
		MaxLevel = 5,
		Costs = { 400, 900, 1800, 3200, 5500 },
		BonusPerLevel = 0.15,
		Multipliers = { [0] = 1.0, [1] = 1.15, [2] = 1.30, [3] = 1.45, [4] = 1.60, [5] = 1.75 },
		Values = { 1.15, 1.30, 1.45, 1.60, 1.75 },
	},

	CashMagnet = {
		Id = "CashMagnet",
		Name = "Cash Magnet",
		DisplayName = "Destruction Coin Multiplier",
		Description = "Increases all destruction cash rewards by +15% per level.",
		StatLabel = "Cash Bonus",
		Icon = "💰",
		MaxLevel = 5,
		Costs = { 400, 900, 1800, 3200, 5500 },
		BonusPerLevel = 0.15,
		Multipliers = { [0] = 1.0, [1] = 1.15, [2] = 1.30, [3] = 1.45, [4] = 1.60, [5] = 1.75 },
		Values = { 1.15, 1.30, 1.45, 1.60, 1.75 },
	},
}

-- Alias `Magnet` -> `CashMagnet` for scripts using short track names
GameConfig.Upgrades.Magnet = GameConfig.Upgrades.CashMagnet
GameConfig.GarageUpgrades = GameConfig.Upgrades

function GameConfig.GetUpgradeCost(arg1: any, arg2: any, arg3: any): number?
	local trackId: string
	local currentLevel: number
	if type(arg1) == "table" then
		trackId = tostring(arg2 or "Engine")
		currentLevel = tonumber(arg3) or 0
	else
		trackId = tostring(arg1 or "Engine")
		currentLevel = tonumber(arg2) or 0
	end
	local track = (GameConfig.Upgrades :: any)[trackId]
	if not track or type(track) ~= "table" or not track.Costs then
		return nil
	end
	if currentLevel >= track.MaxLevel then
		return nil
	end
	return track.Costs[currentLevel + 1]
end

function GameConfig.GetUpgradeMultiplier(arg1: any, arg2: any, arg3: any): number
	local trackId: string
	local level: number
	if type(arg1) == "table" then
		trackId = tostring(arg2 or "Engine")
		level = tonumber(arg3) or 0
	else
		trackId = tostring(arg1 or "Engine")
		level = tonumber(arg2) or 0
	end
	local track = (GameConfig.Upgrades :: any)[trackId]
	if not track or type(track) ~= "table" then
		return 1.0
	end
	local clamped = math.clamp(level or 0, 0, track.MaxLevel or 5)
	if track.Multipliers and track.Multipliers[clamped] then
		return track.Multipliers[clamped]
	end
	return 1.0 + (track.BonusPerLevel or 0.1) * clamped
end

--------------------------------------------------------------------------------
-- 6. LEO CITY LAYOUT CONSTANTS
--------------------------------------------------------------------------------

GameConfig.City = {
	Name = "Leo City",
	GridRadius = 3, -- 7x7 city block grid (-3..3) around Leo Plaza
	GridBlocksPerSide = 7,
	BlockSize = 180, -- Studs between intersection centers (lot + road)
	LotSize = 140, -- Buildable block interior size in studs
	RoadWidth = 40, -- Two-lane avenue width in studs
	SidewalkWidth = 7, -- Raised sidewalk rim around each lot
	SidewalkHeight = 0.6,
	WorldExtent = 1600, -- Total baseplate extent in studs
	SpawnPosition = Vector3.new(0, 4, 24),
	VehicleSpawnOffset = Vector3.new(0, 3.5, 0),
	GaragePosition = Vector3.new(0, 2, -25),
	SpeedShopPosition = Vector3.new(180, 2, -180),
	SafeHousePosition = Vector3.new(-180, 2, 180),
	SafeHouseClearRadius = 34,
	MechanicHealRadius = 26,
	RepairCooldown = 5.0,
	AutoTowFee = 150,
	TrafficCount = 16,
	PropsPerBlock = 10,
	RampCount = 12,
	StuntAirTimeThreshold = 0.85,
	StuntCashBonus = 75,

	Districts = {
		Plaza = {
			Id = "Plaza",
			Name = "Leo Plaza",
			GroundColor = Color3.fromRGB(185, 182, 175),
			MinBuildingHeight = 25,
			MaxBuildingHeight = 45,
			PropWeights = { Hydrant = 2, StreetLight = 3, BusStop = 2, Kiosk = 3, Fence = 2 },
		},
		Downtown = {
			Id = "Downtown",
			Name = "Downtown Core",
			GroundColor = Color3.fromRGB(145, 148, 155),
			MinBuildingHeight = 65,
			MaxBuildingHeight = 155,
			PropWeights = { Hydrant = 3, StreetLight = 4, BusStop = 3, Billboard = 3, Kiosk = 3, Crate = 2 },
		},
		Suburbs = {
			Id = "Suburbs",
			Name = "Sunny Suburbs",
			GroundColor = Color3.fromRGB(105, 168, 92),
			MinBuildingHeight = 18,
			MaxBuildingHeight = 36,
			PropWeights = { Fence = 5, Hydrant = 3, StreetLight = 3, BusStop = 2, Crate = 2 },
		},
		Industrial = {
			Id = "Industrial",
			Name = "Industrial Yard",
			GroundColor = Color3.fromRGB(132, 126, 118),
			MinBuildingHeight = 28,
			MaxBuildingHeight = 60,
			PropWeights = { Crate = 5, GasPump = 3, Billboard = 3, Fence = 3, Hydrant = 2, StreetLight = 2 },
		},
		Park = {
			Id = "Park",
			Name = "Central Stunt Park",
			GroundColor = Color3.fromRGB(78, 162, 74),
			MinBuildingHeight = 0,
			MaxBuildingHeight = 16,
			PropWeights = { Fence = 4, Kiosk = 3, StreetLight = 3, Crate = 3, Hydrant = 2 },
		},
	},

	Landmarks = {
		LeoPlaza = {
			Name = "Leo Plaza & Garage",
			GridX = 0,
			GridZ = 0,
			Position = Vector3.new(0, 0, 0),
			Description = "Central plaza featuring the Mechanic Garage, fountain, and starter ramps.",
		},
		LeoTower = {
			Name = "Leo Tower",
			GridX = 1,
			GridZ = 1,
			Position = Vector3.new(180, 0, 180),
			Description = "Sky-piercing glass headquarters in the heart of Downtown.",
		},
		SpeedShop = {
			Name = "Speed Shop Showroom",
			GridX = 1,
			GridZ = -1,
			Position = Vector3.new(180, 0, -180),
			Description = "Upgrade your vehicle's Engine, Armor, Nitro, Plow, and Cash Magnet.",
		},
		FuelDepot = {
			Name = "Octane Fuel Station",
			GridX = -1,
			GridZ = -1,
			Position = Vector3.new(-180, 0, -180),
			Description = "Explosive gas pumps for huge chain-reaction combos!",
		},
		SafeHouse = {
			Name = "Hideout Garage",
			GridX = -1,
			GridZ = 1,
			Position = Vector3.new(-180, 0, 180),
			Description = "Drive inside the glowing green bay to instantly lose a police pursuit!",
		},
		StuntArena = {
			Name = "Mega Ramp Park",
			GridX = -2,
			GridZ = 0,
			Position = Vector3.new(-360, 0, 0),
			Description = "High-flying stunt ramps, smash rings, and crate pyramids.",
		},
	},
}

GameConfig.LeoCity = GameConfig.City
GameConfig.World = GameConfig.City

--------------------------------------------------------------------------------
-- 7. ECONOMY DEFAULTS
--------------------------------------------------------------------------------

GameConfig.Economy = {
	StartingCash = 500,
	BigJumpMinAirTime = 0.85,
	BigJumpReward = 75,
	DriftMinDuration = 1.0,
	DriftRewardPerSecond = 25,
	CopWreckReward = 250,
}

return GameConfig
