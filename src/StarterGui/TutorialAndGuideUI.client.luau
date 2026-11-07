--!strict
--[[
	TutorialAndGuideUI.client.luau
	World of Destruction (Roblox)
	
	Ultra-Visual [H] Guide & [M] VIP Store Modal:
	- Bottom-Left Onboarding Card (`tutorialCard`) is permanently hidden (`tutorialCard.Visible = false`)
	  on creation and inside `updateTutorialUI()` so it NEVER overlaps the bottom-left screen.
	- [H] Guide Modal shows 5 simple visual icon cards (`TIER 1 -> TIER 5 SMASH TARGETS`) instead of walls of text.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Remove any legacy 3D waypoint folder if present
local oldWaypoint = Workspace:FindFirstChild("OnboardingWaypoint3D")
if oldWaypoint then
	oldWaypoint:Destroy()
end

--------------------------------------------------------------------------------
-- UI Construction: Permanently Hidden Tutorial Card + Visual [H] Guide Modal
--------------------------------------------------------------------------------
local existingGui = playerGui:FindFirstChild("TutorialAndGuideGui")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialAndGuideGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
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

--------------------------------------------------------------------------------
-- 1. Bottom-Left Onboarding Card — Permanently Hidden (`Visible = false`)
--------------------------------------------------------------------------------
local tutorialCard = Instance.new("Frame")
tutorialCard.Name = "OnboardingTutorialCard"
tutorialCard.AnchorPoint = Vector2.new(0, 1)
tutorialCard.Position = UDim2.new(0, 14, 1, -60)
tutorialCard.Size = UDim2.fromOffset(230, 68)
tutorialCard.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
tutorialCard.BackgroundTransparency = 1
tutorialCard.BorderSizePixel = 0
tutorialCard.Visible = false
tutorialCard.Parent = screenGui

local function updateTutorialUI()
	-- Permanently keep the bottom-left tutorial box hidden so it never appears on screen
	tutorialCard.Visible = false
end

updateTutorialUI()

--------------------------------------------------------------------------------
-- 2. Center Modal Window: [H] Smash Tiers Guide / Ranks / [M] VIP Store
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
modalWindow.Size = UDim2.fromOffset(720, 460)
modalWindow.BackgroundColor3 = Color3.fromRGB(13, 18, 30)
modalWindow.BorderSizePixel = 0
modalWindow.Parent = modalBackdrop
addCorner(modalWindow, 14)
addStroke(modalWindow, Color3.fromRGB(0, 215, 255), 2)

local modalScale = Instance.new("UIScale")
modalScale.Name = "ModalAutoScale"
modalScale.Scale = 1.0
modalScale.Parent = modalWindow

local camScaleConn: RBXScriptConnection? = nil
local function updateViewportScales()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		modalScale.Scale = math.clamp(math.min(vp.X / 840, vp.Y / 540), 0.60, 1.0)
	end
end

local function bindCameraViewport()
	if camScaleConn then
		camScaleConn:Disconnect()
		camScaleConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		camScaleConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateViewportScales)
		updateViewportScales()
	end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
bindCameraViewport()

-- Header Bar
local modalHeader = Instance.new("Frame")
modalHeader.Name = "Header"
modalHeader.Size = UDim2.new(1, 0, 0, 50)
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
modalTitle.Text = "SMASH TIERS (1 -> 5) & VIP STORE"
modalTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
modalTitle.TextSize = 18
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

-- Tab Bar
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -36, 0, 38)
tabBar.Position = UDim2.fromOffset(18, 58)
tabBar.BackgroundTransparency = 1
tabBar.Parent = modalWindow

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.Parent = tabBar

local function createTabButton(name: string, label: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(221, 36)
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

local tabControlsBtn = createTabButton("TabControls", "SMASH TIERS (1 -> 5)", 1)
local tabLevelsBtn = createTabButton("TabLevels", "LEVEL RANKS", 2)
local tabStoreBtn = createTabButton("TabStore", "VIP STORE", 3)

-- Tab Content Pages
local contentContainer = Instance.new("Frame")
contentContainer.Name = "ContentContainer"
contentContainer.Size = UDim2.new(1, -36, 1, -110)
contentContainer.Position = UDim2.fromOffset(18, 102)
contentContainer.BackgroundTransparency = 1
contentContainer.Parent = modalWindow

local controlsPage = Instance.new("Frame")
controlsPage.Name = "ControlsPage"
controlsPage.Size = UDim2.fromScale(1, 1)
controlsPage.BackgroundTransparency = 1
controlsPage.BorderSizePixel = 0
controlsPage.Parent = contentContainer

local levelsPage = Instance.new("ScrollingFrame")
levelsPage.Name = "LevelsPage"
levelsPage.Size = UDim2.fromScale(1, 1)
levelsPage.CanvasSize = UDim2.fromOffset(0, 560)
levelsPage.ScrollBarThickness = 6
levelsPage.BackgroundTransparency = 1
levelsPage.BorderSizePixel = 0
levelsPage.Visible = false
levelsPage.Parent = contentContainer

local storePage = Instance.new("ScrollingFrame")
storePage.Name = "StorePage"
storePage.Size = UDim2.fromScale(1, 1)
storePage.CanvasSize = UDim2.fromOffset(0, 680)
storePage.ScrollBarThickness = 6
storePage.BackgroundTransparency = 1
storePage.BorderSizePixel = 0
storePage.Visible = false
storePage.Parent = contentContainer

--------------------------------------------------------------------------------
-- Populate Page 1: 5 Simple Visual Icon Cards (TIER 1 -> TIER 5 SMASH TARGETS)
--------------------------------------------------------------------------------
local controlsList = Instance.new("UIListLayout")
controlsList.Padding = UDim.new(0, 8)
controlsList.SortOrder = Enum.SortOrder.LayoutOrder
controlsList.Parent = controlsPage

type SmashTierCardSpec = {
	tierNum: number,
	badgeText: string,
	vehiclesText: string,
	targetsText: string,
	color: Color3,
}

local SMASH_TIER_CARDS: { SmashTierCardSpec } = {
	{
		tierNum = 1,
		badgeText = "TIER 1",
		vehiclesText = "COMPACT (FREE)",
		targetsText = "SMASH CRATES, CONES & CARTS",
		color = Color3.fromRGB(65, 205, 255),
	},
	{
		tierNum = 2,
		badgeText = "TIER 2",
		vehiclesText = "SEDAN & MUSCLE ($1.5K - $4.5K)",
		targetsText = "SMASH GOLD ATMs, TAXIS & HYDRANTS",
		color = Color3.fromRGB(75, 235, 130),
	},
	{
		tierNum = 3,
		badgeText = "TIER 3",
		vehiclesText = "SUV, PICKUP & SPORTS ($9K - $28K)",
		targetsText = "SMASH ARMORED TRUCKS, GAS & COPS",
		color = Color3.fromRGB(255, 195, 50),
	},
	{
		tierNum = 4,
		badgeText = "TIER 4",
		vehiclesText = "MONSTER TRUCK ($50,000)",
		targetsText = "CRUSH BUSES & SWAT TRUCKS",
		color = Color3.fromRGB(255, 115, 45),
	},
	{
		tierNum = 5,
		badgeText = "TIER 5",
		vehiclesText = "BULLDOZER ($95,000)",
		targetsText = "BREAK GOLDEN BANK VAULTS",
		color = Color3.fromRGB(255, 65, 85),
	},
}

for idx, spec in ipairs(SMASH_TIER_CARDS) do
	local card = Instance.new("Frame")
	card.Name = "SmashTierCard_" .. tostring(spec.tierNum)
	card.LayoutOrder = idx
	card.Size = UDim2.new(1, 0, 0, 62)
	card.BackgroundColor3 = Color3.fromRGB(20, 27, 44)
	card.BorderSizePixel = 0
	card.Parent = controlsPage
	addCorner(card, 10)
	addStroke(card, spec.color, 1.6)

	local iconBox = Instance.new("Frame")
	iconBox.Name = "TierIconBadge"
	iconBox.Size = UDim2.fromOffset(96, 46)
	iconBox.Position = UDim2.fromOffset(8, 8)
	iconBox.BackgroundColor3 = spec.color
	iconBox.BorderSizePixel = 0
	iconBox.Parent = card
	addCorner(iconBox, 8)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.fromScale(1, 1)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.Text = spec.badgeText
	iconLabel.TextColor3 = Color3.fromRGB(12, 16, 26)
	iconLabel.TextSize = 18
	iconLabel.Parent = iconBox

	local targetsLabel = Instance.new("TextLabel")
	targetsLabel.Name = "TargetsLabel"
	targetsLabel.Size = UDim2.new(1, -330, 0, 28)
	targetsLabel.Position = UDim2.fromOffset(118, 8)
	targetsLabel.BackgroundTransparency = 1
	targetsLabel.Font = Enum.Font.GothamBlack
	targetsLabel.Text = spec.targetsText
	targetsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	targetsLabel.TextSize = 15
	targetsLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetsLabel.Parent = card

	local carTag = Instance.new("TextLabel")
	carTag.Name = "VehiclesTag"
	carTag.Size = UDim2.new(1, -330, 0, 20)
	carTag.Position = UDim2.fromOffset(118, 34)
	carTag.BackgroundTransparency = 1
	carTag.Font = Enum.Font.GothamBold
	carTag.Text = "CAR: " .. spec.vehiclesText
	carTag.TextColor3 = spec.color
	carTag.TextSize = 12
	carTag.TextXAlignment = Enum.TextXAlignment.Left
	carTag.Parent = card

	local openShopBtn = Instance.new("TextButton")
	openShopBtn.Name = "GarageBtn"
	openShopBtn.AnchorPoint = Vector2.new(1, 0.5)
	openShopBtn.Position = UDim2.new(1, -12, 0.5, 0)
	openShopBtn.Size = UDim2.fromOffset(170, 40)
	openShopBtn.BackgroundColor3 = Color3.fromRGB(36, 128, 225)
	openShopBtn.Font = Enum.Font.GothamBlack
	openShopBtn.Text = "OPEN GARAGE [B]"
	openShopBtn.TextColor3 = Color3.new(1, 1, 1)
	openShopBtn.TextSize = 13
	openShopBtn.Parent = card
	addCorner(openShopBtn, 8)

	openShopBtn.Activated:Connect(function()
		modalBackdrop.Visible = false
		localPlayer:SetAttribute("ToggleShopUI", not localPlayer:GetAttribute("ToggleShopUI"))
	end)
end

--------------------------------------------------------------------------------
-- Populate Page 2: Level Ranks & Cash Milestones
--------------------------------------------------------------------------------
local levelsList = Instance.new("UIListLayout")
levelsList.Padding = UDim.new(0, 8)
levelsList.Parent = levelsPage

local FALLBACK_RANKS = {
	{ MinLevel = 1, Title = "STREET ROOKIE", CashBonus = "$250" },
	{ MinLevel = 5, Title = "CURB CRUSHER", CashBonus = "+$1,250" },
	{ MinLevel = 10, Title = "ASPHALT OUTLAW", CashBonus = "+$2,500" },
	{ MinLevel = 15, Title = "NEON MENACE", CashBonus = "+$3,500" },
	{ MinLevel = 20, Title = "DEMOLITION PRO", CashBonus = "+$5,000" },
	{ MinLevel = 25, Title = "CITY FLATTENER", CashBonus = "+$7,500" },
	{ MinLevel = 30, Title = "HEAT BRINGER", CashBonus = "+$9,000" },
	{ MinLevel = 35, Title = "APEX WRECKER", CashBonus = "+$12,000" },
	{ MinLevel = 40, Title = "TITAN OF CHAOS", CashBonus = "+$15,000" },
	{ MinLevel = 45, Title = "CATACLYSM KING", CashBonus = "+$20,000" },
	{ MinLevel = 50, Title = "LORD OF DESTRUCTION", CashBonus = "+$50,000" },
}

local function renderRanksTable()
	for _, child in ipairs(levelsPage:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local curLevel = tonumber(localPlayer:GetAttribute("Level")) or 1
	for _, r in ipairs(FALLBACK_RANKS) do
		local unlocked = curLevel >= r.MinLevel
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 42)
		row.BackgroundColor3 = if unlocked then Color3.fromRGB(20, 38, 34) else Color3.fromRGB(18, 24, 38)
		row.BorderSizePixel = 0
		row.Parent = levelsPage
		addCorner(row, 8)
		addStroke(row, if unlocked then Color3.fromRGB(65, 240, 145) else Color3.fromRGB(50, 65, 92), 1.2)

		local lvlBadge = Instance.new("TextLabel")
		lvlBadge.Size = UDim2.fromOffset(78, 26)
		lvlBadge.Position = UDim2.fromOffset(10, 8)
		lvlBadge.BackgroundColor3 = if unlocked then Color3.fromRGB(40, 175, 105) else Color3.fromRGB(34, 44, 66)
		lvlBadge.Font = Enum.Font.GothamBlack
		lvlBadge.Text = string.format("LV. %d", r.MinLevel)
		lvlBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
		lvlBadge.TextSize = 12
		lvlBadge.Parent = row
		addCorner(lvlBadge, 6)

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.fromOffset(260, 42)
		titleLbl.Position = UDim2.fromOffset(100, 0)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBlack
		titleLbl.Text = r.Title
		titleLbl.TextColor3 = if unlocked then Color3.fromRGB(110, 255, 175) else Color3.fromRGB(220, 228, 245)
		titleLbl.TextSize = 14
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Parent = row

		local noteLbl = Instance.new("TextLabel")
		noteLbl.Size = UDim2.new(1, -380, 1, 0)
		noteLbl.Position = UDim2.fromOffset(365, 0)
		noteLbl.BackgroundTransparency = 1
		noteLbl.Font = Enum.Font.GothamBlack
		noteLbl.Text = string.format("BONUS: %s", r.CashBonus)
		noteLbl.TextColor3 = if unlocked then Color3.fromRGB(255, 220, 85) else Color3.fromRGB(160, 175, 200)
		noteLbl.TextSize = 13
		noteLbl.TextXAlignment = Enum.TextXAlignment.Right
		noteLbl.Parent = row
	end
end

--------------------------------------------------------------------------------
-- Populate Page 3: VIP Store
--------------------------------------------------------------------------------
local storeList = Instance.new("UIListLayout")
storeList.Padding = UDim.new(0, 8)
storeList.Parent = storePage

local storeStatusBanner = Instance.new("TextLabel")
storeStatusBanner.Name = "StoreStatusBanner"
storeStatusBanner.Size = UDim2.new(1, -12, 0, 34)
storeStatusBanner.BackgroundColor3 = Color3.fromRGB(32, 26, 52)
storeStatusBanner.Font = Enum.Font.GothamBlack
storeStatusBanner.Text = "VIP PASSES & CASH PACKS"
storeStatusBanner.TextColor3 = Color3.fromRGB(255, 215, 65)
storeStatusBanner.TextSize = 13
storeStatusBanner.Parent = storePage
addCorner(storeStatusBanner, 8)

local DEFAULT_GAMEPASSES = {
	{ Key = "VIP2xCash", Title = "VIP 2X CASH & XP", PriceRobux = 399, Tag = "2X ALL REWARDS" },
	{ Key = "UnlimitedNitro", Title = "INFINITE NITRO", PriceRobux = 299, Tag = "ENDLESS BOOST" },
	{ Key = "GoldenBulldozerPass", Title = "GOLDEN BULLDOZER", PriceRobux = 499, Tag = "TIER 5 GOLD RIG" },
	{ Key = "HeatShieldScanner", Title = "POLICE HEAT SHIELD", PriceRobux = 249, Tag = "-50% COP HEAT" },
	{ Key = "MegaMagnetPass", Title = "MEGA CASH MAGNET", PriceRobux = 199, Tag = "+50% CASH DROPS" },
}

local DEFAULT_DEVPRODUCTS = {
	{ Key = "CashPackStarter", Title = "+$10,000 CASH PACK", PriceRobux = 49, Tag = "INSTANT CASH" },
	{ Key = "CashPackPro", Title = "+$50,000 CASH VAULT", PriceRobux = 199, Tag = "UNLOCK TIER 4" },
	{ Key = "CashPackTycoon", Title = "+$250,000 MEGA CRATE", PriceRobux = 699, Tag = "UNLOCK TIER 5" },
	{ Key = "BribePoliceChief", Title = "CLEAR POLICE HEAT", PriceRobux = 35, Tag = "0 WANTED STARS" },
	{ Key = "InstantMaxRepairAndBoost", Title = "MAX REPAIR + 2X BOOST", PriceRobux = 29, Tag = "100% HP + NITRO" },
}

local function renderStoreCatalog()
	for _, child in ipairs(storePage:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local function createStoreRow(kind: "GamePass" | "DevProduct", item: { Key: string, Title: string, PriceRobux: number, Tag: string })
		local isOwned = kind == "GamePass" and (localPlayer:GetAttribute("Pass_" .. item.Key) == true or localPlayer:GetAttribute(item.Key) == true)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 50)
		row.BackgroundColor3 = if isOwned then Color3.fromRGB(20, 40, 34) else Color3.fromRGB(20, 27, 44)
		row.BorderSizePixel = 0
		row.Parent = storePage
		addCorner(row, 9)
		addStroke(
			row,
			if isOwned then Color3.fromRGB(65, 240, 145) elseif kind == "GamePass" then Color3.fromRGB(255, 200, 55) else Color3.fromRGB(0, 215, 255),
			1.4
		)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromOffset(260, 50)
		title.Position = UDim2.fromOffset(14, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = item.Title
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = row

		local tagLbl = Instance.new("TextLabel")
		tagLbl.Size = UDim2.fromOffset(190, 50)
		tagLbl.Position = UDim2.fromOffset(280, 0)
		tagLbl.BackgroundTransparency = 1
		tagLbl.Font = Enum.Font.GothamBold
		tagLbl.Text = item.Tag
		tagLbl.TextColor3 = Color3.fromRGB(255, 215, 75)
		tagLbl.TextSize = 12
		tagLbl.TextXAlignment = Enum.TextXAlignment.Left
		tagLbl.Parent = row

		local buyBtn = Instance.new("TextButton")
		buyBtn.AnchorPoint = Vector2.new(1, 0.5)
		buyBtn.Position = UDim2.new(1, -10, 0.5, 0)
		buyBtn.Size = UDim2.fromOffset(135, 34)
		buyBtn.BackgroundColor3 = if isOwned then Color3.fromRGB(40, 150, 90) else Color3.fromRGB(245, 185, 35)
		buyBtn.Font = Enum.Font.GothamBlack
		buyBtn.Text = if isOwned then "OWNED" else string.format("R$ %d", item.PriceRobux)
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
	updateTutorialUI()
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
	updateTutorialUI()
	if modalBackdrop.Visible and ((tabName == "Controls" and controlsPage.Visible) or (tabName == "Store" and storePage.Visible)) then
		modalBackdrop.Visible = false
		return
	end
	updateViewportScales()
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

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.H then
		openModalWithTab("Controls")
	elseif input.KeyCode == Enum.KeyCode.M then
		openModalWithTab("Store")
	end
end)

localPlayer:GetAttributeChangedSignal("ToggleHelpUI"):Connect(function()
	openModalWithTab("Controls")
end)
localPlayer:GetAttributeChangedSignal("ToggleVIPUI"):Connect(function()
	openModalWithTab("Store")
end)

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
