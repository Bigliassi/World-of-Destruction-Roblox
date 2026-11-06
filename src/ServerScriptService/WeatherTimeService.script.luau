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
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	roadReflectance: number,
	roadMaterial: Enum.Material,
	gripMultiplier: number,
	isRaining: boolean,
	hasLightning: boolean,
	bloomIntensity: number,
}

local PRESETS: { WeatherPreset } = {
	{
		name = "Sunny",
		clockTime = 13.5,
		brightness = 3.0,
		ambient = Color3.fromRGB(115, 125, 140),
		outdoorAmbient = Color3.fromRGB(145, 155, 175),
		colorShiftTop = Color3.fromRGB(255, 250, 235),
		atmosphereDensity = 0.26,
		atmosphereColor = Color3.fromRGB(190, 220, 255),
		atmosphereDecay = Color3.fromRGB(120, 155, 200),
		roadReflectance = 0.04,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 1.0,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 0.65,
	},
	{
		name = "GoldenHourSunset",
		clockTime = 17.8,
		brightness = 2.4,
		ambient = Color3.fromRGB(125, 85, 70),
		outdoorAmbient = Color3.fromRGB(175, 110, 85),
		colorShiftTop = Color3.fromRGB(255, 165, 95),
		atmosphereDensity = 0.34,
		atmosphereColor = Color3.fromRGB(255, 150, 95),
		atmosphereDecay = Color3.fromRGB(130, 65, 85),
		roadReflectance = 0.12,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.98,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 0.95,
	},
	{
		name = "NeonNight",
		clockTime = 0.5,
		brightness = 1.2,
		ambient = Color3.fromRGB(38, 46, 72),
		outdoorAmbient = Color3.fromRGB(52, 64, 98),
		colorShiftTop = Color3.fromRGB(95, 135, 255),
		atmosphereDensity = 0.38,
		atmosphereColor = Color3.fromRGB(28, 36, 62),
		atmosphereDecay = Color3.fromRGB(16, 22, 42),
		roadReflectance = 0.18,
		roadMaterial = Enum.Material.SmoothPlastic,
		gripMultiplier = 0.95,
		isRaining = false,
		hasLightning = false,
		bloomIntensity = 1.35,
	},
	{
		name = "Rainstorm",
		clockTime = 22.0,
		brightness = 0.95,
		ambient = Color3.fromRGB(32, 42, 62),
		outdoorAmbient = Color3.fromRGB(45, 58, 82),
		colorShiftTop = Color3.fromRGB(120, 160, 220),
		atmosphereDensity = 0.48,
		atmosphereColor = Color3.fromRGB(35, 45, 68),
		atmosphereDecay = Color3.fromRGB(20, 26, 44),
		roadReflectance = 0.38,
		roadMaterial = Enum.Material.Glass,
		gripMultiplier = 0.85,
		isRaining = true,
		hasLightning = true,
		bloomIntensity = 1.45,
	},
}

--------------------------------------------------------------------------------
-- RAIN CANOPY & ROAD REFLECTION HELPERS
--------------------------------------------------------------------------------
local rainPart = Instance.new("Part")
rainPart.Name = "LeoCityRainCanopy"
rainPart.Size = Vector3.new(1400, 2, 1400)
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
		if part:IsA("BasePart") and (part.Name == "RoadNS" or part.Name == "RoadEW") then
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

	local strikeX = math.random(-520, 520)
	local strikeZ = math.random(-520, 520)

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
local DWELL_DURATION = 55.0
local TRANSITION_DURATION = 8.0
local currentPresetIndex = 1

local function applyPreset(preset: WeatherPreset)
	Workspace:SetAttribute("CurrentWeather", preset.name)
	Workspace:SetAttribute("WeatherState", preset.name)
	Workspace:SetAttribute("TimeOfDayState", preset.name)
	Workspace:SetAttribute("RoadGripMultiplier", preset.gripMultiplier)
	Workspace:SetAttribute("IsRaining", preset.isRaining)
	Workspace:SetAttribute("ClockTime", preset.clockTime)

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
			Color = preset.atmosphereColor,
			Decay = preset.atmosphereDecay,
		}):Play()
	end

	if bloom then
		TweenService:Create(bloom, tweenInfo, {
			Intensity = preset.bloomIntensity,
		}):Play()
	end

	rainEmitter.Enabled = preset.isRaining
	updateRoadWetness(preset.roadReflectance, preset.roadMaterial)
end

-- Initialize immediately with Sunny or GoldenHour, then cycle continuously
applyPreset(PRESETS[currentPresetIndex])

task.spawn(function()
	while true do
		local preset = PRESETS[currentPresetIndex]
		local elapsed = 0
		while elapsed < DWELL_DURATION do
			task.wait(4.0)
			elapsed += 4.0
			if preset.hasLightning and math.random() < 0.35 then
				triggerLightningStrike()
			end
		end

		currentPresetIndex = (currentPresetIndex % #PRESETS) + 1
		applyPreset(PRESETS[currentPresetIndex])
	end
end)

print("[WeatherTimeService] Dynamic Day/Night & Weather cycle active.")
