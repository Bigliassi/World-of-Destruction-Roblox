--!strict
-- CameraAndFXController.client.luau
-- Dynamic speed-scaled chase camera, trauma 3D shake, police pursuit vignette,
-- 3D floating BillboardGui popups, 3D Magnetized Flying Gold Coins,
-- Physical 3D Golden Breadcrumb Trail (self-explanatory for a 5-year-old),
-- and crisp one-shot Casino & Material SFX (NO annoying continuous speed-up engine/drift loops!).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==========================================
-- 1. SCREEN VIGNETTE FOR POLICE PURSUIT & IMPACTS
-- ==========================================
local existingFxGui = playerGui:FindFirstChild("WorldOfDestructionFXGui")
if existingFxGui then
	existingFxGui:Destroy()
end

local fxGui = Instance.new("ScreenGui")
fxGui.Name = "WorldOfDestructionFXGui"
fxGui.IgnoreGuiInset = true
fxGui.ResetOnSpawn = false
fxGui.DisplayOrder = -5
fxGui.Parent = playerGui

local vignetteFrame = Instance.new("Frame")
vignetteFrame.Name = "PursuitVignette"
vignetteFrame.Size = UDim2.fromScale(1, 1)
vignetteFrame.BackgroundTransparency = 1
vignetteFrame.BorderSizePixel = 0
vignetteFrame.Parent = fxGui

local vignetteStroke = Instance.new("UIStroke")
vignetteStroke.Thickness = 26
vignetteStroke.Color = Color3.fromRGB(255, 45, 45)
vignetteStroke.Transparency = 1
vignetteStroke.Parent = vignetteFrame

local impactFlash = Instance.new("Frame")
impactFlash.Name = "ImpactFlash"
impactFlash.Size = UDim2.fromScale(1, 1)
impactFlash.BackgroundColor3 = Color3.fromRGB(255, 200, 120)
impactFlash.BackgroundTransparency = 1
impactFlash.BorderSizePixel = 0
impactFlash.Parent = fxGui

-- ==========================================
-- 2. CRISP ONE-SHOT CASINO & FOLEY SOUND ENGINE
--    (Zero looped engine hum or speed-up sound!)
-- ==========================================
local sfxFolder = SoundService:FindFirstChild("WODClientSFX")
if not sfxFolder then
	sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "WODClientSFX"
	sfxFolder.Parent = SoundService
end

-- Clean up any legacy looped vehicle sounds if present
for _, child in ipairs(sfxFolder:GetChildren()) do
	if child:IsA("Sound") and (child.Looped or child.Name == "VehicleEnginePurr" or child.Name == "VehicleDriftSkid" or child.Name == "EngineHumLoop" or child.Name == "DriftTireLoop") then
		child:Stop()
		child:Destroy()
	end
end

local lastImpactSoundAt = 0.0
local lastCashSoundAt = 0.0
local lastExplosionSoundAt = 0.0
local rollingComboCount = 0
local lastComboTickAt = 0.0

local function spawnShapedLayer(params: {
	name: string,
	soundId: string,
	volume: number,
	speed: number,
	timePosition: number?,
	maxDuration: number?,
	lowGain: number?,
	midGain: number?,
	highGain: number?,
	pitchOctave: number?,
})
	local sfxScale = tonumber(player:GetAttribute("SFXVolume")) or 1.0
	if sfxScale <= 0.001 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = params.name
	sound.SoundId = params.soundId
	sound.Looped = false
	sound.Volume = params.volume * sfxScale
	sound.PlaybackSpeed = math.max(0.35, params.speed)
	if params.timePosition and params.timePosition > 0 then
		sound.TimePosition = params.timePosition
	end

	if params.lowGain or params.midGain or params.highGain then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = params.lowGain or 0
		eq.MidGain = params.midGain or 0
		eq.HighGain = params.highGain or 0
		eq.Parent = sound
	end

	if params.pitchOctave and math.abs(params.pitchOctave - 1.0) > 0.01 then
		local ps = Instance.new("PitchShiftSoundEffect")
		ps.Octave = math.clamp(params.pitchOctave, 0.5, 2.0)
		ps.Parent = sound
	end

	sound.Parent = sfxFolder
	sound:Play()

	local cutoff = params.maxDuration or 0.85
	task.delay(cutoff, function()
		if sound and sound.Parent then
			TweenService:Create(sound, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {
				Volume = 0,
			}):Play()
		end
	end)
	task.delay(cutoff + 0.12, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Soft, musical ascending Casino Coin Chime (electronicpingshort.wav at Volume = 0.16, pitch 1.0 -> 1.8)
local function playCasinoCoinChime(pitchRatio: number?)
	local now = os.clock()
	if now - lastCashSoundAt < 0.045 then
		return
	end
	lastCashSoundAt = now

	if now - lastComboTickAt > 3.2 then
		rollingComboCount = 0
	end
	rollingComboCount += 1
	lastComboTickAt = now

	local speed: number
	if pitchRatio ~= nil then
		speed = math.clamp(1.0 + pitchRatio * 0.8, 1.0, 1.8)
	else
		local step = math.clamp((rollingComboCount - 1) / 10, 0, 1)
		speed = 1.0 + step * 0.8
	end

	spawnShapedLayer({
		name = "CasinoCoinChime",
		soundId = "rbxasset://sounds/electronicpingshort.wav",
		volume = 0.16,
		speed = speed,
		maxDuration = 0.32,
		lowGain = -10,
		midGain = 3,
		highGain = -4,
	})
end

-- Crisp 3-note major chord Jackpot Slot Fanfare
local function playJackpotSlotFanfare()
	local notes = { 1.0, 1.25, 1.5 }
	for i, pitch in ipairs(notes) do
		task.delay((i - 1) * 0.085, function()
			spawnShapedLayer({
				name = "JackpotFanfare_" .. tostring(i),
				soundId = "rbxasset://sounds/electronicpingshort.wav",
				volume = 0.20,
				speed = pitch,
				maxDuration = 0.45,
				lowGain = -8,
				midGain = 4,
				highGain = -3,
			})
		end)
	end
end

local function classifyPropSoundKind(propTypeRaw: any, isExplosion: boolean?): string
	local pType = typeof(propTypeRaw) == "string" and propTypeRaw or ""
	local lower = string.lower(pType)

	if lower == "explosivebarrel" or lower == "gaspump" or string.find(lower, "explosive") or string.find(lower, "gaspump") or string.find(lower, "tnt") then
		return "TrueExplosion"
	end
	if isExplosion == true and (pType == "" or lower == "explosion") then
		return "TrueExplosion"
	end
	if lower == "firehydrant" or string.find(lower, "hydrant") then
		return "HydrantBurst"
	end
	if
		lower == "crate"
		or lower == "jackpotcrate"
		or lower == "fence"
		or lower == "bench"
		or lower == "palmtree"
		or string.find(lower, "wood")
		or string.find(lower, "crate")
		or string.find(lower, "fence")
		or string.find(lower, "bench")
		or string.find(lower, "tree")
		or string.find(lower, "bush")
		or string.find(lower, "stand")
	then
		return "WoodSnap"
	end
	return "MetalClatter"
end

local function playProceduralSound(kind: string, pitchVariance: number?)
	local now = os.clock()
	local jitter = (pitchVariance or 0.06) * (math.random() * 2 - 1)

	-- Deduplicate physical impact sounds within a 0.12s window so events never stack
	if kind == "WoodSnap" or kind == "MetalClatter" or kind == "HydrantBurst" or kind == "Impact" or kind == "HeavySmash" then
		if now - lastImpactSoundAt < 0.12 then
			return
		end
		lastImpactSoundAt = now
	end

	if kind == "WoodSnap" or kind == "Impact" then
		-- Subtle wooden snap at Volume = 0.18
		spawnShapedLayer({
			name = "WoodSnapCrack",
			soundId = "rbxasset://sounds/snap.mp3",
			volume = 0.18,
			speed = 1.35 + jitter,
			maxDuration = 0.22,
			lowGain = -20,
			midGain = 4,
			highGain = 6,
		})
		spawnShapedLayer({
			name = "WoodSnapClick",
			soundId = "rbxasset://sounds/clickfast.wav",
			volume = 0.16,
			speed = 1.28 + jitter * 0.5,
			maxDuration = 0.16,
			lowGain = -20,
			midGain = 4,
			highGain = 6,
		})
	elseif kind == "MetalClatter" or kind == "HeavySmash" then
		-- Subtle metallic clatter at Volume = 0.18
		spawnShapedLayer({
			name = "MetalPrimaryHit",
			soundId = "rbxasset://sounds/metal.ogg",
			volume = 0.18,
			speed = 1.15 + jitter,
			maxDuration = 0.28,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
		})
		spawnShapedLayer({
			name = "MetalClinkSwitch",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.18,
			speed = 1.15 + jitter,
			maxDuration = 0.22,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
			pitchOctave = 1.12,
		})
	elseif kind == "HydrantBurst" then
		-- Subtle hydrant burst at Volume = 0.18
		spawnShapedLayer({
			name = "HydrantMetalTap",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.18,
			speed = 1.2 + jitter * 0.5,
			maxDuration = 0.20,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
		})
		task.delay(0.03, function()
			spawnShapedLayer({
				name = "HydrantWaterSpray",
				soundId = "rbxasset://sounds/action_swim.mp3",
				volume = 0.18,
				speed = 1.1 + jitter * 0.3,
				maxDuration = 0.65,
				lowGain = -14,
				midGain = 2,
				highGain = 6,
			})
		end)
	elseif kind == "CashChime" then
		playCasinoCoinChime(nil)
	elseif kind == "LevelUp" or kind == "JackpotFanfare" then
		playJackpotSlotFanfare()
	elseif kind == "TrueExplosion" then
		if now - lastExplosionSoundAt < 0.16 then
			return
		end
		lastExplosionSoundAt = now
		lastImpactSoundAt = now

		spawnShapedLayer({
			name = "TrueExplosionPunch",
			soundId = "rbxasset://sounds/bass.mp3",
			volume = 0.32,
			speed = 0.62 + jitter * 0.3,
			maxDuration = 0.65,
			lowGain = 5,
			midGain = 2,
			highGain = -6,
		})
		spawnShapedLayer({
			name = "TrueExplosionDebris",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.18,
			speed = 0.75 + jitter * 0.3,
			maxDuration = 0.38,
			lowGain = -6,
			midGain = 4,
			highGain = 4,
		})
	end
end

-- ==========================================
-- 3. 3D FLOATING BILLBOARD POPUPS
-- ==========================================
local popupContainer = Workspace:FindFirstChild("WODFloatingPopups")
if not popupContainer then
	popupContainer = Instance.new("Folder")
	popupContainer.Name = "WODFloatingPopups"
	popupContainer.Parent = Workspace
end

local function spawn3DPopup(worldPos: Vector3, headline: string, subtext: string?, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "FXPopupAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = worldPos + Vector3.new((math.random() - 0.5) * 2.2, 1.5, (math.random() - 0.5) * 2.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = popupContainer

	local bb = Instance.new("BillboardGui")
	bb.Name = "ImpactBillboard"
	bb.Size = UDim2.fromOffset(145, 44)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Parent = anchor

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Size = UDim2.new(1, 0, 0.60, 0)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.Text = headline
	mainLabel.TextColor3 = color
	mainLabel.TextScaled = true
	mainLabel.TextStrokeTransparency = 0.2
	mainLabel.Parent = bb

	local subLabel: TextLabel? = nil
	if subtext and #subtext > 0 then
		subLabel = Instance.new("TextLabel")
		subLabel.Size = UDim2.new(1, 0, 0.38, 0)
		subLabel.Position = UDim2.fromScale(0, 0.60)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.Text = subtext
		subLabel.TextColor3 = Color3.fromRGB(255, 245, 190)
		subLabel.TextScaled = true
		subLabel.TextStrokeTransparency = 0.35
		subLabel.Parent = bb
	end

	TweenService:Create(bb, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 5.4, 0),
	}):Play()
	TweenService:Create(mainLabel, TweenInfo.new(0.85, Enum.EasingStyle.Linear), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	if subLabel then
		TweenService:Create(subLabel, TweenInfo.new(0.85, Enum.EasingStyle.Linear), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end

	task.delay(0.9, function()
		anchor:Destroy()
	end)
end

-- ==========================================
-- 3B. 3D MAGNETIZED FLYING GOLD COINS ON EVERY SMASH
-- ==========================================
local flyingCoinsFolder = Workspace:FindFirstChild("WODFlyingCoins")
if existingFxGui and flyingCoinsFolder then
	flyingCoinsFolder:ClearAllChildren()
end
if not flyingCoinsFolder then
	flyingCoinsFolder = Instance.new("Folder")
	flyingCoinsFolder.Name = "WODFlyingCoins"
	flyingCoinsFolder.Parent = Workspace
end

type ActiveFlyingCoin = {
	part: Part,
	startPos: Vector3,
	apexPos: Vector3,
	elapsed: number,
	arcDuration: number,
	homingDuration: number,
	delayBeforeHoming: number,
	spinSpeed: number,
	spinPhase: number,
	coinIndex: number,
	totalCoins: number,
	cashPerCoin: number,
	showPopupOnArrival: boolean,
}

local activeFlyingCoins: { ActiveFlyingCoin } = {}

local function getPlayerCenterPosition(): Vector3
	local char = player.Character
	if not char then
		return Vector3.new(0, 4, 0)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		local veh = hum.SeatPart:FindFirstAncestorOfClass("Model")
		if veh and veh.PrimaryPart then
			return veh.PrimaryPart.Position
		end
		return hum.SeatPart.Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		return hrp.Position
	end
	return Vector3.new(0, 4, 0)
end

local function spawnCoinArrivalSparkle(pos: Vector3)
	local sparkAnchor = Instance.new("Part")
	sparkAnchor.Name = "CoinSparkle"
	sparkAnchor.Shape = Enum.PartType.Ball
	sparkAnchor.Size = Vector3.new(1.2, 1.2, 1.2)
	sparkAnchor.Position = pos + Vector3.new((math.random() - 0.5) * 2.0, 1.2, (math.random() - 0.5) * 2.0)
	sparkAnchor.Color = Color3.fromRGB(255, 235, 90)
	sparkAnchor.Material = Enum.Material.Neon
	sparkAnchor.Transparency = 0.2
	sparkAnchor.Anchored = true
	sparkAnchor.CanCollide = false
	sparkAnchor.CanQuery = false
	sparkAnchor.CanTouch = false
	sparkAnchor.Parent = flyingCoinsFolder

	TweenService:Create(sparkAnchor, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3.2, 3.2, 3.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(sparkAnchor, 0.25)
end

local function spawnMagnetizedGoldCoins(originPos: Vector3, totalCash: number, desiredCount: number?)
	-- Cap total simultaneous flying coins for crisp 60fps performance
	if #activeFlyingCoins > 42 then
		return
	end

	local count = math.clamp(desiredCount or math.random(6, 12), 6, 12)
	local perCoinCash = math.max(5, math.floor(totalCash / count))

	for i = 1, count do
		local coin = Instance.new("Part")
		coin.Name = "FlyingGoldCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.3, 1.8, 1.8)
		coin.Color = Color3.fromRGB(255, 215, 35)
		coin.Material = Enum.Material.Neon
		coin.TopSurface = Enum.SurfaceType.Smooth
		coin.BottomSurface = Enum.SurfaceType.Smooth
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.Position = originPos + Vector3.new(0, 1.2, 0)
		coin.Parent = flyingCoinsFolder

		-- Inner smooth gold medallion face for rich 3D depth
		local face = Instance.new("Part")
		face.Name = "CoinFace"
		face.Shape = Enum.PartType.Cylinder
		face.Size = Vector3.new(0.36, 1.32, 1.32)
		face.Color = Color3.fromRGB(255, 190, 20)
		face.Material = Enum.Material.SmoothPlastic
		face.Anchored = false
		face.CanCollide = false
		face.CanQuery = false
		face.CanTouch = false
		face.Massless = true
		face.CFrame = coin.CFrame
		face.Parent = coin

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = coin
		weld.Part1 = face
		weld.Parent = coin

		local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.45
		local radius = 3.2 + math.random() * 4.5
		local height = 5.5 + math.random() * 4.8
		local apexPos = originPos + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)

		table.insert(activeFlyingCoins, {
			part = coin,
			startPos = originPos + Vector3.new(0, 1.0, 0),
			apexPos = apexPos,
			elapsed = 0,
			arcDuration = 0.25,
			homingDuration = 0.45,
			delayBeforeHoming = (i - 1) * 0.024,
			spinSpeed = 12 + math.random() * 6,
			spinPhase = math.random() * math.pi * 2,
			coinIndex = i,
			totalCoins = count,
			cashPerCoin = perCoinCash,
			showPopupOnArrival = (i == count or i == math.ceil(count * 0.5)),
		})
	end
end

-- ==========================================
-- 3C. PHYSICAL 3D GOLD COIN BREADCRUMB TRAIL & BOUNCING TARGET RING
--     (Self-Explanatory for Any 5-Year-Old in 2 Seconds with Zero Reading!)
-- ==========================================
local existingTrail = Workspace:FindFirstChild("WODGoldenCoinTrail")
if existingTrail then
	existingTrail:Destroy()
end

local trailFolder = Instance.new("Folder")
trailFolder.Name = "WODGoldenCoinTrail"
trailFolder.Parent = Workspace

local TRAIL_DISTANCES = { 15, 28, 42, 56, 70 }
local TRAIL_COLLECT_RADIUS = 8.0

type BreadcrumbNode = {
	rimPart: Part,
	facePart: Part,
	chevronPart: Part,
	worldPos: Vector3,
	collected: boolean,
	distOffset: number,
}

local breadcrumbNodes: { BreadcrumbNode } = {}

local function createCoinFaceSurfaceGui(parent: BasePart, normalId: Enum.NormalId)
	local sg = Instance.new("SurfaceGui")
	sg.Face = normalId
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 42
	sg.LightInfluence = 0
	sg.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = "$"
	lbl.TextColor3 = Color3.fromRGB(255, 250, 195)
	lbl.TextScaled = true
	lbl.Rotation = 90
	lbl.Parent = sg
end

for idx, dist in ipairs(TRAIL_DISTANCES) do
	local rim = Instance.new("Part")
	rim.Name = "BreadcrumbCoin_" .. tostring(idx)
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.36, 3.1, 3.1)
	rim.Color = Color3.fromRGB(255, 215, 35)
	rim.Material = Enum.Material.Neon
	rim.TopSurface = Enum.SurfaceType.Smooth
	rim.BottomSurface = Enum.SurfaceType.Smooth
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.Position = Vector3.new(0, 3.2, -dist)
	rim.Parent = trailFolder

	local face = Instance.new("Part")
	face.Name = "BreadcrumbCoinFace_" .. tostring(idx)
	face.Shape = Enum.PartType.Cylinder
	face.Size = Vector3.new(0.44, 2.35, 2.35)
	face.Color = Color3.fromRGB(255, 195, 25)
	face.Material = Enum.Material.SmoothPlastic
	face.TopSurface = Enum.SurfaceType.Smooth
	face.BottomSurface = Enum.SurfaceType.Smooth
	face.Anchored = true
	face.CanCollide = false
	face.CanQuery = false
	face.CanTouch = false
	face.Position = rim.Position
	face.Parent = trailFolder

	createCoinFaceSurfaceGui(face, Enum.NormalId.Right)
	createCoinFaceSurfaceGui(face, Enum.NormalId.Left)

	-- Glowing road ring/chevron beneath each coin
	local chevron = Instance.new("Part")
	chevron.Name = "RoadCoinRing_" .. tostring(idx)
	chevron.Shape = Enum.PartType.Cylinder
	chevron.Size = Vector3.new(0.18, 3.6, 3.6)
	chevron.Color = Color3.fromRGB(255, 225, 75)
	chevron.Material = Enum.Material.Neon
	chevron.Transparency = 0.35
	chevron.Anchored = true
	chevron.CanCollide = false
	chevron.CanQuery = false
	chevron.CanTouch = false
	chevron.CFrame = CFrame.new(0, 0.3, -dist) * CFrame.Angles(0, 0, math.rad(90))
	chevron.Parent = trailFolder

	table.insert(breadcrumbNodes, {
		rimPart = rim,
		facePart = face,
		chevronPart = chevron,
		worldPos = Vector3.new(0, 3.2, -dist),
		collected = false,
		distOffset = dist,
	})
end

-- Bouncing Target Ring on the road at the destination prop cluster / vehicle
local targetRingPart = Instance.new("Part")
targetRingPart.Name = "BouncingTargetRing"
targetRingPart.Shape = Enum.PartType.Cylinder
targetRingPart.Size = Vector3.new(0.35, 9.5, 9.5)
targetRingPart.Color = Color3.fromRGB(255, 215, 35)
targetRingPart.Material = Enum.Material.Neon
targetRingPart.Transparency = 0.2
targetRingPart.Anchored = true
targetRingPart.CanCollide = false
targetRingPart.CanQuery = false
targetRingPart.CanTouch = false
targetRingPart.CFrame = CFrame.new(0, 0.4, -75) * CFrame.Angles(0, 0, math.rad(90))
targetRingPart.Parent = trailFolder

local targetBillboard = Instance.new("BillboardGui")
targetBillboard.Name = "TargetVisualPrompt"
targetBillboard.Size = UDim2.fromOffset(170, 56)
targetBillboard.StudsOffset = Vector3.new(0, 6.2, 0)
targetBillboard.AlwaysOnTop = true
targetBillboard.MaxDistance = 260
targetBillboard.Parent = targetRingPart

local targetBadge = Instance.new("Frame")
targetBadge.Size = UDim2.fromScale(1, 1)
targetBadge.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
targetBadge.BackgroundTransparency = 0.12
targetBadge.BorderSizePixel = 0
targetBadge.Parent = targetBillboard

local targetCorner = Instance.new("UICorner")
targetCorner.CornerRadius = UDim.new(0, 12)
targetCorner.Parent = targetBadge

local targetStroke = Instance.new("UIStroke")
targetStroke.Color = Color3.fromRGB(255, 215, 35)
targetStroke.Thickness = 2.8
targetStroke.Parent = targetBadge

local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.new(1, -12, 1, -6)
targetLabel.Position = UDim2.fromOffset(6, 3)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = Enum.Font.GothamBlack
targetLabel.Text = "💥 SMASH COINS!"
targetLabel.TextColor3 = Color3.fromRGB(255, 225, 55)
targetLabel.TextScaled = true
targetLabel.Parent = targetBadge

local currentTrailTargetInst: Instance? = nil
local currentTrailTargetPos: Vector3 = Vector3.new(0, 2.5, -75)
local currentTrailOriginPos: Vector3 = Vector3.zero
local lastTrailRefreshAt = 0.0

local function getInstanceWorldPos(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if p then
			return p.Position
		end
	end
	return nil
end

local function findBestGuidanceTarget(playerPos: Vector3, playerForward: Vector3, isSeated: boolean): (Instance?, Vector3, string)
	-- 1. If player is on foot (not seated in a car), point the coin trail straight to their car!
	if not isSeated then
		local bestVeh: Instance? = nil
		local bestVehPos = Vector3.zero
		local bestVehDist = 220

		local vehiclesFolder = Workspace:FindFirstChild("Vehicles")
		local parkedFolder = Workspace:FindFirstChild("ParkedVehicles")
		local candidates: { Instance } = {}

		if vehiclesFolder then
			for _, v in ipairs(vehiclesFolder:GetChildren()) do
				table.insert(candidates, v)
			end
		end
		if parkedFolder then
			for _, v in ipairs(parkedFolder:GetChildren()) do
				table.insert(candidates, v)
			end
		end

		for _, v in ipairs(candidates) do
			if v:IsA("Model") and v:GetAttribute("IsWrecked") ~= true then
				local vPos = getInstanceWorldPos(v)
				if vPos then
					local d = (vPos - playerPos).Magnitude
					-- Prioritize personal vehicle owned by this player
					if v:GetAttribute("OwnerUserId") == player.UserId then
						d *= 0.35
					end
					if d < bestVehDist then
						bestVehDist = d
						bestVeh = v
						bestVehPos = vPos
					end
				end
			end
		end

		if bestVeh then
			return bestVeh, bestVehPos, "🚗 DRIVE CAR!"
		end
	end

	-- 2. If Act 5 Boss Goliath is active, point straight to Boss Goliath!
	if player:GetAttribute("BossActive") == true then
		local bossModel = Workspace:FindFirstChild("MegaCorpBossConvoy")
		if bossModel then
			local bPos = getInstanceWorldPos(bossModel)
			if bPos then
				return bossModel, bPos, "💥 RAM BOSS!"
			end
		end
	end

	-- 3. Find the best smashable prop cluster ahead of the player
	local bestProp: Instance? = nil
	local bestPropPos = playerPos + playerForward * 75
	local bestScore = math.huge
	local bestLabel = "💥 SMASH!"

	local tagged = CollectionService:GetTagged("Destructible")
	if #tagged == 0 then
		local leoCity = Workspace:FindFirstChild("LeoCity")
		local propsFolder = leoCity and leoCity:FindFirstChild("DestructibleProps")
		if propsFolder then
			tagged = propsFolder:GetChildren()
		end
	end

	for _, prop in ipairs(tagged) do
		if prop:GetAttribute("Destroyed") ~= true and not CollectionService:HasTag(prop, "Vehicle") then
			local pPos = getInstanceWorldPos(prop)
			if pPos then
				local delta = Vector3.new(pPos.X - playerPos.X, 0, pPos.Z - playerPos.Z)
				local dist = delta.Magnitude
				if dist >= 16 and dist <= 220 then
					local dir = delta.Unit
					local forwardDot = dir:Dot(playerForward)
					-- Strongly prefer props in front of the car, and prioritize JackpotCrates / high-value targets
					local anglePenalty = (1 - forwardDot) * 55
					local pType = tostring(prop:GetAttribute("PropType") or prop.Name)
					local jackpotBonus = (pType == "JackpotCrate" or prop:GetAttribute("IsJackpotCrate") == true) and -35 or 0
					local score = dist + anglePenalty + jackpotBonus
					if score < bestScore then
						bestScore = score
						bestProp = prop
						bestPropPos = pPos
						if pType == "JackpotCrate" or prop:GetAttribute("IsJackpotCrate") == true then
							bestLabel = "🎰 JACKPOT CRATE!"
						elseif pType == "FireHydrant" then
							bestLabel = "💦 SMASH HYDRANT!"
						else
							bestLabel = "💥 SMASH COINS!"
						end
					end
				end
			end
		end
	end

	return bestProp, bestPropPos, bestLabel
end

local function layoutBreadcrumbTrail(playerPos: Vector3, playerForward: Vector3, targetPos: Vector3, labelText: string)
	currentTrailOriginPos = playerPos
	currentTrailTargetPos = targetPos
	targetLabel.Text = labelText

	local flatDelta = Vector3.new(targetPos.X - playerPos.X, 0, targetPos.Z - playerPos.Z)
	local totalDist = flatDelta.Magnitude
	local targetDir = if totalDist > 1 then flatDelta.Unit else playerForward

	local roadY = math.clamp(playerPos.Y - 1.5, 0.5, 12.0)

	for i, node in ipairs(breadcrumbNodes) do
		local d = node.distOffset
		-- Blend smoothly from the car's nose direction toward the target direction so coins form an inviting curve
		local alpha = i / #breadcrumbNodes
		local blendedDir = (playerForward * (1 - alpha * 0.65) + targetDir * (alpha * 0.65))
		if blendedDir.Magnitude < 0.05 then
			blendedDir = targetDir
		else
			blendedDir = blendedDir.Unit
		end

		local stepDist = if totalDist > 20 then math.min(d, math.max(12, totalDist * (i / #breadcrumbNodes))) else d
		local posXZ = Vector3.new(playerPos.X, 0, playerPos.Z) + blendedDir * stepDist
		node.worldPos = Vector3.new(posXZ.X, roadY + 2.4, posXZ.Z)
		node.collected = false
		node.rimPart.Transparency = 0.05
		node.facePart.Transparency = 0
		node.chevronPart.Transparency = 0.35
	end
end

-- ==========================================
-- 4. TRAUMA CAMERA SHAKE & IMPACT FLASH
-- ==========================================
local trauma = 0.0
local currentFov = 70.0
local lastSpeed = 0.0
local noiseClock = 0.0

local function addCameraTrauma(amount: number, flashAlpha: number?)
	trauma = math.clamp(trauma + amount, 0, 1.0)
	if flashAlpha and flashAlpha > 0 then
		impactFlash.BackgroundTransparency = math.clamp(1 - flashAlpha, 0.45, 0.95)
		TweenService:Create(impactFlash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end
end

-- ==========================================
-- 5. REMOTE & ATTRIBUTE LISTENERS
-- ==========================================
local lastCashAttr = tonumber(player:GetAttribute("Cash")) or 0
local lastLevelAttr = tonumber(player:GetAttribute("Level")) or 1

player.AttributeChanged:Connect(function(attr: string)
	if attr == "Cash" then
		local nowCash = tonumber(player:GetAttribute("Cash")) or 0
		if nowCash > lastCashAttr then
			playCasinoCoinChime(nil)
		end
		lastCashAttr = nowCash
	elseif attr == "Level" then
		local nowLvl = tonumber(player:GetAttribute("Level")) or 1
		if nowLvl > lastLevelAttr then
			playJackpotSlotFanfare()
			addCameraTrauma(0.35, 0.25)
			local pPos = getPlayerCenterPosition()
			spawn3DPopup(pPos, "LEVEL UP! LV." .. tostring(nowLvl), "RANK PROMOTION", Color3.fromRGB(95, 225, 255))
			spawnMagnetizedGoldCoins(pPos + Vector3.new(0, 3, 0), nowLvl * 250, 10)
		end
		lastLevelAttr = nowLvl
	end
end)

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then return end

	local function bindEvent(name: string, callback: (...any) -> ())
		local r = remotes:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(callback)
		end
	end

	bindEvent("DamageDealt", function(worldPos: any, damageOrCash: any, labelText: any)
		local pos = typeof(worldPos) == "Vector3" and worldPos or getPlayerCenterPosition()
		local amount = tonumber(damageOrCash) or 100
		local title = amount >= 0 and ("+$" .. tostring(math.floor(amount))) or tostring(labelText or "SMASH!")
		local subtitle = typeof(labelText) == "string" and labelText or "DESTRUCTION"
		spawn3DPopup(pos, title, subtitle, Color3.fromRGB(110, 255, 140))
		spawnMagnetizedGoldCoins(pos, math.max(25, amount), math.random(6, 9))
		addCameraTrauma(math.clamp(amount / 750, 0.12, 0.48), 0.10)
		local sfxKind = classifyPropSoundKind(labelText, false)
		playProceduralSound(sfxKind, 0.08)
	end)

	bindEvent("DestructionOccurred", function(worldPosOrPayload: any, propName: any, cashAwarded: any)
		local pos = Vector3.zero
		local cash = 75
		local sub = "PROP WRECKED"
		local propType: string = typeof(propName) == "string" and propName or ""
		local isExplosion = false
		local isJackpotCrate = false

		if typeof(worldPosOrPayload) == "Vector3" then
			pos = worldPosOrPayload
			cash = tonumber(cashAwarded) or 75
			sub = propType ~= "" and ("WRECKED " .. string.upper(propType)) or "PROP WRECKED"
		elseif type(worldPosOrPayload) == "table" then
			if typeof(worldPosOrPayload.position) == "Vector3" then
				pos = worldPosOrPayload.position
			elseif typeof(worldPosOrPayload.Position) == "Vector3" then
				pos = worldPosOrPayload.Position
			end
			cash = tonumber(worldPosOrPayload.cashEarned or worldPosOrPayload.CashReward) or 75
			local pType = worldPosOrPayload.propType or worldPosOrPayload.Type
			if typeof(pType) == "string" then
				propType = pType
				sub = "WRECKED " .. string.upper(pType)
			end
			isExplosion = (worldPosOrPayload.isExplosion == true) or (worldPosOrPayload.IsExplosion == true)
			isJackpotCrate = (worldPosOrPayload.isJackpotCrate == true) or (propType == "JackpotCrate")
		end

		if isJackpotCrate then
			sub = "🎰 JACKPOT CRATE 3X! (+35% SPIN)"
			playJackpotSlotFanfare()
		end

		spawn3DPopup(pos, "+$" .. tostring(math.floor(cash)), sub, Color3.fromRGB(255, 215, 45))

		-- Spawn 6 to 12 physical 3D Spinning Gold Coins that fountain upward and magnetically fly into the player's car!
		local coinCount = if isJackpotCrate then 12 else math.clamp(math.floor(6 + (cash / 35)), 6, 12)
		spawnMagnetizedGoldCoins(pos, cash, coinCount)

		local sfxKind = classifyPropSoundKind(propType, isExplosion)
		if sfxKind == "TrueExplosion" then
			addCameraTrauma(0.55, 0.25)
		else
			addCameraTrauma(0.20, 0.08)
		end
		playProceduralSound(sfxKind, 0.08)
	end)

	bindEvent("StyleCallout", function(payload: any)
		if type(payload) == "table" and payload.IsJackpotSpin == true then
			playJackpotSlotFanfare()
			addCameraTrauma(0.42, 0.30)
			local pPos = getPlayerCenterPosition()
			local prizeTitle = tostring(payload.PrizeTitle or payload.Callout or "JACKPOT WINNER!")
			local cashWon = tonumber(payload.CashAwarded) or 3500
			spawn3DPopup(pPos + Vector3.new(0, 2.5, 0), "🎰 " .. prizeTitle, "CASINO JACKPOT SPIN!", Color3.fromRGB(255, 215, 35))
			spawnMagnetizedGoldCoins(pPos + Vector3.new(0, 4.0, 0), math.max(1000, cashWon), 12)
		end
	end)

	bindEvent("ExplosionEffect", function(worldPos: any, radius: any)
		local pos = typeof(worldPos) == "Vector3" and worldPos or Vector3.zero
		local r = tonumber(radius) or 35
		spawn3DPopup(pos, "BOOM!", "EXPLOSIVE CHAIN REACTION", Color3.fromRGB(255, 95, 45))
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dist = root and (root.Position - pos).Magnitude or 40
		local intensity = math.clamp(1 - (dist / math.max(80, r * 3)), 0.25, 0.95)
		addCameraTrauma(intensity, intensity * 0.45)
		playProceduralSound("TrueExplosion", 0.06)
	end)

	bindEvent("ChallengeCompleted", function()
		playJackpotSlotFanfare()
	end)

	bindEvent("CameraShake", function(intensity: any)
		addCameraTrauma(tonumber(intensity) or 0.35, 0.15)
	end)
end)

-- ==========================================
-- 6. RENDERSTEPPED CHASE CAMERA, FOV, 3D COIN MAGNETISM, BREADCRUMB TRAIL & VIGNETTE
-- ==========================================
local sirenPhase = 0.0
local coinSpinClock = 0.0

RunService.RenderStepped:Connect(function(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	noiseClock += dt * 28
	sirenPhase += dt * 8.5
	coinSpinClock += dt

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	-- Compute vehicle/character speed & local collision deceleration trauma
	local speedMph = tonumber(player:GetAttribute("SpeedMPH")) or 0
	if root and speedMph == 0 then
		speedMph = root.AssemblyLinearVelocity.Magnitude * 0.68
	end
	local speedDrop = lastSpeed - speedMph
	if speedDrop > 38 then
		addCameraTrauma(math.clamp(speedDrop / 105, 0.16, 0.55), 0.14)
		playProceduralSound("MetalClatter", 0.08)
	end
	lastSpeed = speedMph

	-- Dynamic Speed-Based FOV Scaling (70 base -> up to 92 at high speed / nitro)
	local isSeatedInVehicle = (humanoid ~= nil and humanoid.Sit) or (player:GetAttribute("IsDriving") == true) or (player:GetAttribute("InVehicle") == true)
	local isDriving = isSeatedInVehicle or (speedMph > 8)
	local nitroBoost = (player:GetAttribute("TouchNitro") == true) and 5 or 0
	local targetFov = isDriving and math.clamp(70 + (speedMph / 140) * 18 + nitroBoost, 70, 92) or 70
	currentFov = currentFov + (targetFov - currentFov) * math.min(1, dt * 8)
	cam.FieldOfView = currentFov

	local playerCenter = getPlayerCenterPosition()

	-- Update 3D Magnetized Flying Gold Coins (0.25s upward fountain arc -> 0.45s magnetic homing into car!)
	if #activeFlyingCoins > 0 then
		for i = #activeFlyingCoins, 1, -1 do
			local c = activeFlyingCoins[i]
			c.elapsed += dt
			local spinAngle = c.spinPhase + c.elapsed * c.spinSpeed

			if c.elapsed <= c.arcDuration then
				-- Fountain upward arc (0.25s)
				local t = math.clamp(c.elapsed / c.arcDuration, 0, 1)
				local easeOut = 1 - (1 - t) * (1 - t)
				local pos = c.startPos:Lerp(c.apexPos, easeOut)
				c.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, spinAngle, 0)
			else
				-- Magnetic homing into player's car/character (0.45s)
				local homeElapsed = c.elapsed - c.arcDuration - c.delayBeforeHoming
				if homeElapsed <= 0 then
					c.part.CFrame = CFrame.new(c.apexPos) * CFrame.Angles(0, spinAngle, 0)
				else
					local t = math.clamp(homeElapsed / c.homingDuration, 0, 1)
					local easeIn = t * t
					local pos = c.apexPos:Lerp(playerCenter + Vector3.new(0, 1.5, 0), easeIn)
					c.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, spinAngle * 1.35, 0)

					if t >= 1.0 then
						-- Coin hit the car! Play soft ascending musical CashChime & flash popup
						local pitchRatio = (c.coinIndex - 1) / math.max(1, c.totalCoins - 1)
						playCasinoCoinChime(pitchRatio)
						spawnCoinArrivalSparkle(playerCenter)
						if c.showPopupOnArrival then
							spawn3DPopup(
								playerCenter + Vector3.new(0, 2.2, 0),
								"+$" .. tostring(c.cashPerCoin * c.totalCoins),
								"GOLD MAGNET",
								Color3.fromRGB(255, 225, 55)
							)
						end
						c.part:Destroy()
						table.remove(activeFlyingCoins, i)
					end
				end
			end
		end
	end

	-- Update Physical 3D Gold Coin Breadcrumb Trail & Bouncing Target Ring
	local inHomeMenu = (player:GetAttribute("HomeMenuActive") == true) or (player:GetAttribute("HomeMenuCameraActive") == true)
	if root and not inHomeMenu then
		local look = root.CFrame.LookVector
		local flatForward = Vector3.new(look.X, 0, look.Z)
		if flatForward.Magnitude < 0.05 then
			flatForward = Vector3.new(0, 0, -1)
		else
			flatForward = flatForward.Unit
		end

		local now = os.clock()
		local targetDestroyed = (currentTrailTargetInst == nil)
			or (currentTrailTargetInst.Parent == nil)
			or (currentTrailTargetInst:GetAttribute("Destroyed") == true)
		local distFromOrigin = (Vector3.new(playerCenter.X, 0, playerCenter.Z) - Vector3.new(currentTrailOriginPos.X, 0, currentTrailOriginPos.Z)).Magnitude
		local distToTarget = (Vector3.new(playerCenter.X, 0, playerCenter.Z) - Vector3.new(currentTrailTargetPos.X, 0, currentTrailTargetPos.Z)).Magnitude

		local allCollected = true
		for _, node in ipairs(breadcrumbNodes) do
			if not node.collected then
				allCollected = false
				break
			end
		end

		if targetDestroyed or allCollected or distToTarget < 10 or distFromOrigin > 52 or (now - lastTrailRefreshAt > 4.0) then
			lastTrailRefreshAt = now
			local bestInst, bestPos, labelText = findBestGuidanceTarget(playerCenter, flatForward, isSeatedInVehicle)
			currentTrailTargetInst = bestInst
			layoutBreadcrumbTrail(playerCenter, flatForward, bestPos, labelText)
		end

		-- Animate the 5 spinning 3D Gold Coins & check 8-stud collection radius
		for i, node in ipairs(breadcrumbNodes) do
			if not node.collected then
				local flatDist = (Vector3.new(playerCenter.X, 0, playerCenter.Z) - Vector3.new(node.worldPos.X, 0, node.worldPos.Z)).Magnitude
				if flatDist <= TRAIL_COLLECT_RADIUS then
					node.collected = true
					node.rimPart.Transparency = 1
					node.facePart.Transparency = 1
					node.chevronPart.Transparency = 1

					-- Pop with musical ascending coin chime + gold sparkle burst + instant visual reward!
					playCasinoCoinChime((i - 1) / math.max(1, #breadcrumbNodes - 1))
					spawnCoinArrivalSparkle(node.worldPos)
					spawn3DPopup(node.worldPos, "🪙 GOLD TRAIL!", "KEEP SMASHING!", Color3.fromRGB(255, 225, 55))
					spawnMagnetizedGoldCoins(node.worldPos, 25, 6)
				else
					local bob = math.sin(coinSpinClock * 4.2 + i * 0.75) * 0.42
					local spin = coinSpinClock * 3.4 + i * 0.5
					local cf = CFrame.new(node.worldPos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0)
					node.rimPart.CFrame = cf
					node.facePart.CFrame = cf
					node.chevronPart.CFrame = CFrame.new(node.worldPos.X, node.worldPos.Y - 2.1, node.worldPos.Z)
						* CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end

		-- Animate Bouncing Target Ring at destination
		if currentTrailTargetInst and currentTrailTargetInst.Parent then
			local livePos = getInstanceWorldPos(currentTrailTargetInst)
			if livePos then
				currentTrailTargetPos = livePos
			end
		end
		local ringPulse = 9.0 + math.sin(coinSpinClock * 5.0) * 1.4
		local ringY = math.clamp(currentTrailTargetPos.Y - 1.2, 0.4, 8.0) + math.abs(math.sin(coinSpinClock * 4.5)) * 0.55
		targetRingPart.Transparency = 0.22
		targetRingPart.Size = Vector3.new(0.35, ringPulse, ringPulse)
		targetRingPart.CFrame = CFrame.new(currentTrailTargetPos.X, ringY, currentTrailTargetPos.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		targetBillboard.Enabled = true
	else
		for _, node in ipairs(breadcrumbNodes) do
			node.rimPart.Transparency = 1
			node.facePart.Transparency = 1
			node.chevronPart.Transparency = 1
		end
		targetRingPart.Transparency = 1
		targetBillboard.Enabled = false
	end

	-- Trauma-Based 3D Rotational & Positional Camera Shake (scaled by Settings CameraShakeScale)
	local shakeScale = tonumber(player:GetAttribute("CameraShakeScale")) or 1.0
	if trauma > 0.001 and shakeScale > 0 then
		local shake = trauma * trauma * shakeScale
		local dx = math.noise(noiseClock, 1.3) * 1.6 * shake
		local dy = math.noise(1.3, noiseClock) * 1.6 * shake
		local roll = math.noise(noiseClock, noiseClock) * math.rad(5.5) * shake
		cam.CFrame = cam.CFrame * CFrame.new(dx, dy, 0) * CFrame.Angles(dy * 0.02, dx * 0.02, roll)
		trauma = math.max(0, trauma - dt * 1.45)
	elseif trauma > 0.001 then
		trauma = 0
	end

	-- Home Menu Aerial Orbit Camera over sunlit Leo Plaza & Leo Tower when HomeMenuActive == true
	if inHomeMenu then
		local orbitAngle = os.clock() * 0.22
		local orbitPos = Vector3.new(math.cos(orbitAngle) * 115, 62, math.sin(orbitAngle) * 115 + 25)
		cam.CFrame = CFrame.lookAt(orbitPos, Vector3.new(0, 18, -30))
	end

	-- Police Siren Screen Vignette at High Heat
	local stars = tonumber(player:GetAttribute("HeatStars") or player:GetAttribute("WantedLevel")) or 0
	if stars >= 1 then
		local wave = math.sin(sirenPhase)
		vignetteStroke.Color = (wave >= 0) and Color3.fromRGB(255, 45, 55) or Color3.fromRGB(45, 130, 255)
		local pulseAlpha = 0.78 - (math.abs(wave) * (0.14 + stars * 0.04))
		vignetteStroke.Transparency = math.clamp(pulseAlpha, 0.42, 0.92)
	else
		vignetteStroke.Transparency = 1
	end
end)
