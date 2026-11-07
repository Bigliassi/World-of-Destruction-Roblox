--!strict
-- WeatherTimeService.script.luau
-- Crisp Snowy Christmas NYC late-afternoon / twilight weather system for Leo City:
-- Keeps ClockTime around 15.6 (crisp winter twilight where snowy Central Park and tall Manhattan
-- limestone skyscrapers are clearly visible while warm golden Christmas lights & streetlamps glow),
-- BloomEffect.Intensity = 0.14, BloomEffect.Threshold = 2.2 (zero blurry neon blobs),
-- and gentle falling snowflakes (SnowEmitter) across the city.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------------------------------------
-- LIGHTING POST-PROCESSING & ATMOSPHERE SETUP
--------------------------------------------------------------------------------
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.15
atmosphere.Offset = 0.10
atmosphere.Color = Color3.fromRGB(185, 200, 222)
atmosphere.Decay = Color3.fromRGB(125, 140, 165)
atmosphere.Glare = 0.04
atmosphere.Haze = 0.45

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if not bloom then
	bloom = Instance.new("BloomEffect")
	bloom.Parent = Lighting
end
bloom.Enabled = true
bloom.Intensity = 0.14
bloom.Size = 14
bloom.Threshold = 2.2

local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Parent = Lighting
end
colorCorrection.Enabled = true
colorCorrection.Brightness = 0.02
colorCorrection.Contrast = 0.12
colorCorrection.Saturation = 0.06
colorCorrection.TintColor = Color3.fromRGB(246, 249, 255)

--------------------------------------------------------------------------------
-- WEATHER & TIME PRESETS (SNOWY CHRISTMAS MANHATTAN)
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
	bloomIntensity: number,
}

local PRESETS: { WeatherPreset } = {
	{
		name = "Snowstorm",
		displayName = "Central Park Christmas Snowfall",
		clockTime = 15.6,
		brightness = 2.55,
		ambient = Color3.fromRGB(128, 138, 156),
		outdoorAmbient = Color3.fromRGB(158, 170, 190),
		fogColor = Color3.fromRGB(168, 182, 204),
		colorShiftTop = Color3.fromRGB(215, 226, 245),
		atmosphereDensity = 0.15,
		atmosphereOffset = 0.10,
		atmosphereGlare = 0.04,
		atmosphereHaze = 0.45,
		atmosphereColor = Color3.fromRGB(185, 200, 222),
		atmosphereDecay = Color3.fromRGB(125, 140, 165),
		roadReflectance = 0.10,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.96,
		isSnowing = true,
		isRaining = false,
		snowRate = 280,
		rainRate = 0,
		bloomIntensity = 0.14,
	},
	{
		name = "CloudyNYC",
		displayName = "5th Avenue Holiday Flurries",
		clockTime = 15.6,
		brightness = 2.60,
		ambient = Color3.fromRGB(132, 142, 160),
		outdoorAmbient = Color3.fromRGB(162, 174, 194),
		fogColor = Color3.fromRGB(172, 186, 208),
		colorShiftTop = Color3.fromRGB(220, 230, 248),
		atmosphereDensity = 0.14,
		atmosphereOffset = 0.09,
		atmosphereGlare = 0.04,
		atmosphereHaze = 0.40,
		atmosphereColor = Color3.fromRGB(190, 204, 226),
		atmosphereDecay = Color3.fromRGB(130, 144, 168),
		roadReflectance = 0.10,
		roadMaterial = Enum.Material.Asphalt,
		gripMultiplier = 0.97,
		isSnowing = true,
		isRaining = false,
		snowRate = 220,
		rainRate = 0,
		bloomIntensity = 0.14,
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
snowEmitter.Color = ColorSequence.new(Color3.fromRGB(246, 250, 255))
snowEmitter.LightEmission = 0.30
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
snowEmitter.Rate = 280
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
			bloom.Size = 14
			bloom.Threshold = 2.2
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
			bloom.Threshold = 2.2
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

-- Initialize immediately with Snowy Christmas Manhattan at ClockTime = 15.6
applyPreset(PRESETS[1], true)

task.spawn(function()
	while true do
		task.wait(DWELL_DURATION)
		currentPresetIndex = (currentPresetIndex % #PRESETS) + 1
		applyPreset(PRESETS[currentPresetIndex], false)
	end
end)

print("[WeatherTimeService] Snowy Christmas Manhattan weather cycle active at ClockTime 15.6.")
