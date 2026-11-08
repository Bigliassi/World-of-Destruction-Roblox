--!strict
--[[
	GraphicsAndAtmosphereService.script.luau
	World of Destruction (Roblox)
	Configures high-end Snowy Christmas Manhattan golden-blue twilight lighting, PBR specular reflections,
	3D volumetric Roblox clouds, and crisp post-processing.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local function ensurePostEffect(className: string, name: string): any
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

local function ensureVolumetricClouds(): Clouds
	local terrain = Workspace.Terrain
	local existingClouds = terrain:FindFirstChildOfClass("Clouds")
	if existingClouds then
		return existingClouds
	end
	local clouds = Instance.new("Clouds")
	clouds.Name = "WoDVolumetricClouds"
	clouds.Parent = terrain
	return clouds
end

local function configureCrispLighting()
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.18
	Lighting.EnvironmentDiffuseScale = 1.0
	Lighting.EnvironmentSpecularScale = 1.0
	Lighting.ClockTime = 16.0
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(98, 110, 132)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 150, 175)
	Lighting.FogColor = Color3.fromRGB(145, 168, 205)
	Lighting.ColorShift_Top = Color3.fromRGB(195, 212, 240)

	local clouds: Clouds = ensureVolumetricClouds()
	clouds.Enabled = true
	clouds.Cover = 0.65
	clouds.Density = 0.72
	clouds.Color = Color3.fromRGB(195, 210, 235)

	local atmosphere: Atmosphere = ensurePostEffect("Atmosphere", "WoDAtmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(145, 168, 205)
	atmosphere.Decay = Color3.fromRGB(92, 112, 148)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 1.1

	local sky: Sky = ensurePostEffect("Sky", "WoDSky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 11
	sky.StarCount = 2200

	local bloom: BloomEffect = ensurePostEffect("BloomEffect", "WoDBloom")
	bloom.Enabled = true
	bloom.Intensity = 0.18
	bloom.Size = 20
	bloom.Threshold = 2.0

	local cc: ColorCorrectionEffect = ensurePostEffect("ColorCorrectionEffect", "WoDColorCorrection")
	cc.Enabled = true
	cc.Brightness = 0.02
	cc.Contrast = 0.16
	cc.Saturation = 0.12
	cc.TintColor = Color3.fromRGB(246, 249, 255)

	local sunRays: SunRaysEffect = ensurePostEffect("SunRaysEffect", "WoDSunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.65

	local dof: DepthOfFieldEffect = ensurePostEffect("DepthOfFieldEffect", "WoDDepthOfField")
	dof.Enabled = false

	-- Clean up any legacy CityNavigationBeacons or LeoCityViralZones so there is zero visual clutter
	local leoCity = Workspace:FindFirstChild("LeoCity")
	if leoCity and leoCity:FindFirstChild("CityNavigationBeacons") then
		leoCity.CityNavigationBeacons:Destroy()
	end
	if Workspace:FindFirstChild("CityNavigationBeacons") then
		Workspace.CityNavigationBeacons:Destroy()
	end
	if Workspace:FindFirstChild("LeoCityViralZones") then
		Workspace.LeoCityViralZones:Destroy()
	end

	Lighting:SetAttribute("GraphicsConfiguredV1", true)
end

configureCrispLighting()
