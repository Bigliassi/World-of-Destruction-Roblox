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
	-- Core Lighting properties tuned for moody, cinematic New York Winter Overcast / Snowy & Rainy Dusk
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.28
	Lighting.EnvironmentDiffuseScale = 0.85
	Lighting.EnvironmentSpecularScale = 0.92
	Lighting.ClockTime = 16.4
	Lighting.Brightness = 1.85
	Lighting.Ambient = Color3.fromRGB(78, 88, 105)
	Lighting.OutdoorAmbient = Color3.fromRGB(95, 108, 128)
	Lighting.FogColor = Color3.fromRGB(85, 96, 115)
	Lighting.ColorShift_Top = Color3.fromRGB(165, 182, 210)

	-- Atmosphere (moody slate-blue NYC winter overcast haze)
	local atmosphere: Atmosphere = ensurePostEffect("Atmosphere", "WoDAtmosphere")
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.18
	atmosphere.Color = Color3.fromRGB(110, 124, 145)
	atmosphere.Decay = Color3.fromRGB(68, 78, 96)
	atmosphere.Glare = 0.08
	atmosphere.Haze = 1.65

	-- Sky
	local sky: Sky = ensurePostEffect("Sky", "WoDSky")
	sky.CelestialBodiesShown = false
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 11
	sky.StarCount = 600

	-- BloomEffect (subtle so taillights and neon signs look crisp and NEVER bloom into blurry blobs!)
	local bloom: BloomEffect = ensurePostEffect("BloomEffect", "WoDBloom")
	bloom.Enabled = true
	bloom.Intensity = 0.24
	bloom.Size = 16
	bloom.Threshold = 1.85

	-- ColorCorrectionEffect (cinematic NYC steel-blue & warm-amber contrast)
	local cc: ColorCorrectionEffect = ensurePostEffect("ColorCorrectionEffect", "WoDColorCorrection")
	cc.Enabled = true
	cc.Brightness = 0.01
	cc.Contrast = 0.16
	cc.Saturation = -0.08
	cc.TintColor = Color3.fromRGB(232, 238, 248)

	-- SunRaysEffect (subtle winter dusk rays between Manhattan skyscrapers)
	local sunRays: SunRaysEffect = ensurePostEffect("SunRaysEffect", "WoDSunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.04
	sunRays.Spread = 0.55

	-- Subtle DepthOfFieldEffect (keeps foreground razor-sharp, softens distant misty skyline)
	local dof: DepthOfFieldEffect = ensurePostEffect("DepthOfFieldEffect", "WoDDepthOfField")
	dof.Enabled = true
	dof.FarIntensity = 0.10
	dof.FocusDistance = 175
	dof.InFocusRadius = 250
	dof.NearIntensity = 0

	Lighting:SetAttribute("GraphicsConfiguredV1", true)
end

configureCrispLighting()

--------------------------------------------------------------------------------
-- 2. Subtle Ground Halo Rings on Speed Shop & Repair Bay Pads (NO Floating BillboardGui Overlap!)
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
		Subtitle = "VEHICLE DEALER & GARAGE",
		Position = Vector3.new(58, 0, -24),
		Color = Color3.fromRGB(0, 225, 255),
		PillarHeight = 0,
		RingRadius = 11,
	},
	{
		Id = "SpeedShopEast",
		Title = "SPEED SHOP [B]",
		Subtitle = "VEHICLE DEALER & GARAGE",
		Position = Vector3.new(200, 0, 0),
		Color = Color3.fromRGB(0, 225, 255),
		PillarHeight = 0,
		RingRadius = 13,
	},
	{
		Id = "MechanicBayPlaza",
		Title = "REPAIR BAY [R]",
		Subtitle = "100% REPAIR & NITRO",
		Position = Vector3.new(-58, 0, -24),
		Color = Color3.fromRGB(60, 245, 130),
		PillarHeight = 0,
		RingRadius = 11,
	},
	{
		Id = "MechanicBayWest",
		Title = "REPAIR BAY [R]",
		Subtitle = "100% REPAIR & NITRO",
		Position = Vector3.new(-200, 0, 0),
		Color = Color3.fromRGB(60, 245, 130),
		PillarHeight = 0,
		RingRadius = 13,
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

		-- Subtle Ground Pad Halo Ring only (NO floating BillboardGui text cards that overlap on screen!)
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
		groundRing.Transparency = 0.58
		groundRing.Size = Vector3.new(0.22, spec.RingRadius * 2, spec.RingRadius * 2)
		groundRing.CFrame = CFrame.new(spec.Position + Vector3.new(0, 0.18, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		groundRing.Parent = model

		local pointLight = Instance.new("PointLight")
		pointLight.Color = spec.Color
		pointLight.Brightness = 1.4
		pointLight.Range = 26
		pointLight.Shadows = false
		pointLight.Parent = groundRing

		table.insert(animatedRings, {
			Part = groundRing,
			BasePos = spec.Position + Vector3.new(0, 0.18, 0),
			BaseRadius = spec.RingRadius,
			Phase = idx * 0.85,
		})
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
