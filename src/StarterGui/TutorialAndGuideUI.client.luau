--!strict
--[[
	TutorialAndGuideUI.client.luau
	World of Destruction (Roblox) — Version 1.0
	
	Interactive Onboarding Tutorial + How to Play / 50-Level Progression / VIP Store Modal:
	- Step-by-Step Interactive Onboarding Tutorial on first join:
	  * Step 1: Enter or Summon [V] your vehicle
	  * Step 2: Smash 5 objects to start a Chaos Combo
	  * Step 3: Trigger Nitro [LeftShift] & Drift [Space]
	  * Step 4: Visit or open the Speed Shop [B] to upgrade your ride
	  * Step 5: Survive or evade Police Heat!
	- Renders a glowing 3D Waypoint Beam & Floating Target Arrow from the player to
	  their nearest vehicle, destructible cluster, or Speed Shop showroom during onboarding.
	- Provides an interactive [H] How to Play / 50-Level Ranks / [M] VIP Store modal
	  accessible anytime from the top-right utility bar or the H and M keys, including
	  instant Studio Sandbox GamePass & DevProduct test-grant buttons!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Remote Discovery Helpers
--------------------------------------------------------------------------------
local function getRemotesFolder(): Folder?
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		return existing
	end
	return nil
end

local function findRemoteEvent(name: string): RemoteEvent?
	local folder = getRemotesFolder()
	if folder then
		local r = folder:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			return r
		end
	end
	local rootR = ReplicatedStorage:FindFirstChild(name)
	if rootR and rootR:IsA("RemoteEvent") then
		return rootR
	end
	return nil
end

local function findRemoteFunction(name: string): RemoteFunction?
	local folder = getRemotesFolder()
	if folder then
		local rf = folder:FindFirstChild(name)
		if rf and rf:IsA("RemoteFunction") then
			return rf
		end
	end
	local rootRf = ReplicatedStorage:FindFirstChild(name)
	if rootRf and rootRf:IsA("RemoteFunction") then
		return rootRf
	end
	return nil
end

--------------------------------------------------------------------------------
-- Tutorial Steps Specification
--------------------------------------------------------------------------------
type TutorialStepSpec = {
	StepNumber: number,
	Title: string,
	Instruction: string,
	KeyHint: string,
	AccentColor: Color3,
	TargetKind: "Vehicle" | "Destructibles" | "Stunt" | "SpeedShop" | "Heat",
}

local TUTORIAL_STEPS: { TutorialStepSpec } = {
	{
		StepNumber = 1,
		Title = "STEP 1/5 • ENTER OR SUMMON YOUR RIDE",
		Instruction = "Walk up to any car or press [V] to summon your personal vehicle right in front of you!",
		KeyHint = "Press [V] to Summon Vehicle",
		AccentColor = Color3.fromRGB(0, 225, 255),
		TargetKind = "Vehicle",
	},
	{
		StepNumber = 2,
		Title = "STEP 2/5 • SMASH 5 OBJECTS & START A COMBO",
		Instruction = "Plow through cones, crates, hydrants, fences, or parked cars to build your Chaos Combo!",
		KeyHint = "Drive with [WASD] into breakable props",
		AccentColor = Color3.fromRGB(255, 185, 35),
		TargetKind = "Destructibles",
	},
	{
		StepNumber = 3,
		Title = "STEP 3/5 • TRIGGER NITRO [SHIFT] & DRIFT [SPACE]",
		Instruction = "Hold [LeftShift] for a blazing Nitro burst or tap [Space] while turning to Drift around corners!",
		KeyHint = "Hold [LeftShift] Nitro or [Space] Drift",
		AccentColor = Color3.fromRGB(55, 245, 155),
		TargetKind = "Stunt",
	},
	{
		StepNumber = 4,
		Title = "STEP 4/5 • VISIT THE SPEED SHOP [B]",
		Instruction = "Drive onto the glowing cyan Speed Shop pad or press [B] to upgrade Engine, Armor, Nitro, Plow & Magnet!",
		KeyHint = "Press [B] or follow the Cyan Beam to Speed Shop",
		AccentColor = Color3.fromRGB(185, 95, 255),
		TargetKind = "SpeedShop",
	},
	{
		StepNumber = 5,
		Title = "STEP 5/5 • SURVIVE OR EVADE POLICE HEAT!",
		Instruction = "Higher Wanted Stars multiply your Cash up to 3.0x! Wreck pursuing cruisers or outrun them to bank your haul!",
		KeyHint = "Cause Chaos to raise Heat or press [Complete]",
		AccentColor = Color3.fromRGB(255, 80, 95),
		TargetKind = "Heat",
	},
}

--------------------------------------------------------------------------------
-- 3D Waypoint Beam & Floating Target Marker
--------------------------------------------------------------------------------
local waypointFolder: Folder? = nil
local waypointStartPart: Part? = nil
local waypointEndPart: Part? = nil
local waypointBeam: Beam? = nil
local waypointBillboardTitle: TextLabel? = nil
local waypointBillboardDist: TextLabel? = nil

local function ensure3DWaypoint()
	if waypointFolder and waypointFolder.Parent then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "OnboardingWaypoint3D"
	folder.Parent = Workspace

	local startPart = Instance.new("Part")
	startPart.Name = "WaypointPlayerAnchor"
	startPart.Size = Vector3.new(0.5, 0.5, 0.5)
	startPart.Transparency = 1
	startPart.Anchored = true
	startPart.CanCollide = false
	startPart.CanQuery = false
	startPart.CanTouch = false
	startPart.Parent = folder

	local startAtt = Instance.new("Attachment")
	startAtt.Name = "StartAttachment"
	startAtt.Parent = startPart

	local endPart = Instance.new("Part")
	endPart.Name = "WaypointTargetMarker"
	endPart.Shape = Enum.PartType.Cylinder
	endPart.Material = Enum.Material.Neon
	endPart.Color = Color3.fromRGB(0, 225, 255)
	endPart.Size = Vector3.new(0.4, 8, 8)
	endPart.Transparency = 0.25
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Parent = folder

	local endAtt = Instance.new("Attachment")
	endAtt.Name = "EndAttachment"
	endAtt.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Name = "GuidanceBeam"
	beam.Attachment0 = startAtt
	beam.Attachment1 = endAtt
	beam.Width0 = 1.6
	beam.Width1 = 2.4
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 24
	beam.Color = ColorSequence.new(Color3.fromRGB(0, 225, 255), Color3.fromRGB(255, 215, 55))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	beam.Parent = folder

	local bb = Instance.new("BillboardGui")
	bb.Name = "TargetFloatingBadge"
	bb.Size = UDim2.fromOffset(180, 48)
	bb.StudsOffset = Vector3.new(0, 6.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 800
	bb.Parent = endPart

	local badgeFrame = Instance.new("Frame")
	badgeFrame.Size = UDim2.fromScale(1, 1)
	badgeFrame.BackgroundColor3 = Color3.fromRGB(12, 17, 28)
	badgeFrame.BackgroundTransparency = 0.12
	badgeFrame.BorderSizePixel = 0
	badgeFrame.Parent = bb

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 8)
	badgeCorner.Parent = badgeFrame

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.fromRGB(0, 225, 255)
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badgeFrame

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -10, 0, 22)
	titleLbl.Position = UDim2.fromOffset(5, 4)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.Text = "▼ TARGET"
	titleLbl.TextColor3 = Color3.fromRGB(0, 235, 255)
	titleLbl.TextSize = 13
	titleLbl.Parent = badgeFrame

	local distLbl = Instance.new("TextLabel")
	distLbl.Size = UDim2.new(1, -10, 0, 18)
	distLbl.Position = UDim2.fromOffset(5, 25)
	distLbl.BackgroundTransparency = 1
	distLbl.Font = Enum.Font.GothamBold
	distLbl.Text = "0m"
	distLbl.TextColor3 = Color3.fromRGB(230, 238, 250)
	distLbl.TextSize = 12
	distLbl.Parent = badgeFrame

	waypointFolder = folder
	waypointStartPart = startPart
	waypointEndPart = endPart
	waypointBeam = beam
	waypointBillboardTitle = titleLbl
	waypointBillboardDist = distLbl
end

local function setWaypointVisible(visible: boolean)
	if not waypointFolder then
		return
	end
	if waypointBeam then
		waypointBeam.Enabled = visible
	end
	if waypointEndPart then
		waypointEndPart.Transparency = if visible then 0.25 else 1
		local bb = waypointEndPart:FindFirstChild("TargetFloatingBadge") :: BillboardGui?
		if bb then
			bb.Enabled = visible
		end
	end
end

local function findNearestVehiclePosition(origin: Vector3): Vector3
	local bestPos: Vector3? = nil
	local bestDist = math.huge

	for _, folderName in ipairs({ "PlayerVehicles", "Vehicles", "LeoCity" }) do
		local container = Workspace:FindFirstChild(folderName)
		if container then
			for _, desc in ipairs(container:GetDescendants()) do
				if desc:IsA("VehicleSeat") then
					local d = (desc.Position - origin).Magnitude
					if d < bestDist then
						bestDist = d
						bestPos = desc.Position
					end
				end
			end
		end
	end

	return bestPos or (origin + Vector3.new(0, 0, -18))
end

local function findNearestSpeedShopPosition(origin: Vector3): Vector3
	local shops = {
		Vector3.new(48, 1, -24),
		Vector3.new(180, 1, 0),
		Vector3.new(360, 1, 360),
	}
	local best = shops[1]
	local bestDist = (best - origin).Magnitude
	for _, s in ipairs(shops) do
		local d = (s - origin).Magnitude
		if d < bestDist then
			bestDist = d
			best = s
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- UI Construction: Onboarding Banner + Top Buttons + Modal Window
--------------------------------------------------------------------------------
local existingGui = playerGui:FindFirstChild("TutorialAndGuideGui")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialAndGuideGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 18
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

-- 1. Top-Right Quick Access Bar ([H] Guide & Ranks | [M] VIP Store | Level Pill)
local topAccessBar = Instance.new("Frame")
topAccessBar.Name = "TopAccessBar"
topAccessBar.AnchorPoint = Vector2.new(1, 0)
topAccessBar.Position = UDim2.new(1, -16, 0, 12)
topAccessBar.Size = UDim2.fromOffset(390, 38)
topAccessBar.BackgroundTransparency = 1
topAccessBar.Parent = screenGui

local topLayout = Instance.new("UIListLayout")
topLayout.FillDirection = Enum.FillDirection.Horizontal
topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topLayout.Padding = UDim.new(0, 8)
topLayout.Parent = topAccessBar

-- Level & XP Pill Badge
local levelPill = Instance.new("Frame")
levelPill.Name = "LevelBadgePill"
levelPill.Size = UDim2.fromOffset(148, 36)
levelPill.BackgroundColor3 = Color3.fromRGB(15, 20, 32)
levelPill.BackgroundTransparency = 0.12
levelPill.BorderSizePixel = 0
levelPill.LayoutOrder = 1
levelPill.Parent = topAccessBar
addCorner(levelPill, 8)
addStroke(levelPill, Color3.fromRGB(255, 200, 50), 1.5)

local levelTitleText = Instance.new("TextLabel")
levelTitleText.Name = "LevelTitle"
levelTitleText.Size = UDim2.new(1, -12, 0, 18)
levelTitleText.Position = UDim2.fromOffset(6, 3)
levelTitleText.BackgroundTransparency = 1
levelTitleText.Font = Enum.Font.GothamBlack
levelTitleText.Text = "LV.1 • STREET ROOKIE"
levelTitleText.TextColor3 = Color3.fromRGB(255, 215, 65)
levelTitleText.TextSize = 11
levelTitleText.TextXAlignment = Enum.TextXAlignment.Left
levelTitleText.TextTruncate = Enum.TextTruncate.AtEnd
levelTitleText.Parent = levelPill

local xpBarBg = Instance.new("Frame")
xpBarBg.Name = "XPBarBg"
xpBarBg.Size = UDim2.new(1, -12, 0, 7)
xpBarBg.Position = UDim2.fromOffset(6, 23)
xpBarBg.BackgroundColor3 = Color3.fromRGB(32, 40, 58)
xpBarBg.BorderSizePixel = 0
xpBarBg.Parent = levelPill
addCorner(xpBarBg, 4)

local xpBarFill = Instance.new("Frame")
xpBarFill.Name = "XPBarFill"
xpBarFill.Size = UDim2.fromScale(0.15, 1)
xpBarFill.BackgroundColor3 = Color3.fromRGB(0, 225, 255)
xpBarFill.BorderSizePixel = 0
xpBarFill.Parent = xpBarBg
addCorner(xpBarFill, 4)

local guideToggleBtn = Instance.new("TextButton")
guideToggleBtn.Name = "GuideButton"
guideToggleBtn.Size = UDim2.fromOffset(112, 36)
guideToggleBtn.BackgroundColor3 = Color3.fromRGB(16, 24, 38)
guideToggleBtn.BackgroundTransparency = 0.1
guideToggleBtn.Font = Enum.Font.GothamBold
guideToggleBtn.Text = "[H] GUIDE & RANKS"
guideToggleBtn.TextColor3 = Color3.fromRGB(0, 225, 255)
guideToggleBtn.TextSize = 11
guideToggleBtn.LayoutOrder = 2
guideToggleBtn.Parent = topAccessBar
addCorner(guideToggleBtn, 8)
addStroke(guideToggleBtn, Color3.fromRGB(0, 210, 255), 1.5)

local storeToggleBtn = Instance.new("TextButton")
storeToggleBtn.Name = "VIPStoreButton"
storeToggleBtn.Size = UDim2.fromOffset(112, 36)
storeToggleBtn.BackgroundColor3 = Color3.fromRGB(32, 22, 42)
storeToggleBtn.BackgroundTransparency = 0.1
storeToggleBtn.Font = Enum.Font.GothamBlack
storeToggleBtn.Text = "[M] VIP STORE"
storeToggleBtn.TextColor3 = Color3.fromRGB(255, 210, 55)
storeToggleBtn.TextSize = 11
storeToggleBtn.LayoutOrder = 3
storeToggleBtn.Parent = topAccessBar
addCorner(storeToggleBtn, 8)
addStroke(storeToggleBtn, Color3.fromRGB(255, 195, 45), 1.5)

--------------------------------------------------------------------------------
-- 2. Interactive Onboarding Tutorial Tracker Card (Top-Left / Below Mini-Stats)
--------------------------------------------------------------------------------
local tutorialCard = Instance.new("Frame")
tutorialCard.Name = "OnboardingTutorialCard"
tutorialCard.Position = UDim2.fromOffset(16, 130)
tutorialCard.Size = UDim2.fromOffset(335, 128)
tutorialCard.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
tutorialCard.BackgroundTransparency = 0.12
tutorialCard.BorderSizePixel = 0
tutorialCard.Parent = screenGui
addCorner(tutorialCard, 12)
local tutorialCardStroke = addStroke(tutorialCard, Color3.fromRGB(0, 225, 255), 2)

local tutHeader = Instance.new("TextLabel")
tutHeader.Name = "StepHeader"
tutHeader.Size = UDim2.new(1, -24, 0, 22)
tutHeader.Position = UDim2.fromOffset(12, 8)
tutHeader.BackgroundTransparency = 1
tutHeader.Font = Enum.Font.GothamBlack
tutHeader.Text = TUTORIAL_STEPS[1].Title
tutHeader.TextColor3 = Color3.fromRGB(0, 225, 255)
tutHeader.TextSize = 13
tutHeader.TextXAlignment = Enum.TextXAlignment.Left
tutHeader.Parent = tutorialCard

local tutBody = Instance.new("TextLabel")
tutBody.Name = "StepBody"
tutBody.Size = UDim2.new(1, -24, 0, 42)
tutBody.Position = UDim2.fromOffset(12, 30)
tutBody.BackgroundTransparency = 1
tutBody.Font = Enum.Font.GothamMedium
tutBody.Text = TUTORIAL_STEPS[1].Instruction
tutBody.TextColor3 = Color3.fromRGB(230, 236, 248)
tutBody.TextSize = 12
tutBody.TextWrapped = true
tutBody.TextXAlignment = Enum.TextXAlignment.Left
tutBody.TextYAlignment = Enum.TextYAlignment.Top
tutBody.Parent = tutorialCard

local tutProgressBg = Instance.new("Frame")
tutProgressBg.Name = "StepProgressBg"
tutProgressBg.Size = UDim2.new(1, -24, 0, 8)
tutProgressBg.Position = UDim2.fromOffset(12, 76)
tutProgressBg.BackgroundColor3 = Color3.fromRGB(28, 36, 52)
tutProgressBg.BorderSizePixel = 0
tutProgressBg.Parent = tutorialCard
addCorner(tutProgressBg, 4)

local tutProgressFill = Instance.new("Frame")
tutProgressFill.Name = "StepProgressFill"
tutProgressFill.Size = UDim2.fromScale(0.2, 1)
tutProgressFill.BackgroundColor3 = Color3.fromRGB(0, 225, 255)
tutProgressFill.BorderSizePixel = 0
tutProgressFill.Parent = tutProgressBg
addCorner(tutProgressFill, 4)

local tutHintLabel = Instance.new("TextLabel")
tutHintLabel.Name = "KeyHint"
tutHintLabel.Size = UDim2.new(1, -135, 0, 26)
tutHintLabel.Position = UDim2.fromOffset(12, 92)
tutHintLabel.BackgroundTransparency = 1
tutHintLabel.Font = Enum.Font.GothamBold
tutHintLabel.Text = TUTORIAL_STEPS[1].KeyHint
tutHintLabel.TextColor3 = Color3.fromRGB(165, 210, 255)
tutHintLabel.TextSize = 11
tutHintLabel.TextXAlignment = Enum.TextXAlignment.Left
tutHintLabel.Parent = tutorialCard

local tutNextBtn = Instance.new("TextButton")
tutNextBtn.Name = "NextStepBtn"
tutNextBtn.Size = UDim2.fromOffset(58, 24)
tutNextBtn.Position = UDim2.new(1, -124, 0, 93)
tutNextBtn.BackgroundColor3 = Color3.fromRGB(25, 110, 175)
tutNextBtn.Font = Enum.Font.GothamBold
tutNextBtn.Text = "Next ▸"
tutNextBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tutNextBtn.TextSize = 11
tutNextBtn.Parent = tutorialCard
addCorner(tutNextBtn, 6)

local tutSkipBtn = Instance.new("TextButton")
tutSkipBtn.Name = "SkipTutorialBtn"
tutSkipBtn.Size = UDim2.fromOffset(52, 24)
tutSkipBtn.Position = UDim2.new(1, -62, 0, 93)
tutSkipBtn.BackgroundColor3 = Color3.fromRGB(38, 46, 64)
tutSkipBtn.Font = Enum.Font.GothamBold
tutSkipBtn.Text = "Hide"
tutSkipBtn.TextColor3 = Color3.fromRGB(185, 195, 215)
tutSkipBtn.TextSize = 11
tutSkipBtn.Parent = tutorialCard
addCorner(tutSkipBtn, 6)

--------------------------------------------------------------------------------
-- 3. Center Modal Window: [H] How to Play / 50-Level Ranks / [M] VIP Store
--------------------------------------------------------------------------------
local modalBackdrop = Instance.new("Frame")
modalBackdrop.Name = "ModalBackdrop"
modalBackdrop.Size = UDim2.fromScale(1, 1)
modalBackdrop.BackgroundColor3 = Color3.fromRGB(4, 7, 14)
modalBackdrop.BackgroundTransparency = 0.35
modalBackdrop.Visible = false
modalBackdrop.Parent = screenGui

local modalWindow = Instance.new("Frame")
modalWindow.Name = "GuideAndStoreModal"
modalWindow.AnchorPoint = Vector2.new(0.5, 0.5)
modalWindow.Position = UDim2.fromScale(0.5, 0.5)
modalWindow.Size = UDim2.fromOffset(740, 470)
modalWindow.BackgroundColor3 = Color3.fromRGB(13, 18, 30)
modalWindow.BorderSizePixel = 0
modalWindow.Parent = modalBackdrop
addCorner(modalWindow, 14)
addStroke(modalWindow, Color3.fromRGB(0, 215, 255), 2)

-- Header Bar
local modalHeader = Instance.new("Frame")
modalHeader.Name = "Header"
modalHeader.Size = UDim2.new(1, 0, 0, 52)
modalHeader.BackgroundColor3 = Color3.fromRGB(18, 25, 42)
modalHeader.BorderSizePixel = 0
modalHeader.Parent = modalWindow
addCorner(modalHeader, 14)

local modalTitle = Instance.new("TextLabel")
modalTitle.Name = "Title"
modalTitle.Size = UDim2.new(1, -120, 1, 0)
modalTitle.Position = UDim2.fromOffset(18, 0)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBlack
modalTitle.Text = "WORLD OF DESTRUCTION v1.0 • HANDBOOK & VIP STORE"
modalTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
modalTitle.TextSize = 16
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.Parent = modalHeader

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -14, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(82, 32)
closeBtn.BackgroundColor3 = Color3.fromRGB(210, 55, 70)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.Text = "CLOSE [X]"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 12
closeBtn.Parent = modalHeader
addCorner(closeBtn, 8)

-- Tab Bar (How to Play | 50-Level Ranks | VIP Store & Sandbox)
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -36, 0, 38)
tabBar.Position = UDim2.fromOffset(18, 60)
tabBar.BackgroundTransparency = 1
tabBar.Parent = modalWindow

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.Parent = tabBar

local function createTabButton(name: string, label: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(228, 36)
	btn.BackgroundColor3 = Color3.fromRGB(24, 32, 52)
	btn.Font = Enum.Font.GothamBlack
	btn.Text = label
	btn.TextColor3 = Color3.fromRGB(210, 220, 240)
	btn.TextSize = 13
	btn.LayoutOrder = order
	btn.Parent = tabBar
	addCorner(btn, 8)
	addStroke(btn, Color3.fromRGB(55, 75, 110), 1.5)
	return btn
end

local tabControlsBtn = createTabButton("TabControls", "1. HOW TO PLAY & CONTROLS", 1)
local tabLevelsBtn = createTabButton("TabLevels", "2. 50-LEVEL RANKS & REWARDS", 2)
local tabStoreBtn = createTabButton("TabStore", "3. VIP STORE [SANDBOX READY]", 3)

-- Tab Content Pages
local contentContainer = Instance.new("Frame")
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, -36, 1, -114)
contentContainer.Position = UDim2.fromOffset(18, 104)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = modalWindow

local controlsPage = Instance.new("ScrollingFrame")
controlsPage.Name = "ControlsPage"
controlsPage.Size = UDim2.fromScale(1, 1)
controlsPage.CanvasSize = UDim2.fromOffset(0, 520)
controlsPage.ScrollBarThickness = 6
controlsPage.BackgroundTransparency = 1
controlsPage.BorderSizePixel = 0
controlsPage.Parent = contentContainer

local levelsPage = Instance.new("ScrollingFrame")
levelsPage.Name = "LevelsPage"
levelsPage.Size = UDim2.fromScale(1, 1)
levelsPage.CanvasSize = UDim2.fromOffset(0, 620)
levelsPage.ScrollBarThickness = 6
levelsPage.BackgroundTransparency = 1
levelsPage.BorderSizePixel = 0
levelsPage.Visible = false
levelsPage.Parent = contentContainer

local storePage = Instance.new("ScrollingFrame")
storePage.Name = "StorePage"
storePage.Size = UDim2.fromScale(1, 1)
storePage.CanvasSize = UDim2.fromOffset(0, 760)
storePage.ScrollBarThickness = 6
storePage.BackgroundTransparency = 1
storePage.BorderSizePixel = 0
storePage.Visible = false
storePage.Parent = contentContainer

--------------------------------------------------------------------------------
-- Populate Page 1: How to Play & Controls
--------------------------------------------------------------------------------
local controlsList = Instance.new("UIListLayout")
controlsList.Padding = UDim.new(0, 10)
controlsList.Parent = controlsPage

local GUIDE_SECTIONS = {
	{
		Header = "DRIVING, NITRO & STUNT CONTROLS",
		Color = Color3.fromRGB(0, 225, 255),
		Lines = "• [W / A / S / D] or Arrow Keys — Drive, Steer, Brake & Reverse\n"
			.. "• [V] — Summon your equipped Vehicle directly in front of you anytime\n"
			.. "• [F] or Walk into Seat — Enter / Exit Vehicle\n"
			.. "• [LeftShift] — Trigger Blazing Nitro Boost (regenerates automatically)\n"
			.. "• [Space] — Handbrake Drift around corners for DRIFT KING combos\n"
			.. "• [C] — Cycle Camera View | [R] — Flip / Unstuck Vehicle",
	},
	{
		Header = "CHAOS COMBO MULTIPLIER & OVERDRIVE (UP TO 10X)",
		Color = Color3.fromRGB(255, 195, 45),
		Lines = "• Every prop, fence, hydrant, barrel, or car you smash refreshes your 4.5s Combo Timer.\n"
			.. "• Chain hits, airtime jumps, and drifts to climb: 1x ➔ 2x ➔ 3x ➔ 5x ➔ 8x ➔ 10x OVERDRIVE!\n"
			.. "• When your combo timer finishes cleanly, you bank a +25% Combo Completion Cash Bonus!",
	},
	{
		Header = "SPEED SHOP [B], GARAGE UPGRADES & MECHANIC BAYS",
		Color = Color3.fromRGB(185, 95, 255),
		Lines = "• Press [B] or drive onto the glowing Cyan Speed Shop pads in Leo City.\n"
			.. "• Upgrade 5 core tracks (Engine, Armor, Nitro, Wrecking Plow, Cash Magnet) up to Level 5.\n"
			.. "• Unlock 8 unique vehicles from the Street Bolt Motorcycle up to the Goliath Rig!\n"
			.. "• Drive through green Mechanic Repair Bays for an instant 100% repair.",
	},
	{
		Header = "POLICE HEAT (1 TO 5 STARS) & RISK-REWARD BOUNTY",
		Color = Color3.fromRGB(255, 80, 95),
		Lines = "• Smashing Leo City raises your Wanted Heat from 1★ Patrols to 5★ Apex Enforcers.\n"
			.. "• Higher Heat multiplies ALL Cash earned up to 3.0x — ram cruisers at high speed for COP TAKEDOWN bonuses!",
	},
}

for _, sec in ipairs(GUIDE_SECTIONS) do
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -12, 0, 112)
	card.BackgroundColor3 = Color3.fromRGB(20, 27, 44)
	card.BorderSizePixel = 0
	card.Parent = controlsPage
	addCorner(card, 10)
	addStroke(card, sec.Color, 1.5)

	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, -20, 0, 24)
	h.Position = UDim2.fromOffset(12, 8)
	h.BackgroundTransparency = 1
	h.Font = Enum.Font.GothamBlack
	h.Text = sec.Header
	h.TextColor3 = sec.Color
	h.TextSize = 14
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.Parent = card

	local b = Instance.new("TextLabel")
	b.Size = UDim2.new(1, -20, 0, 74)
	b.Position = UDim2.fromOffset(12, 32)
	b.BackgroundTransparency = 1
	b.Font = Enum.Font.GothamMedium
	b.Text = sec.Lines
	b.TextColor3 = Color3.fromRGB(228, 235, 248)
	b.TextSize = 12
	b.TextWrapped = true
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.Parent = card
end

--------------------------------------------------------------------------------
-- Populate Page 2: 50-Level Ranks & Milestone Rewards
--------------------------------------------------------------------------------
local levelsList = Instance.new("UIListLayout")
levelsList.Padding = UDim.new(0, 8)
levelsList.Parent = levelsPage

local FALLBACK_RANKS = {
	{ MinLevel = 1, Title = "Street Rookie", CashBonus = 250, Note = "Starter Rank — Welcome to Leo City!" },
	{ MinLevel = 5, Title = "Curb Crusher", CashBonus = 1250, Note = "Milestone Bonus: +$1,250 Cash!" },
	{ MinLevel = 10, Title = "Asphalt Outlaw", CashBonus = 2500, Note = "Milestone Bonus: +$2,500 Cash!" },
	{ MinLevel = 15, Title = "Neon Menace", CashBonus = 3500, Note = "Milestone Bonus: +$3,500 Cash!" },
	{ MinLevel = 20, Title = "Demolition Expert", CashBonus = 5000, Note = "Milestone Bonus: +$5,000 Cash!" },
	{ MinLevel = 25, Title = "City Flattener", CashBonus = 7500, Note = "Milestone Bonus: +$7,500 Cash!" },
	{ MinLevel = 30, Title = "Heat Bringer", CashBonus = 9000, Note = "Milestone Bonus: +$9,000 Cash!" },
	{ MinLevel = 35, Title = "Apex Wrecker", CashBonus = 12000, Note = "Milestone Bonus: +$12,000 Cash!" },
	{ MinLevel = 40, Title = "Titan of Chaos", CashBonus = 15000, Note = "Milestone Bonus: +$15,000 Cash!" },
	{ MinLevel = 45, Title = "Cataclysm King", CashBonus = 20000, Note = "Milestone Bonus: +$20,000 Cash!" },
	{ MinLevel = 50, Title = "Lord of Destruction", CashBonus = 50000, Note = "MAX LEVEL 50 • +$50,000 Sovereign Jackpot!" },
}

local function renderRanksTable()
	for _, child in ipairs(levelsPage:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local curLevel = tonumber(localPlayer:GetAttribute("Level")) or 1
	local curXP = tonumber(localPlayer:GetAttribute("XP")) or 0
	local reqXP = tonumber(localPlayer:GetAttribute("XPRequired")) or 250
	local curRank = tostring(localPlayer:GetAttribute("RankTitle") or "Street Rookie")

	local summaryBanner = Instance.new("Frame")
	summaryBanner.Size = UDim2.new(1, -12, 0, 54)
	summaryBanner.BackgroundColor3 = Color3.fromRGB(24, 34, 56)
	summaryBanner.BorderSizePixel = 0
	summaryBanner.Parent = levelsPage
	addCorner(summaryBanner, 10)
	addStroke(summaryBanner, Color3.fromRGB(255, 210, 55), 1.5)

	local summaryText = Instance.new("TextLabel")
	summaryText.Size = UDim2.new(1, -20, 1, 0)
	summaryText.Position = UDim2.fromOffset(12, 0)
	summaryText.BackgroundTransparency = 1
	summaryText.Font = Enum.Font.GothamBlack
	summaryText.Text = string.format(
		"YOUR PROGRESSION: LEVEL %d / 50 (%s) • XP: %d / %d",
		curLevel,
		string.upper(curRank),
		curXP,
		reqXP
	)
	summaryText.TextColor3 = Color3.fromRGB(255, 220, 75)
	summaryText.TextSize = 14
	summaryText.TextXAlignment = Enum.TextXAlignment.Left
	summaryText.Parent = summaryBanner

	for _, r in ipairs(FALLBACK_RANKS) do
		local unlocked = curLevel >= r.MinLevel
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 44)
		row.BackgroundColor3 = if unlocked then Color3.fromRGB(20, 38, 34) else Color3.fromRGB(18, 24, 38)
		row.BorderSizePixel = 0
		row.Parent = levelsPage
		addCorner(row, 8)
		addStroke(row, if unlocked then Color3.fromRGB(65, 240, 145) else Color3.fromRGB(50, 65, 92), 1.2)

		local lvlBadge = Instance.new("TextLabel")
		lvlBadge.Size = UDim2.fromOffset(78, 28)
		lvlBadge.Position = UDim2.fromOffset(10, 8)
		lvlBadge.BackgroundColor3 = if unlocked then Color3.fromRGB(40, 175, 105) else Color3.fromRGB(34, 44, 66)
		lvlBadge.Font = Enum.Font.GothamBlack
		lvlBadge.Text = string.format("LV. %d", r.MinLevel)
		lvlBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		lvlBadge.TextSize = 12
		lvlBadge.Parent = row
		addCorner(lvlBadge, 6)

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.fromOffset(210, 44)
		titleLbl.Position = UDim2.fromOffset(100, 0)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBlack
		titleLbl.Text = r.Title
		titleLbl.TextColor3 = if unlocked then Color3.fromRGB(110, 255, 175) else Color3.fromRGB(220, 228, 245)
		titleLbl.TextSize = 14
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Parent = row

		local noteLbl = Instance.new("TextLabel")
		noteLbl.Size = UDim2.new(1, -325, 1, 0)
		noteLbl.Position = UDim2.fromOffset(315, 0)
		noteLbl.BackgroundTransparency = 1
		noteLbl.Font = Enum.Font.GothamBold
		noteLbl.Text = string.format("%s  (%s)", r.Note, if unlocked then "UNLOCKED ✓" else "LOCKED")
		noteLbl.TextColor3 = if unlocked then Color3.fromRGB(255, 220, 85) else Color3.fromRGB(160, 175, 200)
		noteLbl.TextSize = 12
		noteLbl.TextXAlignment = Enum.TextXAlignment.Right
		noteLbl.Parent = row
	end
end

--------------------------------------------------------------------------------
-- Populate Page 3: VIP Store & Studio Sandbox Tester
--------------------------------------------------------------------------------
local storeList = Instance.new("UIListLayout")
storeList.Padding = UDim.new(0, 8)
storeList.Parent = storePage

local storeStatusBanner = Instance.new("TextLabel")
storeStatusBanner.Name = "StoreStatusBanner"
storeStatusBanner.Size = UDim2.new(1, -12, 0, 36)
storeStatusBanner.BackgroundColor3 = Color3.fromRGB(32, 26, 52)
storeStatusBanner.Font = Enum.Font.GothamBlack
storeStatusBanner.Text = "STUDIO SANDBOX MODE ACTIVE: Click any GamePass or DevProduct below to test-unlock for FREE!"
storeStatusBanner.TextColor3 = Color3.fromRGB(255, 215, 65)
storeStatusBanner.TextSize = 12
storeStatusBanner.Parent = storePage
addCorner(storeStatusBanner, 8)

local DEFAULT_GAMEPASSES = {
	{ Key = "VIP2xCash", Title = "VIP 2x Cash & XP", PriceRobux = 399, Description = "Permanently doubles all Cash & XP earned from smashing, stunts, combos, and missions!" },
	{ Key = "UnlimitedNitro", Title = "Unlimited Plasma Nitro", PriceRobux = 299, Description = "Infinite Nitro boost meter that never depletes + twin Blue Plasma exhaust flames!" },
	{ Key = "GoldenBulldozerPass", Title = "Golden Apex Bulldozer", PriceRobux = 499, Description = "Unlocks the heavily armored Golden Apex Bulldozer & Goliath Rig with 24K Gold trim!" },
	{ Key = "HeatShieldScanner", Title = "Police Heat Shield Scanner", PriceRobux = 249, Description = "50% slower Police Heat buildup and 50% faster cooldown when evading pursuit!" },
	{ Key = "MegaMagnetPass", Title = "Mega Combo & Cash Magnet", PriceRobux = 199, Description = "Doubles your Combo Timer window (9.0s) and grants a permanent +50% Cash Magnet boost!" },
}

local DEFAULT_DEVPRODUCTS = {
	{ Key = "CashPackStarter", Title = "Starter Cash Pack (+$10,000)", PriceRobux = 49, Description = "Instantly adds $10,000 Destruction Cash to your wallet for Speed Shop upgrades!" },
	{ Key = "CashPackPro", Title = "Pro Cash Vault (+$50,000)", PriceRobux = 199, Description = "Instantly adds $50,000 Destruction Cash to unlock heavy vehicles & high-tier upgrades!" },
	{ Key = "CashPackTycoon", Title = "Tycoon Mega Crate (+$250,000)", PriceRobux = 699, Description = "Instantly adds $250,000 Destruction Cash — max out every Speed Shop track & vehicle!" },
	{ Key = "BribePoliceChief", Title = "Bribe Police Chief (Clear Heat)", PriceRobux = 35, Description = "Instantly calls off all pursuing Police units and resets 5-Star Heat to 0!" },
	{ Key = "InstantMaxRepairAndBoost", Title = "Max Repair + 60s Overdrive", PriceRobux = 29, Description = "Instantly repairs your vehicle to 100% HP, refills Nitro, and triggers 60s 2x Overdrive!" },
}

local function renderStoreCatalog()
	for _, child in ipairs(storePage:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local function createStoreRow(kind: "GamePass" | "DevProduct", item: { Key: string, Title: string, PriceRobux: number, Description: string })
		local isOwned = kind == "GamePass" and (localPlayer:GetAttribute("Pass_" .. item.Key) == true or localPlayer:GetAttribute(item.Key) == true)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 58)
		row.BackgroundColor3 = if isOwned then Color3.fromRGB(20, 40, 34) else Color3.fromRGB(20, 27, 44)
		row.BorderSizePixel = 0
		row.Parent = storePage
		addCorner(row, 9)
		addStroke(
			row,
			if isOwned then Color3.fromRGB(65, 240, 145) elseif kind == "GamePass" then Color3.fromRGB(255, 200, 55) else Color3.fromRGB(0, 215, 255),
			1.4
		)

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.fromOffset(86, 22)
		badge.Position = UDim2.fromOffset(10, 7)
		badge.BackgroundColor3 = if kind == "GamePass" then Color3.fromRGB(165, 115, 20) else Color3.fromRGB(20, 115, 155)
		badge.Font = Enum.Font.GothamBlack
		badge.Text = if kind == "GamePass" then "GAMEPASS" else "CONSUMABLE"
		badge.TextColor3 = Color3.fromRGB(255, 255, 255)
		badge.TextSize = 10
		badge.Parent = row
		addCorner(badge, 5)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -250, 0, 22)
		title.Position = UDim2.fromOffset(104, 6)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = item.Title
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = row

		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -165, 0, 22)
		desc.Position = UDim2.fromOffset(10, 31)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.GothamMedium
		desc.Text = item.Description
		desc.TextColor3 = Color3.fromRGB(205, 215, 235)
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Parent = row

		local buyBtn = Instance.new("TextButton")
		buyBtn.AnchorPoint = Vector2.new(1, 0.5)
		buyBtn.Position = UDim2.new(1, -10, 0.5, 0)
		buyBtn.Size = UDim2.fromOffset(135, 36)
		buyBtn.BackgroundColor3 = if isOwned then Color3.fromRGB(40, 150, 90) else Color3.fromRGB(245, 185, 35)
		buyBtn.Font = Enum.Font.GothamBlack
		buyBtn.Text = if isOwned then "ACTIVE ✓" else string.format("R$ %d (TEST)", item.PriceRobux)
		buyBtn.TextColor3 = if isOwned then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(15, 20, 30)
		buyBtn.TextSize = 12
		buyBtn.Parent = row
		addCorner(buyBtn, 8)

		buyBtn.Activated:Connect(function()
			local reqRemote = findRemoteEvent("RequestMonetizationPurchase")
			if reqRemote then
				reqRemote:FireServer(kind, item.Key)
			end
			task.delay(0.25, renderStoreCatalog)
		end)
	end

	for _, gp in ipairs(DEFAULT_GAMEPASSES) do
		createStoreRow("GamePass", gp)
	end
	for _, dp in ipairs(DEFAULT_DEVPRODUCTS) do
		createStoreRow("DevProduct", dp)
	end
end

local function switchModalTab(tabName: "Controls" | "Levels" | "Store")
	controlsPage.Visible = (tabName == "Controls")
	levelsPage.Visible = (tabName == "Levels")
	storePage.Visible = (tabName == "Store")

	tabControlsBtn.BackgroundColor3 = if tabName == "Controls" then Color3.fromRGB(0, 145, 205) else Color3.fromRGB(24, 32, 52)
	tabLevelsBtn.BackgroundColor3 = if tabName == "Levels" then Color3.fromRGB(0, 145, 205) else Color3.fromRGB(24, 32, 52)
	tabStoreBtn.BackgroundColor3 = if tabName == "Store" then Color3.fromRGB(185, 130, 25) else Color3.fromRGB(24, 32, 52)

	if tabName == "Levels" then
		renderRanksTable()
	elseif tabName == "Store" then
		renderStoreCatalog()
	end
end

local function openModalWithTab(tabName: "Controls" | "Levels" | "Store")
	if modalBackdrop.Visible and ((tabName == "Controls" and controlsPage.Visible) or (tabName == "Store" and storePage.Visible)) then
		modalBackdrop.Visible = false
		return
	end
	modalBackdrop.Visible = true
	switchModalTab(tabName)
end

tabControlsBtn.Activated:Connect(function()
	switchModalTab("Controls")
end)
tabLevelsBtn.Activated:Connect(function()
	switchModalTab("Levels")
end)
tabStoreBtn.Activated:Connect(function()
	switchModalTab("Store")
end)
closeBtn.Activated:Connect(function()
	modalBackdrop.Visible = false
end)
guideToggleBtn.Activated:Connect(function()
	openModalWithTab("Controls")
end)
storeToggleBtn.Activated:Connect(function()
	openModalWithTab("Store")
end)

--------------------------------------------------------------------------------
-- Onboarding Step Progression & Live Attribute Watchers
--------------------------------------------------------------------------------
local currentStepIndex = 1
local tutorialCompleted = false
local usedNitroOrDrift = false
local visitedSpeedShop = false

local function updateTutorialUI()
	if tutorialCompleted then
		tutorialCard.Visible = false
		setWaypointVisible(false)
		return
	end

	local spec = TUTORIAL_STEPS[currentStepIndex]
	if not spec then
		tutorialCompleted = true
		tutorialCard.Visible = false
		setWaypointVisible(false)
		return
	end

	tutHeader.Text = spec.Title
	tutHeader.TextColor3 = spec.AccentColor
	tutBody.Text = spec.Instruction
	tutHintLabel.Text = spec.KeyHint
	tutorialCardStroke.Color = spec.AccentColor
	tutProgressFill.BackgroundColor3 = spec.AccentColor

	TweenService:Create(
		tutProgressFill,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(currentStepIndex / #TUTORIAL_STEPS, 1) }
	):Play()

	if currentStepIndex == #TUTORIAL_STEPS then
		tutNextBtn.Text = "Finish ✓"
	else
		tutNextBtn.Text = "Next ▸"
	end
end

local function advanceTutorialStep()
	if tutorialCompleted then
		return
	end
	if currentStepIndex < #TUTORIAL_STEPS then
		currentStepIndex += 1
		updateTutorialUI()
	else
		tutorialCompleted = true
		updateTutorialUI()
	end
end

tutNextBtn.Activated:Connect(advanceTutorialStep)
tutSkipBtn.Activated:Connect(function()
	tutorialCompleted = true
	updateTutorialUI()
end)

-- Keyboard shortcuts: [H] Guide & Ranks, [M] VIP Store, plus detecting [V], [LeftShift], [Space], [B]
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Space then
		usedNitroOrDrift = true
	elseif input.KeyCode == Enum.KeyCode.B then
		visitedSpeedShop = true
	end

	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.H then
		openModalWithTab("Controls")
	elseif input.KeyCode == Enum.KeyCode.M then
		openModalWithTab("Store")
	end
end)

-- Update Top-Right Level & XP Badge
local function refreshLevelBadge()
	local lvl = tonumber(localPlayer:GetAttribute("Level")) or 1
	local rank = tostring(localPlayer:GetAttribute("RankTitle") or "Street Rookie")
	local ratio = tonumber(localPlayer:GetAttribute("XPProgressRatio")) or 0.1
	levelTitleText.Text = string.format("LV.%d • %s", lvl, string.upper(rank))
	xpBarFill.Size = UDim2.fromScale(math.clamp(ratio, 0.06, 1), 1)
end

localPlayer:GetAttributeChangedSignal("Level"):Connect(refreshLevelBadge)
localPlayer:GetAttributeChangedSignal("XPProgressRatio"):Connect(refreshLevelBadge)
localPlayer:GetAttributeChangedSignal("RankTitle"):Connect(refreshLevelBadge)
localPlayer:GetAttributeChangedSignal("ToggleHelpUI"):Connect(function()
	openModalWithTab("Controls")
end)
localPlayer:GetAttributeChangedSignal("ToggleVIPUI"):Connect(function()
	openModalWithTab("Store")
end)
refreshLevelBadge()

-- Listen for server MonetizationNotifications
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if folder then
		local monNotif = folder:FindFirstChild("MonetizationNotification")
		if monNotif and monNotif:IsA("RemoteEvent") then
			monNotif.OnClientEvent:Connect(function(payload: { [string]: any })
				if type(payload) == "table" and payload.Message then
					storeStatusBanner.Text = tostring(payload.Message)
					renderStoreCatalog()
				end
			end)
		end
	end
end)

-- Main Onboarding & 3D Waypoint Update Loop
ensure3DWaypoint()
updateTutorialUI()

RunService.RenderStepped:Connect(function()
	if tutorialCompleted then
		return
	end

	local character = localPlayer.Character
	local rootPart = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not rootPart then
		setWaypointVisible(false)
		return
	end

	local playerPos = rootPart.Position
	local isSeated = (humanoid ~= nil and humanoid.SeatPart ~= nil) or localPlayer:GetAttribute("IsDriving") == true

	-- Auto-check completion conditions for current step
	if currentStepIndex == 1 then
		if isSeated then
			advanceTutorialStep()
			return
		end
	elseif currentStepIndex == 2 then
		local destCount = tonumber(localPlayer:GetAttribute("TotalDestructions")) or 0
		local comboCount = tonumber(localPlayer:GetAttribute("ComboCount")) or 0
		if destCount >= 5 or comboCount >= 3 then
			advanceTutorialStep()
			return
		end
	elseif currentStepIndex == 3 then
		if usedNitroOrDrift then
			advanceTutorialStep()
			return
		end
	elseif currentStepIndex == 4 then
		local nearestShop = findNearestSpeedShopPosition(playerPos)
		local engLvl = tonumber(localPlayer:GetAttribute("Upgrade_Engine")) or 1
		if visitedSpeedShop or (nearestShop - playerPos).Magnitude < 24 or engLvl > 1 then
			advanceTutorialStep()
			return
		end
	elseif currentStepIndex == 5 then
		local heatStars = tonumber(localPlayer:GetAttribute("HeatStars")) or 0
		local missionsDone = tonumber(localPlayer:GetAttribute("MissionsCompleted")) or 0
		if heatStars >= 1 or missionsDone >= 1 then
			advanceTutorialStep()
			return
		end
	end

	-- Update 3D Waypoint Beam position toward step objective
	local spec = TUTORIAL_STEPS[currentStepIndex]
	if not spec or not waypointStartPart or not waypointEndPart then
		return
	end

	local targetPos = playerPos + Vector3.new(0, 0, -30)
	local targetLabel = "▼ OBJECTIVE"

	if spec.TargetKind == "Vehicle" then
		targetPos = findNearestVehiclePosition(playerPos)
		targetLabel = "▼ YOUR VEHICLE [V]"
	elseif spec.TargetKind == "Destructibles" then
		targetPos = Vector3.new(0, 1.5, -18)
		targetLabel = "▼ SMASH PLAZA PROPS"
	elseif spec.TargetKind == "Stunt" then
		targetPos = Vector3.new(0, 1.5, -58)
		targetLabel = "▼ MEGA-RAMP STUNT"
	elseif spec.TargetKind == "SpeedShop" then
		targetPos = findNearestSpeedShopPosition(playerPos)
		targetLabel = "▼ SPEED SHOP [B]"
	elseif spec.TargetKind == "Heat" then
		targetPos = Vector3.new(-26, 1.5, -206)
		targetLabel = "▼ LEO TOWER CHAOS"
	end

	setWaypointVisible(true)
	waypointStartPart.Position = playerPos + Vector3.new(0, 1.5, 0)
	waypointEndPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	waypointEndPart.Color = spec.AccentColor

	if waypointBillboardTitle then
		waypointBillboardTitle.Text = targetLabel
		waypointBillboardTitle.TextColor3 = spec.AccentColor
	end
	if waypointBillboardDist then
		local distMeters = math.floor((targetPos - playerPos).Magnitude)
		waypointBillboardDist.Text = string.format("%d m away", distMeters)
	end
end)
