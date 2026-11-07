--!strict
--[[
	GraphicsAndAtmosphereService.script.luau
	World of Destruction (Roblox)
	Configures crisp, high-contrast Snowy Christmas Manhattan late-afternoon / twilight lighting & post-processing.
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

local function configureCrispLighting()
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.20
	Lighting.EnvironmentDiffuseScale = 0.92
	Lighting.EnvironmentSpecularScale = 0.95
	Lighting.ClockTime = 15.6
	Lighting.Brightness = 2.55
	Lighting.Ambient = Color3.fromRGB(128, 138, 156)
	Lighting.OutdoorAmbient = Color3.fromRGB(158, 170, 190)
	Lighting.FogColor = Color3.fromRGB(168, 182, 204)
	Lighting.ColorShift_Top = Color3.fromRGB(215, 226, 245)

	local atmosphere: Atmosphere = ensurePostEffect("Atmosphere", "WoDAtmosphere")
	atmosphere.Density = 0.15
	atmosphere.Offset = 0.10
	atmosphere.Color = Color3.fromRGB(185, 200, 222)
	atmosphere.Decay = Color3.fromRGB(125, 140, 165)
	atmosphere.Glare = 0.04
	atmosphere.Haze = 0.45

	local sky: Sky = ensurePostEffect("Sky", "WoDSky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 11
	sky.StarCount = 1500

	local bloom: BloomEffect = ensurePostEffect("BloomEffect", "WoDBloom")
	bloom.Enabled = true
	bloom.Intensity = 0.14
	bloom.Size = 14
	bloom.Threshold = 2.2

	local cc: ColorCorrectionEffect = ensurePostEffect("ColorCorrectionEffect", "WoDColorCorrection")
	cc.Enabled = true
	cc.Brightness = 0.02
	cc.Contrast = 0.12
	cc.Saturation = 0.06
	cc.TintColor = Color3.fromRGB(246, 249, 255)

	local sunRays: SunRaysEffect = ensurePostEffect("SunRaysEffect", "WoDSunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.04
	sunRays.Spread = 0.50

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
