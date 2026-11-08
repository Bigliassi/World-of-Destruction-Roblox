--!strict
--[[
	MissionService.script.luau
	World of Destruction (Roblox)

	Main & Side Missions Engine across all Manhattan Landmarks:
	- Creates ReplicatedStorage.Remotes:
	    * SelectMission (RemoteEvent)
	    * TeleportToMission (RemoteEvent)
	    * MissionStateUpdated (RemoteEvent)
	- 7 Progressive Main Missions (The Manhattan Tour) that automatically advance one after another:
	    1. "CHRISTMAS PARTY CRASH"      — Vector3.new(-36, 0, 18)   — Smash 8  — Reward: $1,500
	    2. "TIMES SQUARE CONCERT MAYHEM"— Vector3.new(0, 0, -180)   — Smash 10 — Reward: $3,000
	    3. "WALL STREET BANK HEIST"     — Vector3.new(180, 0, 0)    — Smash 6  — Reward: $6,000
	    4. "SCHOOL & UNIVERSITY RUN"    — Vector3.new(-360, 0, 0)   — Smash 10 — Reward: $10,000
	    5. "HOSPITAL EMERGENCY BLITZ"   — Vector3.new(-180, 0, -180)— Smash 10 — Reward: $16,000
	    6. "HARBOR PORT & BOAT SMASH"   — Vector3.new(720, 0, 0)    — Smash 12 — Reward: $25,000
	    7. "CENTRAL PARK MONUMENT FINALE"—Vector3.new(-180, 0, 180) — Smash 15 — Reward: $50,000
	- 6 Always-Available Side Missions at those landmarks that players can drive into OR click on the Map
	  to activate/teleport to!
	- Physical 3D Mission Beacons in Workspace.ManhattanMissionZones:
	    * Glowing 3D Ground Ring (Radius = 14)
	    * Giant Rotating 3D Visual Symbol floating 12 studs above it (Golden Star, Green Dollar Sign,
	      Red Cross, Ship Anchor/Boat, Christmas Tree, Electric Guitar, Graduation Cap) so young kids
	      spot every landmark visually without reading a word!
	    * Ensures Harbor Pier deck & smashable landmark props exist around each mission zone.
	- Syncs Player Attributes:
	    ActiveMissionId, ActiveMissionTitle, ActiveMissionCategory ("MAIN" or "SIDE"),
	    ActiveMissionProgress, ActiveMissionGoal, ActiveMissionReward, ActiveMissionPos (Vector3),
	    ActiveMissionColor (Color3).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- 1. REMOTES & BINDABLES SETUP
--------------------------------------------------------------------------------
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = parent
	return re
end

local function ensureBindableEvent(parent: Instance, name: string): BindableEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local be = Instance.new("BindableEvent")
	be.Name = name
	be.Parent = parent
	return be
end

local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
local serverEventsFolder = ensureFolder(ServerStorage, "ServerEvents")
local eventsFolder = ensureFolder(ServerStorage, "Events")

local SelectMissionRemote = ensureRemoteEvent(remotesFolder, "SelectMission")
local TeleportToMissionRemote = ensureRemoteEvent(remotesFolder, "TeleportToMission")
local MissionStateUpdatedRemote = ensureRemoteEvent(remotesFolder, "MissionStateUpdated")

local NotificationRemote = ensureRemoteEvent(remotesFolder, "Notification")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")
local WalletUpdatedRemote = ensureRemoteEvent(remotesFolder, "WalletUpdated")
local MissionUpdateRemote = ensureRemoteEvent(remotesFolder, "MissionUpdate")

local DestructionOccurredBindable = ensureBindableEvent(serverEventsFolder, "DestructionOccurred")
local RootDestructionBindable = ensureBindableEvent(ServerStorage, "DestructionEvent")
local FolderDestructionBindable = ensureBindableEvent(eventsFolder, "DestructionEvent")
local AddCashBindable = ServerStorage:FindFirstChild("AddCashEvent") :: BindableEvent?
local UpdatePlayerDataBindable = ServerStorage:FindFirstChild("UpdatePlayerDataEvent") :: BindableEvent?
local SpawnPlayerVehicleBindable = ServerStorage:FindFirstChild("SpawnPlayerVehicleEvent") :: BindableEvent?

--------------------------------------------------------------------------------
-- 2. MISSION DEFINITIONS (7 MAIN MISSIONS + 6 SIDE MISSIONS)
--------------------------------------------------------------------------------
export type MissionSymbolKind =
	"GoldenStar"
	| "ChristmasTree"
	| "ConcertGuitar"
	| "DollarSign"
	| "SchoolCap"
	| "HospitalCross"
	| "HarborBoat"

export type MissionDef = {
	Id: string,
	Order: number,
	Category: "MAIN" | "SIDE",
	Title: string,
	LandmarkName: string,
	MapPinLabel: string,
	IconEmoji: string,
	TargetEmoji: string,
	Position: Vector3,
	TeleportPos: Vector3,
	TeleportLookAt: Vector3,
	Goal: number,
	Reward: number,
	Color: Color3,
	SymbolKind: MissionSymbolKind,
}

local MAIN_MISSIONS: { MissionDef } = {
	{
		Id = "Main_1_ChristmasParty",
		Order = 1,
		Category = "MAIN",
		Title = "CHRISTMAS PARTY CRASH",
		LandmarkName = "Rockefeller Christmas Plaza",
		MapPinLabel = "CHRISTMAS PARTY",
		IconEmoji = "🎄",
		TargetEmoji = "🎁",
		Position = Vector3.new(-36, 0, 18),
		TeleportPos = Vector3.new(0, 3.5, 44),
		TeleportLookAt = Vector3.new(-36, 3.5, 18),
		Goal = 8,
		Reward = 1500,
		Color = Color3.fromRGB(255, 215, 45),
		SymbolKind = "ChristmasTree",
	},
	{
		Id = "Main_2_ConcertMayhem",
		Order = 2,
		Category = "MAIN",
		Title = "TIMES SQUARE CONCERT MAYHEM",
		LandmarkName = "Times Square Concert Stage",
		MapPinLabel = "CONCERT STAGE",
		IconEmoji = "🎸",
		TargetEmoji = "🔊",
		Position = Vector3.new(0, 0, -180),
		TeleportPos = Vector3.new(0, 3.5, -132),
		TeleportLookAt = Vector3.new(0, 3.5, -180),
		Goal = 10,
		Reward = 3000,
		Color = Color3.fromRGB(255, 85, 220),
		SymbolKind = "ConcertGuitar",
	},
	{
		Id = "Main_3_BankHeist",
		Order = 3,
		Category = "MAIN",
		Title = "WALL STREET BANK HEIST",
		LandmarkName = "Manhattan Gold Reserve Bank",
		MapPinLabel = "GOLD BANK",
		IconEmoji = "🏦",
		TargetEmoji = "💰",
		Position = Vector3.new(180, 0, 0),
		TeleportPos = Vector3.new(132, 3.5, 0),
		TeleportLookAt = Vector3.new(180, 3.5, 0),
		Goal = 6,
		Reward = 6000,
		Color = Color3.fromRGB(65, 245, 115),
		SymbolKind = "DollarSign",
	},
	{
		Id = "Main_4_SchoolRun",
		Order = 4,
		Category = "MAIN",
		Title = "SCHOOL & UNIVERSITY RUN",
		LandmarkName = "Manhattan University & School",
		MapPinLabel = "UNIVERSITY & SCHOOL",
		IconEmoji = "🎓",
		TargetEmoji = "📚",
		Position = Vector3.new(-360, 0, 0),
		TeleportPos = Vector3.new(-312, 3.5, 0),
		TeleportLookAt = Vector3.new(-360, 3.5, 0),
		Goal = 10,
		Reward = 10000,
		Color = Color3.fromRGB(70, 185, 255),
		SymbolKind = "SchoolCap",
	},
	{
		Id = "Main_5_HospitalBlitz",
		Order = 5,
		Category = "MAIN",
		Title = "HOSPITAL EMERGENCY BLITZ",
		LandmarkName = "Manhattan General Hospital",
		MapPinLabel = "CITY HOSPITAL",
		IconEmoji = "🏥",
		TargetEmoji = "🚑",
		Position = Vector3.new(-180, 0, -180),
		TeleportPos = Vector3.new(-132, 3.5, -180),
		TeleportLookAt = Vector3.new(-180, 3.5, -180),
		Goal = 10,
		Reward = 16000,
		Color = Color3.fromRGB(255, 75, 85),
		SymbolKind = "HospitalCross",
	},
	{
		Id = "Main_6_HarborSmash",
		Order = 6,
		Category = "MAIN",
		Title = "HARBOR PORT & BOAT SMASH",
		LandmarkName = "East River Harbor Pier & Boats",
		MapPinLabel = "HARBOR & BOATS",
		IconEmoji = "🚢",
		TargetEmoji = "⚓",
		Position = Vector3.new(720, 0, 0),
		TeleportPos = Vector3.new(665, 3.5, 0),
		TeleportLookAt = Vector3.new(720, 3.5, 0),
		Goal = 12,
		Reward = 25000,
		Color = Color3.fromRGB(55, 215, 255),
		SymbolKind = "HarborBoat",
	},
	{
		Id = "Main_7_CentralParkFinale",
		Order = 7,
		Category = "MAIN",
		Title = "CENTRAL PARK MONUMENT FINALE",
		LandmarkName = "Central Park Triumphal Arch & Ice Rink",
		MapPinLabel = "CENTRAL PARK",
		IconEmoji = "🏆",
		TargetEmoji = "⭐",
		Position = Vector3.new(-180, 0, 180),
		TeleportPos = Vector3.new(-132, 3.5, 180),
		TeleportLookAt = Vector3.new(-180, 3.5, 180),
		Goal = 15,
		Reward = 50000,
		Color = Color3.fromRGB(255, 215, 45),
		SymbolKind = "GoldenStar",
	},
}

local SIDE_MISSIONS: { MissionDef } = {
	{
		Id = "Side_ChristmasMarket",
		Order = 1,
		Category = "SIDE",
		Title = "CHRISTMAS PARTY CRASH",
		LandmarkName = "🎄 Christmas Market",
		MapPinLabel = "🎄 Christmas Market",
		IconEmoji = "🎄",
		TargetEmoji = "🎁",
		Position = Vector3.new(-36, 0, 18),
		TeleportPos = Vector3.new(0, 3.5, 44),
		TeleportLookAt = Vector3.new(-36, 3.5, 18),
		Goal = 8,
		Reward = 1500,
		Color = Color3.fromRGB(65, 235, 115),
		SymbolKind = "ChristmasTree",
	},
	{
		Id = "Side_ConcertStage",
		Order = 2,
		Category = "SIDE",
		Title = "TIMES SQUARE CONCERT MAYHEM",
		LandmarkName = "🎸 Concert Stage",
		MapPinLabel = "🎸 Concert Stage",
		IconEmoji = "🎸",
		TargetEmoji = "🔊",
		Position = Vector3.new(0, 0, -180),
		TeleportPos = Vector3.new(0, 3.5, -132),
		TeleportLookAt = Vector3.new(0, 3.5, -180),
		Goal = 10,
		Reward = 3000,
		Color = Color3.fromRGB(255, 85, 220),
		SymbolKind = "ConcertGuitar",
	},
	{
		Id = "Side_GoldBank",
		Order = 3,
		Category = "SIDE",
		Title = "WALL STREET BANK HEIST",
		LandmarkName = "🏦 Gold Bank",
		MapPinLabel = "🏦 Gold Bank",
		IconEmoji = "🏦",
		TargetEmoji = "💰",
		Position = Vector3.new(180, 0, 0),
		TeleportPos = Vector3.new(132, 3.5, 0),
		TeleportLookAt = Vector3.new(180, 3.5, 0),
		Goal = 6,
		Reward = 6000,
		Color = Color3.fromRGB(75, 250, 125),
		SymbolKind = "DollarSign",
	},
	{
		Id = "Side_UniversitySchool",
		Order = 4,
		Category = "SIDE",
		Title = "SCHOOL & UNIVERSITY RUN",
		LandmarkName = "🎓 University & School",
		MapPinLabel = "🎓 University & School",
		IconEmoji = "🎓",
		TargetEmoji = "📚",
		Position = Vector3.new(-360, 0, 0),
		TeleportPos = Vector3.new(-312, 3.5, 0),
		TeleportLookAt = Vector3.new(-360, 3.5, 0),
		Goal = 10,
		Reward = 10000,
		Color = Color3.fromRGB(70, 185, 255),
		SymbolKind = "SchoolCap",
	},
	{
		Id = "Side_CityHospital",
		Order = 5,
		Category = "SIDE",
		Title = "HOSPITAL EMERGENCY BLITZ",
		LandmarkName = "🏥 City Hospital",
		MapPinLabel = "🏥 City Hospital",
		IconEmoji = "🏥",
		TargetEmoji = "🚑",
		Position = Vector3.new(-180, 0, -180),
		TeleportPos = Vector3.new(-132, 3.5, -180),
		TeleportLookAt = Vector3.new(-180, 3.5, -180),
		Goal = 10,
		Reward = 16000,
		Color = Color3.fromRGB(255, 75, 85),
		SymbolKind = "HospitalCross",
	},
	{
		Id = "Side_HarborBoats",
		Order = 6,
		Category = "SIDE",
		Title = "HARBOR PORT & BOAT SMASH",
		LandmarkName = "🚢 Harbor Pier & Boats",
		MapPinLabel = "🚢 Harbor Pier & Boats",
		IconEmoji = "🚢",
		TargetEmoji = "⚓",
		Position = Vector3.new(720, 0, 0),
		TeleportPos = Vector3.new(665, 3.5, 0),
		TeleportLookAt = Vector3.new(720, 3.5, 0),
		Goal = 12,
		Reward = 25000,
		Color = Color3.fromRGB(55, 215, 255),
		SymbolKind = "HarborBoat",
	},
}

local MISSION_BY_ID: { [string]: MissionDef } = {}
for _, m in ipairs(MAIN_MISSIONS) do
	MISSION_BY_ID[m.Id] = m
	MISSION_BY_ID[string.lower(m.Id)] = m
	MISSION_BY_ID[string.lower(m.Title)] = m
end
for _, s in ipairs(SIDE_MISSIONS) do
	MISSION_BY_ID[s.Id] = s
	MISSION_BY_ID[string.lower(s.Id)] = s
	MISSION_BY_ID[string.lower(s.LandmarkName)] = s
end

--------------------------------------------------------------------------------
-- 3. PHYSICAL 3D MISSION BEACONS & LANDMARK PROPS IN WORKSPACE
--------------------------------------------------------------------------------
local existingZones = Workspace:FindFirstChild("ManhattanMissionZones")
if existingZones then
	existingZones:Destroy()
end

local ZonesFolder = Instance.new("Folder")
ZonesFolder.Name = "ManhattanMissionZones"
ZonesFolder.Parent = Workspace

type RotatingSymbolEntry = {
	model: Model,
	basePos: Vector3,
	phaseOffset: number,
}

local rotatingSymbols: { RotatingSymbolEntry } = {}

local function makeAnchoredPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	canCollide: boolean?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = if canCollide ~= nil then canCollide else false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function makeDestructibleLandmarkProp(
	parent: Instance,
	name: string,
	propType: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	accentColor: Color3,
	cashVal: number
)
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("PropType", propType)
	model:SetAttribute("IsDestructible", true)
	model:SetAttribute("RequiredTier", 1)
	model:SetAttribute("BreakThreshold", 3)
	model:SetAttribute("CashValue", cashVal)
	model:SetAttribute("ChaosPoints", cashVal)
	model:SetAttribute("OriginCFrame", cf)

	local body = Instance.new("Part")
	body.Name = "PropCore"
	body.Size = size
	body.CFrame = cf
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	local ribbon = Instance.new("Part")
	ribbon.Name = "PropAccent"
	ribbon.Size = Vector3.new(size.X + 0.12, size.Y * 0.25, size.Z + 0.12)
	ribbon.CFrame = cf
	ribbon.Color = accentColor
	ribbon.Material = Enum.Material.Neon
	ribbon.Anchored = false
	ribbon.CanCollide = false
	ribbon.Massless = true
	ribbon.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = ribbon
	weld.Parent = ribbon

	model.PrimaryPart = body
	model.Parent = parent
	CollectionService:AddTag(model, "Destructible")
end

-- Builds a 3D Ground Ring (Radius = 14) with 16 glowing neon segments + soft center pad
local function buildGroundRing(parent: Instance, centerPos: Vector3, radius: number, color: Color3): Model
	local ringModel = Instance.new("Model")
	ringModel.Name = "MissionGroundRing"
	ringModel.Parent = parent

	local segments = 16
	local segAngle = (math.pi * 2) / segments
	local chordLen = 2 * radius * math.sin(segAngle * 0.5) + 0.8

	for i = 1, segments do
		local theta = (i - 0.5) * segAngle
		local px = centerPos.X + math.cos(theta) * radius
		local pz = centerPos.Z + math.sin(theta) * radius
		local segPos = Vector3.new(px, 0.38, pz)
		local tangent = Vector3.new(-math.sin(theta), 0, math.cos(theta))
		local cf = CFrame.lookAt(segPos, segPos + tangent)

		makeAnchoredPart(
			ringModel,
			"RingSegment_" .. tostring(i),
			Vector3.new(1.35, 0.35, chordLen),
			cf,
			color,
			Enum.Material.Neon,
			0.08,
			false
		)
	end

	-- Inner glowing ground disc so players spot the zone from high above
	local disc = makeAnchoredPart(
		ringModel,
		"RingFloorGlow",
		Vector3.new(0.18, radius * 1.9, radius * 1.9),
		CFrame.new(centerPos.X, 0.24, centerPos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.Material.Neon,
		0.78,
		false,
		Enum.PartType.Cylinder
	)
	ringModel.PrimaryPart = disc

	-- Tall translucent sky beacon beam so kids can see landmarks across Manhattan
	makeAnchoredPart(
		ringModel,
		"SkyBeaconPillar",
		Vector3.new(95, 2.6, 2.6),
		CFrame.new(centerPos.X, 48, centerPos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.Material.Neon,
		0.84,
		false,
		Enum.PartType.Cylinder
	)

	return ringModel
end

-- Builds a Giant Rotating 3D Visual Symbol floating 12 studs above the ground ring
local function buildRotating3DSymbol(parent: Instance, centerPos: Vector3, kind: MissionSymbolKind, color: Color3, idx: number): Model
	local symModel = Instance.new("Model")
	symModel.Name = "Rotating3DSymbol_" .. kind
	symModel.Parent = parent

	local hoverPos = Vector3.new(centerPos.X, 12.0, centerPos.Z)
	local core = makeAnchoredPart(
		symModel,
		"SymbolCore",
		Vector3.new(1.5, 1.5, 1.5),
		CFrame.new(hoverPos),
		color,
		Enum.Material.Neon,
		1.0,
		false
	)
	symModel.PrimaryPart = core

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3.5
	light.Range = 28
	light.Parent = core

	local function addPart(name: string, size: Vector3, offset: CFrame, partColor: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		makeAnchoredPart(
			symModel,
			name,
			size,
			core.CFrame * offset,
			partColor,
			mat or Enum.Material.Neon,
			0,
			false,
			shape
		)
	end

	if kind == "GoldenStar" then
		-- Giant 3D Golden Star (intersecting rotated golden bars + glowing center jewel)
		local gold = Color3.fromRGB(255, 215, 35)
		addPart("StarRay1", Vector3.new(7.5, 2.0, 1.4), CFrame.identity, gold)
		addPart("StarRay2", Vector3.new(2.0, 7.5, 1.4), CFrame.identity, gold)
		addPart("StarRay3", Vector3.new(7.2, 2.0, 1.2), CFrame.Angles(0, 0, math.rad(45)), gold)
		addPart("StarRay4", Vector3.new(7.2, 2.0, 1.2), CFrame.Angles(0, 0, math.rad(-45)), gold)
		addPart("StarJewel", Vector3.new(3.2, 3.2, 2.0), CFrame.identity, Color3.fromRGB(255, 250, 175), Enum.Material.Neon, Enum.PartType.Ball)
	elseif kind == "ChristmasTree" then
		-- Giant 3D Holiday Tree with Gold Star Topper & Ornaments
		local green = Color3.fromRGB(40, 225, 95)
		local gold = Color3.fromRGB(255, 220, 45)
		addPart("TreeTrunk", Vector3.new(1.8, 2.6, 1.8), CFrame.new(0, -3.2, 0), Color3.fromRGB(125, 78, 42), Enum.Material.Wood)
		addPart("TreeTier1", Vector3.new(6.8, 2.2, 6.8), CFrame.new(0, -1.4, 0), green)
		addPart("TreeTier2", Vector3.new(5.0, 2.2, 5.0), CFrame.new(0, 0.6, 0), green)
		addPart("TreeTier3", Vector3.new(3.2, 2.2, 3.2), CFrame.new(0, 2.5, 0), green)
		addPart("TreeStarA", Vector3.new(2.6, 2.6, 0.9), CFrame.new(0, 4.4, 0) * CFrame.Angles(0, 0, math.rad(45)), gold)
		addPart("TreeStarB", Vector3.new(2.6, 2.6, 0.9), CFrame.new(0, 4.4, 0), gold)
	elseif kind == "ConcertGuitar" then
		-- Giant 3D Neon Electric Guitar / Music Icon
		local magenta = Color3.fromRGB(255, 75, 215)
		local cyan = Color3.fromRGB(55, 235, 255)
		addPart("GuitarBodyLower", Vector3.new(4.8, 3.4, 1.2), CFrame.new(-1.2, -1.4, 0) * CFrame.Angles(0, 0, math.rad(-35)), magenta)
		addPart("GuitarBodyUpper", Vector3.new(3.6, 2.4, 1.2), CFrame.new(0.2, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-35)), cyan)
		addPart("GuitarNeck", Vector3.new(1.1, 6.5, 0.8), CFrame.new(1.8, 2.0, 0) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(255, 230, 85))
		addPart("GuitarHeadstock", Vector3.new(1.8, 2.0, 1.0), CFrame.new(3.4, 4.2, 0) * CFrame.Angles(0, 0, math.rad(-35)), magenta)
	elseif kind == "DollarSign" then
		-- Giant 3D Green Dollar Sign ($)
		local emerald = Color3.fromRGB(55, 255, 110)
		local gold = Color3.fromRGB(255, 220, 55)
		addPart("DollarBarTop", Vector3.new(5.2, 1.2, 1.4), CFrame.new(0, 3.0, 0), emerald)
		addPart("DollarBarMid", Vector3.new(5.2, 1.2, 1.4), CFrame.new(0, 0, 0), emerald)
		addPart("DollarBarBot", Vector3.new(5.2, 1.2, 1.4), CFrame.new(0, -3.0, 0), emerald)
		addPart("DollarLeftUpper", Vector3.new(1.2, 3.2, 1.4), CFrame.new(-2.0, 1.5, 0), emerald)
		addPart("DollarRightLower", Vector3.new(1.2, 3.2, 1.4), CFrame.new(2.0, -1.5, 0), emerald)
		addPart("DollarVerticalStrike", Vector3.new(1.0, 8.8, 1.7), CFrame.new(0, 0, 0), gold)
	elseif kind == "SchoolCap" then
		-- Giant 3D Graduation Cap & Golden Star
		local blue = Color3.fromRGB(65, 185, 255)
		local gold = Color3.fromRGB(255, 215, 45)
		addPart("MortarboardTop", Vector3.new(7.0, 0.8, 7.0), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(45), math.rad(8)), blue)
		addPart("CapSkull", Vector3.new(4.2, 2.2, 4.2), CFrame.new(0, 0.0, 0), Color3.fromRGB(35, 110, 215))
		addPart("GoldTassel", Vector3.new(0.8, 3.4, 0.8), CFrame.new(2.8, 0.2, 2.0), gold)
	elseif kind == "HospitalCross" then
		-- Giant 3D Glowing Red Cross (+) inside White Med Emblem
		local red = Color3.fromRGB(255, 55, 70)
		local white = Color3.fromRGB(245, 250, 255)
		addPart("CrossBacking", Vector3.new(1.2, 7.8, 7.8), CFrame.Angles(0, math.rad(90), 0), white, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		addPart("CrossVertical", Vector3.new(2.0, 6.2, 1.8), CFrame.identity, red)
		addPart("CrossHorizontal", Vector3.new(6.2, 2.0, 1.8), CFrame.identity, red)
	elseif kind == "HarborBoat" then
		-- Giant 3D Harbor Ship / Boat & Anchor Symbol
		local hullColor = Color3.fromRGB(45, 205, 255)
		local cabinColor = Color3.fromRGB(250, 252, 255)
		local smokestackColor = Color3.fromRGB(255, 95, 55)
		addPart("BoatHull", Vector3.new(3.4, 2.2, 8.4), CFrame.new(0, -1.5, 0), hullColor)
		addPart("BoatCabin", Vector3.new(2.8, 2.0, 4.2), CFrame.new(0, 0.5, 0.4), cabinColor)
		addPart("BoatSmokestack", Vector3.new(1.4, 2.4, 1.4), CFrame.new(0, 2.4, 0.8), smokestackColor)
		addPart("BoatProWedge", Vector3.new(3.4, 2.2, 2.6), CFrame.new(0, -1.5, -5.2), Color3.fromRGB(255, 215, 45))
	end

	-- Save initial relative CFrame offsets so we can rotate the entire 3D symbol smoothly
	for _, child in ipairs(symModel:GetChildren()) do
		if child:IsA("BasePart") and child ~= core then
			child:SetAttribute("RelCF", core.CFrame:ToObjectSpace(child.CFrame))
		end
	end

	table.insert(rotatingSymbols, {
		model = symModel,
		basePos = hoverPos,
		phaseOffset = idx * 0.9,
	})

	return symModel
end

-- Build the East River Harbor Pier & Boats at Vector3.new(720, 0, 0) + Landmark Smash Props
local function buildHarborPierAndLandmarkProps()
	local pierFolder = Instance.new("Folder")
	pierFolder.Name = "HarborPierAndLandmarkProps"
	pierFolder.Parent = ZonesFolder

	-- Solid drivable Harbor Pier Deck connecting East Coastline (X = 580) out to X = 765 around Z = 0
	makeAnchoredPart(
		pierFolder,
		"EastRiverHarborPierDeck",
		Vector3.new(190, 1.2, 76),
		CFrame.new(675, -0.35, 0),
		Color3.fromRGB(112, 80, 52),
		Enum.Material.WoodPlanks,
		0,
		true
	)

	-- Wooden Pier Bollards along North/South edges
	for x = 600, 750, 30 do
		for _, sz in ipairs({ -35, 35 }) do
			makeAnchoredPart(
				pierFolder,
				"PierBollard",
				Vector3.new(2.4, 4.5, 2.4),
				CFrame.new(x, 2.0, sz),
				Color3.fromRGB(75, 52, 34),
				Enum.Material.Wood,
				0,
				true
			)
		end
	end

	-- 2 Colorful Harbor Boats moored right at the pier (destructible Tier 1 targets!)
	for idx, zOff in ipairs({ -24, 24 }) do
		makeDestructibleLandmarkProp(
			pierFolder,
			"HarborSpeedBoat_" .. tostring(idx),
			"Crate",
			Vector3.new(8.5, 4.2, 18.0),
			CFrame.new(742, 2.2, zOff),
			Color3.fromRGB(45, 195, 255),
			Color3.fromRGB(255, 210, 45),
			150
		)
	end

	-- Spawn clusters of easy-smash Tier-1 Mission Props around all 7 Landmark coordinates
	local landmarkPropClusters = {
		{ pos = Vector3.new(-36, 0, 18), propType = "JackpotCrate", color = Color3.fromRGB(235, 45, 55), accent = Color3.fromRGB(255, 215, 45), count = 10, radius = 16 },
		{ pos = Vector3.new(0, 0, -180), propType = "Crate", color = Color3.fromRGB(235, 65, 210), accent = Color3.fromRGB(65, 240, 255), count = 12, radius = 18 },
		{ pos = Vector3.new(180, 0, 0), propType = "JackpotCrate", color = Color3.fromRGB(255, 205, 40), accent = Color3.fromRGB(65, 255, 120), count = 10, radius = 16 },
		{ pos = Vector3.new(-360, 0, 0), propType = "Crate", color = Color3.fromRGB(55, 165, 255), accent = Color3.fromRGB(255, 220, 55), count = 12, radius = 18 },
		{ pos = Vector3.new(-180, 0, -180), propType = "Crate", color = Color3.fromRGB(255, 70, 85), accent = Color3.fromRGB(250, 250, 255), count = 12, radius = 18 },
		{ pos = Vector3.new(720, 0, 0), propType = "Crate", color = Color3.fromRGB(235, 145, 45), accent = Color3.fromRGB(55, 225, 255), count = 16, radius = 20 },
		{ pos = Vector3.new(-180, 0, 180), propType = "JackpotCrate", color = Color3.fromRGB(255, 210, 50), accent = Color3.fromRGB(85, 245, 135), count = 16, radius = 20 },
	}

	for _, cluster in ipairs(landmarkPropClusters) do
		for i = 1, cluster.count do
			local angle = ((i - 1) / cluster.count) * math.pi * 2
			local px = cluster.pos.X + math.cos(angle) * cluster.radius
			local pz = cluster.pos.Z + math.sin(angle) * cluster.radius
			makeDestructibleLandmarkProp(
				pierFolder,
				string.format("MissionTargetProp_%d", i),
				cluster.propType,
				Vector3.new(3.8, 3.8, 3.8),
				CFrame.new(px, 2.2, pz) * CFrame.Angles(0, angle, 0),
				cluster.color,
				cluster.accent,
				75
			)
		end
	end
end

-- Build all 7 Landmark 3D Ground Rings & Giant Rotating 3D Visual Symbols
local zoneModelsByMissionId: { [string]: Model } = {}

local function buildAllMissionBeacons()
	buildHarborPierAndLandmarkProps()

	for idx, m in ipairs(MAIN_MISSIONS) do
		local zoneContainer = Instance.new("Model")
		zoneContainer.Name = "MissionZone_" .. m.Id
		zoneContainer:SetAttribute("MissionId", m.Id)
		zoneContainer:SetAttribute("LandmarkName", m.LandmarkName)
		zoneContainer:SetAttribute("ZoneRadius", 14)
		zoneContainer.Parent = ZonesFolder

		buildGroundRing(zoneContainer, m.Position, 14, m.Color)
		buildRotating3DSymbol(zoneContainer, m.Position, m.SymbolKind, m.Color, idx)

		zoneModelsByMissionId[m.Id] = zoneContainer
	end
end

buildAllMissionBeacons()

--------------------------------------------------------------------------------
-- 4. PLAYER MISSION STATE & ATTRIBUTE SYNC
--------------------------------------------------------------------------------
type PlayerMissionState = {
	mainIndex: number,
	activeMission: MissionDef,
	progress: number,
	lastKnownDestructions: number,
	lastSmashClock: number,
	lastZoneSwitchClock: number,
}

local playerStates: { [number]: PlayerMissionState } = {}

local function syncPlayerMissionAttributes(player: Player, state: PlayerMissionState, completedSummary: { [string]: any }?)
	local m = state.activeMission
	player:SetAttribute("MainMissionIndex", state.mainIndex)
	player:SetAttribute("ActiveMissionId", m.Id)
	player:SetAttribute("ActiveMissionTitle", m.Title)
	player:SetAttribute("ActiveMissionCategory", m.Category)
	player:SetAttribute("ActiveMissionProgress", state.progress)
	player:SetAttribute("ActiveMissionGoal", m.Goal)
	player:SetAttribute("ActiveMissionReward", m.Reward)
	player:SetAttribute("ActiveMissionPos", m.Position)
	player:SetAttribute("ActiveMissionColor", m.Color)
	player:SetAttribute("ActiveMissionIcon", m.IconEmoji)
	player:SetAttribute("ActiveMissionTargetEmoji", m.TargetEmoji)
	player:SetAttribute("ActiveMissionLandmark", m.LandmarkName)

	local payload = {
		ActiveMissionId = m.Id,
		ActiveMissionTitle = m.Title,
		ActiveMissionCategory = m.Category,
		ActiveMissionProgress = state.progress,
		ActiveMissionGoal = m.Goal,
		ActiveMissionReward = m.Reward,
		ActiveMissionPos = m.Position,
		ActiveMissionColor = m.Color,
		ActiveMissionIcon = m.IconEmoji,
		ActiveMissionTargetEmoji = m.TargetEmoji,
		LandmarkName = m.LandmarkName,
		MainMissionIndex = state.mainIndex,
		CompletedMission = completedSummary,
	}
	MissionStateUpdatedRemote:FireClient(player, payload)
	MissionUpdateRemote:FireClient(player, payload)
end

local function awardMissionReward(player: Player, rewardCash: number, missionTitle: string)
	local currentCash = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 500))
	local newCash = currentCash + rewardCash
	player:SetAttribute("Cash", newCash)

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash") :: IntValue?
		if cashVal then
			cashVal.Value = newCash
		end
	end

	local completedCount = (tonumber(player:GetAttribute("MissionsCompleted")) or 0) + 1
	player:SetAttribute("MissionsCompleted", completedCount)

	if AddCashBindable then
		-- Note: Cash attribute was already updated above; notify wallet & profile persistence cleanly
	end
	if UpdatePlayerDataBindable then
		pcall(function()
			UpdatePlayerDataBindable:Fire(player, {
				Cash = newCash,
				MissionsCompleted = completedCount,
			})
		end)
	end

	WalletUpdatedRemote:FireClient(player, newCash, rewardCash, "MissionCompleted")
	StyleCalloutRemote:FireClient(player, {
		Callout = string.format("🏆 MISSION COMPLETE! +$%d!", rewardCash),
		Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
		ComboCount = tonumber(player:GetAttribute("ComboCount")) or 1,
		CashAwarded = rewardCash,
	})
	NotificationRemote:FireClient(player, {
		Title = "🏆 MISSION COMPLETE!",
		Message = string.format("%s (+$%d)", missionTitle, rewardCash),
		Category = "Success",
		Color = Color3.fromRGB(85, 255, 130),
		Duration = 3.2,
	})
end

local function advanceOrCompleteMission(player: Player, state: PlayerMissionState)
	local finished = state.activeMission
	local reward = finished.Reward
	local completedSummary = {
		Id = finished.Id,
		Title = finished.Title,
		Category = finished.Category,
		Reward = reward,
		IconEmoji = finished.IconEmoji,
	}

	awardMissionReward(player, reward, finished.Title)

	if finished.Category == "MAIN" then
		state.mainIndex = (state.mainIndex % #MAIN_MISSIONS) + 1
	end

	-- Advance to the next Main Mission automatically!
	state.activeMission = MAIN_MISSIONS[state.mainIndex] or MAIN_MISSIONS[1]
	state.progress = 0
	syncPlayerMissionAttributes(player, state, completedSummary)
end

local function recordPlayerDestruction(player: Player, amount: number)
	local state = playerStates[player.UserId]
	if not state then
		return
	end

	local now = os.clock()
	if now - state.lastSmashClock < 0.03 then
		return
	end
	state.lastSmashClock = now

	local step = math.max(1, math.floor(amount))
	state.progress = math.min(state.activeMission.Goal, state.progress + step)

	if state.progress >= state.activeMission.Goal then
		advanceOrCompleteMission(player, state)
	else
		syncPlayerMissionAttributes(player, state, nil)
	end
end

--------------------------------------------------------------------------------
-- 5. DESTRUCTION LISTENERS (ATTRIBUTE + SERVERSTORAGE BINDABLE)
--------------------------------------------------------------------------------
local function handleBindableDestruction(arg1: any, _arg2: any)
	local attacker: Player? = nil
	if typeof(arg1) == "Instance" and arg1:IsA("Player") then
		attacker = arg1
	elseif type(arg1) == "table" then
		local p = arg1.player or arg1.Player
		if typeof(p) == "Instance" and p:IsA("Player") then
			attacker = p
		end
	end
	if not attacker then
		return
	end

	local state = playerStates[attacker.UserId]
	if not state then
		return
	end

	-- Sync with TotalDestructions so AttributeChangedSignal doesn't double-count the same smash
	local attrTotal = tonumber(attacker:GetAttribute("TotalDestructions")) or 0
	state.lastKnownDestructions = math.max(state.lastKnownDestructions + 1, attrTotal)
	recordPlayerDestruction(attacker, 1)
end

DestructionOccurredBindable.Event:Connect(handleBindableDestruction)
RootDestructionBindable.Event:Connect(handleBindableDestruction)
FolderDestructionBindable.Event:Connect(handleBindableDestruction)

--------------------------------------------------------------------------------
-- 6. SELECT MISSION & TELEPORT TO MISSION HANDLERS
--------------------------------------------------------------------------------
local function resolveMissionById(rawId: any, playerState: PlayerMissionState): MissionDef?
	if type(rawId) == "number" then
		local idx = math.clamp(math.floor(rawId), 1, #MAIN_MISSIONS)
		return MAIN_MISSIONS[idx]
	end
	if type(rawId) ~= "string" or rawId == "" then
		return nil
	end
	if rawId == "ACTIVE_MAIN" or rawId == "MAIN" then
		return MAIN_MISSIONS[playerState.mainIndex] or MAIN_MISSIONS[1]
	end
	local direct = MISSION_BY_ID[rawId] or MISSION_BY_ID[string.lower(rawId)]
	if direct then
		return direct
	end
	local lower = string.lower(rawId)
	for _, m in ipairs(SIDE_MISSIONS) do
		if string.find(string.lower(m.Id), lower, 1, true) or string.find(string.lower(m.Title), lower, 1, true) then
			return m
		end
	end
	for _, m in ipairs(MAIN_MISSIONS) do
		if string.find(string.lower(m.Id), lower, 1, true) or string.find(string.lower(m.Title), lower, 1, true) then
			return m
		end
	end
	return nil
end

local function findPlayerVehicle(player: Player): Model?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		local m = hum.SeatPart:FindFirstAncestorOfClass("Model")
		if m and m ~= char then
			return m
		end
	end

	local vehiclesFolder = Workspace:FindFirstChild("Vehicles")
	if vehiclesFolder then
		for _, child in ipairs(vehiclesFolder:GetChildren()) do
			if child:IsA("Model") and tonumber(child:GetAttribute("OwnerUserId")) == player.UserId then
				return child
			end
		end
	end
	return nil
end

local function teleportPlayerToSafeRoad(player: Player, targetCF: CFrame)
	local veh = findPlayerVehicle(player)
	if not veh and SpawnPlayerVehicleBindable then
		pcall(function()
			SpawnPlayerVehicleBindable:Fire(player, nil, targetCF, true)
		end)
		veh = findPlayerVehicle(player)
	end

	if veh and veh.Parent then
		for _, desc in ipairs(veh:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.AssemblyLinearVelocity = Vector3.zero
				desc.AssemblyAngularVelocity = Vector3.zero
			end
		end
		veh:PivotTo(targetCF)

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = veh:FindFirstChild("DriveSeat") :: VehicleSeat?
		if hum and seat and seat.Occupant ~= hum then
			seat:Sit(hum)
		end
	else
		local char = player.Character
		if char then
			char:PivotTo(targetCF)
		end
	end
end

SelectMissionRemote.OnServerEvent:Connect(function(player: Player, missionIdArg: any)
	local state = playerStates[player.UserId]
	if not state then
		return
	end
	local targetMission = resolveMissionById(missionIdArg, state)
	if not targetMission then
		return
	end

	if state.activeMission.Id ~= targetMission.Id then
		state.activeMission = targetMission
		state.progress = 0
	end
	syncPlayerMissionAttributes(player, state, nil)
end)

TeleportToMissionRemote.OnServerEvent:Connect(function(player: Player, missionIdOrPos: any)
	local state = playerStates[player.UserId]
	if not state then
		return
	end

	local targetCF: CFrame? = nil
	if typeof(missionIdOrPos) == "Vector3" then
		local pos = Vector3.new(missionIdOrPos.X, 3.5, missionIdOrPos.Z)
		targetCF = CFrame.new(pos)
	else
		local targetMission = resolveMissionById(missionIdOrPos, state)
		if targetMission then
			if state.activeMission.Id ~= targetMission.Id then
				state.activeMission = targetMission
				state.progress = 0
			end
			syncPlayerMissionAttributes(player, state, nil)
			targetCF = CFrame.lookAt(targetCF and targetCF.Position or targetMission.TeleportPos, targetMission.TeleportLookAt)
		elseif type(missionIdOrPos) == "string" and string.lower(missionIdOrPos) == "speedshop" then
			targetCF = CFrame.lookAt(Vector3.new(18, 3.5, -22), Vector3.new(52, 3.5, -22))
		end
	end

	if targetCF then
		teleportPlayerToSafeRoad(player, targetCF)
	end
end)

--------------------------------------------------------------------------------
-- 7. PLAYER LIFECYCLE & DRIVE-INTO-BEACON ZONE DETECTION
--------------------------------------------------------------------------------
local function initPlayerMissions(player: Player)
	local initDest = tonumber(player:GetAttribute("TotalDestructions")) or 0
	local state: PlayerMissionState = {
		mainIndex = 1,
		activeMission = MAIN_MISSIONS[1],
		progress = 0,
		lastKnownDestructions = initDest,
		lastSmashClock = 0,
		lastZoneSwitchClock = 0,
	}
	playerStates[player.UserId] = state
	syncPlayerMissionAttributes(player, state, nil)

	player:GetAttributeChangedSignal("TotalDestructions"):Connect(function()
		local currentTotal = tonumber(player:GetAttribute("TotalDestructions")) or 0
		if currentTotal > state.lastKnownDestructions then
			local delta = currentTotal - state.lastKnownDestructions
			state.lastKnownDestructions = currentTotal
			recordPlayerDestruction(player, delta)
		else
			state.lastKnownDestructions = currentTotal
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayerMissions, plr)
end
Players.PlayerAdded:Connect(initPlayerMissions)
Players.PlayerRemoving:Connect(function(plr: Player)
	playerStates[plr.UserId] = nil
end)

-- Rotate the 3D Landmark Symbols & check if players drive into a Side Mission Ground Ring (Radius = 14)
local animClock = 0
local zoneCheckAccum = 0

RunService.Heartbeat:Connect(function(dt: number)
	animClock += dt
	local rotAngle = animClock * 1.6

	for _, entry in ipairs(rotatingSymbols) do
		local core = entry.model.PrimaryPart
		if core and core.Parent then
			local bobY = math.sin(animClock * 2.2 + entry.phaseOffset) * 1.1
			local newCoreCF = CFrame.new(entry.basePos + Vector3.new(0, bobY, 0))
				* CFrame.Angles(0, rotAngle + entry.phaseOffset, 0)
			core.CFrame = newCoreCF
			for _, child in ipairs(entry.model:GetChildren()) do
				if child:IsA("BasePart") and child ~= core then
					local relCF = child:GetAttribute("RelCF") :: CFrame?
					if relCF then
						child.CFrame = newCoreCF * relCF
					end
				end
			end
		end
	end

	zoneCheckAccum += dt
	if zoneCheckAccum < 0.35 then
		return
	end
	zoneCheckAccum = 0

	local now = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		local state = playerStates[plr.UserId]
		if not state or (now - state.lastZoneSwitchClock) < 6.0 then
			continue
		end

		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		local pPos = Vector3.new(root.Position.X, 0, root.Position.Z)
		-- If player is already inside their active mission's zone, keep their active mission!
		local activeDist = (pPos - Vector3.new(state.activeMission.Position.X, 0, state.activeMission.Position.Z)).Magnitude
		if activeDist <= 28 then
			continue
		end

		-- Otherwise, if they drive directly into another landmark's 14-stud Ground Ring, activate that Side Mission!
		for _, sideMission in ipairs(SIDE_MISSIONS) do
			if sideMission.Id ~= state.activeMission.Id then
				local d = (pPos - Vector3.new(sideMission.Position.X, 0, sideMission.Position.Z)).Magnitude
				if d <= 14.5 then
					state.lastZoneSwitchClock = now
					state.activeMission = sideMission
					state.progress = 0
					syncPlayerMissionAttributes(plr, state, nil)
					break
				end
			end
		end
	end
end)

print("[MissionService] Initialized 7 Main Missions, 6 Side Missions, and 3D Landmark Beacons in Workspace.ManhattanMissionZones.")
