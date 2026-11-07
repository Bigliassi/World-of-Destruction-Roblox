--!strict
--[[
	HomeMenuAndSettingsUI.client.luau
	World of Destruction (Roblox)
	
	Simple, High-Impact, Emoji-Free Home Card & Settings UI:
	- Centered Home Card (540x430):
	  * Title: "WORLD OF DESTRUCTION"
	  * Subtitle: "NEW YORK DEMOLITION EDITION"
	  * Live Next-Goal Progress Bar: "NEXT RIDE UNLOCK: [Progress Bar] $Cash / $Price"
	  * 4 Big, Bold, 3D Tactile Beveled Buttons (zero emojis, zero subtext paragraphs):
	    1. PLAY NOW (Emerald green)
	    2. GARAGE & UPGRADES (Electric blue -> opens SpeedShopUI & closes Home Menu)
	    3. AVATAR SHOP (Royal purple -> opens CharacterCreatorAndWardrobeUI & closes Home Menu)
	    4. SETTINGS (Slate -> opens Settings modal with Weather selector, Volume, Driving Mode, Control Scheme)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- 3D Tactile Beveled UI Helpers (Zero Emojis)
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

local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

local function makeTactile3DButton(params: {
	name: string,
	title: string,
	badgeText: string?,
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

	if params.badgeText and #params.badgeText > 0 then
		local badge = Instance.new("Frame")
		badge.Name = "KeyBadge"
		badge.Size = UDim2.fromOffset(44, 30)
		badge.Position = UDim2.new(0, 12, 0.5, -15)
		badge.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
		badge.BackgroundTransparency = 0.18
		badge.BorderSizePixel = 0
		badge.ZIndex = zBase + 3
		badge.Parent = face
		addCorner(badge, 7)
		addStroke(badge, brightenColor(params.baseColor, 0.32), 1, 0.3)

		local badgeLbl = Instance.new("TextLabel")
		badgeLbl.Size = UDim2.fromScale(1, 1)
		badgeLbl.BackgroundTransparency = 1
		badgeLbl.Font = Enum.Font.GothamBlack
		badgeLbl.Text = params.badgeText
		badgeLbl.TextColor3 = Color3.fromRGB(255, 230, 110)
		badgeLbl.TextSize = 12
		badgeLbl.ZIndex = zBase + 4
		badgeLbl.Parent = badge
	end

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -24, 1, 0)
	titleLbl.Position = UDim2.fromOffset(12, 0)
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
-- Next Vehicle Unlock Calculator
--------------------------------------------------------------------------------
local NEXT_RIDE_LADDER = {
	{ id = "Sedan", name = "CRUISER V8", price = 1500 },
	{ id = "Muscle", name = "HELLFIRE GT", price = 4500 },
	{ id = "SUV", name = "TITAN 4X4", price = 9000 },
	{ id = "Pickup", name = "RANCH RAMMER", price = 15000 },
	{ id = "Sports", name = "APEX HYPER GT", price = 28000 },
	{ id = "MonsterTruck", name = "CRUSHER XL", price = 50000 },
	{ id = "Bulldozer", name = "GOLIATH DOZER", price = 95000 },
}

-- Sync prices with VehicleCatalog if present and lower/higher
task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 5)
	local vcMod = shared and shared:FindFirstChild("VehicleCatalog")
	if vcMod and vcMod:IsA("ModuleScript") then
		local ok, vc = pcall(require, vcMod)
		if ok and type(vc) == "table" and type(vc.Archetypes) == "table" then
			for _, entry in ipairs(NEXT_RIDE_LADDER) do
				local arch = vc.Archetypes[entry.id]
				if arch and type(arch.DisplayName) == "string" then
					entry.name = string.upper(arch.DisplayName)
				end
			end
		end
	end
end)

local function getPlayerCash(): number
	local attrCash = localPlayer:GetAttribute("Cash")
	if typeof(attrCash) == "number" then
		return attrCash
	end
	local ls = localPlayer:FindFirstChild("leaderstats")
	local cashObj = ls and ls:FindFirstChild("Cash")
	if cashObj and cashObj:IsA("ValueBase") then
		return tonumber(cashObj.Value) or 0
	end
	return 500
end

local function getNextLockedRide(): (string, number)
	local unlockedStr = tostring(localPlayer:GetAttribute("UnlockedVehicles") or "Compact")
	local selectedStr = tostring(localPlayer:GetAttribute("SelectedVehicle") or localPlayer:GetAttribute("EquippedVehicle") or "Compact")
	for _, item in ipairs(NEXT_RIDE_LADDER) do
		local isOwned = string.find(unlockedStr, item.id, 1, true) ~= nil or selectedStr == item.id
		if not isOwned then
			return item.name, item.price
		end
	end
	return "GOLIATH DOZER", 95000
end

--------------------------------------------------------------------------------
-- 1. CENTERED HIGH-IMPACT HOME CARD (540 x 430)
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
homeCard.Size = UDim2.fromOffset(540, 430)
homeCard.Position = UDim2.fromScale(0.5, 0.5)
homeCard.AnchorPoint = Vector2.new(0.5, 0.5)
homeCard.BackgroundColor3 = Color3.fromRGB(13, 18, 30)
homeCard.BackgroundTransparency = 0.06
homeCard.BorderSizePixel = 0
homeCard.Parent = homeRoot
addCorner(homeCard, 18)
addStroke(homeCard, Color3.fromRGB(255, 190, 50), 2.5, 0.12)

-- Header Section inside Home Card
local headerBox = Instance.new("Frame")
headerBox.Name = "HeaderBanner"
headerBox.Size = UDim2.new(1, -36, 0, 82)
headerBox.Position = UDim2.fromOffset(18, 16)
headerBox.BackgroundColor3 = Color3.fromRGB(20, 27, 44)
headerBox.BorderSizePixel = 0
headerBox.Parent = homeCard
addCorner(headerBox, 12)
addStroke(headerBox, Color3.fromRGB(255, 200, 65), 1.5, 0.28)

local heroTitle = Instance.new("TextLabel")
heroTitle.Name = "HeroTitle"
heroTitle.Size = UDim2.new(1, -24, 0, 44)
heroTitle.Position = UDim2.fromOffset(12, 8)
heroTitle.BackgroundTransparency = 1
heroTitle.Font = Enum.Font.GothamBlack
heroTitle.Text = "WORLD OF DESTRUCTION"
heroTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
heroTitle.TextSize = 32
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

local heroSubtitle = Instance.new("TextLabel")
heroSubtitle.Name = "HeroSubtitle"
heroSubtitle.Size = UDim2.new(1, -24, 0, 22)
heroSubtitle.Position = UDim2.fromOffset(12, 52)
heroSubtitle.BackgroundTransparency = 1
heroSubtitle.Font = Enum.Font.GothamBlack
heroSubtitle.Text = "NEW YORK DEMOLITION EDITION"
heroSubtitle.TextColor3 = Color3.fromRGB(115, 215, 255)
heroSubtitle.TextSize = 13
heroSubtitle.TextXAlignment = Enum.TextXAlignment.Center
heroSubtitle.Parent = headerBox

-- Live Next-Goal Progress Bar right on the Home Card
local nextGoalBox = Instance.new("Frame")
nextGoalBox.Name = "NextGoalProgressCard"
nextGoalBox.Size = UDim2.new(1, -36, 0, 48)
nextGoalBox.Position = UDim2.fromOffset(18, 108)
nextGoalBox.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
nextGoalBox.BorderSizePixel = 0
nextGoalBox.Parent = homeCard
addCorner(nextGoalBox, 10)
addStroke(nextGoalBox, Color3.fromRGB(70, 175, 255), 1.2, 0.3)

local nextGoalLabel = Instance.new("TextLabel")
nextGoalLabel.Name = "NextGoalLabel"
nextGoalLabel.Size = UDim2.new(1, -24, 0, 18)
nextGoalLabel.Position = UDim2.fromOffset(12, 5)
nextGoalLabel.BackgroundTransparency = 1
nextGoalLabel.Font = Enum.Font.GothamBlack
nextGoalLabel.Text = "NEXT RIDE UNLOCK: CRUISER V8  -  $500 / $1,500"
nextGoalLabel.TextColor3 = Color3.fromRGB(255, 220, 75)
nextGoalLabel.TextSize = 12
nextGoalLabel.TextXAlignment = Enum.TextXAlignment.Left
nextGoalLabel.Parent = nextGoalBox

local nextGoalBarBg = Instance.new("Frame")
nextGoalBarBg.Name = "ProgressBarBg"
nextGoalBarBg.Size = UDim2.new(1, -24, 0, 14)
nextGoalBarBg.Position = UDim2.fromOffset(12, 27)
nextGoalBarBg.BackgroundColor3 = Color3.fromRGB(10, 13, 22)
nextGoalBarBg.BorderSizePixel = 0
nextGoalBarBg.Parent = nextGoalBox
addCorner(nextGoalBarBg, 7)

local nextGoalBarFill = Instance.new("Frame")
nextGoalBarFill.Name = "ProgressBarFill"
nextGoalBarFill.Size = UDim2.fromScale(0.33, 1)
nextGoalBarFill.BackgroundColor3 = Color3.fromRGB(50, 225, 115)
nextGoalBarFill.BorderSizePixel = 0
nextGoalBarFill.Parent = nextGoalBarBg
addCorner(nextGoalBarFill, 7)

local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 215, 110)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 55)),
})
fillGrad.Parent = nextGoalBarFill

local nextGoalPctText = Instance.new("TextLabel")
nextGoalPctText.Size = UDim2.fromScale(1, 1)
nextGoalPctText.BackgroundTransparency = 1
nextGoalPctText.Font = Enum.Font.GothamBlack
nextGoalPctText.Text = "33%"
nextGoalPctText.TextColor3 = Color3.new(1, 1, 1)
nextGoalPctText.TextSize = 10
nextGoalPctText.TextStrokeTransparency = 0.3
nextGoalPctText.Parent = nextGoalBarBg

-- 4 Big, Bold, 3D Tactile Beveled Buttons Stack
local buttonsStack = Instance.new("Frame")
buttonsStack.Name = "MainButtonsStack"
buttonsStack.Size = UDim2.new(1, -36, 0, 246)
buttonsStack.Position = UDim2.fromOffset(18, 168)
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

-- 1. PLAY NOW (Large emerald green 3D button)
makeTactile3DButton({
	name = "PlayNowBtn",
	title = "PLAY NOW",
	badgeText = "GO",
	size = UDim2.new(1, 0, 0, 58),
	layoutOrder = 1,
	baseColor = Color3.fromRGB(28, 190, 92),
	textSize = 22,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
	end,
})

-- 2. GARAGE & UPGRADES (Electric blue 3D button)
makeTactile3DButton({
	name = "GarageAndUpgradesBtn",
	title = "GARAGE & UPGRADES",
	badgeText = "B",
	size = UDim2.new(1, 0, 0, 52),
	layoutOrder = 2,
	baseColor = Color3.fromRGB(36, 128, 240),
	textSize = 18,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
		localPlayer:SetAttribute("ToggleShopUI", not localPlayer:GetAttribute("ToggleShopUI"))
	end,
})

-- 3. AVATAR SHOP (Royal purple 3D button)
makeTactile3DButton({
	name = "AvatarShopBtn",
	title = "AVATAR SHOP",
	badgeText = "C",
	size = UDim2.new(1, 0, 0, 52),
	layoutOrder = 3,
	baseColor = Color3.fromRGB(128, 62, 225),
	textSize = 18,
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
		localPlayer:SetAttribute("ToggleAvatarUI", not localPlayer:GetAttribute("ToggleAvatarUI"))
	end,
})

-- 4. SETTINGS (Slate 3D button)
makeTactile3DButton({
	name = "SettingsBtn",
	title = "SETTINGS",
	badgeText = "P",
	size = UDim2.new(1, 0, 0, 52),
	layoutOrder = 4,
	baseColor = Color3.fromRGB(64, 78, 104),
	textSize = 18,
	parent = buttonsStack,
	onClick = function()
		settingsModal.Visible = true
	end,
})

local function refreshHomeCardProgress()
	local cash = getPlayerCash()
	local rideName, ridePrice = getNextLockedRide()
	local ratio = math.clamp(cash / math.max(1, ridePrice), 0, 1)
	local pct = math.floor(ratio * 100)
	nextGoalLabel.Text = string.format(
		"NEXT RIDE UNLOCK: %s  |  $%s / $%s",
		rideName,
		formatNumber(cash),
		formatNumber(ridePrice)
	)
	nextGoalBarFill.Size = UDim2.fromScale(ratio, 1)
	nextGoalPctText.Text = string.format("%d%%", pct)
end

--------------------------------------------------------------------------------
-- 2. CLEAN SETTINGS MODAL (WEATHER, VOLUME, DRIVING MODE, CONTROL SCHEME)
--------------------------------------------------------------------------------
settingsModal = Instance.new("Frame")
settingsModal.Name = "SettingsModal"
settingsModal.Size = UDim2.fromOffset(580, 420)
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
	title = "CLOSE [X]",
	size = UDim2.fromOffset(108, 38),
	position = UDim2.new(1, -124, 0, 14),
	baseColor = Color3.fromRGB(215, 55, 65),
	textSize = 14,
	zIndex = 32,
	parent = settingsModal,
	onClick = function()
		settingsModal.Visible = false
	end,
})

local rowsFrame = Instance.new("Frame")
rowsFrame.Size = UDim2.new(1, -40, 0, 270)
rowsFrame.Position = UDim2.fromOffset(20, 66)
rowsFrame.BackgroundTransparency = 1
rowsFrame.ZIndex = 31
rowsFrame.Parent = settingsModal

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.FillDirection = Enum.FillDirection.Vertical
rowsLayout.Padding = UDim.new(0, 10)
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = rowsFrame

local function makeSettingRow(order: number, labelText: string, initialValueText: string, btnColor: Color3, onCycle: (TextLabel) -> ())
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(22, 28, 44)
	row.BorderSizePixel = 0
	row.ZIndex = 31
	row.Parent = rowsFrame
	addCorner(row, 10)
	addStroke(row, Color3.fromRGB(65, 85, 125), 1.2, 0.3)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.46, -16, 1, 0)
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = labelText
	lbl.TextColor3 = Color3.fromRGB(235, 242, 255)
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 32
	lbl.Parent = row

	local btnFrame, btnLbl = makeTactile3DButton({
		name = "ToggleBtn_" .. tostring(order),
		title = initialValueText,
		size = UDim2.fromOffset(270, 42),
		position = UDim2.new(1, -282, 0.5, -21),
		baseColor = btnColor,
		textSize = 14,
		zIndex = 32,
		parent = row,
		onClick = function() end,
	})
	local face = btnFrame:FindFirstChild("ButtonFace") :: TextButton?
	if face then
		face.MouseButton1Click:Connect(function()
			onCycle(btnLbl)
		end)
	end
end

-- 1. Weather Selector: Snowy NYC, Rainy NYC, Cloudy Dusk, Sunny Day
local weatherPresets = {
	{ name = "SNOWY NYC", attr = "Snowy NYC", mode = "Snowy", clock = 16.4, bright = 1.85, fogEnd = 900 },
	{ name = "RAINY NYC", attr = "Rainy NYC", mode = "Rainy", clock = 16.4, bright = 1.85, fogEnd = 750 },
	{ name = "CLOUDY DUSK", attr = "Cloudy Dusk", mode = "Sunset", clock = 16.4, bright = 1.85, fogEnd = 1100 },
	{ name = "SUNNY DAY", attr = "Sunny Day", mode = "Sunny", clock = 13.5, bright = 3.2, fogEnd = 2200 },
}
local weatherIdx = 1
makeSettingRow(1, "NYC WEATHER & SKY", weatherPresets[1].name, Color3.fromRGB(220, 138, 35), function(lbl)
	weatherIdx = (weatherIdx % #weatherPresets) + 1
	local wp = weatherPresets[weatherIdx]
	localPlayer:SetAttribute("WeatherPreference", wp.attr)
	localPlayer:SetAttribute("WeatherMode", wp.mode)
	localPlayer:SetAttribute("TimeOfDayPreference", wp.mode)
	Lighting.ClockTime = wp.clock
	Lighting.Brightness = wp.bright
	Lighting.FogEnd = wp.fogEnd
	lbl.Text = wp.name
end)

-- 2. Audio Volume
local sfxPresets = {
	{ label = "100% (FULL)", val = 1.0 },
	{ label = "60% (MEDIUM)", val = 0.6 },
	{ label = "25% (LOW)", val = 0.25 },
	{ label = "MUTE (0%)", val = 0.0 },
}
local sfxIndex = 1
makeSettingRow(2, "AUDIO VOLUME", sfxPresets[1].label, Color3.fromRGB(42, 138, 225), function(lbl)
	sfxIndex = (sfxIndex % #sfxPresets) + 1
	local p = sfxPresets[sfxIndex]
	localPlayer:SetAttribute("SFXVolume", p.val)
	lbl.Text = p.label
end)

-- 3. Driving Mode
makeSettingRow(3, "DRIVING MODE", "PROGRESSIVE REALISTIC", Color3.fromRGB(38, 175, 95), function(lbl)
	local cur = tostring(localPlayer:GetAttribute("DrivingMode") or "Progressive")
	local nextMode = if cur == "Progressive" then "Arcade" else "Progressive"
	localPlayer:SetAttribute("DrivingMode", nextMode)
	lbl.Text = if nextMode == "Progressive" then "PROGRESSIVE REALISTIC" else "ARCADE BOOST (+18%)"
end)

-- 4. Control Scheme
local controlSchemes = {
	{ label = "STANDARD (WASD)", val = "Standard" },
	{ label = "ARROW KEYS / ALT", val = "Arrows" },
	{ label = "GAMEPAD PRO", val = "Gamepad" },
}
local schemeIdx = 1
makeSettingRow(4, "CONTROL SCHEME", controlSchemes[1].label, Color3.fromRGB(125, 78, 220), function(lbl)
	schemeIdx = (schemeIdx % #controlSchemes) + 1
	local cs = controlSchemes[schemeIdx]
	localPlayer:SetAttribute("ControlScheme", cs.val)
	lbl.Text = cs.label
end)

-- Bottom button in Settings Modal to toggle Home Card
makeTactile3DButton({
	name = "ReturnToHomeMenuBtn",
	title = "TOGGLE HOME MENU [TAB]",
	size = UDim2.new(1, -40, 0, 46),
	position = UDim2.new(0, 20, 1, -60),
	baseColor = Color3.fromRGB(48, 118, 215),
	textSize = 15,
	zIndex = 32,
	parent = settingsModal,
	onClick = function()
		settingsModal.Visible = false
		setHomeMenuOpen(not homeRoot.Visible)
	end,
})

--------------------------------------------------------------------------------
-- 3. GRAND FINALE VICTORY CELEBRATION MODAL (Emoji-Free)
--------------------------------------------------------------------------------
local victoryModal = Instance.new("Frame")
victoryModal.Name = "GrandFinaleVictoryModal"
victoryModal.Size = UDim2.fromOffset(580, 320)
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
vicHeader.Size = UDim2.new(1, -32, 0, 44)
vicHeader.Position = UDim2.fromOffset(16, 20)
vicHeader.BackgroundTransparency = 1
vicHeader.Font = Enum.Font.GothamBlack
vicHeader.Text = "NEW YORK LIBERATED - CAMPAIGN COMPLETE"
vicHeader.TextColor3 = Color3.fromRGB(255, 220, 65)
vicHeader.TextSize = 22
vicHeader.TextScaled = true
vicHeader.ZIndex = 41
vicHeader.Parent = victoryModal

local vicBody = Instance.new("TextLabel")
vicBody.Size = UDim2.new(1, -48, 0, 120)
vicBody.Position = UDim2.fromOffset(24, 76)
vicBody.BackgroundTransparency = 1
vicBody.Font = Enum.Font.GothamBold
vicBody.Text = "You shattered MegaCorp's lockdown and wrecked the Armored Boss Goliath Convoy!\n\nREWARDS UNLOCKED:\n- +$50,000 GRAND FINALE JACKPOT\n- +5,000 XP & CHAMPION STATUS\n- ENDLESS OVERDRIVE MODE UNLOCKED"
vicBody.TextColor3 = Color3.fromRGB(235, 245, 255)
vicBody.TextSize = 15
vicBody.TextWrapped = true
vicBody.ZIndex = 41
vicBody.Parent = victoryModal

makeTactile3DButton({
	name = "ContinueOverdriveBtn",
	title = "CONTINUE OVERDRIVE",
	size = UDim2.fromOffset(360, 58),
	position = UDim2.new(0.5, -180, 1, -78),
	baseColor = Color3.fromRGB(35, 195, 95),
	textSize = 18,
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
	if attr == "Cash" or attr == "UnlockedVehicles" or attr == "SelectedVehicle" or attr == "EquippedVehicle" then
		refreshHomeCardProgress()
	elseif attr == "CampaignCompleted" then
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

refreshHomeCardProgress()
