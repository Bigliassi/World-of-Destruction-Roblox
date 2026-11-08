--!strict
-- WeatherTimeService.script.luau
-- High-End Snowy Christmas NYC golden-blue twilight weather system for Leo City:
-- Keeps ClockTime at 16.0 (magical Manhattan winter golden-blue twilight where the sky is rich royal/slate blue,
-- snow is crisp white, and every building window, Christmas tree, and concert spotlight glows warmly),
-- 3D Volumetric Clouds under Workspace.Terrain, full PBR diffuse/specular scales (1.0),
-- BloomEffect (Intensity = 0.18, Size = 20, Threshold = 2.0), and gentle falling snowflakes across the city.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- LIGHTING POST-PROCESSING, VOLUMETRIC CLOUDS & ATMOSPHERE SETUP
--------------------------------------------------------------------------------
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.18
Lighting.EnvironmentDiffuseScale = 1.0
Lighting.EnvironmentSpecularScale = 1.0

local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
if not clouds then
	clouds = Instance.new("Clouds")
	clouds.Name = "WoDVolumetricClouds"
	clouds.Parent = Workspace.Terrain
end
clouds.Enabled = true
clouds.Cover = 0.65
clouds.Density = 0.72
clouds.Color = Color3.fromRGB(195, 210, 235)

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.22
atmosphere.Offset = 0.15
atmosphere.Color = Color3.fromRGB(145, 168, 205)
atmosphere.Decay = Color3.fromRGB(92, 112, 148)
atmosphere.Glare = 0.12
atmosphere.Haze = 1.1

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Parent = Lighting
end
bloom.Enabled = true
bloom.Intensity = 0.18
bloom.Size = 20
bloom.Threshold = 2.0

local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
if not sunRays then
	sunRays = Instance.new("SunRaysEffect")
	sunRays.Parent = Lighting
end
sunRays.Enabled = true
sunRays.Intensity = 0.08
sunRays.Spread = 0.65

local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Parent = Lighting
end
colorCorrection.Enabled = true
colorCorrection.Brightness = 0.02
colorCorrection.Contrast = 0.16
colorCorrection.Saturation = 0.12
colorCorrection.TintColor = Color3.fromRGB(246, 249, 255)

--------------------------------------------------------------------------------
-- WEATHER & TIME PRESETS (SNOWY CHRISTMAS MANHATTAN TWILIGHT)
--------------------------------------------------------------------------------
type WeatherPreset = {
	name: string,
	displayName: string,
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	fogColor: Color3,
	colorShiftTop: Color3,
	atmosphereDensity: number,
	atmosphereOffset: number,
	atmosphereGlare: number,
	atmosphereHaze: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	cloudCover: number,
	cloudDensity: number,
	cloudColor: Color3,
	roadReflectance: number,
	roadMaterial: Enum.Material,
	gripMultiplier: number,
	isSnowing: boolean,
	isRaining: boolean,
	snowRate: number,
	rainRate: number,
	bloomIntensity: number,
}

local PRESETS: { WeatherPreset } = {
	{
		name = "Snowstorm",
		displayName = "Central Park Christmas Snowfall",
		clockTime = 16.0,
		brightness = 2.8,
		ambient = Color3.fromRGB(98, 110, 132),
		outdoorAmbient = Color3.fromRGB(135, 150, 175),
		fogColor = Color3.fromRGB(145, 168, 205),
		colorShiftTop = Color3.fromRGB(195, 212, 240),
		atmosphereDensity = 0.22,
		atmosphereOffset = 0.15,
		atmosphereGlare = 0.12,
		atmosphereHaze = 1.1,
		atmosphereColor = Color3.fromRGB(145, 168, 205),
		atmosphereDecay = Color3.fromRGB(92, 112, 148),
		cloudCover = 0.65,
		cloudDensity = 0.72,
		cloudColor = Color3.fromRGB(195, 210, 235),
		roadReflectance = 0.16,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.96,
		isSnowing = true,
		isRaining = false,
		snowRate = 300,
		rainRate = 0,
		bloomIntensity = 0.18,
	},
	{
		name = "CloudyNYC",
		displayName = "5th Avenue Holiday Flurries",
		clockTime = 16.0,
		brightness = 2.8,
		ambient = Color3.fromRGB(98, 110, 132),
		outdoorAmbient = Color3.fromRGB(135, 150, 175),
		fogColor = Color3.fromRGB(145, 168, 205),
		colorShiftTop = Color3.fromRGB(195, 212, 240),
		atmosphereDensity = 0.22,
		atmosphereOffset = 0.15,
		atmosphereGlare = 0.12,
		atmosphereHaze = 1.1,
		atmosphereColor = Color3.fromRGB(145, 168, 205),
		atmosphereDecay = Color3.fromRGB(92, 112, 148),
		cloudCover = 0.68,
		cloudDensity = 0.74,
		cloudColor = Color3.fromRGB(195, 210, 235),
		roadReflectance = 0.16,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.97,
		isSnowing = true,
		isRaining = false,
		snowRate = 240,
		rainRate = 0,
		bloomIntensity = 0.18,
	},
}

--------------------------------------------------------------------------------
-- OVERHEAD NYC PRECIPITATION CANOPY (GENTLE CHRISTMAS SNOWFLAKES)
--------------------------------------------------------------------------------
local existingCanopy = Workspace:FindFirstChild("NYCPrecipitationCanopy")
if existingCanopy then
	existingCanopy:Destroy()
end

local canopyPart = Instance.new("Part")
canopyPart.Name = "NYCPrecipitationCanopy"
canopyPart.Size = Vector3.new(520, 2, 520)
canopyPart.Position = Vector3.new(0, 96, 0)
canopyPart.Anchored = true
canopyPart.CanCollide = false
canopyPart.CanQuery = false
canopyPart.CanTouch = false
canopyPart.CastShadow = false
canopyPart.Transparency = 1
canopyPart.Parent = Workspace

local snowEmitter = Instance.new("ParticleEmitter")
snowEmitter.Name = "SnowEmitter"
snowEmitter.Color = ColorSequence.new(Color3.fromRGB(246, 250, 255))
snowEmitter.LightEmission = 0.35
snowEmitter.LightInfluence = 0.45
snowEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.38),
	NumberSequenceKeypoint.new(0.5, 0.48),
	NumberSequenceKeypoint.new(1, 0.28),
})
snowEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.18),
	NumberSequenceKeypoint.new(0.8, 0.28),
	NumberSequenceKeypoint.new(1, 0.90),
})
snowEmitter.Lifetime = NumberRange.new(3.5, 5.2)
snowEmitter.Rate = 300
snowEmitter.Speed = NumberRange.new(18, 28)
snowEmitter.SpreadAngle = Vector2.new(16, 16)
snowEmitter.Acceleration = Vector3.new(-4, -3, 2)
snowEmitter.RotSpeed = NumberRange.new(-40, 40)
snowEmitter.EmissionDirection = Enum.NormalId.Bottom
snowEmitter.Enabled = true
snowEmitter.Parent = canopyPart

local rainEmitter = Instance.new("ParticleEmitter")
rainEmitter.Name = "RainEmitter"
rainEmitter.Rate = 0
rainEmitter.Enabled = false
rainEmitter.Parent = canopyPart

-- Follow active players on Heartbeat so gentle Christmas snow surrounds the player & nearby skyscrapers
RunService.Heartbeat:Connect(function()
	local sumPos = Vector3.zero
	local count = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			sumPos += hrp.Position
			count += 1
		end
	end
	if count > 0 then
		local avg = sumPos / count
		canopyPart.Position = Vector3.new(avg.X, 96, avg.Z)
	else
		local cam = Workspace.CurrentCamera
		if cam then
			local cPos = cam.CFrame.Position
			canopyPart.Position = Vector3.new(cPos.X, 96, cPos.Z)
		end
	end
end)

local function updateRoadWetness(reflectance: number, material: Enum.Material)
	local city = Workspace:FindFirstChild("LeoCity")
	local roads = city and city:FindFirstChild("Roads")
	if not roads then
		return
	end
	for _, part in ipairs(roads:GetChildren()) do
		if part:IsA("BasePart") and (part.Name == "RoadNS" or part.Name == "RoadEW" or part.Name == "GrandCentralAveNS") then
			part.Reflectance = reflectance
			part.Material = material
		end
	end
end

--------------------------------------------------------------------------------
-- APPLY WEATHER & CYCLE LOOP
--------------------------------------------------------------------------------
local DWELL_DURATION = 60.0
local TRANSITION_DURATION = 6.0
local currentPresetIndex = 1

local function applyPreset(preset: WeatherPreset, instant: boolean?)
	Workspace:SetAttribute("CurrentWeather", preset.name)
	Workspace:SetAttribute("WeatherState", preset.name)
	Workspace:SetAttribute("WeatherDisplayName", preset.displayName)
	Workspace:SetAttribute("TimeOfDayState", preset.name)
	Workspace:SetAttribute("RoadGripMultiplier", preset.gripMultiplier)
	Workspace:SetAttribute("IsSnowing", preset.isSnowing)
	Workspace:SetAttribute("IsRaining", preset.isRaining)
	Workspace:SetAttribute("ClockTime", preset.clockTime)

	if clouds then
		clouds.Enabled = true
		clouds.Cover = preset.cloudCover
		clouds.Density = preset.cloudDensity
		clouds.Color = preset.cloudColor
	end

	if instant then
		Lighting.ClockTime = preset.clockTime
		Lighting.Brightness = preset.brightness
		Lighting.Ambient = preset.ambient
		Lighting.OutdoorAmbient = preset.outdoorAmbient
		Lighting.FogColor = preset.fogColor
		Lighting.ColorShift_Top = preset.colorShiftTop
		if atmosphere then
			atmosphere.Density = preset.atmosphereDensity
			atmosphere.Offset = preset.atmosphereOffset
			atmosphere.Glare = preset.atmosphereGlare
			atmosphere.Haze = preset.atmosphereHaze
			atmosphere.Color = preset.atmosphereColor
			atmosphere.Decay = preset.atmosphereDecay
		end
		if bloom then
			bloom.Intensity = preset.bloomIntensity
			bloom.Size = 20
			bloom.Threshold = 2.0
		end
	else
		local tweenInfo = TweenInfo.new(TRANSITION_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(Lighting, tweenInfo, {
			ClockTime = preset.clockTime,
			Brightness = preset.brightness,
			Ambient = preset.ambient,
			OutdoorAmbient = preset.outdoorAmbient,
			FogColor = preset.fogColor,
			ColorShift_Top = preset.colorShiftTop,
		}):Play()

		if atmosphere then
			TweenService:Create(atmosphere, tweenInfo, {
				Density = preset.atmosphereDensity,
				Offset = preset.atmosphereOffset,
				Glare = preset.atmosphereGlare,
				Haze = preset.atmosphereHaze,
				Color = preset.atmosphereColor,
				Decay = preset.atmosphereDecay,
			}):Play()
		end

		if bloom then
			bloom.Size = 20
			bloom.Threshold = 2.0
			TweenService:Create(bloom, tweenInfo, {
				Intensity = preset.bloomIntensity,
			}):Play()
		end
	end

	snowEmitter.Rate = preset.snowRate
	snowEmitter.Enabled = preset.isSnowing
	rainEmitter.Rate = 0
	rainEmitter.Enabled = false
	updateRoadWetness(preset.roadReflectance, preset.roadMaterial)
end

-- Initialize immediately with Snowy Christmas Manhattan at ClockTime = 16.0
applyPreset(PRESETS[1], true)

task.spawn(function()
	while true do
		task.wait(DWELL_DURATION)
		currentPresetIndex = (currentPresetIndex % #PRESETS) + 1
		applyPreset(PRESETS[currentPresetIndex], false)
	end
end)

print("[WeatherTimeService] Snowy Christmas Manhattan twilight weather cycle active at ClockTime 16.0 with 3D volumetric clouds.")
