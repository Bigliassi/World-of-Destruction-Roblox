--!strict
--[[
	HomeMenuAndSettingsUI.client.luau
	World of Destruction (Roblox) — Version 1.0
	
	Provides:
	1. AAA Console-Style Home Menu Screen (opens on first launch and anytime via [M]/[Tab]/[P] or HUD Menu button):
	   - Smooth orbital camera over sunlit Leo Plaza & Leo Tower while active (`HomeMenuActive = true`)
	   - Left Column: "WORLD OF DESTRUCTION — OPERATION: TAKE BACK LEO CITY" hero branding +
	     4 Large 3D Tactile Beveled Buttons (Play Campaign Act 1–5, Freeplay Sandbox, Garage & Avatar Shop, Settings)
	   - Right Column: "THE STORY: BEGINNING TO END (5-ACT CAMPAIGN ROADMAP)" showing Act 1 (Beginning) through
	     Act 5 (Boss Goliath Convoy Finale) with live progress highlighting
	2. Full Settings Modal (accessible from Home Menu or In-Game [P] / Settings button):
	   - SFX Volume (100% / 60% / 25% / Mute)
	   - Vehicle Engine Sound (ON / OFF)
	   - Lighting & Time of Day (Bright Sunny Day / Golden Sunset / Neon Night)
	   - Driving Physics Mode (Progressive Realistic / Arcade Boost)
	   - Camera Shake (Normal / Reduced / Off)
	   - 3D Waypoint Guide Beam (ON / OFF)
	3. Grand Finale Victory Celebration Modal when `CampaignCompleted` transitions to `true`.
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
if localPlayer:GetAttribute("TimeOfDayPreference") == nil then
	localPlayer:SetAttribute("TimeOfDayPreference", "Sunny")
end
if localPlayer:GetAttribute("DrivingMode") == nil then
	localPlayer:SetAttribute("DrivingMode", "Progressive")
end
if localPlayer:GetAttribute("CameraShakeScale") == nil then
	localPlayer:SetAttribute("CameraShakeScale", 1.0)
end
if localPlayer:GetAttribute("ShowWaypointBeam") == nil then
	localPlayer:SetAttribute("ShowWaypointBeam", true)
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
		uiScale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.64, 1.05)
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
-- 3D Tactile Beveled UI Helpers
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
	subtitle: string?,
	badgeText: string?,
	size: UDim2,
	position: UDim2?,
	layoutOrder: number?,
	baseColor: Color3,
	parent: Instance,
	onClick: () -> (),
}): (Frame, TextLabel)
	local lipDepth = 5
	local container = Instance.new("Frame")
	container.Name = params.name
	container.Size = params.size
	if params.position then
		container.Position = params.position
	end
	if params.layoutOrder then
		container.LayoutOrder = params.layoutOrder
	end
	container.BackgroundColor3 = darkenColor(params.baseColor, 0.52)
	container.BorderSizePixel = 0
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
	face.Parent = container
	addCorner(face, 11)
	addStroke(face, brightenColor(params.baseColor, 0.28), 1.5, 0.25)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, brightenColor(params.baseColor, 0.18)),
		ColorSequenceKeypoint.new(1, darkenColor(params.baseColor, 0.86)),
	})
	grad.Parent = face

	-- Top 38% white gloss sheen
	local gloss = Instance.new("Frame")
	gloss.Name = "TopGlossSheen"
	gloss.Size = UDim2.new(1, -6, 0.38, 0)
	gloss.Position = UDim2.fromOffset(3, 2)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.84
	gloss.BorderSizePixel = 0
	gloss.Parent = face
	addCorner(gloss, 8)

	local textOffsetLeft = 14
	if params.badgeText and #params.badgeText > 0 then
		textOffsetLeft = 58
		local badge = Instance.new("Frame")
		badge.Name = "KeyBadge"
		badge.Size = UDim2.fromOffset(38, 34)
		badge.Position = UDim2.new(0, 10, 0.5, -17)
		badge.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
		badge.BackgroundTransparency = 0.2
		badge.BorderSizePixel = 0
		badge.Parent = face
		addCorner(badge, 8)
		addStroke(badge, brightenColor(params.baseColor, 0.3), 1, 0.35)

		local badgeLbl = Instance.new("TextLabel")
		badgeLbl.Size = UDim2.fromScale(1, 1)
		badgeLbl.BackgroundTransparency = 1
		badgeLbl.Font = Enum.Font.GothamBlack
		badgeLbl.Text = params.badgeText
		badgeLbl.TextColor3 = Color3.fromRGB(255, 235, 120)
		badgeLbl.TextSize = 15
		badgeLbl.Parent = badge
	end

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -(textOffsetLeft + 12), 0, if params.subtitle then 22 else 28)
	titleLbl.Position = UDim2.new(0, textOffsetLeft, 0.5, if params.subtitle then -18 else -14)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.Text = params.title
	titleLbl.TextColor3 = Color3.new(1, 1, 1)
	titleLbl.TextSize = if params.subtitle then 16 else 15
	titleLbl.TextXAlignment = if params.badgeText then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	titleLbl.TextStrokeTransparency = 0.45
	titleLbl.Parent = face

	if params.subtitle then
		local subLbl = Instance.new("TextLabel")
		subLbl.Name = "Subtitle"
		subLbl.Size = UDim2.new(1, -(textOffsetLeft + 12), 0, 15)
		subLbl.Position = UDim2.new(0, textOffsetLeft, 0.5, 4)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.GothamBold
		subLbl.Text = params.subtitle
		subLbl.TextColor3 = Color3.fromRGB(235, 242, 255)
		subLbl.TextSize = 11
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.TextTransparency = 0.12
		subLbl.Parent = face
	end

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
-- 1. HOME MENU OVERLAY
--------------------------------------------------------------------------------
local homeRoot = Instance.new("Frame")
homeRoot.Name = "HomeMenuOverlay"
homeRoot.Size = UDim2.fromScale(1, 1)
homeRoot.BackgroundColor3 = Color3.fromRGB(8, 12, 22)
homeRoot.BackgroundTransparency = 0.32
homeRoot.BorderSizePixel = 0
homeRoot.Visible = true
homeRoot.Parent = screenGui

-- Main Content Wrapper (1120 x 610 centered)
local homeContent = Instance.new("Frame")
homeContent.Name = "HomeContent"
homeContent.Size = UDim2.fromOffset(1120, 610)
homeContent.Position = UDim2.fromScale(0.5, 0.5)
homeContent.AnchorPoint = Vector2.new(0.5, 0.5)
homeContent.BackgroundTransparency = 1
homeContent.Parent = homeRoot

-- LEFT COLUMN: Hero Title + 4 Large 3D Tactile Action Buttons
local leftCol = Instance.new("Frame")
leftCol.Name = "LeftColumn"
leftCol.Size = UDim2.fromOffset(470, 590)
leftCol.Position = UDim2.fromOffset(0, 10)
leftCol.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
leftCol.BackgroundTransparency = 0.12
leftCol.BorderSizePixel = 0
leftCol.Parent = homeContent
addCorner(leftCol, 16)
addStroke(leftCol, Color3.fromRGB(255, 185, 50), 2, 0.2)

local titleBanner = Instance.new("Frame")
titleBanner.Name = "HeroTitleBanner"
titleBanner.Size = UDim2.new(1, -28, 0, 124)
titleBanner.Position = UDim2.fromOffset(14, 14)
titleBanner.BackgroundColor3 = Color3.fromRGB(22, 28, 46)
titleBanner.BorderSizePixel = 0
titleBanner.Parent = leftCol
addCorner(titleBanner, 12)
addStroke(titleBanner, Color3.fromRGB(255, 200, 60), 1.5, 0.25)

local heroTag = Instance.new("TextLabel")
heroTag.Size = UDim2.new(1, -20, 0, 20)
heroTag.Position = UDim2.fromOffset(12, 10)
heroTag.BackgroundTransparency = 1
heroTag.Font = Enum.Font.GothamBlack
heroTag.Text = "★ LEO CITY OPEN-WORLD VEHICULAR MAYHEM ★"
heroTag.TextColor3 = Color3.fromRGB(255, 210, 70)
heroTag.TextSize = 12
heroTag.TextXAlignment = Enum.TextXAlignment.Left
heroTag.Parent = titleBanner

local heroMain = Instance.new("TextLabel")
heroMain.Size = UDim2.new(1, -20, 0, 42)
heroMain.Position = UDim2.fromOffset(12, 30)
heroMain.BackgroundTransparency = 1
heroMain.Font = Enum.Font.GothamBlack
heroMain.Text = "WORLD OF DESTRUCTION"
heroMain.TextColor3 = Color3.fromRGB(255, 255, 255)
heroMain.TextSize = 30
heroMain.TextScaled = true
heroMain.TextXAlignment = Enum.TextXAlignment.Left
heroMain.Parent = titleBanner

local heroGrad = Instance.new("UIGradient")
heroGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 50)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 45)),
})
heroGrad.Parent = heroMain

local heroSub = Instance.new("TextLabel")
heroSub.Size = UDim2.new(1, -20, 0, 38)
heroSub.Position = UDim2.fromOffset(12, 76)
heroSub.BackgroundTransparency = 1
heroSub.Font = Enum.Font.GothamBold
heroSub.Text = "OPERATION: TAKE BACK LEO CITY • 5-ACT CAMPAIGN & FREEPLAY"
heroSub.TextColor3 = Color3.fromRGB(165, 220, 255)
heroSub.TextSize = 12
heroSub.TextWrapped = true
heroSub.TextXAlignment = Enum.TextXAlignment.Left
heroSub.Parent = titleBanner

local buttonsStack = Instance.new("Frame")
buttonsStack.Name = "MainButtonsStack"
buttonsStack.Size = UDim2.new(1, -28, 0, 360)
buttonsStack.Position = UDim2.fromOffset(14, 152)
buttonsStack.BackgroundTransparency = 1
buttonsStack.Parent = leftCol

local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.Padding = UDim.new(0, 12)
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Parent = buttonsStack

local settingsModal: Frame

local function setHomeMenuOpen(isOpen: boolean)
	homeRoot.Visible = isOpen
	localPlayer:SetAttribute("HomeMenuActive", isOpen)
	localPlayer:SetAttribute("HomeMenuCameraActive", isOpen)
end

local _, playCampaignBtnLabel = makeTactile3DButton({
	name = "PlayCampaignBtn",
	title = "▶ PLAY CAMPAIGN (ACT 1–5)",
	subtitle = "Dismantle MegaCorp across 5 Acts & defeat the Boss Goliath!",
	badgeText = "▶",
	size = UDim2.new(1, 0, 0, 76),
	layoutOrder = 1,
	baseColor = Color3.fromRGB(32, 185, 95),
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
	end,
})

makeTactile3DButton({
	name = "FreeplaySandboxBtn",
	title = "🔥 FREEPLAY SANDBOX",
	subtitle = "Jump straight into open-world sunlit destruction, ramps & combos!",
	badgeText = "🔥",
	size = UDim2.new(1, 0, 0, 76),
	layoutOrder = 2,
	baseColor = Color3.fromRGB(235, 125, 30),
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
	end,
})

makeTactile3DButton({
	name = "GarageAndAvatarBtn",
	title = "🚗 GARAGE & AVATAR SHOP",
	subtitle = "Unlock 8 vehicle classes, 5 upgrade tracks & custom outfits!",
	badgeText = "B/C",
	size = UDim2.new(1, 0, 0, 76),
	layoutOrder = 3,
	baseColor = Color3.fromRGB(38, 128, 235),
	parent = buttonsStack,
	onClick = function()
		setHomeMenuOpen(false)
		localPlayer:SetAttribute("ToggleShopUI", true)
	end,
})

makeTactile3DButton({
	name = "OpenSettingsBtn",
	title = "⚙ SETTINGS & AUDIO/GRAPHICS",
	subtitle = "Configure SFX volume, sunny/sunset/night lighting & driving mode!",
	badgeText = "P",
	size = UDim2.new(1, 0, 0, 76),
	layoutOrder = 4,
	baseColor = Color3.fromRGB(115, 72, 215),
	parent = buttonsStack,
	onClick = function()
		settingsModal.Visible = true
	end,
})

local footerControls = Instance.new("TextLabel")
footerControls.Size = UDim2.new(1, -28, 0, 44)
footerControls.Position = UDim2.new(0, 14, 1, -54)
footerControls.BackgroundTransparency = 1
footerControls.Font = Enum.Font.GothamBold
footerControls.Text = "QUICK KEYS: [WASD] Drive • [Shift] Nitro • [Space] Drift • [V] Summon Car • [B] Garage • [P/Tab] Menu"
footerControls.TextColor3 = Color3.fromRGB(185, 200, 225)
footerControls.TextSize = 11
footerControls.TextWrapped = true
footerControls.Parent = leftCol

--------------------------------------------------------------------------------
-- RIGHT COLUMN: 5-ACT STORY ROADMAP (BEGINNING -> END)
--------------------------------------------------------------------------------
local rightCol = Instance.new("Frame")
rightCol.Name = "RightStoryColumn"
rightCol.Size = UDim2.fromOffset(630, 590)
rightCol.Position = UDim2.fromOffset(490, 10)
rightCol.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
rightCol.BackgroundTransparency = 0.12
rightCol.BorderSizePixel = 0
rightCol.Parent = homeContent
addCorner(rightCol, 16)
addStroke(rightCol, Color3.fromRGB(85, 195, 255), 2, 0.2)

local roadmapHeader = Instance.new("Frame")
roadmapHeader.Size = UDim2.new(1, -28, 0, 96)
roadmapHeader.Position = UDim2.fromOffset(14, 14)
roadmapHeader.BackgroundColor3 = Color3.fromRGB(20, 28, 46)
roadmapHeader.BorderSizePixel = 0
roadmapHeader.Parent = rightCol
addCorner(roadmapHeader, 12)
addStroke(roadmapHeader, Color3.fromRGB(95, 205, 255), 1.5, 0.3)

local roadmapTitle = Instance.new("TextLabel")
roadmapTitle.Size = UDim2.new(1, -20, 0, 26)
roadmapTitle.Position = UDim2.fromOffset(12, 8)
roadmapTitle.BackgroundTransparency = 1
roadmapTitle.Font = Enum.Font.GothamBlack
roadmapTitle.Text = "THE STORY: BEGINNING TO END (5-ACT CAMPAIGN ROADMAP)"
roadmapTitle.TextColor3 = Color3.fromRGB(255, 215, 65)
roadmapTitle.TextSize = 16
roadmapTitle.TextXAlignment = Enum.TextXAlignment.Left
roadmapTitle.Parent = roadmapHeader

local roadmapPremise = Instance.new("TextLabel")
roadmapPremise.Size = UDim2.new(1, -20, 0, 52)
roadmapPremise.Position = UDim2.fromOffset(12, 36)
roadmapPremise.BackgroundTransparency = 1
roadmapPremise.Font = Enum.Font.GothamMedium
roadmapPremise.Text = "THE MISSION: Corrupt Mayor Vance & MegaCorp have locked down Leo City with surveillance towers and blockades. Smash their property across 5 escalating Acts, upgrade your ride, and defeat Mayor Vance's Armored Goliath Convoy at Leo Tower to liberate the city!"
roadmapPremise.TextColor3 = Color3.fromRGB(225, 235, 250)
roadmapPremise.TextSize = 12
roadmapPremise.TextWrapped = true
roadmapPremise.TextXAlignment = Enum.TextXAlignment.Left
roadmapPremise.Parent = roadmapHeader

local actsContainer = Instance.new("Frame")
actsContainer.Name = "ActsRoadmapList"
actsContainer.Size = UDim2.new(1, -28, 0, 450)
actsContainer.Position = UDim2.fromOffset(14, 122)
actsContainer.BackgroundTransparency = 1
actsContainer.Parent = rightCol

local actsLayout = Instance.new("UIListLayout")
actsLayout.FillDirection = Enum.FillDirection.Vertical
actsLayout.Padding = UDim.new(0, 8)
actsLayout.SortOrder = Enum.SortOrder.LayoutOrder
actsLayout.Parent = actsContainer

local ROADMAP_SPECS = {
	{
		act = 1,
		tag = "ACT 1 • THE BEGINNING",
		title = "Break Out of Leo Plaza",
		desc = "Smash 12 MegaCorp Props or Barriers around Leo Plaza to spark the uprising!",
		reward = "$2,500",
	},
	{
		act = 2,
		tag = "ACT 2 • CHAPTER 2",
		title = "Flood the Midtown Grid",
		desc = "Smash 6 Fire Hydrants or Streetlights & reach a 3x Chaos Combo!",
		reward = "$5,000",
	},
	{
		act = 3,
		tag = "ACT 3 • CHAPTER 3",
		title = "Industrial Sabotage",
		desc = "Cause $15,000 in Destruction Value or detonate Boom Gas Station!",
		reward = "$10,000",
	},
	{
		act = 4,
		tag = "ACT 4 • CHAPTER 4",
		title = "Break the Blockade",
		desc = "Land 2 Stunt Jumps or Drifts & Wreck 1 Enforcer Cruiser!",
		reward = "$18,000",
	},
	{
		act = 5,
		tag = "ACT 5 • THE END / BOSS FINALE",
		title = "Defeat Mayor Vance's Boss Goliath Convoy",
		desc = "Ram & Destroy the Armored Boss Goliath on Grand Central Ave to liberate Leo City!",
		reward = "$50,000 + CROWN",
	},
}

type ActCardRefs = {
	frame: Frame,
	stroke: UIStroke,
	statusBadge: TextLabel,
	progFill: Frame,
}
local actCards: { [number]: ActCardRefs } = {}

for _, spec in ipairs(ROADMAP_SPECS) do
	local card = Instance.new("Frame")
	card.Name = "ActCard_" .. tostring(spec.act)
	card.LayoutOrder = spec.act
	card.Size = UDim2.new(1, 0, 0, 82)
	card.BackgroundColor3 = Color3.fromRGB(22, 28, 44)
	card.BorderSizePixel = 0
	card.Parent = actsContainer
	addCorner(card, 10)
	local st = addStroke(card, Color3.fromRGB(70, 90, 130), 1.5, 0.3)

	local tagLbl = Instance.new("TextLabel")
	tagLbl.Size = UDim2.new(0.65, -12, 0, 18)
	tagLbl.Position = UDim2.fromOffset(12, 6)
	tagLbl.BackgroundTransparency = 1
	tagLbl.Font = Enum.Font.GothamBlack
	tagLbl.Text = spec.tag .. " — " .. string.upper(spec.title)
	tagLbl.TextColor3 = if spec.act == 5 then Color3.fromRGB(255, 200, 55) else Color3.fromRGB(115, 215, 255)
	tagLbl.TextSize = 13
	tagLbl.TextXAlignment = Enum.TextXAlignment.Left
	tagLbl.Parent = card

	local statusBadge = Instance.new("TextLabel")
	statusBadge.Size = UDim2.fromOffset(170, 20)
	statusBadge.Position = UDim2.new(1, -180, 0, 6)
	statusBadge.BackgroundColor3 = Color3.fromRGB(32, 42, 64)
	statusBadge.Font = Enum.Font.GothamBlack
	statusBadge.Text = "REWARD: " .. spec.reward
	statusBadge.TextColor3 = Color3.fromRGB(110, 255, 145)
	statusBadge.TextSize = 11
	statusBadge.Parent = card
	addCorner(statusBadge, 6)

	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.new(1, -24, 0, 28)
	descLbl.Position = UDim2.fromOffset(12, 26)
	descLbl.BackgroundTransparency = 1
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.Text = spec.desc
	descLbl.TextColor3 = Color3.fromRGB(220, 228, 242)
	descLbl.TextSize = 12
	descLbl.TextWrapped = true
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.Parent = card

	local progBg = Instance.new("Frame")
	progBg.Size = UDim2.new(1, -24, 0, 10)
	progBg.Position = UDim2.fromOffset(12, 62)
	progBg.BackgroundColor3 = Color3.fromRGB(12, 15, 24)
	progBg.BorderSizePixel = 0
	progBg.Parent = card
	addCorner(progBg, 5)

	local progFill = Instance.new("Frame")
	progFill.Size = UDim2.fromScale(0, 1)
	progFill.BackgroundColor3 = Color3.fromRGB(50, 225, 115)
	progFill.BorderSizePixel = 0
	progFill.Parent = progBg
	addCorner(progFill, 5)

	actCards[spec.act] = {
		frame = card,
		stroke = st,
		statusBadge = statusBadge,
		progFill = progFill,
	}
end

local function refreshCampaignRoadmapUI()
	local currentAct = math.clamp(tonumber(localPlayer:GetAttribute("CampaignAct")) or 1, 1, 5)
	local completed = localPlayer:GetAttribute("CampaignCompleted") == true
	local prog = tonumber(localPlayer:GetAttribute("CampaignProgress")) or 0
	local goal = math.max(1, tonumber(localPlayer:GetAttribute("CampaignGoal")) or 12)
	local ratio = math.clamp(prog / goal, 0, 1)

	if completed then
		playCampaignBtnLabel.Text = "▶ CONTINUE ENDLESS OVERDRIVE"
	else
		playCampaignBtnLabel.Text = string.format("▶ PLAY CAMPAIGN (ACT %d OF 5)", currentAct)
	end

	for actNum, refs in pairs(actCards) do
		local spec = ROADMAP_SPECS[actNum]
		if completed or actNum < currentAct then
			refs.frame.BackgroundColor3 = Color3.fromRGB(18, 42, 34)
			refs.stroke.Color = Color3.fromRGB(65, 235, 125)
			refs.stroke.Transparency = 0.1
			refs.statusBadge.Text = "✓ COMPLETED (" .. spec.reward .. ")"
			refs.statusBadge.TextColor3 = Color3.fromRGB(120, 255, 155)
			refs.progFill.Size = UDim2.fromScale(1, 1)
		elseif actNum == currentAct then
			refs.frame.BackgroundColor3 = Color3.fromRGB(32, 38, 62)
			refs.stroke.Color = Color3.fromRGB(255, 205, 55)
			refs.stroke.Transparency = 0
			refs.statusBadge.Text = string.format("ACTIVE: %d/%d • %s", math.floor(prog), math.floor(goal), spec.reward)
			refs.statusBadge.TextColor3 = Color3.fromRGB(255, 225, 85)
			refs.progFill.Size = UDim2.fromScale(ratio, 1)
		else
			refs.frame.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
			refs.stroke.Color = Color3.fromRGB(60, 75, 105)
			refs.stroke.Transparency = 0.45
			refs.statusBadge.Text = "REWARD: " .. spec.reward
			refs.statusBadge.TextColor3 = Color3.fromRGB(170, 185, 210)
			refs.progFill.Size = UDim2.fromScale(0, 1)
		end
	end
end

--------------------------------------------------------------------------------
-- 2. FULL SETTINGS MODAL (AUDIO, LIGHTING, DRIVING MODE, CAMERA SHAKE, WAYPOINT)
--------------------------------------------------------------------------------
settingsModal = Instance.new("Frame")
settingsModal.Name = "SettingsModal"
settingsModal.Size = UDim2.fromOffset(660, 510)
settingsModal.Position = UDim2.fromScale(0.5, 0.5)
settingsModal.AnchorPoint = Vector2.new(0.5, 0.5)
settingsModal.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
settingsModal.BackgroundTransparency = 0.04
settingsModal.BorderSizePixel = 0
settingsModal.Visible = false
settingsModal.ZIndex = 30
settingsModal.Parent = screenGui
addCorner(settingsModal, 16)
addStroke(settingsModal, Color3.fromRGB(130, 95, 255), 2.2, 0.1)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -140, 0, 36)
settingsTitle.Position = UDim2.fromOffset(20, 14)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Font = Enum.Font.GothamBlack
settingsTitle.Text = "⚙ GAME SETTINGS • AUDIO, LIGHTING & PHYSICS"
settingsTitle.TextColor3 = Color3.fromRGB(255, 220, 75)
settingsTitle.TextSize = 18
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.ZIndex = 31
settingsTitle.Parent = settingsModal

makeTactile3DButton({
	name = "CloseSettingsBtn",
	title = "✕ CLOSE",
	size = UDim2.fromOffset(104, 38),
	position = UDim2.new(1, -120, 0, 14),
	baseColor = Color3.fromRGB(215, 55, 65),
	parent = settingsModal,
	onClick = function()
		settingsModal.Visible = false
	end,
})

local rowsFrame = Instance.new("Frame")
rowsFrame.Size = UDim2.new(1, -40, 0, 380)
rowsFrame.Position = UDim2.fromOffset(20, 64)
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
	row.Size = UDim2.new(1, 0, 0, 54)
	row.BackgroundColor3 = Color3.fromRGB(22, 28, 44)
	row.BorderSizePixel = 0
	row.ZIndex = 31
	row.Parent = rowsFrame
	addCorner(row, 10)
	addStroke(row, Color3.fromRGB(65, 85, 125), 1.2, 0.3)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.52, -16, 1, 0)
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
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

-- 1. SFX Volume
local sfxPresets = {
	{ label = "🔊 100% (FULL)", val = 1.0 },
	{ label = "🔉 60% (MEDIUM)", val = 0.6 },
	{ label = "🔈 25% (LOW)", val = 0.25 },
	{ label = "🔇 MUTE (0%)", val = 0.0 },
}
local sfxIndex = 1
makeSettingRow(1, "SFX & Impact Volume", sfxPresets[1].label, Color3.fromRGB(42, 138, 225), function(lbl)
	sfxIndex = (sfxIndex % #sfxPresets) + 1
	local p = sfxPresets[sfxIndex]
	localPlayer:SetAttribute("SFXVolume", p.val)
	lbl.Text = p.label
end)

-- 2. Vehicle Engine Sound
makeSettingRow(2, "Vehicle Engine Hum Audio", "ON (ACTIVE)", Color3.fromRGB(38, 175, 95), function(lbl)
	local nextState = not (localPlayer:GetAttribute("EngineSoundEnabled") == true)
	localPlayer:SetAttribute("EngineSoundEnabled", nextState)
	lbl.Text = if nextState then "ON (ACTIVE)" else "OFF (MUTED)"
end)

-- 3. Lighting & Time of Day
local timePresets = {
	{ mode = "Sunny", label = "☀ BRIGHT SUNNY DAY (13:30)", clock = 13.5, bright = 3.6 },
	{ mode = "Sunset", label = "🌅 GOLDEN SUNSET (15:30)", clock = 15.5, bright = 3.35 },
	{ mode = "Night", label = "🌃 NEON NIGHT (00:30)", clock = 0.5, bright = 1.6 },
}
local timeIdx = 1
makeSettingRow(3, "Lighting & Time of Day", timePresets[1].label, Color3.fromRGB(230, 145, 35), function(lbl)
	timeIdx = (timeIdx % #timePresets) + 1
	local tp = timePresets[timeIdx]
	localPlayer:SetAttribute("TimeOfDayPreference", tp.mode)
	Lighting.ClockTime = tp.clock
	Lighting.Brightness = tp.bright
	lbl.Text = tp.label
end)

-- 4. Driving Physics Mode
makeSettingRow(4, "Driving Physics Mode", "⚙ PROGRESSIVE REALISTIC", Color3.fromRGB(125, 78, 220), function(lbl)
	local cur = tostring(localPlayer:GetAttribute("DrivingMode") or "Progressive")
	local nextMode = if cur == "Progressive" then "Arcade" else "Progressive"
	localPlayer:SetAttribute("DrivingMode", nextMode)
	lbl.Text = if nextMode == "Progressive" then "⚙ PROGRESSIVE REALISTIC" else "⚡ ARCADE BOOST (+18%)"
end)

-- 5. Camera Shake
local shakePresets = {
	{ label = "NORMAL (100%)", val = 1.0 },
	{ label = "REDUCED (45%)", val = 0.45 },
	{ label = "OFF (0%)", val = 0.0 },
}
local shakeIdx = 1
makeSettingRow(5, "Impact Camera Shake", shakePresets[1].label, Color3.fromRGB(55, 145, 185), function(lbl)
	shakeIdx = (shakeIdx % #shakePresets) + 1
	local sp = shakePresets[shakeIdx]
	localPlayer:SetAttribute("CameraShakeScale", sp.val)
	lbl.Text = sp.label
end)

-- 6. 3D Waypoint Guide Beam
makeSettingRow(6, "3D Objective Waypoint Beam", "ON (VISIBLE)", Color3.fromRGB(45, 175, 125), function(lbl)
	local nextBeam = not (localPlayer:GetAttribute("ShowWaypointBeam") == true)
	localPlayer:SetAttribute("ShowWaypointBeam", nextBeam)
	lbl.Text = if nextBeam then "ON (VISIBLE)" else "OFF (HIDDEN)"
end)

-- Bottom button in Settings Modal to toggle Home Menu screen
makeTactile3DButton({
	name = "ReturnToHomeMenuBtn",
	title = "🏠 OPEN / CLOSE MAIN HOME SCREEN",
	size = UDim2.new(1, -40, 0, 44),
	position = UDim2.new(0, 20, 1, -56),
	baseColor = Color3.fromRGB(48, 118, 215),
	parent = settingsModal,
	onClick = function()
		settingsModal.Visible = false
		setHomeMenuOpen(not homeRoot.Visible)
	end,
})

--------------------------------------------------------------------------------
-- 3. GRAND FINALE VICTORY CELEBRATION MODAL
--------------------------------------------------------------------------------
local victoryModal = Instance.new("Frame")
victoryModal.Name = "GrandFinaleVictoryModal"
victoryModal.Size = UDim2.fromOffset(640, 360)
victoryModal.Position = UDim2.fromScale(0.5, 0.5)
victoryModal.AnchorPoint = Vector2.new(0.5, 0.5)
victoryModal.BackgroundColor3 = Color3.fromRGB(18, 22, 36)
victoryModal.BorderSizePixel = 0
victoryModal.Visible = false
victoryModal.ZIndex = 40
victoryModal.Parent = screenGui
addCorner(victoryModal, 18)
addStroke(victoryModal, Color3.fromRGB(255, 215, 55), 3, 0)

local vicHeader = Instance.new("TextLabel")
vicHeader.Size = UDim2.new(1, -32, 0, 48)
vicHeader.Position = UDim2.fromOffset(16, 20)
vicHeader.BackgroundTransparency = 1
vicHeader.Font = Enum.Font.GothamBlack
vicHeader.Text = "🏆 LEO CITY LIBERATED! CAMPAIGN COMPLETE! 🏆"
vicHeader.TextColor3 = Color3.fromRGB(255, 220, 65)
vicHeader.TextSize = 22
vicHeader.TextScaled = true
vicHeader.ZIndex = 41
vicHeader.Parent = victoryModal

local vicBody = Instance.new("TextLabel")
vicBody.Size = UDim2.new(1, -48, 0, 140)
vicBody.Position = UDim2.fromOffset(24, 80)
vicBody.BackgroundTransparency = 1
vicBody.Font = Enum.Font.GothamBold
vicBody.Text = "You shattered MegaCorp's lockdown across all 5 Acts and wrecked Mayor Vance's Armored Boss Goliath Convoy on Grand Central Avenue!\n\nCHAMPIONSHIP REWARDS UNLOCKED:\n• +$50,000 GRAND FINALE JACKPOT\n• +5,000 XP & CHAMPION OF LEO CITY STATUS\n• ENDLESS OVERDRIVE FREEPLAY MODE UNLOCKED!"
vicBody.TextColor3 = Color3.fromRGB(235, 245, 255)
vicBody.TextSize = 15
vicBody.TextWrapped = true
vicBody.ZIndex = 41
vicBody.Parent = victoryModal

makeTactile3DButton({
	name = "ContinueOverdriveBtn",
	title = "🔥 CONTINUE IN ENDLESS OVERDRIVE",
	size = UDim2.fromOffset(420, 64),
	position = UDim2.new(0.5, -210, 1, -84),
	baseColor = Color3.fromRGB(35, 195, 95),
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
	if attr == "CampaignAct" or attr == "CampaignProgress" or attr == "CampaignGoal" or attr == "CampaignCompleted" then
		refreshCampaignRoadmapUI()
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
	end
end)

refreshCampaignRoadmapUI()
