--!strict
-- CharacterCreatorAndWardrobeUI.client.luau
-- In-Game Character Creator ("CREATE YOUR WRECKER") & Wardrobe UI ([C] key / HUD dock button / Boutique Kiosk)
-- Supports Free Starters, Destruction Cash items, and Paid Robux items + VIP Mega Bundle with 3D Viewport preview.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarCatalog = require(Shared:WaitForChild("AvatarCatalog"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local getAvatarWardrobeRF = Remotes:WaitForChild("GetAvatarWardrobe") :: RemoteFunction
local equipAvatarItemRF = Remotes:WaitForChild("EquipAvatarItem") :: RemoteFunction
local purchaseAvatarItemRF = Remotes:WaitForChild("PurchaseAvatarItem") :: RemoteFunction
local applyCharacterPresetRE = Remotes:WaitForChild("ApplyCharacterPreset") :: RemoteEvent
local avatarUpdatedRE = Remotes:WaitForChild("AvatarUpdated") :: RemoteEvent
local openAvatarEditorRE = Remotes:WaitForChild("OpenAvatarEditor") :: RemoteEvent

local currentLoadout: AvatarCatalog.AvatarLoadout = AvatarCatalog.GetDefaultLoadout()
local unlockedItems: { [string]: boolean } = {}
local activeCategory = "Presets"
local showOnStartup = false
local previewYaw = 22
local previewModel: Model? = nil

local existingGui = playerGui:FindFirstChild("CharacterCreatorAndWardrobeUI")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharacterCreatorAndWardrobeUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 28
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Full Modal Backdrop
local backdrop = Instance.new("Frame")
backdrop.Name = "CreatorModal"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(6, 10, 19)
backdrop.BackgroundTransparency = 0.22
backdrop.Visible = false
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UDim2.fromOffset(920, 560)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
panel.Parent = backdrop
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(56, 189, 248)
panelStroke.Thickness = 2

-- Dynamic UIScale on MainPanel so the modal never clips off the edges of the Studio window
local panelScale = Instance.new("UIScale")
panelScale.Name = "ModalAutoScale"
panelScale.Scale = 1.0
panelScale.Parent = panel

local camScaleConn: RBXScriptConnection? = nil
local function updatePanelScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		panelScale.Scale = math.clamp(math.min(vp.X / 980, vp.Y / 620), 0.58, 1.0)
	end
end

local function bindCameraViewport()
	if camScaleConn then
		camScaleConn:Disconnect()
		camScaleConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		camScaleConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelScale)
		updatePanelScale()
	end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
bindCameraViewport()

-- Header Bar
local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(0.55, 0, 0, 44)
headerTitle.Position = UDim2.fromOffset(22, 10)
headerTitle.BackgroundTransparency = 1
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Font = Enum.Font.GothamBlack
headerTitle.TextSize = 24
headerTitle.TextColor3 = Color3.fromRGB(250, 204, 21)
headerTitle.Text = "CREATE YOUR WRECKER — AVATAR & GEAR SHOP"
headerTitle.Parent = panel

local statusBanner = Instance.new("TextLabel")
statusBanner.Size = UDim2.new(0.55, 0, 0, 20)
statusBanner.Position = UDim2.fromOffset(22, 48)
statusBanner.BackgroundTransparency = 1
statusBanner.TextXAlignment = Enum.TextXAlignment.Left
statusBanner.Font = Enum.Font.GothamBold
statusBanner.TextSize = 13
statusBanner.TextColor3 = Color3.fromRGB(125, 211, 252)
statusBanner.Text = "Mix Free Starters, Destruction Cash Gear, and VIP Robux Armor!"
statusBanner.Parent = panel

-- VIP Robux Mega Bundle Top Banner
local vipBtn = Instance.new("TextButton")
vipBtn.Name = "VIPBundleBanner"
vipBtn.Size = UDim2.fromOffset(315, 48)
vipBtn.Position = UDim2.new(1, -385, 0, 14)
vipBtn.BackgroundColor3 = Color3.fromRGB(234, 179, 8)
vipBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
vipBtn.Font = Enum.Font.GothamBlack
vipBtn.TextSize = 13
vipBtn.Text = "UNLOCK ALL ROBUX + CASH GEAR\nVIP MEGA BUNDLE — 599 R$"
vipBtn.Parent = panel
Instance.new("UICorner", vipBtn).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(44, 44)
closeBtn.Position = UDim2.new(1, -58, 0, 16)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 18
closeBtn.Text = "X"
closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

-- Left Column: 3D Viewport Character Preview
local previewCard = Instance.new("Frame")
previewCard.Size = UDim2.fromOffset(290, 465)
previewCard.Position = UDim2.fromOffset(20, 76)
previewCard.BackgroundColor3 = Color3.fromRGB(9, 14, 26)
previewCard.Parent = panel
Instance.new("UICorner", previewCard).CornerRadius = UDim.new(0, 12)

local viewport = Instance.new("ViewportFrame")
viewport.Size = UDim2.new(1, -16, 0, 305)
viewport.Position = UDim2.fromOffset(8, 8)
viewport.BackgroundColor3 = Color3.fromRGB(17, 24, 39)
viewport.Ambient = Color3.fromRGB(190, 200, 220)
viewport.LightColor = Color3.fromRGB(255, 250, 235)
viewport.LightDirection = Vector3.new(-1, -1, 1)
viewport.Parent = previewCard
Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 10)

local vpCam = Instance.new("Camera")
vpCam.Parent = viewport
viewport.CurrentCamera = vpCam

local vpWorld = Instance.new("WorldModel")
vpWorld.Parent = viewport

local rotLeftBtn = Instance.new("TextButton")
rotLeftBtn.Size = UDim2.fromOffset(44, 32)
rotLeftBtn.Position = UDim2.fromOffset(14, 272)
rotLeftBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
rotLeftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
rotLeftBtn.Font = Enum.Font.GothamBlack
rotLeftBtn.TextSize = 16
rotLeftBtn.Text = "<"
rotLeftBtn.Parent = previewCard
Instance.new("UICorner", rotLeftBtn).CornerRadius = UDim.new(0, 6)

local randBtn = Instance.new("TextButton")
randBtn.Size = UDim2.fromOffset(156, 32)
randBtn.Position = UDim2.fromOffset(67, 272)
randBtn.BackgroundColor3 = Color3.fromRGB(79, 70, 229)
randBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
randBtn.Font = Enum.Font.GothamBold
randBtn.TextSize = 13
randBtn.Text = "RANDOMIZE LOOK"
randBtn.Parent = previewCard
Instance.new("UICorner", randBtn).CornerRadius = UDim.new(0, 6)

local rotRightBtn = Instance.new("TextButton")
rotRightBtn.Size = UDim2.fromOffset(44, 32)
rotRightBtn.Position = UDim2.fromOffset(232, 272)
rotRightBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
rotRightBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
rotRightBtn.Font = Enum.Font.GothamBlack
rotRightBtn.TextSize = 16
rotRightBtn.Text = ">"
rotRightBtn.Parent = previewCard
Instance.new("UICorner", rotRightBtn).CornerRadius = UDim.new(0, 6)

local perksLabel = Instance.new("TextLabel")
perksLabel.Size = UDim2.new(1, -20, 0, 42)
perksLabel.Position = UDim2.fromOffset(10, 320)
perksLabel.BackgroundTransparency = 1
perksLabel.Font = Enum.Font.GothamBold
perksLabel.TextSize = 12
perksLabel.TextColor3 = Color3.fromRGB(74, 222, 128)
perksLabel.TextWrapped = true
perksLabel.Text = "Active Perks: Base Stats"
perksLabel.Parent = previewCard

local startupToggleBtn = Instance.new("TextButton")
startupToggleBtn.Size = UDim2.new(1, -24, 0, 28)
startupToggleBtn.Position = UDim2.fromOffset(12, 366)
startupToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
startupToggleBtn.TextColor3 = Color3.fromRGB(203, 213, 225)
startupToggleBtn.Font = Enum.Font.GothamBold
startupToggleBtn.TextSize = 12
startupToggleBtn.Text = "[ ] Show Creator on Startup"
startupToggleBtn.Parent = previewCard
Instance.new("UICorner", startupToggleBtn).CornerRadius = UDim.new(0, 6)

local playBtn = Instance.new("TextButton")
playBtn.Size = UDim2.new(1, -24, 0, 52)
playBtn.Position = UDim2.fromOffset(12, 401)
playBtn.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
playBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
playBtn.Font = Enum.Font.GothamBlack
playBtn.TextSize = 16
playBtn.Text = "SAVE & START SMASHING! [PLAY]"
playBtn.Parent = previewCard
Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 10)

-- Right Column: Category Tabs + Item Grid
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.fromOffset(576, 40)
tabBar.Position = UDim2.fromOffset(324, 76)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)

local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Size = UDim2.fromOffset(576, 414)
gridScroll.Position = UDim2.fromOffset(324, 126)
gridScroll.BackgroundColor3 = Color3.fromRGB(9, 14, 26)
gridScroll.BorderSizePixel = 0
gridScroll.ScrollBarThickness = 6
gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
gridScroll.Parent = panel
Instance.new("UICorner", gridScroll).CornerRadius = UDim.new(0, 12)

local gridPadding = Instance.new("UIPadding", gridScroll)
gridPadding.PaddingTop = UDim.new(0, 12)
gridPadding.PaddingLeft = UDim.new(0, 12)
gridPadding.PaddingRight = UDim.new(0, 12)
gridPadding.PaddingBottom = UDim.new(0, 12)

local gridLayout = Instance.new("UIGridLayout", gridScroll)
gridLayout.CellSize = UDim2.fromOffset(176, 178)
gridLayout.CellPadding = UDim2.fromOffset(10, 10)

local function updateViewportCamera()
	local focusPos = Vector3.new(0, 0.25, 0)
	if previewModel then
		local torso = (previewModel:FindFirstChild("UpperTorso") or previewModel:FindFirstChild("Torso") or previewModel:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if torso then
			focusPos = torso.Position + Vector3.new(0, 0.1, 0)
		end
	end
	local rad = math.rad(previewYaw)
	-- Character faces -Z at CFrame.new(0, 0, 0), so position camera on the -Z side facing the front
	local camPos = focusPos + Vector3.new(math.sin(rad) * 6.2, 0.7, -math.cos(rad) * 6.2)
	vpCam.CFrame = CFrame.lookAt(camPos, focusPos)
end

local function buildR15FallbackMannequin(): Model
	local m = Instance.new("Model")
	m.Name = "PreviewWrecker"

	local function makePart(name: string, size: Vector3, cf: CFrame, meshType: Enum.MeshType?, meshScale: Vector3?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = m
		if meshType then
			local sm = Instance.new("SpecialMesh")
			sm.MeshType = meshType
			if meshScale then
				sm.Scale = meshScale
			end
			sm.Parent = p
		end
		return p
	end

	local hrp = makePart("HumanoidRootPart", Vector3.new(1.6, 1.6, 0.8), CFrame.new(0, 0, 0), nil, nil)
	hrp.Transparency = 1

	-- Articulated R15 Torso & Rounded Head
	local upperTorso = makePart("UpperTorso", Vector3.new(1.65, 1.25, 0.85), CFrame.new(0, 0.35, 0), Enum.MeshType.Brick, Vector3.new(0.98, 0.98, 0.96))
	makePart("LowerTorso", Vector3.new(1.5, 0.65, 0.8), CFrame.new(0, -0.58, 0), Enum.MeshType.Brick, Vector3.new(0.96, 0.96, 0.94))

	local head = makePart("Head", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, 1.58, 0), Enum.MeshType.Head, Vector3.new(1.25, 1.25, 1.25))
	-- Subtle facial features on front (-Z) of Head
	local leftEye = makePart("LeftEye", Vector3.new(0.12, 0.16, 0.06), CFrame.new(-0.2, 1.64, -0.56), Enum.MeshType.Sphere, nil)
	leftEye.Color = Color3.fromRGB(20, 24, 34)
	local rightEye = makePart("RightEye", Vector3.new(0.12, 0.16, 0.06), CFrame.new(0.2, 1.64, -0.56), Enum.MeshType.Sphere, nil)
	rightEye.Color = Color3.fromRGB(20, 24, 34)

	-- Articulated Left Arm (UpperArm, LowerArm, Hand)
	makePart("LeftUpperArm", Vector3.new(0.62, 0.9, 0.62), CFrame.new(-1.18, 0.42, 0) * CFrame.Angles(0, 0, math.rad(6)), Enum.MeshType.Brick, Vector3.new(0.95, 0.98, 0.95))
	makePart("LeftLowerArm", Vector3.new(0.56, 0.82, 0.56), CFrame.new(-1.24, -0.38, -0.06) * CFrame.Angles(math.rad(12), 0, math.rad(4)), Enum.MeshType.Brick, Vector3.new(0.94, 0.98, 0.94))
	makePart("LeftHand", Vector3.new(0.54, 0.4, 0.54), CFrame.new(-1.26, -0.94, -0.14), Enum.MeshType.Head, Vector3.new(1.05, 1.0, 1.05))

	-- Articulated Right Arm (UpperArm, LowerArm, Hand)
	makePart("RightUpperArm", Vector3.new(0.62, 0.9, 0.62), CFrame.new(1.18, 0.42, 0) * CFrame.Angles(0, 0, math.rad(-6)), Enum.MeshType.Brick, Vector3.new(0.95, 0.98, 0.95))
	makePart("RightLowerArm", Vector3.new(0.56, 0.82, 0.56), CFrame.new(1.24, -0.38, -0.06) * CFrame.Angles(math.rad(12), 0, math.rad(-4)), Enum.MeshType.Brick, Vector3.new(0.94, 0.98, 0.94))
	makePart("RightHand", Vector3.new(0.54, 0.4, 0.54), CFrame.new(1.26, -0.94, -0.14) * CFrame.Angles(math.rad(-25), 0, 0), Enum.MeshType.Head, Vector3.new(1.05, 1.0, 1.05))

	-- Articulated Left & Right Legs + Boots
	makePart("LeftUpperLeg", Vector3.new(0.7, 0.95, 0.7), CFrame.new(-0.44, -1.35, 0), Enum.MeshType.Brick, Vector3.new(0.96, 0.98, 0.96))
	makePart("LeftLowerLeg", Vector3.new(0.64, 0.92, 0.64), CFrame.new(-0.44, -2.22, 0), Enum.MeshType.Brick, Vector3.new(0.95, 0.98, 0.95))
	makePart("LeftFoot", Vector3.new(0.68, 0.34, 0.92), CFrame.new(-0.44, -2.8, -0.12), Enum.MeshType.Brick, Vector3.new(0.96, 0.94, 0.96))

	makePart("RightUpperLeg", Vector3.new(0.7, 0.95, 0.7), CFrame.new(0.44, -1.35, 0), Enum.MeshType.Brick, Vector3.new(0.96, 0.98, 0.96))
	makePart("RightLowerLeg", Vector3.new(0.64, 0.92, 0.64), CFrame.new(0.44, -2.22, 0), Enum.MeshType.Brick, Vector3.new(0.95, 0.98, 0.95))
	makePart("RightFoot", Vector3.new(0.68, 0.34, 0.92), CFrame.new(0.44, -2.8, -0.12), Enum.MeshType.Brick, Vector3.new(0.96, 0.94, 0.96))

	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = m

	m.PrimaryPart = hrp or upperTorso or head
	return m
end

local function rebuildPreviewModel()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end

	local m: Model? = nil
	local liveChar = player.Character
	if liveChar and (liveChar:FindFirstChild("HumanoidRootPart") or liveChar:FindFirstChild("UpperTorso") or liveChar:FindFirstChild("Torso")) then
		local ok, cloned = pcall(function()
			liveChar.Archivable = true
			return liveChar:Clone()
		end)
		if ok and cloned then
			for _, desc in ipairs(cloned:GetDescendants()) do
				if desc:IsA("BaseScript") or desc:IsA("ProximityPrompt") or desc:IsA("ForceField") or desc:IsA("BillboardGui") or desc:IsA("Sound") then
					desc:Destroy()
				elseif desc:IsA("Humanoid") then
					desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
			end
			local root = (cloned:FindFirstChild("HumanoidRootPart") or cloned:FindFirstChild("UpperTorso") or cloned:FindFirstChild("Torso")) :: BasePart?
			if root then
				cloned.PrimaryPart = root
			end
			cloned:PivotTo(CFrame.new(0, 0, 0))
			m = cloned
		end
	end

	if not m then
		m = buildR15FallbackMannequin()
		m:PivotTo(CFrame.new(0, 0, 0))
	end

	m.Name = "PreviewWrecker"
	m.Parent = vpWorld

	AvatarCatalog.ApplyLoadoutToCharacter(m, currentLoadout)

	-- Keep all parts anchored inside the ViewportFrame
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	previewModel = m
	updateViewportCamera()

	local perks = AvatarCatalog.ComputePerks(currentLoadout)
	perksLabel.Text = string.format(
		"Perks: Cash x%.2f | XP x%.2f | Speed x%.2f | Chaos x%.2f",
		perks.CashMult,
		perks.XPMult,
		perks.SprintMult,
		perks.ChaosMult
	)
end

local renderCategoryGrid: () -> ()

local tabButtons: { [string]: TextButton } = {}
for _, cat in ipairs(AvatarCatalog.Categories) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(76, 36)
	b.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
	b.TextColor3 = Color3.fromRGB(226, 232, 240)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = cat.Label
	b.Parent = tabBar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	tabButtons[cat.Id] = b
	b.MouseButton1Click:Connect(function()
		activeCategory = cat.Id
		renderCategoryGrid()
	end)
end

renderCategoryGrid = function()
	for id, btn in pairs(tabButtons) do
		local selected = (id == activeCategory)
		btn.BackgroundColor3 = selected and Color3.fromRGB(56, 189, 248) or Color3.fromRGB(30, 41, 59)
		btn.TextColor3 = selected and Color3.fromRGB(15, 23, 42) or Color3.fromRGB(226, 232, 240)
	end

	for _, child in ipairs(gridScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if activeCategory == "Presets" then
		for _, preset in ipairs(AvatarCatalog.Presets) do
			local card = Instance.new("Frame")
			card.BackgroundColor3 = Color3.fromRGB(22, 32, 54)
			card.Parent = gridScroll
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.new(1, -16, 0, 22)
			badge.Position = UDim2.fromOffset(8, 8)
			badge.BackgroundTransparency = 1
			badge.Font = Enum.Font.GothamBlack
			badge.TextSize = 11
			badge.TextColor3 = Color3.fromRGB(250, 204, 21)
			badge.Text = preset.Badge
			badge.Parent = card

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -16, 0, 38)
			nameLbl.Position = UDim2.fromOffset(8, 36)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.GothamBlack
			nameLbl.TextSize = 16
			nameLbl.TextWrapped = true
			nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLbl.Text = preset.Name
			nameLbl.Parent = card

			local applyBtn = Instance.new("TextButton")
			applyBtn.Size = UDim2.new(1, -20, 0, 38)
			applyBtn.Position = UDim2.fromOffset(10, 126)
			applyBtn.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
			applyBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
			applyBtn.Font = Enum.Font.GothamBlack
			applyBtn.TextSize = 13
			applyBtn.Text = "APPLY PRESET"
			applyBtn.Parent = card
			Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

			applyBtn.MouseButton1Click:Connect(function()
				applyCharacterPresetRE:FireServer(preset.Id)
				statusBanner.Text = "Applied Preset: " .. preset.Name .. " (Unlocked pieces equipped!)"
			end)
		end
		return
	end

	local items = AvatarCatalog.GetItemsByCategory(activeCategory)
	for _, item in ipairs(items) do
		local isOwned = unlockedItems[item.Id] or item.Currency == "Free"
		local isEquipped = ((currentLoadout :: any)[item.Category] == item.Id)

		local card = Instance.new("Frame")
		card.BackgroundColor3 = Color3.fromRGB(22, 32, 54)
		card.Parent = gridScroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(1, -20, 0, 36)
		swatch.Position = UDim2.fromOffset(10, 10)
		swatch.BackgroundColor3 = item.PrimaryColor
		swatch.Parent = card
		Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 6)

		local accentDot = Instance.new("Frame")
		accentDot.Size = UDim2.fromOffset(28, 22)
		accentDot.Position = UDim2.new(1, -34, 0.5, -11)
		accentDot.BackgroundColor3 = item.AccentColor
		accentDot.Parent = swatch
		Instance.new("UICorner", accentDot).CornerRadius = UDim.new(0, 4)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -16, 0, 34)
		title.Position = UDim2.fromOffset(8, 50)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 13
		title.TextWrapped = true
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.Text = item.Name
		title.Parent = card

		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -16, 0, 36)
		desc.Position = UDim2.fromOffset(8, 84)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.GothamMedium
		desc.TextSize = 11
		desc.TextWrapped = true
		desc.TextColor3 = item.PerkLabel and Color3.fromRGB(250, 204, 21) or Color3.fromRGB(148, 163, 184)
		desc.Text = item.PerkLabel or item.Description
		desc.Parent = card

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(1, -16, 0, 36)
		actionBtn.Position = UDim2.fromOffset(8, 132)
		actionBtn.Font = Enum.Font.GothamBlack
		actionBtn.TextSize = 12
		actionBtn.Parent = card
		Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 8)

		if isEquipped then
			actionBtn.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
			actionBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
			actionBtn.Text = "EQUIPPED"
		elseif isOwned then
			actionBtn.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
			actionBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
			actionBtn.Text = (item.Currency == "Free") and "FREE • EQUIP" or "OWNED • EQUIP"
		elseif item.Currency == "Cash" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
			actionBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
			actionBtn.Text = string.format("BUY $%d CASH", item.Price)
		else
			actionBtn.BackgroundColor3 = Color3.fromRGB(250, 204, 21)
			actionBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
			actionBtn.Text = string.format("BUY %d R$ ROBUX", item.Price)
		end

		actionBtn.MouseButton1Click:Connect(function()
			local res = isOwned and equipAvatarItemRF:InvokeServer(item.Id) or purchaseAvatarItemRF:InvokeServer(item.Id)
			if res and res.Message then
				statusBanner.Text = res.Message
			end
		end)
	end
end

local function toggleEditor(forceState: boolean?)
	local nextVisible = if forceState ~= nil then forceState else not backdrop.Visible
	backdrop.Visible = nextVisible
	if nextVisible then
		updatePanelScale()
		rebuildPreviewModel()
		renderCategoryGrid()
	end
end

rotLeftBtn.MouseButton1Click:Connect(function()
	previewYaw -= 30
	updateViewportCamera()
end)

rotRightBtn.MouseButton1Click:Connect(function()
	previewYaw += 30
	updateViewportCamera()
end)

randBtn.MouseButton1Click:Connect(function()
	local randomPreset = AvatarCatalog.Presets[math.random(1, #AvatarCatalog.Presets)]
	applyCharacterPresetRE:FireServer(randomPreset.Id)
	statusBanner.Text = "Randomized Look: " .. randomPreset.Name
end)

vipBtn.MouseButton1Click:Connect(function()
	local res = purchaseAvatarItemRF:InvokeServer(AvatarCatalog.VIPAvatarMegaBundle.Id)
	if res and res.Message then
		statusBanner.Text = res.Message
	end
end)

startupToggleBtn.MouseButton1Click:Connect(function()
	showOnStartup = not showOnStartup
	startupToggleBtn.Text = showOnStartup and "[✓] Show Creator on Startup" or "[ ] Show Creator on Startup"
end)

closeBtn.MouseButton1Click:Connect(function()
	applyCharacterPresetRE:FireServer("MarkCustomized")
	toggleEditor(false)
end)

playBtn.MouseButton1Click:Connect(function()
	applyCharacterPresetRE:FireServer("MarkCustomized")
	toggleEditor(false)
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
		toggleEditor()
	end
end)

player:GetAttributeChangedSignal("ToggleAvatarUI"):Connect(function()
	toggleEditor()
end)

openAvatarEditorRE.OnClientEvent:Connect(function()
	toggleEditor(true)
end)

avatarUpdatedRE.OnClientEvent:Connect(function(payload)
	if payload.Loadout then
		currentLoadout = payload.Loadout
	end
	if payload.Unlocked then
		unlockedItems = payload.Unlocked
	end
	if backdrop.Visible then
		rebuildPreviewModel()
		renderCategoryGrid()
	end
end)

player.CharacterAdded:Connect(function()
	if backdrop.Visible then
		task.defer(rebuildPreviewModel)
	end
end)

task.spawn(function()
	local ok, data = pcall(function()
		return getAvatarWardrobeRF:InvokeServer()
	end)
	if ok and data then
		currentLoadout = data.Loadout or currentLoadout
		unlockedItems = data.Unlocked or unlockedItems
		renderCategoryGrid()
		if showOnStartup and not data.HasCustomized then
			toggleEditor(true)
		end
	end
end)
