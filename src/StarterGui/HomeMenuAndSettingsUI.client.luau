--!strict
--[[
	HomeMenuAndSettingsUI.client.luau
	World of Destruction (Roblox)
	
	Ultra-Clean, Zero-Emoji, Minimal-Text Home Menu & 2x2 Settings Modal:
	- Home Menu:
	  * Title: "WORLD OF DESTRUCTION"
	  * 4 big, clean 3D buttons with ONLY 1-2 words each (no subtitles or paragraphs!):
	    1. PLAY
	    2. GARAGE
	    3. AVATAR
	    4. SETTINGS
	- Settings Modal:
	  * 4 big visual toggle pills in a 2x2 grid (zero explanation sentences!):
	    1. SOUND: ON / MUTE
	    2. WEATHER: SNOW / RAIN / CLEAR
	    3. DRIVING: NORMAL / TURBO
	    4. CONTROLS: AUTO / PAD / TOUCH
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Initialize default player settings attributes if not yet set
if localPlayer:GetAttribute("SFXVolume") == nil then
	localPlayer:SetAttribute("SFXVolume", 1.0)
end
if localPlayer:GetAttribute("EngineSoundEnabled") == nil then
	localPlayer:SetAttribute("EngineSoundEnabled", true)
end
if localPlayer:GetAttribute("WeatherPreference") == nil then
	localPlayer:SetAttribute("WeatherPreference", "Snowy NYC")
end
if localPlayer:GetAttribute("TimeOfDayPreference") == nil then
	localPlayer:SetAttribute("TimeOfDayPreference", "Snowy")
end
if localPlayer:GetAttribute("DrivingMode") == nil then
	localPlayer:SetAttribute("DrivingMode", "Progressive")
end
if localPlayer:GetAttribute("ControlScheme") == nil then
	localPlayer:SetAttribute("ControlScheme", "Standard")
end
if localPlayer:GetAttribute("CameraShakeScale") == nil then
	localPlayer:SetAttribute("CameraShakeScale", 1.0)
end
if localPlayer:GetAttribute("HomeMenuActive") == nil then
	localPlayer:SetAttribute("HomeMenuActive", true)
end
if localPlayer:GetAttribute("HomeMenuCameraActive") == nil then
	localPlayer:SetAttribute("HomeMenuCameraActive", true)
end

local existingGui = playerGui:FindFirstChild("WorldOfDestructionHomeMenuGui")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WorldOfDestructionHomeMenuGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 25
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Name = "HomeMenuAutoScale"
uiScale.Scale = 1.0
uiScale.Parent = screenGui

local function updateMenuScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.68, 1.05)
	end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateMenuScale)
		updateMenuScale()
	end
end)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateMenuScale)
	updateMenuScale()
end

--------------------------------------------------------------------------------
-- 3D Tactile Beveled UI Helpers (Zero Emojis, Zero Subtitles)
--------------------------------------------------------------------------------
local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number, trans: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = trans or 0.2
	s.Parent = parent
	return s
end

local function darkenColor(c: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(c.R * factor, 0, 1),
		math.clamp(c.G * factor, 0, 1),
		math.clamp(c.B * factor, 0, 1)
	)
end

local function brightenColor(c: Color3, boost: number): Color3
	return Color3.new(
		math.clamp(c.R + boost, 0, 1),
		math.clamp(c.G + boost, 0, 1),
		math.clamp(c.B + boost, 0, 1)
	)
end

local function makeTactile3DButton(params: {
	name: string,
	title: string,
	size: UDim2,
	position: UDim2?,
	layoutOrder: number?,
	baseColor: Color3,
	textSize: number?,
	zIndex: number?,
	parent: Instance,
	onClick: () -> (),
}): (Frame, TextLabel)
	local lipDepth = 5
	local zBase = params.zIndex or 2
	local container = Instance.new("Frame")
	container.Name = params.name
	container.Size = params.size
	if params.position then
		container.Position = params.position
	end
	if params.layoutOrder then
		container.LayoutOrder = params.layoutOrder
	end
	container.BackgroundColor3 = darkenColor(params.baseColor, 0.50)
	container.BorderSizePixel = 0
	container.ZIndex = zBase
	container.Parent = params.parent
	addCorner(container, 12)
	addStroke(container, darkenColor(params.baseColor, 0.35), 1.5, 0.15)

	local face = Instance.new("TextButton")
	face.Name = "ButtonFace"
	face.Size = UDim2.new(1, 0, 1, -lipDepth)
	face.Position = UDim2.fromOffset(0, 0)
	face.BackgroundColor3 = params.baseColor
	face.BorderSizePixel = 0
	face.AutoButtonColor = false
	face.Text = ""
	face.ZIndex = zBase + 1
	face.Parent = container
	addCorner(face, 11)
	addStroke(face, brightenColor(params.baseColor, 0.28), 1.5, 0.22)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, brightenColor(params.baseColor, 0.18)),
		ColorSequenceKeypoint.new(1, darkenColor(params.baseColor, 0.86)),
	})
	grad.Parent = face

	local gloss = Instance.new("Frame")
	gloss.Name = "TopGlossSheen"
	gloss.Size = UDim2.new(1, -6, 0.38, 0)
	gloss.Position = UDim2.fromOffset(3, 2)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.84
	gloss.BorderSizePixel = 0
	gloss.ZIndex = zBase + 2
	gloss.Parent = face
	addCorner(gloss, 8)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -16, 1, 0)
	titleLbl.Position = UDim2.fromOffset(8, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.Text = params.title
	titleLbl.TextColor3 = Color3.new(1, 1, 1)
	titleLbl.TextSize = params.textSize or 20
	titleLbl.TextXAlignment = Enum.TextXAlignment.Center
	titleLbl.TextStrokeTransparency = 0.40
	titleLbl.ZIndex = zBase + 3
	titleLbl.Parent = face

	face.MouseEnter:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, -1),
			BackgroundColor3 = brightenColor(params.baseColor, 0.08),
		}):Play()
	end)
	face.MouseLeave:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
			BackgroundColor3 = params.baseColor,
		}):Play()
	end)
	face.MouseButton1Down:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 3),
		}):Play()
	end)
	face.MouseButton1Up:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		}):Play()
	end)
	face.MouseButton1Click:Connect(params.onClick)

	return container, titleLbl
end

--------------------------------------------------------------------------------
-- 1. CENTERED HOME CARD (Title: WORLD OF DESTRUCTION + 4 Clean Buttons)
--------------------------------------------------------------------------------
local homeRoot = Instance.new("Frame")
homeRoot.Name = "HomeMenuOverlay"
homeRoot.Size = UDim2.fromScale(1, 1)
homeRoot.BackgroundColor3 = Color3.fromRGB(6, 10, 18)
homeRoot.BackgroundTransparency = 0.35
homeRoot.BorderSizePixel = 0
homeRoot.Visible = true
homeRoot.Parent = screenGui

local homeCard = Instance.new("Frame")
homeCard.Name = "HomeCard"
homeCard.Size = UDim2.fromOffset(440, 360)
homeCard.Position = UDim2.fromScale(0.5, 0.5)
homeCard.AnchorPoint = Vector2.new(0.5, 0.5)
homeCard.BackgroundColor3 = Color3.fromRGB(13, 18, 30)
homeCard.BackgroundTransparency = 0.06
homeCard.BorderSizePixel = 0
homeCard.Parent = homeRoot
addCorner(homeCard, 18)
addStroke(homeCard, Color3.fromRGB(255, 190, 50), 2.5, 0.12)

local headerBox = Instance.new("Frame")
headerBox.Name = "HeaderBanner"
headerBox.Size = UDim2.new(1, -36, 0, 62)
headerBox.Position = UDim2.fromOffset(18, 16)
headerBox.BackgroundColor3 = Color3.fromRGB(20, 27, 44)
headerBox.BorderSizePixel = 0
headerBox.Parent = homeCard
addCorner(headerBox, 12)
addStroke(headerBox, Color3.fromRGB(255, 200, 65), 1.5, 0.28)

local heroTitle = Instance.new("TextLabel")
heroTitle.Name = "HeroTitle"
heroTitle.Size = UDim2.new(1, -24, 1, 0)
heroTitle.Position = UDim2.fromOffset(12, 0)
heroTitle.BackgroundTransparency = 1
heroTitle.Font = Enum.Font.GothamBlack
heroTitle.Text = "WORLD OF DESTRUCTION"
heroTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
heroTitle.TextSize = 28
heroTitle.TextScaled = true
heroTitle.TextXAlignment = Enum.TextXAlignment.Center
heroTitle.Parent = headerBox

local heroGrad = Instance.new("UIGradient")
heroGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 155)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 185, 50)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 115, 40)),
})
heroGrad.Parent = heroTitle

local buttonsStack = Instance.new("Frame")
buttonsStack.Name = "MainButtonsStack"
buttonsStack.Size = UDim2.new(1, -36, 0, 252)
buttonsStack.Position = UDim2.fromOffset(18, 92)
buttonsStack.BackgroundTransparency = 1
buttonsStack.Parent = homeCard

local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.Padding = UDim.new(0, 10)
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Parent = buttonsStack

local settingsModal: Frame

local function setHomeMenuOpen(isOpen: boolean)
	homeRoot.Visible = isOpen
	localPlayer:SetAttribute("HomeMenuActive", isOpen)
	localPlayer:SetAttribute("HomeMenuCameraActive", isOpen)
end

-- 1. PLAY
makeTactile3DButton({
	name = "PlayNowBtn",
	title = "PLAY",
	size = UDim2.new(1, 0, 0, 58),
	layoutOrder = 1,
	baseColor = Color3.fromRGB(28, 190, 92),
	textSize = 24,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
	end,
})

-- 2. GARAGE
makeTactile3DButton({
	name = "GarageAndUpgradesBtn",
	title = "GARAGE",
	size = UDim2.new(1, 0, 0, 54),
	layoutOrder = 2,
	baseColor = Color3.fromRGB(36, 128, 240),
	textSize = 20,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
		localPlayer:SetAttribute("ToggleShopUI", not localPlayer:GetAttribute("ToggleShopUI"))
	end,
})

-- 3. AVATAR
makeTactile3DButton({
	name = "AvatarShopBtn",
	title = "AVATAR",
	size = UDim2.new(1, 0, 0, 54),
	layoutOrder = 3,
	baseColor = Color3.fromRGB(128, 62, 225),
	textSize = 20,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
		localPlayer:SetAttribute("ToggleAvatarUI", not localPlayer:GetAttribute("ToggleAvatarUI"))
	end,
})

-- 4. SETTINGS
makeTactile3DButton({
	name = "SettingsBtn",
	title = "SETTINGS",
	size = UDim2.new(1, 0, 0, 54),
	layoutOrder = 4,
	baseColor = Color3.fromRGB(64, 78, 104),
	textSize = 20,
	parent = buttonsStack,
	onClick = function()
		settingsModal.Visible = true
	end,
})

--------------------------------------------------------------------------------
-- 2. SETTINGS MODAL (2x2 Grid of 4 Big Visual Toggle Pills, Zero Sentences)
--------------------------------------------------------------------------------
settingsModal = Instance.new("Frame")
settingsModal.Name = "SettingsModal"
settingsModal.Size = UDim2.fromOffset(520, 270)
settingsModal.Position = UDim2.fromScale(0.5, 0.5)
settingsModal.AnchorPoint = Vector2.new(0.5, 0.5)
settingsModal.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
settingsModal.BackgroundTransparency = 0.04
settingsModal.BorderSizePixel = 0
settingsModal.Visible = false
settingsModal.ZIndex = 30
settingsModal.Parent = screenGui
addCorner(settingsModal, 16)
addStroke(settingsModal, Color3.fromRGB(95, 135, 220), 2.2, 0.1)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -140, 0, 38)
settingsTitle.Position = UDim2.fromOffset(20, 14)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Font = Enum.Font.GothamBlack
settingsTitle.Text = "SETTINGS"
settingsTitle.TextColor3 = Color3.fromRGB(255, 220, 75)
settingsTitle.TextSize = 22
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.ZIndex = 31
settingsTitle.Parent = settingsModal

makeTactile3DButton({
	name = "CloseSettingsBtn",
	title = "CLOSE",
	size = UDim2.fromOffset(96, 38),
	position = UDim2.new(1, -114, 0, 14),
	baseColor = Color3.fromRGB(215, 55, 65),
	textSize = 15,
	zIndex = 32,
	parent = settingsModal,
	onClick = function()
		settingsModal.Visible = false
	end,
})

local gridFrame = Instance.new("Frame")
gridFrame.Name = "ToggleGrid2x2"
gridFrame.Size = UDim2.new(1, -40, 0, 182)
gridFrame.Position = UDim2.fromOffset(20, 68)
gridFrame.BackgroundTransparency = 1
gridFrame.ZIndex = 31
gridFrame.Parent = settingsModal

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(232, 82)
gridLayout.CellPadding = UDim2.fromOffset(16, 16)
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridFrame

local function makeToggleTile(order: number, initialText: string, baseColor: Color3, onCycle: (TextLabel) -> ())
	local tileFrame, tileLbl = makeTactile3DButton({
		name = "SettingTile_" .. tostring(order),
		title = initialText,
		size = UDim2.fromOffset(232, 82),
		layoutOrder = order,
		baseColor = baseColor,
		textSize = 18,
		zIndex = 32,
		parent = gridFrame,
		onClick = function() end,
	})
	local face = tileFrame:FindFirstChild("ButtonFace") :: TextButton?
	if face then
		face.MouseButton1Click:Connect(function()
			onCycle(tileLbl)
		end)
	end
end

-- Tile 1: SOUND: ON / MUTE
local soundMuted = (tonumber(localPlayer:GetAttribute("SFXVolume")) or 1.0) <= 0.01
makeToggleTile(1, if soundMuted then "SOUND: MUTE" else "SOUND: ON", Color3.fromRGB(42, 138, 225), function(lbl)
	soundMuted = not soundMuted
	localPlayer:SetAttribute("SFXVolume", if soundMuted then 0.0 else 1.0)
	localPlayer:SetAttribute("EngineSoundEnabled", not soundMuted)
	lbl.Text = if soundMuted then "SOUND: MUTE" else "SOUND: ON"
end)

-- Tile 2: WEATHER: SNOW / RAIN / CLEAR
local weatherModes = {
	{ label = "WEATHER: SNOW", attr = "Snowy NYC", mode = "Snowy", clock = 16.4, bright = 1.85, fogEnd = 900 },
	{ label = "WEATHER: RAIN", attr = "Rainy NYC", mode = "Rainy", clock = 16.4, bright = 1.85, fogEnd = 750 },
	{ label = "WEATHER: CLEAR", attr = "Sunny Day", mode = "Sunny", clock = 13.5, bright = 3.2, fogEnd = 2200 },
}
local weatherIdx = 1
makeToggleTile(2, weatherModes[1].label, Color3.fromRGB(220, 138, 35), function(lbl)
	weatherIdx = (weatherIdx % #weatherModes) + 1
	local wm = weatherModes[weatherIdx]
	localPlayer:SetAttribute("WeatherPreference", wm.attr)
	localPlayer:SetAttribute("WeatherMode", wm.mode)
	localPlayer:SetAttribute("TimeOfDayPreference", wm.mode)
	Lighting.ClockTime = wm.clock
	Lighting.Brightness = wm.bright
	Lighting.FogEnd = wm.fogEnd
	lbl.Text = wm.label
end)

-- Tile 3: DRIVING: NORMAL / TURBO
makeToggleTile(3, "DRIVING: NORMAL", Color3.fromRGB(38, 175, 95), function(lbl)
	local cur = tostring(localPlayer:GetAttribute("DrivingMode") or "Progressive")
	local nextMode = if cur == "Progressive" then "Arcade" else "Progressive"
	localPlayer:SetAttribute("DrivingMode", nextMode)
	lbl.Text = if nextMode == "Progressive" then "DRIVING: NORMAL" else "DRIVING: TURBO"
end)

-- Tile 4: CONTROLS: AUTO / PAD / TOUCH
local controlModes = {
	{ label = "CONTROLS: AUTO", val = "Standard" },
	{ label = "CONTROLS: PAD", val = "Gamepad" },
	{ label = "CONTROLS: TOUCH", val = "Touch" },
}
local controlIdx = 1
makeToggleTile(4, controlModes[1].label, Color3.fromRGB(125, 78, 220), function(lbl)
	controlIdx = (controlIdx % #controlModes) + 1
	local cm = controlModes[controlIdx]
	localPlayer:SetAttribute("ControlScheme", cm.val)
	lbl.Text = cm.label
end)

--------------------------------------------------------------------------------
-- 3. VICTORY MODAL (Minimal Text, Zero Emojis)
--------------------------------------------------------------------------------
local victoryModal = Instance.new("Frame")
victoryModal.Name = "GrandFinaleVictoryModal"
victoryModal.Size = UDim2.fromOffset(460, 220)
victoryModal.Position = UDim2.fromScale(0.5, 0.5)
victoryModal.AnchorPoint = Vector2.new(0.5, 0.5)
victoryModal.BackgroundColor3 = Color3.fromRGB(16, 20, 34)
victoryModal.BorderSizePixel = 0
victoryModal.Visible = false
victoryModal.ZIndex = 40
victoryModal.Parent = screenGui
addCorner(victoryModal, 18)
addStroke(victoryModal, Color3.fromRGB(255, 215, 55), 3, 0)

local vicHeader = Instance.new("TextLabel")
vicHeader.Size = UDim2.new(1, -32, 0, 48)
vicHeader.Position = UDim2.fromOffset(16, 24)
vicHeader.BackgroundTransparency = 1
vicHeader.Font = Enum.Font.GothamBlack
vicHeader.Text = "VICTORY • +$50,000 JACKPOT"
vicHeader.TextColor3 = Color3.fromRGB(255, 220, 65)
vicHeader.TextSize = 24
vicHeader.TextScaled = true
vicHeader.ZIndex = 41
vicHeader.Parent = victoryModal

makeTactile3DButton({
	name = "ContinueOverdriveBtn",
	title = "PLAY",
	size = UDim2.fromOffset(260, 58),
	position = UDim2.new(0.5, -130, 1, -82),
	baseColor = Color3.fromRGB(35, 195, 95),
	textSize = 22,
	zIndex = 42,
	parent = victoryModal,
	onClick = function()
		victoryModal.Visible = false
	end,
})

--------------------------------------------------------------------------------
-- 4. ATTRIBUTE WATCHERS & KEYBOARD SHORTCUTS ([P] Settings, [Tab] Home Menu)
--------------------------------------------------------------------------------
local wasCompleted = localPlayer:GetAttribute("CampaignCompleted") == true

localPlayer.AttributeChanged:Connect(function(attr: string)
	if attr == "CampaignCompleted" then
		local nowCompleted = localPlayer:GetAttribute("CampaignCompleted") == true
		if nowCompleted and not wasCompleted then
			wasCompleted = true
			victoryModal.Visible = true
		end
	elseif attr == "ToggleSettingsUI" then
		settingsModal.Visible = not settingsModal.Visible
	elseif attr == "ToggleHomeMenuUI" then
		setHomeMenuOpen(not homeRoot.Visible)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		settingsModal.Visible = not settingsModal.Visible
	elseif input.KeyCode == Enum.KeyCode.Tab then
		setHomeMenuOpen(not homeRoot.Visible)
	elseif input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Backspace then
		if settingsModal.Visible then
			settingsModal.Visible = false
		end
	end
end)
