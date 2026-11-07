--!strict
-- CameraAndFXController.client.luau
-- Dynamic speed-scaled chase camera, trauma 3D shake, police pursuit vignette, 3D floating BillboardGui popups, and procedural SFX.

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
-- 2. FOLEY & PHYSICAL SOUND ENGINE (NO EXPLOSIONS ON PROPS)
-- ==========================================
local sfxFolder = SoundService:FindFirstChild("WODClientSFX")
if not sfxFolder then
	sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "WODClientSFX"
	sfxFolder.Parent = SoundService
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
		-- Crisp, snappy wooden crack + dry mid thump with zero bass boom
		spawnShapedLayer({
			name = "WoodSnapCrack",
			soundId = "rbxasset://sounds/snap.mp3",
			volume = 0.24,
			speed = 1.35 + jitter,
			maxDuration = 0.24,
			lowGain = -20,
			midGain = 4,
			highGain = 6,
		})
		spawnShapedLayer({
			name = "WoodSnapClick",
			soundId = "rbxasset://sounds/clickfast.wav",
			volume = 0.20,
			speed = 1.28 + jitter * 0.5,
			maxDuration = 0.18,
			lowGain = -20,
			midGain = 4,
			highGain = 6,
		})
		spawnShapedLayer({
			name = "WoodSnapBody",
			soundId = "rbxasset://sounds/impact_water.mp3",
			volume = 0.24,
			speed = 1.35 + jitter,
			timePosition = 0.02,
			maxDuration = 0.20,
			lowGain = -20,
			midGain = 4,
			highGain = 6,
		})
	elseif kind == "MetalClatter" or kind == "HeavySmash" then
		-- Crisp metallic clink/clatter with low rumble filtered out
		spawnShapedLayer({
			name = "MetalPrimaryHit",
			soundId = "rbxasset://sounds/metal.ogg",
			volume = 0.22,
			speed = 1.15 + jitter,
			maxDuration = 0.30,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
		})
		spawnShapedLayer({
			name = "MetalClinkSwitch",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.22,
			speed = 1.15 + jitter,
			maxDuration = 0.24,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
			pitchOctave = 1.12,
		})
		task.delay(0.055, function()
			spawnShapedLayer({
				name = "MetalSecondaryClatter",
				soundId = "rbxasset://sounds/hit.wav",
				volume = 0.16,
				speed = 1.28 + jitter,
				maxDuration = 0.22,
				lowGain = -18,
				midGain = 3,
				highGain = 8,
			})
		end)
	elseif kind == "HydrantBurst" then
		-- Crisp metallic tap followed by soft pressurized water geyser spray
		spawnShapedLayer({
			name = "HydrantMetalTap",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.22,
			speed = 1.2 + jitter * 0.5,
			maxDuration = 0.22,
			lowGain = -18,
			midGain = 3,
			highGain = 8,
		})
		task.delay(0.03, function()
			spawnShapedLayer({
				name = "HydrantWaterBurst",
				soundId = "rbxasset://sounds/impact_water.mp3",
				volume = 0.25,
				speed = 1.1 + jitter * 0.4,
				maxDuration = 0.65,
				lowGain = -12,
				midGain = 2,
				highGain = 5,
			})
			spawnShapedLayer({
				name = "HydrantWaterSpray",
				soundId = "rbxasset://sounds/action_swim.mp3",
				volume = 0.22,
				speed = 1.1 + jitter * 0.3,
				maxDuration = 0.75,
				lowGain = -14,
				midGain = 2,
				highGain = 6,
			})
		end)
	elseif kind == "CashChime" then
		-- Rate-limited (at most once every 0.18s) with rising combo pitch
		if now - lastCashSoundAt < 0.18 then
			return
		end
		lastCashSoundAt = now

		if now - lastComboTickAt > 3.2 then
			rollingComboCount = 0
		end
		rollingComboCount += 1
		lastComboTickAt = now

		local attrCombo = tonumber(
			player:GetAttribute("Combo")
			or player:GetAttribute("ComboCount")
			or player:GetAttribute("ComboStreak")
		) or 0
		local comboCount = math.max(attrCombo, rollingComboCount - 1)
		local speed = 1.15 + math.min(comboCount * 0.04, 0.6)

		spawnShapedLayer({
			name = "CashChimePing",
			soundId = "rbxasset://sounds/electronicpingshort.wav",
			volume = 0.14,
			speed = speed,
			maxDuration = 0.35,
			lowGain = -10,
			midGain = 2,
			highGain = -6,
		})
	elseif kind == "LevelUp" then
		-- Pleasant 3-note ascending arpeggio chime at pitches 1.0, 1.25, 1.5 (0.09s apart)
		local notes = { 1.0, 1.25, 1.5 }
		for i, pitch in ipairs(notes) do
			task.delay((i - 1) * 0.09, function()
				spawnShapedLayer({
					name = "LevelUpArpeggio_" .. tostring(i),
					soundId = "rbxasset://sounds/electronicpingshort.wav",
					volume = 0.22,
					speed = pitch,
					maxDuration = 0.45,
					lowGain = -8,
					midGain = 3,
					highGain = -4,
				})
			end)
		end
	elseif kind == "TrueExplosion" then
		-- ONLY played for genuine GasPump / ExplosiveBarrel detonations or ExplosionEffect remote
		if now - lastExplosionSoundAt < 0.16 then
			return
		end
		lastExplosionSoundAt = now
		lastImpactSoundAt = now

		spawnShapedLayer({
			name = "TrueExplosionPunch",
			soundId = "rbxasset://sounds/bass.mp3",
			volume = 0.38,
			speed = 0.62 + jitter * 0.3,
			maxDuration = 0.70,
			lowGain = 6,
			midGain = 2,
			highGain = -6,
		})
		spawnShapedLayer({
			name = "TrueExplosionBlast",
			soundId = "rbxasset://sounds/impact_water.mp3",
			volume = 0.32,
			speed = 0.58 + jitter * 0.3,
			maxDuration = 0.75,
			lowGain = 5,
			midGain = 3,
			highGain = -2,
		})
		spawnShapedLayer({
			name = "TrueExplosionDebris",
			soundId = "rbxasset://sounds/switch.wav",
			volume = 0.20,
			speed = 0.75 + jitter * 0.3,
			maxDuration = 0.40,
			lowGain = -6,
			midGain = 4,
			highGain = 4,
		})
	end
end

-- ==========================================
-- 2B. SUBTLE CONTINUOUS VEHICLE ENGINE & DRIFT AUDIO
-- ==========================================
local engineSound = Instance.new("Sound")
engineSound.Name = "VehicleEnginePurr"
engineSound.SoundId = "rbxasset://sounds/bass.mp3"
engineSound.Looped = true
engineSound.Volume = 0
engineSound.PlaybackSpeed = 0.70
local engineEq = Instance.new("EqualizerSoundEffect")
engineEq.LowGain = 3
engineEq.MidGain = -4
engineEq.HighGain = -24
engineEq.Parent = engineSound
local enginePitch = Instance.new("PitchShiftSoundEffect")
enginePitch.Octave = 0.85
enginePitch.Parent = engineSound
engineSound.Parent = sfxFolder

local driftSound = Instance.new("Sound")
driftSound.Name = "VehicleDriftSkid"
driftSound.SoundId = "rbxasset://sounds/swoosh.wav"
driftSound.Looped = true
driftSound.Volume = 0
driftSound.PlaybackSpeed = 1.05
local driftEq = Instance.new("EqualizerSoundEffect")
driftEq.LowGain = -18
driftEq.MidGain = 1
driftEq.HighGain = -6
driftEq.Parent = driftSound
driftSound.Parent = sfxFolder

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
	bb.Size = UDim2.fromOffset(120, 38)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Parent = anchor

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Size = UDim2.new(1, 0, 0.58, 0)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.Text = headline
	mainLabel.TextColor3 = color
	mainLabel.TextScaled = true
	mainLabel.TextStrokeTransparency = 0.3
	mainLabel.Parent = bb

	local subLabel: TextLabel? = nil
	if subtext and #subtext > 0 then
		subLabel = Instance.new("TextLabel")
		subLabel.Size = UDim2.new(1, 0, 0.38, 0)
		subLabel.Position = UDim2.fromScale(0, 0.58)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.Text = subtext
		subLabel.TextColor3 = Color3.fromRGB(255, 245, 190)
		subLabel.TextScaled = true
		subLabel.TextStrokeTransparency = 0.45
		subLabel.Parent = bb
	end

	TweenService:Create(bb, TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 5.2, 0),
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
			playProceduralSound("CashChime", 0.08)
		end
		lastCashAttr = nowCash
	elseif attr == "Level" then
		local nowLvl = tonumber(player:GetAttribute("Level")) or 1
		if nowLvl > lastLevelAttr then
			playProceduralSound("LevelUp", 0.04)
			addCameraTrauma(0.35, 0.25)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				spawn3DPopup(root.Position, "LEVEL UP! LV." .. tostring(nowLvl), "RANK PROMOTION", Color3.fromRGB(95, 225, 255))
			end
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
		local pos = typeof(worldPos) == "Vector3" and worldPos or (
			player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			and (player.Character.HumanoidRootPart :: BasePart).Position or Vector3.zero
		)
		local amount = tonumber(damageOrCash) or 100
		local title = amount >= 0 and ("+$" .. tostring(math.floor(amount))) or tostring(labelText or "SMASH!")
		local subtitle = typeof(labelText) == "string" and labelText or "DESTRUCTION"
		spawn3DPopup(pos, title, subtitle, Color3.fromRGB(110, 255, 140))
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
		end

		spawn3DPopup(pos, "+$" .. tostring(math.floor(cash)), sub, Color3.fromRGB(255, 210, 65))

		local sfxKind = classifyPropSoundKind(propType, isExplosion)
		if sfxKind == "TrueExplosion" then
			addCameraTrauma(0.55, 0.25)
		else
			addCameraTrauma(0.20, 0.08)
		end
		playProceduralSound(sfxKind, 0.08)
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
		playProceduralSound("LevelUp", 0.02)
	end)

	bindEvent("CameraShake", function(intensity: any)
		addCameraTrauma(tonumber(intensity) or 0.35, 0.15)
	end)
end)

-- ==========================================
-- 6. RENDERSTEPPED CHASE CAMERA, FOV, ENGINE AUDIO & SIREN VIGNETTE
-- ==========================================
local sirenPhase = 0.0
local currentEngineVol = 0.0
local currentEngineSpeed = 0.70
local currentDriftVol = 0.0

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
	local isSeatedInVehicle = (humanoid ~= nil and humanoid.Sit) or (player:GetAttribute("IsDriving") == true)
	local isDriving = isSeatedInVehicle or (speedMph > 8)
	local nitroBoost = (player:GetAttribute("TouchNitro") == true) and 5 or 0
	local targetFov = isDriving and math.clamp(70 + (speedMph / 140) * 18 + nitroBoost, 70, 92) or 70
	currentFov = currentFov + (targetFov - currentFov) * math.min(1, dt * 8)
	cam.FieldOfView = currentFov

	-- Subtle Continuous Vehicle Engine Hum/Purr & Drift Audio (respects EngineSoundEnabled & SFXVolume)
	local engineEnabled = player:GetAttribute("EngineSoundEnabled") ~= false
	local sfxScale = tonumber(player:GetAttribute("SFXVolume")) or 1.0
	if isSeatedInVehicle and engineEnabled and sfxScale > 0.001 then
		if not engineSound.IsPlaying then
			engineSound:Play()
		end
		local speedRatio = math.clamp(speedMph / 120, 0, 1)
		local nitroExtraVol = (player:GetAttribute("TouchNitro") == true) and 0.02 or 0
		local nitroExtraPitch = (player:GetAttribute("TouchNitro") == true) and 0.15 or 0
		local targetEngineVol = 0.08 + speedRatio * 0.08 + nitroExtraVol -- 0.08..0.16
		local targetEngineSpeed = 0.68 + speedRatio * 0.95 + nitroExtraPitch

		currentEngineVol = currentEngineVol + (targetEngineVol - currentEngineVol) * math.min(1, dt * 8)
		currentEngineSpeed = currentEngineSpeed + (targetEngineSpeed - currentEngineSpeed) * math.min(1, dt * 6)
		engineSound.Volume = math.clamp(currentEngineVol, 0, 0.18)
		engineSound.PlaybackSpeed = currentEngineSpeed

		-- Subtle lateral slip / drift tire sound
		local lateralSlip = 0
		if root then
			local vel = root.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			if flatVel.Magnitude > 18 then
				local rightVec = root.CFrame.RightVector
				lateralSlip = math.abs(flatVel:Dot(rightVec))
			end
		end
		local isDrifting = (player:GetAttribute("TouchDrift") == true and speedMph > 22) or (lateralSlip > 14)
		local targetDriftVol = isDrifting and math.clamp((lateralSlip / 45) * 0.08, 0.03, 0.08) or 0
		currentDriftVol = currentDriftVol + (targetDriftVol - currentDriftVol) * math.min(1, dt * 10)
		if currentDriftVol > 0.005 then
			if not driftSound.IsPlaying then
				driftSound:Play()
			end
			driftSound.Volume = currentDriftVol
			driftSound.PlaybackSpeed = 0.95 + math.clamp(speedMph / 180, 0, 0.35)
		elseif driftSound.IsPlaying then
			driftSound.Volume = 0
			driftSound:Stop()
		end
	else
		currentEngineVol = currentEngineVol + (0 - currentEngineVol) * math.min(1, dt * 10)
		currentDriftVol = 0
		if currentEngineVol < 0.005 then
			if engineSound.IsPlaying then
				engineSound.Volume = 0
				engineSound:Stop()
			end
		else
			engineSound.Volume = currentEngineVol
		end
		if driftSound.IsPlaying then
			driftSound.Volume = 0
			driftSound:Stop()
		end
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
	if player:GetAttribute("HomeMenuActive") == true or player:GetAttribute("HomeMenuCameraActive") == true then
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
