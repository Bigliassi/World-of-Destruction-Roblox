--!strict
--[[
	GraphicsAndAtmosphereService.script.luau
	World of Destruction (Roblox)
	Configures crisp, high-contrast New York Winter Overcast lighting & post-processing.
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
	Lighting.ShadowSoftness = 0.22
	Lighting.EnvironmentDiffuseScale = 0.90
	Lighting.EnvironmentSpecularScale = 0.95
	Lighting.ClockTime = 14.8
	Lighting.Brightness = 2.65
	Lighting.Ambient = Color3.fromRGB(115, 125, 142)
	Lighting.OutdoorAmbient = Color3.fromRGB(145, 158, 178)
	Lighting.FogColor = Color3.fromRGB(125, 138, 158)
	Lighting.ColorShift_Top = Color3.fromRGB(185, 202, 228)

	local atmosphere: Atmosphere = ensurePostEffect("Atmosphere", "WoDAtmosphere")
	atmosphere.Density = 0.19
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(138, 152, 175)
	atmosphere.Decay = Color3.fromRGB(88, 100, 120)
	atmosphere.Glare = 0.06
	atmosphere.Haze = 0.85

	local sky: Sky = ensurePostEffect("Sky", "WoDSky")
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 11
	sky.StarCount = 1200

	local bloom: BloomEffect = ensurePostEffect("BloomEffect", "WoDBloom")
	bloom.Enabled = true
	bloom.Intensity = 0.22
	bloom.Size = 16
	bloom.Threshold = 1.90

	local cc: ColorCorrectionEffect = ensurePostEffect("ColorCorrectionEffect", "WoDColorCorrection")
	cc.Enabled = true
	cc.Brightness = 0.02
	cc.Contrast = 0.14
	cc.Saturation = 0.08
	cc.TintColor = Color3.fromRGB(242, 246, 255)

	local sunRays: SunRaysEffect = ensurePostEffect("SunRaysEffect", "WoDSunRays")
	sunRays.Enabled = true
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.55

	local dof: DepthOfFieldEffect = ensurePostEffect("DepthOfFieldEffect", "WoDDepthOfField")
	dof.Enabled = false

	-- Clean up any legacy CityNavigationBeacons so there is zero Z-fighting with pads
	local leoCity = Workspace:FindFirstChild("LeoCity")
	if leoCity and leoCity:FindFirstChild("CityNavigationBeacons") then
		leoCity.CityNavigationBeacons:Destroy()
	end
	if Workspace:FindFirstChild("CityNavigationBeacons") then
		Workspace.CityNavigationBeacons:Destroy()
	end

	Lighting:SetAttribute("GraphicsConfiguredV1", true)
end

configureCrispLighting()
