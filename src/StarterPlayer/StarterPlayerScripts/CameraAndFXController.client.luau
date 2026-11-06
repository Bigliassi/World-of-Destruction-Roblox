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
-- 2. PROCEDURAL SOUND SYNTHESIS
-- ==========================================
local sfxFolder = SoundService:FindFirstChild("WODClientSFX")
if not sfxFolder then
	sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "WODClientSFX"
	sfxFolder.Parent = SoundService
end

type SfxPreset = { id: string, speed: number, volume: number }
local SFX_PRESETS: { [string]: SfxPreset } = {
	Impact = { id = "rbxasset://sounds/collide.wav", speed = 0.92, volume = 0.65 },
	HeavySmash = { id = "rbxasset://sounds/Launching rocket.wav", speed = 1.25, volume = 0.75 },
	Explosion = { id = "rbxasset://sounds/Rocket shot.wav", speed = 0.78, volume = 0.90 },
	CashChime = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.35, volume = 0.45 },
	LevelUp = { id = "rbxasset://sounds/uuhhh.mp3", speed = 1.45, volume = 0.70 },
}

local function playProceduralSound(kind: string, pitchVariance: number?)
	local preset = SFX_PRESETS[kind] or SFX_PRESETS.Impact
	local sound = Instance.new("Sound")
	sound.Name = kind .. "SFX"
	sound.SoundId = preset.id
	local variance = (pitchVariance or 0.1) * (math.random() * 2 - 1)
	sound.PlaybackSpeed = math.max(0.4, preset.speed + variance)
	sound.Volume = preset.volume
	sound.Parent = sfxFolder
	sound:Play()
	task.delay(2.5, function()
		sound:Destroy()
	end)
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
	anchor.Position = worldPos + Vector3.new((math.random() - 0.5) * 3, 2.5, (math.random() - 0.5) * 3)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = popupContainer

	local bb = Instance.new("BillboardGui")
	bb.Name = "ImpactBillboard"
	bb.Size = UDim2.fromOffset(180, 64)
	bb.StudsOffset = Vector3.new(0, 1, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 260
	bb.Parent = anchor

	local mainLabel = Instance.new("TextLabel")
	mainLabel.Size = UDim2.new(1, 0, 0.6, 0)
	mainLabel.BackgroundTransparency = 1
	mainLabel.Font = Enum.Font.GothamBlack
	mainLabel.Text = headline
	mainLabel.TextColor3 = color
	mainLabel.TextScaled = true
	mainLabel.TextStrokeTransparency = 0.2
	mainLabel.Parent = bb

	if subtext and #subtext > 0 then
		local subLabel = Instance.new("TextLabel")
		subLabel.Size = UDim2.new(1, 0, 0.4, 0)
		subLabel.Position = UDim2.fromScale(0, 0.58)
		subLabel.BackgroundTransparency = 1
		subLabel.Font = Enum.Font.GothamBold
		subLabel.Text = subtext
		subLabel.TextColor3 = Color3.fromRGB(255, 245, 190)
		subLabel.TextScaled = true
		subLabel.TextStrokeTransparency = 0.35
		subLabel.Parent = bb
	end

	TweenService:Create(bb, TweenInfo.new(0.95, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 6.5, 0),
	}):Play()
	TweenService:Create(mainLabel, TweenInfo.new(0.95, Enum.EasingStyle.Linear), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	task.delay(1.0, function()
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
		addCameraTrauma(math.clamp(amount / 600, 0.18, 0.65), 0.15)
		playProceduralSound(amount > 300 and "HeavySmash" or "Impact", 0.12)
	end)

	bindEvent("DestructionOccurred", function(worldPosOrPayload: any, propName: any, cashAwarded: any)
		local pos = Vector3.zero
		local cash = 75
		local sub = "PROP WRECKED"
		if typeof(worldPosOrPayload) == "Vector3" then
			pos = worldPosOrPayload
			cash = tonumber(cashAwarded) or 75
			sub = typeof(propName) == "string" and ("WRECKED " .. string.upper(propName)) or "PROP WRECKED"
		elseif type(worldPosOrPayload) == "table" then
			if typeof(worldPosOrPayload.position) == "Vector3" then
				pos = worldPosOrPayload.position
			elseif typeof(worldPosOrPayload.Position) == "Vector3" then
				pos = worldPosOrPayload.Position
			end
			cash = tonumber(worldPosOrPayload.cashEarned or worldPosOrPayload.CashReward) or 75
			local pType = worldPosOrPayload.propType or worldPosOrPayload.Type
			if typeof(pType) == "string" then
				sub = "WRECKED " .. string.upper(pType)
			end
		end
		spawn3DPopup(pos, "+$" .. tostring(math.floor(cash)), sub, Color3.fromRGB(255, 210, 65))
		addCameraTrauma(0.28, 0.1)
		playProceduralSound("Impact", 0.15)
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
		playProceduralSound("Explosion", 0.08)
	end)

	bindEvent("CameraShake", function(intensity: any)
		addCameraTrauma(tonumber(intensity) or 0.35, 0.15)
	end)
end)

-- ==========================================
-- 6. RENDERSTEPPED CHASE CAMERA, FOV & SIREN VIGNETTE
-- ==========================================
local sirenPhase = 0.0

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
	if speedDrop > 32 then
		addCameraTrauma(math.clamp(speedDrop / 95, 0.2, 0.7), 0.2)
		playProceduralSound("Impact", 0.14)
	end
	lastSpeed = speedMph

	-- Dynamic Speed-Based FOV Scaling (70 base -> up to 92 at high speed / nitro)
	local isDriving = (humanoid and humanoid.Sit) or (speedMph > 8)
	local nitroBoost = (player:GetAttribute("TouchNitro") == true) and 5 or 0
	local targetFov = isDriving and math.clamp(70 + (speedMph / 140) * 18 + nitroBoost, 70, 92) or 70
	currentFov = currentFov + (targetFov - currentFov) * math.min(1, dt * 8)
	cam.FieldOfView = currentFov

	-- Trauma-Based 3D Rotational & Positional Camera Shake
	if trauma > 0.001 then
		local shake = trauma * trauma
		local dx = math.noise(noiseClock, 1.3) * 1.6 * shake
		local dy = math.noise(1.3, noiseClock) * 1.6 * shake
		local roll = math.noise(noiseClock, noiseClock) * math.rad(5.5) * shake
		cam.CFrame = cam.CFrame * CFrame.new(dx, dy, 0) * CFrame.Angles(dy * 0.02, dx * 0.02, roll)
		trauma = math.max(0, trauma - dt * 1.45)
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
