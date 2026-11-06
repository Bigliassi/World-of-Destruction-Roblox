--!strict
--[[
	Types.luau
	Shared Luau type definitions for World of Destruction (Roblox Edition).
]]

export type VehicleClass =
	"Compact"
	| "Sedan"
	| "Muscle"
	| "SUV"
	| "Sports"
	| "Pickup"
	| "MonsterTruck"
	| "Tank"

export type DestructibleTierId =
	"Hydrant"
	| "Fence"
	| "StreetLight"
	| "Crate"
	| "Billboard"
	| "BusStop"
	| "GasPump"
	| "Kiosk"

export type UpgradeTrackId =
	"Engine"
	| "Armor"
	| "Nitro"
	| "Plow"
	| "CashMagnet"

export type PoliceUnitType =
	"Cruiser"
	| "Interceptor"
	| "SWATVan"
	| "Enforcer"

export type DistrictId =
	"Plaza"
	| "Downtown"
	| "Suburbs"
	| "Industrial"
	| "Park"

export type VehicleConfigData = {
	Id: VehicleClass,
	Class: VehicleClass,
	Name: string,
	DisplayName: string,
	Description: string,
	Order: number,
	Tier: number,
	Cost: number,
	Price: number,
	UnlockCost: number,
	TopSpeed: number,
	MaxSpeed: number,
	ReverseSpeed: number,
	Acceleration: number,
	Accel: number,
	Braking: number,
	BrakeForce: number,
	TurnSpeed: number,
	SteerSpeed: number,
	Handling: number,
	DriftFactor: number,
	Grip: number,
	Mass: number,
	Weight: number,
	MaxHealth: number,
	Health: number,
	Armor: number,
	DamageMultiplier: number,
	SmashPower: number,
	RamDamage: number,
	NitroMultiplier: number,
	BoostMultiplier: number,
	NitroDuration: number,
	BoostDuration: number,
	NitroCooldown: number,
	BoostCooldown: number,
	Size: Vector3,
	WheelRadius: number,
	WheelWidth: number,
	SuspensionHeight: number,
	PrimaryColor: Color3,
	Color: Color3,
	SecondaryColor: Color3,
	AccentColor: Color3,
}

export type DestructibleConfigData = {
	Id: DestructibleTierId | string,
	Type: DestructibleTierId | string,
	Name: string,
	DisplayName: string,
	Tier: number,
	MaxHealth: number,
	Health: number,
	HP: number,
	MinImpactSpeed: number,
	SmashSpeed: number,
	CashReward: number,
	CoinReward: number,
	Reward: number,
	BaseReward: number,
	Points: number,
	HeatGenerated: number,
	Heat: number,
	VehicleDamage: number,
	CarDamage: number,
	RespawnTime: number,
	DebrisCount: number,
	FragmentCount: number,
	DebrisColor: Color3,
	Color: Color3,
	AccentColor: Color3,
	Material: Enum.Material,
	Size: Vector3,
	Explosive: boolean,
	IsExplosive: boolean,
	ExplosionRadius: number,
	ExplosionDamage: number,
	WaterGeyser: boolean,
}

export type ComboThreshold = {
	MinHits: number,
	Hits: number,
	Chain: number,
	Multiplier: number,
	Label: string,
	Name: string,
	Color: Color3,
}

export type PoliceStarConfig = {
	Star: number,
	Level: number,
	Threshold: number,
	HeatRequired: number,
	Name: string,
	MaxUnits: number,
	SpawnInterval: number,
	UnitTypes: { PoliceUnitType },
	SpeedMultiplier: number,
	Aggression: number,
}

export type PoliceUnitConfig = {
	Id: PoliceUnitType,
	Name: string,
	TopSpeed: number,
	MaxSpeed: number,
	Acceleration: number,
	TurnSpeed: number,
	MaxHealth: number,
	Health: number,
	Mass: number,
	RamDamage: number,
	CashReward: number,
	HeatRelief: number,
	Size: Vector3,
	Color: Color3,
	StripeColor: Color3,
}

export type UpgradeTrackConfig = {
	Id: UpgradeTrackId,
	Name: string,
	DisplayName: string,
	Description: string,
	StatLabel: string,
	Icon: string,
	MaxLevel: number,
	Costs: { number },
	BonusPerLevel: number,
	Multipliers: { [number]: number },
	Values: { number },
}

export type UpgradeLevels = {
	Engine: number,
	Armor: number,
	Nitro: number,
	Plow: number,
	CashMagnet: number,
}

export type PlayerProfileData = {
	Cash: number,
	LifetimeCash: number,
	TotalDestructions: number,
	BestComboChain: number,
	PoliceWrecked: number,
	SelectedVehicle: VehicleClass,
	OwnedVehicles: { [string]: boolean },
	Upgrades: UpgradeLevels,
}

export type ComboStatePayload = {
	Chain: number,
	Hits: number,
	Multiplier: number,
	ComboCash: number,
	TimeRemaining: number,
	Window: number,
	Label: string,
	Completed: boolean?,
	BonusAwarded: number?,
}

export type DamageDealtPayload = {
	ObjectName: string,
	ObjectType: string,
	Damage: number,
	RemainingHealth: number,
	MaxHealth: number,
	Destroyed: boolean,
	CashEarned: number,
	Multiplier: number,
	Position: Vector3,
	Explosive: boolean?,
}

export type HeatStatePayload = {
	Heat: number,
	MaxHeat: number,
	Stars: number,
	WantedLevel: number,
	ActiveUnits: number,
	BustProgress: number,
	InPursuit: boolean,
	Escaping: boolean?,
}

export type VehicleStatePayload = {
	VehicleClass: VehicleClass,
	VehicleName: string,
	Health: number,
	MaxHealth: number,
	TopSpeed: number,
	NitroDuration: number,
	NitroCooldown: number,
	Model: Model?,
}

export type NotificationPayload = {
	Title: string?,
	Message: string,
	Text: string?,
	Category: ("Info" | "Success" | "Warning" | "Danger" | "Reward" | "Police" | "Combo")?,
	Color: Color3?,
	Duration: number?,
}

local Types = {}

return Types
