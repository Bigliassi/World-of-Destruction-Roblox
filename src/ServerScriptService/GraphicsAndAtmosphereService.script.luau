--!strict
--[[
	GraphicsAndAtmosphereService.script.luau
	World of Destruction (Roblox) — Version 1.0
	
	Configures crisp, modern Roblox graphics in Lighting and Workspace:
	- Lighting properties: Future lighting technology, realistic ShadowSoftness,
	  EnvironmentDiffuseScale, EnvironmentSpecularScale, warm golden-hour defaults.
	- Post-Processing & Atmospheric instances (idempotent with WeatherTimeService):
	  * Atmosphere (crisp horizon haze & sky scatter)
	  * Sky (celestial bodies & clean skybox)
	  * BloomEffect (vibrant neon signage, headlights, and plasma nitro glow)
	  * ColorCorrectionEffect (punchy arcade saturation & contrast)
	  * SunRaysEffect (cinematic volumetric sunbeams through Downtown towers)
	  * DepthOfFieldEffect (subtle distant horizon softness)
	- High-Visibility Landmark Beacons & Neon Signage in Workspace:
	  Places vertical light-beam beacons and floating 3D BillboardGui markers on key
	  Leo City destinations (Speed Shop Showrooms, Mechanic Repair Bays, Park Mega-Ramp,
	  Speedway Mega-Ramp, and Leo Plaza Spawn) so players can navigate effortlessly.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- 1. Lighting & Post-Processing Configuration
--------------------------------------------------------------------------------
local function ensurePostEffect<T>(className: string, name: string): any
	for _, child in ipairs(Lighting:GetChildren()) do
		if child.ClassName == className then
			return child
		end
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function configureCrispLighting()
	-- Core Lighting properties tuned for vibrant Forza-style arcade clarity
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.18
	Lighting.EnvironmentDiffuseScale = 0.85
	Lighting.EnvironmentSpecularScale = 0.90
	Lighting.Brightness = math.max(Lighting.Brightness, 2.5)

	-- Atmosphere
	local atmosphere: Atmosphere = ensurePostEffect("Atmosphere", "WoDAtmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(198, 218, 245)
	atmosphere.Decay = Color3.fromRGB(145, 165, 200)
	atmosphere.Glare = 0.18
	atmosphere.Haze = 1.15

	-- Sky
	local sky: Sky = ensurePostEffect("Sky", "WoDSky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 11
	sky.StarCount = 3000

	-- BloomEffect (makes neon signs, police sirens, and plasma nitro pop)
	local bloom: BloomEffect = ensurePostEffect("BloomEffect", "WoDBloom")
	bloom.Enabled = true
	bloom.Intensity = 0.65
	bloom.Size = 26
	bloom.Threshold = 1.35

	-- ColorCorrectionEffect (saturated, warm sunlit arcade palette)
	local cc: ColorCorrectionEffect = ensurePostEffect("ColorCorrectionEffect", "WoDColorCorrection")
	cc.Enabled = true
	cc.Brightness = 0.02
	cc.Contrast = 0.12
	cc.Saturation = 0.18
	cc.TintColor = Color3.fromRGB(255, 252, 246)

	-- SunRaysEffect (volumetric rays between skyscrapers)
	local sunRays: SunRaysEffect = ensurePostEffect("SunRaysEffect", "WoDSunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.65

	-- Subtle DepthOfFieldEffect (keeps foreground razor-sharp, softens far horizon)
	local dof: DepthOfFieldEffect = ensurePostEffect("DepthOfFieldEffect", "WoDDepthOfField")
	dof.Enabled = true
	dof.FarIntensity = 0.10
	dof.FocusDistance = 160
	dof.InFocusRadius = 220
	dof.NearIntensity = 0

	Lighting:SetAttribute("GraphicsConfiguredV1", true)
end

configureCrispLighting()

--------------------------------------------------------------------------------
-- 2. High-Visibility City Landmark Beacons & Floating Signage
--------------------------------------------------------------------------------
type LandmarkBeaconSpec = {
	Id: string,
	Title: string,
	Subtitle: string,
	Position: Vector3,
	Color: Color3,
	PillarHeight: number,
	RingRadius: number,
}

local LANDMARK_BEACONS: { LandmarkBeaconSpec } = {
	{
		Id = "SpeedShopPlaza",
		Title = "SPEED SHOP [B]",
		Subtitle = "CAR UPGRADES • PAINTS • GARAGE",
		Position = Vector3.new(48, 0, -46),
		Color = Color3.fromRGB(0, 235, 255),
		PillarHeight = 95,
		RingRadius = 14,
	},
	{
		Id = "SpeedShopEast",
		Title = "SPEED SHOP [B]",
		Subtitle = "CAR UPGRADES • PAINTS • GARAGE",
		Position = Vector3.new(158, 0, 0),
		Color = Color3.fromRGB(0, 235, 255),
		PillarHeight = 95,
		RingRadius = 18,
	},
	{
		Id = "MechanicBayPlaza",
		Title = "MECHANIC REPAIR BAY",
		Subtitle = "DRIVE THROUGH FOR INSTANT 100% REPAIR",
		Position = Vector3.new(-48, 0, -24),
		Color = Color3.fromRGB(60, 255, 130),
		PillarHeight = 70,
		RingRadius = 14,
	},
	{
		Id = "MechanicBayWest",
		Title = "MECHANIC REPAIR BAY",
		Subtitle = "INSTANT REPAIR & NITRO REFILL",
		Position = Vector3.new(-180, 0, 0),
		Color = Color3.fromRGB(60, 255, 130),
		PillarHeight = 70,
		RingRadius = 16,
	},
	{
		Id = "LeoPlazaMegaRamp",
		Title = "PLAZA MEGA-RAMP",
		Subtitle = "STUNT ZONE • MEGA AIR MULTIPLIER",
		Position = Vector3.new(0, 0, -58),
		Color = Color3.fromRGB(255, 145, 35),
		PillarHeight = 85,
		RingRadius = 16,
	},
	{
		Id = "BoardwalkMegaRamp",
		Title = "BOARDWALK MEGA-RAMP",
		Subtitle = "HIGH-SPEED LAUNCH • 2X STUNT XP",
		Position = Vector3.new(550, 0, 0),
		Color = Color3.fromRGB(255, 145, 35),
		PillarHeight = 85,
		RingRadius = 16,
	},
	{
		Id = "LeoTowerIcon",
		Title = "LEO TOWER",
		Subtitle = "DOWNTOWN BOSS LANDMARK • JACKPOT PAYOUT",
		Position = Vector3.new(-26, 0, -206),
		Color = Color3.fromRGB(255, 215, 55),
		PillarHeight = 115,
		RingRadius = 16,
	},
	{
		Id = "BoomGasStation",
		Title = "BOOM GAS & NITRO",
		Subtitle = "EXPLOSIVE CHAIN REACTION COMBO ZONE",
		Position = Vector3.new(0, 0, -324),
		Color = Color3.fromRGB(215, 85, 255),
		PillarHeight = 95,
		RingRadius = 20,
	},
}

local animatedRings: { { Part: BasePart, BasePos: Vector3, BaseRadius: number, Phase: number } } = {}

local function buildLandmarkBeacons()
	local parentFolder = Workspace:FindFirstChild("LeoCity") or Workspace
	local existing = parentFolder:FindFirstChild("CityNavigationBeacons")
	if existing then
		existing:Destroy()
	end

	local beaconsFolder = Instance.new("Folder")
	beaconsFolder.Name = "CityNavigationBeacons"
	beaconsFolder.Parent = parentFolder

	for idx, spec in ipairs(LANDMARK_BEACONS) do
		local model = Instance.new("Model")
		model.Name = "Beacon_" .. spec.Id
		model:SetAttribute("LandmarkId", spec.Id)
		model:SetAttribute("LandmarkTitle", spec.Title)
		model.Parent = beaconsFolder

		-- 1. Translucent Neon Sky Beam Pillar (visible across the whole city)
		local beamPart = Instance.new("Part")
		beamPart.Name = "SkyBeaconBeam"
		beamPart.Shape = Enum.PartType.Cylinder
		beamPart.Material = Enum.Material.Neon
		beamPart.Color = spec.Color
		beamPart.Anchored = true
		beamPart.CanCollide = false
		beamPart.CanQuery = false
		beamPart.CanTouch = false
		beamPart.CastShadow = false
		beamPart.Transparency = 0.78
		beamPart.Size = Vector3.new(spec.PillarHeight, 3.2, 3.2)
		beamPart.CFrame = CFrame.new(spec.Position + Vector3.new(0, spec.PillarHeight * 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		beamPart.Parent = model

		-- 2. Ground Pad Halo Ring
		local groundRing = Instance.new("Part")
		groundRing.Name = "GroundHaloRing"
		groundRing.Shape = Enum.PartType.Cylinder
		groundRing.Material = Enum.Material.Neon
		groundRing.Color = spec.Color
		groundRing.Anchored = true
		groundRing.CanCollide = false
		groundRing.CanQuery = false
		groundRing.CanTouch = false
		groundRing.CastShadow = false
		groundRing.Transparency = 0.35
		groundRing.Size = Vector3.new(0.35, spec.RingRadius * 2, spec.RingRadius * 2)
		groundRing.CFrame = CFrame.new(spec.Position + Vector3.new(0, 0.25, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		groundRing.Parent = model

		local pointLight = Instance.new("PointLight")
		pointLight.Color = spec.Color
		pointLight.Brightness = 2.2
		pointLight.Range = 36
		pointLight.Shadows = false
		pointLight.Parent = groundRing

		table.insert(animatedRings, {
			Part = groundRing,
			BasePos = spec.Position + Vector3.new(0, 0.25, 0),
			BaseRadius = spec.RingRadius,
			Phase = idx * 0.85,
		})

		-- 3. High-Visibility Floating Billboard Sign
		local signAnchor = Instance.new("Part")
		signAnchor.Name = "SignAnchor"
		signAnchor.Size = Vector3.new(1, 1, 1)
		signAnchor.Transparency = 1
		signAnchor.Anchored = true
		signAnchor.CanCollide = false
		signAnchor.CanQuery = false
		signAnchor.CanTouch = false
		signAnchor.Position = spec.Position + Vector3.new(0, 22, 0)
		signAnchor.Parent = model

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "LandmarkSignGui"
		billboard.Size = UDim2.fromOffset(230, 56)
		billboard.StudsOffset = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 650
		billboard.LightInfluence = 0
		billboard.Parent = signAnchor

		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
		card.BackgroundTransparency = 0.18
		card.BorderSizePixel = 0
		card.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = spec.Color
		stroke.Thickness = 2
		stroke.Parent = card

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, -12, 0, 28)
		titleLabel.Position = UDim2.fromOffset(6, 4)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.Text = spec.Title
		titleLabel.TextColor3 = spec.Color
		titleLabel.TextSize = 15
		titleLabel.TextScaled = true
		titleLabel.Parent = card

		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.Size = UDim2.new(1, -12, 0, 18)
		subLabel.Position = UDim2.fromOffset(6, 32)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.Text = spec.Subtitle
		subLabel.TextColor3 = Color3.fromRGB(225, 232, 245)
		subLabel.TextSize = 11
		subLabel.TextScaled = true
		subLabel.Parent = card
	end
end

-- Build beacons immediately and re-parent to Workspace.LeoCity once WorldBuilderService finishes
buildLandmarkBeacons()
task.delay(3.0, function()
	local leoCity = Workspace:FindFirstChild("LeoCity")
	local currentBeacons = Workspace:FindFirstChild("CityNavigationBeacons")
	if leoCity and currentBeacons then
		currentBeacons.Parent = leoCity
	end
end)

-- Subtle pulse animation on landmark ground halo rings
local pulseElapsed = 0
RunService.Heartbeat:Connect(function(dt: number)
	pulseElapsed += dt
	if pulseElapsed < 0.05 then
		return
	end
	local t = os.clock()
	pulseElapsed = 0
	for _, item in ipairs(animatedRings) do
		if item.Part and item.Part.Parent then
			local wave = math.sin(t * 2.4 + item.Phase)
			local r = (item.BaseRadius * 2) + wave * 1.4
			item.Part.Size = Vector3.new(0.35, r, r)
			item.Part.Transparency = 0.35 + (wave * 0.12)
		end
	end
end)
