--!strict
-- WeatherTimeService.script.luau
-- Dynamic Day/Night cycle and weather system for Leo City:
-- Cycles smoothly through Sunny, Golden Hour Sunset, Neon Night, and Rainstorm
-- (with wet road reflections & lightning flashes), synced via Lighting and Workspace attributes.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

--------------------------------------------------------------------------------
-- LIGHTING POST-PROCESSING & ATMOSPHERE SETUP
--------------------------------------------------------------------------------
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
end

local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = 0.15
	colorCorrection.Parent = Lighting
end

--------------------------------------------------------------------------------
-- WEATHER & TIME PRESETS
--------------------------------------------------------------------------------
type WeatherPreset = {
	name: string,
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	atmosphereDensity: number,
	atmosphereGlare: number,
	atmosphereHaze: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	roadReflectance: number,
	roadMaterial: Enum.Material,
	gripMultiplier: number,
	isRaining: boolean,
	hasLightning: boolean,
	bloomIntensity: number,
	requiresNightCycle: boolean,
}

local PRESETS: { WeatherPreset } = {
	{
		name = "Sunny",
		clockTime = 13.5,
		brightness = 3.6,
		ambient = Color3.fromRGB(155, 162, 175),
		outdoorAmbient = Color3.fromRGB(185, 192, 205),
		colorShiftTop = Color3.fromRGB(255, 252, 240),
		atmosphereDensity = 0.16,
		atmosphereGlare = 0.05,
		atmosphereHaze = 0.4,
		atmosphereColor = Color3.fromRGB(205, 228, 255),
		atmosphereDecay = Color3.fromRGB(165, 190, 225),
		roadReflectance = 0.04,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 1.0,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 0.30,
		requiresNightCycle = false,
	},
	{
		name = "GoldenAfternoon",
		clockTime = 15.5,
		brightness = 3.35,
		ambient = Color3.fromRGB(162, 155, 150),
		outdoorAmbient = Color3.fromRGB(195, 182, 172),
		colorShiftTop = Color3.fromRGB(255, 232, 195),
		atmosphereDensity = 0.18,
		atmosphereGlare = 0.06,
		atmosphereHaze = 0.45,
		atmosphereColor = Color3.fromRGB(255, 215, 175),
		atmosphereDecay = Color3.fromRGB(185, 145, 135),
		roadReflectance = 0.06,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 1.0,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 0.35,
		requiresNightCycle = false,
	},
	{
		name = "NeonNight",
		clockTime = 0.5,
		brightness = 1.6,
		ambient = Color3.fromRGB(58, 68, 96),
		outdoorAmbient = Color3.fromRGB(75, 88, 122),
		colorShiftTop = Color3.fromRGB(115, 155, 255),
		atmosphereDensity = 0.28,
		atmosphereGlare = 0.10,
		atmosphereHaze = 0.75,
		atmosphereColor = Color3.fromRGB(38, 48, 78),
		atmosphereDecay = Color3.fromRGB(24, 32, 54),
		roadReflectance = 0.18,
		roadMaterial = Enum.Material.SmoothPlastic,
		gripMultiplier = 0.95,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 0.85,
		requiresNightCycle = true,
	},
	{
		name = "Rainstorm",
		clockTime = 22.0,
		brightness = 1.35,
		ambient = Color3.fromRGB(52, 64, 88),
		outdoorAmbient = Color3.fromRGB(68, 82, 110),
		colorShiftTop = Color3.fromRGB(135, 175, 230),
		atmosphereDensity = 0.36,
		atmosphereGlare = 0.12,
		atmosphereHaze = 0.95,
		atmosphereColor = Color3.fromRGB(48, 60, 86),
		atmosphereDecay = Color3.fromRGB(28, 36, 58),
		roadReflectance = 0.32,
		roadMaterial = Enum.Material.Glass,
		gripMultiplier = 0.85,
		isRaining = true,
		hasLightning = true,
		bloomIntensity = 0.95,
		requiresNightCycle = true,
	},
}

--------------------------------------------------------------------------------
-- RAIN CANOPY & ROAD REFLECTION HELPERS
--------------------------------------------------------------------------------
local rainPart = Instance.new("Part")
rainPart.Name = "LeoCityRainCanopy"
rainPart.Size = Vector3.new(2200, 2, 2200)
rainPart.Position = Vector3.new(0, 190, 0)
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.Transparency = 1
rainPart.Parent = Workspace

local rainEmitter = Instance.new("ParticleEmitter")
rainEmitter.Name = "RainDrops"
rainEmitter.Color = ColorSequence.new(Color3.fromRGB(185, 215, 255))
rainEmitter.Size = NumberSequence.new(0.25)
rainEmitter.Transparency = NumberSequence.new(0.35, 0.8)
rainEmitter.Lifetime = NumberRange.new(1.2, 1.6)
rainEmitter.Rate = 450
rainEmitter.Speed = NumberRange.new(125, 150)
rainEmitter.EmissionDirection = Enum.NormalId.Bottom
rainEmitter.Enabled = false
rainEmitter.Parent = rainPart

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
-- LIGHTNING BOLT & FLASH GENERATOR
--------------------------------------------------------------------------------
local function triggerLightningStrike()
	Workspace:SetAttribute("LightningFlash", true)

	local strikeX = math.random(-820, 820)
	local strikeZ = math.random(-820, 820)

	local boltModel = Instance.new("Model")
	boltModel.Name = "LightningBolt"
	for seg = 1, 6 do
		local y = 240 - (seg - 0.5) * 38
		local jitterX = math.random(-14, 14)
		local jitterZ = math.random(-14, 14)
		local p = Instance.new("Part")
		p.Size = Vector3.new(2.2, 42, 2.2)
		p.CFrame = CFrame.new(strikeX + jitterX, y, strikeZ + jitterZ) * CFrame.Angles(0, 0, math.rad(math.random(-18, 18)))
		p.Color = Color3.fromRGB(215, 238, 255)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.Parent = boltModel
	end
	boltModel.Parent = Workspace
	Debris:AddItem(boltModel, 0.28)

	local oldBrightness = Lighting.Brightness
	local oldAmbient = Lighting.OutdoorAmbient
	Lighting.Brightness = 6.5
	Lighting.OutdoorAmbient = Color3.fromRGB(210, 230, 255)

	task.delay(0.12, function()
		Lighting.Brightness = oldBrightness * 1.4
		task.wait(0.08)
		Lighting.Brightness = 5.0
		task.wait(0.12)
		Lighting.Brightness = oldBrightness
		Lighting.OutdoorAmbient = oldAmbient
		Workspace:SetAttribute("LightningFlash", false)
	end)
end

--------------------------------------------------------------------------------
-- APPLY WEATHER & CYCLE LOOP
--------------------------------------------------------------------------------
local DWELL_DURATION = 65.0
local TRANSITION_DURATION = 8.0
local currentPresetIndex = 1

if Workspace:GetAttribute("AllowNightWeatherCycle") == nil then
	Workspace:SetAttribute("AllowNightWeatherCycle", false)
end

local function applyPreset(preset: WeatherPreset, instant: boolean?)
	Workspace:SetAttribute("CurrentWeather", preset.name)
	Workspace:SetAttribute("WeatherState", preset.name)
	Workspace:SetAttribute("TimeOfDayState", preset.name)
	Workspace:SetAttribute("RoadGripMultiplier", preset.gripMultiplier)
	Workspace:SetAttribute("IsRaining", preset.isRaining)
	Workspace:SetAttribute("ClockTime", preset.clockTime)

	if instant then
		Lighting.ClockTime = preset.clockTime
		Lighting.Brightness = preset.brightness
		Lighting.Ambient = preset.ambient
		Lighting.OutdoorAmbient = preset.outdoorAmbient
		Lighting.ColorShift_Top = preset.colorShiftTop
		if atmosphere then
			atmosphere.Density = preset.atmosphereDensity
			atmosphere.Glare = preset.atmosphereGlare
			atmosphere.Haze = preset.atmosphereHaze
			atmosphere.Color = preset.atmosphereColor
			atmosphere.Decay = preset.atmosphereDecay
		end
		if bloom then
			bloom.Intensity = preset.bloomIntensity
		end
	else
		local tweenInfo = TweenInfo.new(TRANSITION_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(Lighting, tweenInfo, {
			ClockTime = preset.clockTime,
			Brightness = preset.brightness,
			Ambient = preset.ambient,
			OutdoorAmbient = preset.outdoorAmbient,
			ColorShift_Top = preset.colorShiftTop,
		}):Play()

		if atmosphere then
			TweenService:Create(atmosphere, tweenInfo, {
				Density = preset.atmosphereDensity,
				Glare = preset.atmosphereGlare,
				Haze = preset.atmosphereHaze,
				Color = preset.atmosphereColor,
				Decay = preset.atmosphereDecay,
			}):Play()
		end

		if bloom then
			TweenService:Create(bloom, tweenInfo, {
				Intensity = preset.bloomIntensity,
			}):Play()
		end
	end

	rainEmitter.Enabled = preset.isRaining
	updateRoadWetness(preset.roadReflectance, preset.roadMaterial)
end

-- Initialize immediately with Bright Sunny Day (13.5 ClockTime, 3.6 Brightness)
applyPreset(PRESETS[1], true)

Workspace:GetAttributeChangedSignal("AllowNightWeatherCycle"):Connect(function()
	local allowNight = Workspace:GetAttribute("AllowNightWeatherCycle") == true
	if not allowNight and PRESETS[currentPresetIndex].requiresNightCycle then
		currentPresetIndex = 1
		applyPreset(PRESETS[currentPresetIndex], false)
	end
end)

task.spawn(function()
	while true do
		local preset = PRESETS[currentPresetIndex]
		local elapsed = 0
		while elapsed < DWELL_DURATION do
			task.wait(4.0)
			elapsed += 4.0
			if preset.hasLightning and (Workspace:GetAttribute("AllowNightWeatherCycle") == true) and math.random() < 0.35 then
				triggerLightningStrike()
			end
		end

		local allowNight = Workspace:GetAttribute("AllowNightWeatherCycle") == true
		if allowNight then
			currentPresetIndex = (currentPresetIndex % #PRESETS) + 1
		else
			-- Keep Leo City bright and sunlit between Sunny (13.5) and GoldenAfternoon (15.5)
			currentPresetIndex = if currentPresetIndex == 1 then 2 else 1
		end
		applyPreset(PRESETS[currentPresetIndex], false)
	end
end)

print("[WeatherTimeService] Dynamic Day/Night & Weather cycle active.")
