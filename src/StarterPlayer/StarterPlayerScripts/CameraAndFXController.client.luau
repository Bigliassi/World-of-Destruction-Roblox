--!strict
-- CameraAndFXController.client.luau
-- Dynamic speed-scaled chase camera, trauma 3D shake, police pursuit vignette,
-- compact offset 3D floating BillboardGui popups, low-arc 3D Smash Gold Coins
-- that erupt strictly from smashed objects into the lower front bumper without blocking view,
-- and crisp one-shot Casino & Material SFX (ZERO looped engine or drift sounds!).

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
-- 3. 3D FLOATING BILLBOARD POPUPS (COMPACT, OFFSET & NON-BLOCKING)
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
	anchor.Position = worldPos + Vector3.new((math.random() - 0.5) * 1.6, 0.8, (math.random() - 0.5) * 1.6)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = popupContainer

	local bb = Instance.new("BillboardGui")
	bb.Name = "ImpactBillboard"
	bb.Size = UDim2.fromOffset(92, 26)
	bb.StudsOffset = Vector3.new(2.5, 1.8, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 160
	bb.Parent = anchor

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Size = UDim2.new(1, 0, if subtext and #subtext > 0 then 0.62 else 1.0, 0)
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
		subLabel.Size = UDim2.new(1, 0, 0.36, 0)
		subLabel.Position = UDim2.fromScale(0, 0.62)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.Text = subtext
		subLabel.TextColor3 = Color3.fromRGB(255, 245, 190)
		subLabel.TextScaled = true
		subLabel.TextStrokeTransparency = 0.35
		subLabel.Parent = bb
	end

	TweenService:Create(bb, TweenInfo.new(0.65, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(2.8, 3.2, 0),
	}):Play()
	TweenService:Create(mainLabel, TweenInfo.new(0.65, Enum.EasingStyle.Linear), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	if subLabel then
		TweenService:Create(subLabel, TweenInfo.new(0.65, Enum.EasingStyle.Linear), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end

	task.delay(0.7, function()
		anchor:Destroy()
	end)
end

-- ==========================================
-- 3B. LOW-ARC 3D GOLD COINS FROM SMASHED OBJECTS ONLY
--     (Never spawns coins on empty road and never blocks camera view!)
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
}

local activeFlyingCoins: { ActiveFlyingCoin } = {}

local function getPlayerBumperTargetPosition(): Vector3
	local char = player.Character
	if not char then
		return Vector3.new(0, 1.5, 0)
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position - Vector3.new(0, 1.4, 0)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return hum.SeatPart.Position - Vector3.new(0, 1.4, 0)
	end
	return Vector3.new(0, 1.5, 0)
end

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
	sparkAnchor.Size = Vector3.new(0.45, 0.45, 0.45)
	sparkAnchor.Position = pos + Vector3.new((math.random() - 0.5) * 1.2, 0.2, (math.random() - 0.5) * 1.2)
	sparkAnchor.Color = Color3.fromRGB(255, 210, 40)
	sparkAnchor.Material = Enum.Material.Metal
	sparkAnchor.Reflectance = 0.35
	sparkAnchor.Transparency = 0.25
	sparkAnchor.Anchored = true
	sparkAnchor.CanCollide = false
	sparkAnchor.CanQuery = false
	sparkAnchor.CanTouch = false
	sparkAnchor.Parent = flyingCoinsFolder

	TweenService:Create(sparkAnchor, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.1, 1.1, 1.1),
		Transparency = 1,
	}):Play()
	Debris:AddItem(sparkAnchor, 0.20)
end

local function spawnMagnetizedGoldCoins(originPos: Vector3, totalCash: number, desiredCount: number?)
	-- Cap total simultaneous flying coins for crisp 60fps performance
	if #activeFlyingCoins > 36 then
		return
	end

	local count = math.clamp(desiredCount or math.random(5, 9), 5, 9)
	local perCoinCash = math.max(5, math.floor(totalCash / count))

	for i = 1, count do
		local coin = Instance.new("Part")
		coin.Name = "FlyingGoldCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.16, 0.78, 0.78)
		coin.Color = Color3.fromRGB(255, 210, 40)
		coin.Material = Enum.Material.Metal
		coin.Reflectance = 0.35
		coin.TopSurface = Enum.SurfaceType.Smooth
		coin.BottomSurface = Enum.SurfaceType.Smooth
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.Position = originPos + Vector3.new(0, 0.6, 0)
		coin.Parent = flyingCoinsFolder

		-- Fountain outward and LOW (peak height = +1.4 to +2.4 studs above ground — well BELOW car roof and camera line-of-sight!)
		local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.45
		local radius = 2.0 + math.random() * 2.8
		local peakHeight = 1.4 + math.random() * 1.0
		local apexPos = originPos + Vector3.new(math.cos(angle) * radius, peakHeight, math.sin(angle) * radius)

		table.insert(activeFlyingCoins, {
			part = coin,
			startPos = originPos + Vector3.new(0, 0.6, 0),
			apexPos = apexPos,
			elapsed = 0,
			arcDuration = 0.22,
			homingDuration = 0.32,
			delayBeforeHoming = (i - 1) * 0.015,
			spinSpeed = 14 + math.random() * 6,
			spinPhase = math.random() * math.pi * 2,
			coinIndex = i,
			totalCoins = count,
			cashPerCoin = perCoinCash,
		})
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
		spawnMagnetizedGoldCoins(pos, math.max(25, amount), math.random(5, 9))
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

		-- Spawn 5 to 9 compact, gleaming 3D Gold Coins at worldPos that fountain low and curve into the lower front bumper!
		local coinCount = if isJackpotCrate then 9 else math.clamp(math.floor(5 + (cash / 45)), 5, 9)
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
			spawn3DPopup(pPos + Vector3.new(0, 1.2, 0), "🎰 " .. prizeTitle, "CASINO JACKPOT SPIN!", Color3.fromRGB(255, 215, 35))
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
-- 6. RENDERSTEPPED CHASE CAMERA, ANTI-OCCLUSION, FOV, LOW-ARC 3D COIN MAGNETISM & VIGNETTE
-- ==========================================
local sirenPhase = 0.0
local smoothCamPos = Vector3.new(0, 12, 24)
local smoothLookTarget = Vector3.new(0, 3, 0)
local lastFinalChaseCFrame: CFrame? = nil
local hasSmoothCam = false
local occludedCameraParts: { [BasePart]: boolean } = {}
local cameraOverlapParams = OverlapParams.new()
cameraOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function isGroundOrRoadPart(part: BasePart): boolean
	local name = part.Name
	if
		name == "Baseplate"
		or name == "Road"
		or name == "Sidewalk"
		or name == "Crosswalk"
		or name == "Ground"
		or name == "PlazaFloor"
		or name == "Ocean"
		or name == "Grass"
		or name == "Terrain"
	then
		return true
	end
	if part.Size.Y <= 2.6 and part.Position.Y <= 2.2 and (part.Size.X >= 24 or part.Size.Z >= 24) then
		return true
	end
	return false
end

local function resolveSeatedVehicleRoot(char: Model?, humanoid: Humanoid?, fallbackRoot: BasePart?): (BasePart?, Model?)
	if humanoid and humanoid.SeatPart then
		local vehModel = humanoid.SeatPart:FindFirstAncestorOfClass("Model")
		if vehModel then
			local chassis = vehModel.PrimaryPart or (vehModel:FindFirstChild("Chassis") :: BasePart?)
			if chassis then
				return chassis, vehModel
			end
		end
		return humanoid.SeatPart, vehModel
	end
	if char then
		local parentModel = char.Parent
		if parentModel and parentModel:IsA("Model") and parentModel ~= Workspace then
			local chassis = parentModel.PrimaryPart or (parentModel:FindFirstChild("Chassis") :: BasePart?)
			if chassis then
				return chassis, parentModel
			end
		end
	end
	return fallbackRoot, nil
end

local function runCameraAntiOcclusionPass(camPos: Vector3, vehicleRoot: BasePart?, vehicleModel: Model?, char: Model?)
	local newOccluded: { [BasePart]: boolean } = {}

	local function markPartOccluded(part: BasePart)
		if isGroundOrRoadPart(part) then
			return
		end
		newOccluded[part] = true
		part.LocalTransparencyModifier = 0.88
	end

	-- 1. Spatial query for all queryable BaseParts within 9 studs of cam.CFrame.Position
	local nearbyParts = Workspace:GetPartBoundsInRadius(camPos, 9.0, cameraOverlapParams)
	for _, part in ipairs(nearbyParts) do
		markPartOccluded(part)
	end

	-- 2. Line-of-sight box query between camera and vehicleRoot so no wall, barricade, or police cruiser blocks the car view
	if vehicleRoot then
		local toCar = vehicleRoot.Position - camPos
		local dist = toCar.Magnitude
		if dist > 2.5 then
			local midPos = camPos + toCar * 0.45
			local boxCF = CFrame.lookAt(midPos, vehicleRoot.Position)
			local losParts = Workspace:GetPartBoundsInBox(boxCF, Vector3.new(5.5, 4.5, math.max(2.0, dist - 4.0)), cameraOverlapParams)
			for _, part in ipairs(losParts) do
				if not (vehicleModel and part:IsDescendantOf(vehicleModel)) and not (char and part:IsDescendantOf(char)) then
					markPartOccluded(part)
				end
			end
		end
	end

	-- 3. Explicit distance check (< 9 studs) on vehicle, character, police, and nearby non-queryable parts (e.g. TaillightBar, SirenRed)
	local function checkContainerPartsWithin9Studs(container: Instance?)
		if not container then
			return
		end
		for _, desc in ipairs(container:GetDescendants()) do
			if desc:IsA("BasePart") then
				if (desc.Position - camPos).Magnitude <= 9.0 then
					markPartOccluded(desc)
				end
			end
		end
	end

	checkContainerPartsWithin9Studs(vehicleModel)
	checkContainerPartsWithin9Studs(char)
	checkContainerPartsWithin9Studs(Workspace:FindFirstChild("PoliceUnits"))
	checkContainerPartsWithin9Studs(Workspace:FindFirstChild("ActivePolice"))

	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") then
			if (child.Position - camPos).Magnitude <= 9.0 then
				markPartOccluded(child)
			end
		elseif child:IsA("Model") and child ~= char and child ~= vehicleModel and child.Name ~= "LeoCity" then
			local primary = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			if primary and (primary.Position - camPos).Magnitude <= 32.0 then
				checkContainerPartsWithin9Studs(child)
			end
		end
	end

	-- Restore LocalTransparencyModifier = 0 for any part now farther than 9 studs from camera
	for prevPart in pairs(occludedCameraParts) do
		if not newOccluded[prevPart] then
			if prevPart.Parent then
				prevPart.LocalTransparencyModifier = 0
			end
		end
	end
	occludedCameraParts = newOccluded
end

RunService.RenderStepped:Connect(function(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	noiseClock += dt * 28
	sirenPhase += dt * 8.5

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
	local isSeatedInVehicle = (humanoid ~= nil and (humanoid.Sit or humanoid.SeatPart ~= nil)) or (player:GetAttribute("IsDriving") == true) or (player:GetAttribute("InVehicle") == true)
	local isDriving = isSeatedInVehicle or (speedMph > 8)
	local nitroBoost = (player:GetAttribute("TouchNitro") == true) and 5 or 0
	local targetFov = isDriving and math.clamp(70 + (speedMph / 140) * 18 + nitroBoost, 70, 92) or 70
	currentFov = currentFov + (targetFov - currentFov) * math.min(1, dt * 8)
	cam.FieldOfView = currentFov

	local targetPos = if root then (root.Position - Vector3.new(0, 1.4, 0)) else getPlayerBumperTargetPosition()

	-- Update 3D Magnetized Flying Gold Coins (0.22s low fountain arc -> 0.32s curve into lower front bumper!)
	if #activeFlyingCoins > 0 then
		for i = #activeFlyingCoins, 1, -1 do
			local c = activeFlyingCoins[i]
			c.elapsed += dt
			local spinAngle = c.spinPhase + c.elapsed * c.spinSpeed

			if c.elapsed <= c.arcDuration then
				-- Low fountain arc (+1.4..2.4 studs above ground — well BELOW car roof and camera line-of-sight!)
				local t = math.clamp(c.elapsed / c.arcDuration, 0, 1)
				local easeOut = 1 - (1 - t) * (1 - t)
				local pos = c.startPos:Lerp(c.apexPos, easeOut)
				c.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, spinAngle, 0)
			else
				-- Curve into the lower front bumper over 0.32s and immediately Destroy upon reaching 4 studs of bumper!
				local homeElapsed = c.elapsed - c.arcDuration - c.delayBeforeHoming
				if homeElapsed <= 0 then
					c.part.CFrame = CFrame.new(c.apexPos) * CFrame.Angles(0, spinAngle, 0)
				else
					local t = math.clamp(homeElapsed / c.homingDuration, 0, 1)
					local easeIn = t * t
					local pos = c.apexPos:Lerp(targetPos, easeIn)
					c.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, spinAngle * 1.35, 0)

					local distToBumper = (pos - targetPos).Magnitude
					if distToBumper <= 4.0 or t >= 1.0 then
						local pitchRatio = (c.coinIndex - 1) / math.max(1, c.totalCoins - 1)
						playCasinoCoinChime(pitchRatio)
						spawnCoinArrivalSparkle(targetPos)
						c.part:Destroy()
						table.remove(activeFlyingCoins, i)
					end
				end
			end
		end
	end

	local inHomeMenu = (player:GetAttribute("HomeMenuActive") == true) or (player:GetAttribute("HomeMenuCameraActive") == true)
	local vehicleRoot, vehicleModel = resolveSeatedVehicleRoot(char, humanoid, root)

	-- Dedicated, Un-Blockable Elevated Third-Person Chase Camera when seated in a vehicle
	if inHomeMenu then
		hasSmoothCam = false
		local orbitAngle = os.clock() * 0.22
		local orbitPos = Vector3.new(math.cos(orbitAngle) * 115, 62, math.sin(orbitAngle) * 115 + 25)
		cam.CFrame = CFrame.lookAt(orbitPos, Vector3.new(0, 18, -30))
	elseif isSeatedInVehicle and vehicleRoot then
		local rawLook = vehicleRoot.CFrame.LookVector
		local flatCarLook = Vector3.new(rawLook.X, 0, rawLook.Z)
		if flatCarLook.Magnitude > 0.01 then
			flatCarLook = flatCarLook.Unit
		else
			flatCarLook = Vector3.new(0, 0, -1)
		end

		local desiredCamPos = vehicleRoot.Position - flatCarLook * 20 + Vector3.new(0, 7.8, 0)
		local lookTarget = vehicleRoot.Position + flatCarLook * 10 + Vector3.new(0, 2.2, 0)

		if not hasSmoothCam or (smoothCamPos - desiredCamPos).Magnitude > 60 then
			smoothCamPos = desiredCamPos
			smoothLookTarget = lookTarget
			hasSmoothCam = true
		else
			local lerpAlpha = math.clamp(dt * 12, 0, 1)
			smoothCamPos = smoothCamPos:Lerp(desiredCamPos, lerpAlpha)
			smoothLookTarget = smoothLookTarget:Lerp(lookTarget, lerpAlpha)
		end

		-- Clamp camera distance >= 19 studs behind and >= 7.5 studs above vehicleRoot so it never enters the car
		local relOffset = smoothCamPos - vehicleRoot.Position
		local horizVec = Vector3.new(relOffset.X, 0, relOffset.Z)
		if horizVec.Magnitude < 19.0 then
			local pushDir = if horizVec.Magnitude > 0.1 then horizVec.Unit else -flatCarLook
			horizVec = pushDir * 19.0
		end
		local minCamY = math.max(smoothCamPos.Y, vehicleRoot.Position.Y + 7.5)
		smoothCamPos = Vector3.new(vehicleRoot.Position.X + horizVec.X, minCamY, vehicleRoot.Position.Z + horizVec.Z)

		cam.CFrame = CFrame.lookAt(smoothCamPos, lookTarget)
	else
		hasSmoothCam = false
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

	lastFinalChaseCFrame = cam.CFrame

	-- Camera Anti-Occlusion Pass: fade any BasePart within 9 studs of cam.CFrame.Position to LocalTransparencyModifier = 0.88
	runCameraAntiOcclusionPass(cam.CFrame.Position, vehicleRoot, vehicleModel, char)

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

-- Post-Camera RenderStep lock (Priority Camera + 1) so Roblox's default PopperCam can never override the chase camera
RunService:BindToRenderStep("WODChaseCameraPostLock", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local inHomeMenu = (player:GetAttribute("HomeMenuActive") == true) or (player:GetAttribute("HomeMenuCameraActive") == true)
	if inHomeMenu and lastFinalChaseCFrame then
		cam.CFrame = lastFinalChaseCFrame
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local isSeatedInVehicle = (humanoid ~= nil and (humanoid.Sit or humanoid.SeatPart ~= nil)) or (player:GetAttribute("IsDriving") == true) or (player:GetAttribute("InVehicle") == true)
	if isSeatedInVehicle and hasSmoothCam and lastFinalChaseCFrame then
		local vehicleRoot, vehicleModel = resolveSeatedVehicleRoot(char, humanoid, root)
		cam.CFrame = lastFinalChaseCFrame
		runCameraAntiOcclusionPass(cam.CFrame.Position, vehicleRoot, vehicleModel, char)
	end
end)
