--!strict
-- WeatherTimeService.script.luau
-- Dynamic NYC Winter Overcast / Snowy & Rainy Dusk weather system for Leo City:
-- Alternates between "NYC Snowy Flurries" ("Snowstorm"), "NYC Rainy Overcast" ("Rainstorm"),
-- and "NYC Cloudy Dusk" ("CloudyNYC") with continuous overhead snow & rain precipitation canopy
-- (Workspace.NYCPrecipitationCanopy) following players and wet NYC road reflections.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
atmosphere.Density = 0.34
atmosphere.Offset = 0.18
atmosphere.Color = Color3.fromRGB(110, 124, 145)
atmosphere.Decay = Color3.fromRGB(68, 78, 96)
atmosphere.Glare = 0.08
atmosphere.Haze = 1.65

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Parent = Lighting
end
bloom.Enabled = true
bloom.Intensity = 0.24
bloom.Size = 16
bloom.Threshold = 1.85

local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Parent = Lighting
end
colorCorrection.Enabled = true
colorCorrection.Brightness = 0.01
colorCorrection.Contrast = 0.16
colorCorrection.Saturation = -0.08
colorCorrection.TintColor = Color3.fromRGB(232, 238, 248)

--------------------------------------------------------------------------------
-- WEATHER & TIME PRESETS (NYC WINTER OVERCAST / SNOWY & RAINY DUSK)
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
	roadReflectance: number,
	roadMaterial: Enum.Material,
	gripMultiplier: number,
	isSnowing: boolean,
	isRaining: boolean,
	snowRate: number,
	rainRate: number,
	hasLightning: boolean,
	bloomIntensity: number,
}

local PRESETS: { WeatherPreset } = {
	{
		name = "Snowstorm",
		displayName = "NYC Snowy Flurries",
		clockTime = 16.4,
		brightness = 1.85,
		ambient = Color3.fromRGB(78, 88, 105),
		outdoorAmbient = Color3.fromRGB(95, 108, 128),
		fogColor = Color3.fromRGB(85, 96, 115),
		colorShiftTop = Color3.fromRGB(165, 182, 210),
		atmosphereDensity = 0.34,
		atmosphereOffset = 0.18,
		atmosphereGlare = 0.08,
		atmosphereHaze = 1.65,
		atmosphereColor = Color3.fromRGB(110, 124, 145),
		atmosphereDecay = Color3.fromRGB(68, 78, 96),
		roadReflectance = 0.14,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.94,
		isSnowing = true,
		isRaining = true,
		snowRate = 420,
		rainRate = 180,
		hasLightning = false,
		bloomIntensity = 0.24,
	},
	{
		name = "Rainstorm",
		displayName = "NYC Rainy Overcast",
		clockTime = 16.4,
		brightness = 1.85,
		ambient = Color3.fromRGB(78, 88, 105),
		outdoorAmbient = Color3.fromRGB(95, 108, 128),
		fogColor = Color3.fromRGB(85, 96, 115),
		colorShiftTop = Color3.fromRGB(152, 172, 202),
		atmosphereDensity = 0.34,
		atmosphereOffset = 0.18,
		atmosphereGlare = 0.08,
		atmosphereHaze = 1.65,
		atmosphereColor = Color3.fromRGB(110, 124, 145),
		atmosphereDecay = Color3.fromRGB(68, 78, 96),
		roadReflectance = 0.18,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.92,
		isSnowing = true,
		isRaining = true,
		snowRate = 180,
		rainRate = 480,
		hasLightning = true,
		bloomIntensity = 0.24,
	},
	{
		name = "CloudyNYC",
		displayName = "NYC Cloudy Dusk",
		clockTime = 16.4,
		brightness = 1.85,
		ambient = Color3.fromRGB(78, 88, 105),
		outdoorAmbient = Color3.fromRGB(95, 108, 128),
		fogColor = Color3.fromRGB(85, 96, 115),
		colorShiftTop = Color3.fromRGB(165, 182, 210),
		atmosphereDensity = 0.34,
		atmosphereOffset = 0.18,
		atmosphereGlare = 0.08,
		atmosphereHaze = 1.65,
		atmosphereColor = Color3.fromRGB(110, 124, 145),
		atmosphereDecay = Color3.fromRGB(68, 78, 96),
		roadReflectance = 0.14,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.96,
		isSnowing = true,
		isRaining = true,
		snowRate = 240,
		rainRate = 140,
		hasLightning = false,
		bloomIntensity = 0.24,
	},
}

--------------------------------------------------------------------------------
-- OVERHEAD NYC PRECIPITATION CANOPY (SNOWFLAKES + ANGLED SILVER RAIN STREAKS)
--------------------------------------------------------------------------------
local existingCanopy = Workspace:FindFirstChild("NYCPrecipitationCanopy")
if existingCanopy then
	existingCanopy:Destroy()
end

local canopyPart = Instance.new("Part")
canopyPart.Name = "NYCPrecipitationCanopy"
canopyPart.Size = Vector3.new(360, 2, 360)
canopyPart.Position = Vector3.new(0, 92, 0)
canopyPart.Anchored = true
canopyPart.CanCollide = false
canopyPart.CanQuery = false
canopyPart.CanTouch = false
canopyPart.CastShadow = false
canopyPart.Transparency = 1
canopyPart.Parent = Workspace

local snowEmitter = Instance.new("ParticleEmitter")
snowEmitter.Name = "SnowEmitter"
snowEmitter.Color = ColorSequence.new(Color3.fromRGB(242, 248, 255))
snowEmitter.LightEmission = 0.35
snowEmitter.LightInfluence = 0.4
snowEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.42),
	NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(1, 0.32),
})
snowEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.8, 0.25),
	NumberSequenceKeypoint.new(1, 0.85),
})
snowEmitter.Lifetime = NumberRange.new(3.2, 4.8)
snowEmitter.Rate = 420
snowEmitter.Speed = NumberRange.new(22, 34)
snowEmitter.SpreadAngle = Vector2.new(18, 18)
snowEmitter.Acceleration = Vector3.new(-6, -4, 3)
snowEmitter.RotSpeed = NumberRange.new(-45, 45)
snowEmitter.EmissionDirection = Enum.NormalId.Bottom
snowEmitter.Enabled = true
snowEmitter.Parent = canopyPart

local rainEmitter = Instance.new("ParticleEmitter")
rainEmitter.Name = "RainEmitter"
rainEmitter.Color = ColorSequence.new(Color3.fromRGB(195, 215, 242))
rainEmitter.LightEmission = 0.25
rainEmitter.LightInfluence = 0.5
rainEmitter.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.22),
	NumberSequenceKeypoint.new(1, 0.18),
})
rainEmitter.Squash = NumberSequence.new(1.8)
rainEmitter.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.28),
	NumberSequenceKeypoint.new(0.85, 0.42),
	NumberSequenceKeypoint.new(1, 0.9),
})
rainEmitter.Lifetime = NumberRange.new(1.0, 1.4)
rainEmitter.Rate = 180
rainEmitter.Speed = NumberRange.new(85, 110)
rainEmitter.SpreadAngle = Vector2.new(6, 6)
rainEmitter.Acceleration = Vector3.new(-14, -35, 5)
rainEmitter.EmissionDirection = Enum.NormalId.Bottom
rainEmitter.Enabled = true
rainEmitter.Parent = canopyPart

-- Follow active players on Heartbeat so snow and rain always surround the player & nearby skyscrapers
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
		canopyPart.Position = Vector3.new(avg.X, 92, avg.Z)
	else
		local cam = Workspace.CurrentCamera
		if cam then
			local cPos = cam.CFrame.Position
			canopyPart.Position = Vector3.new(cPos.X, 92, cPos.Z)
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
	Lighting.Brightness = 3.2
	Lighting.OutdoorAmbient = Color3.fromRGB(145, 165, 195)

	task.delay(0.12, function()
		Lighting.Brightness = oldBrightness * 1.25
		task.wait(0.08)
		Lighting.Brightness = 2.6
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
			bloom.Size = 16
			bloom.Threshold = 1.85
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
			TweenService:Create(bloom, tweenInfo, {
				Intensity = preset.bloomIntensity,
			}):Play()
		end
	end

	snowEmitter.Rate = preset.snowRate
	snowEmitter.Enabled = preset.isSnowing
	rainEmitter.Rate = preset.rainRate
	rainEmitter.Enabled = preset.isRaining
	updateRoadWetness(preset.roadReflectance, preset.roadMaterial)
end

-- Initialize immediately with NYC Snowy Flurries ("Snowstorm") at 16.4 ClockTime
applyPreset(PRESETS[1], true)

task.spawn(function()
	while true do
		local preset = PRESETS[currentPresetIndex]
		local elapsed = 0
		while elapsed < DWELL_DURATION do
			task.wait(4.0)
			elapsed += 4.0
			if preset.hasLightning and math.random() < 0.25 then
				triggerLightningStrike()
			end
		end

		currentPresetIndex = (currentPresetIndex % #PRESETS) + 1
		applyPreset(PRESETS[currentPresetIndex], false)
	end
end)

print("[WeatherTimeService] NYC Winter Overcast, Snow & Rain cycle active.")
