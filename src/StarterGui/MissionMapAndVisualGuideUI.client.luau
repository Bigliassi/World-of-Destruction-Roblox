--!strict
--[[
	MissionMapAndVisualGuideUI.client.luau
	World of Destruction (Roblox)

	Kid-Friendly 3D Visual Guide + Self-Explanatory Picture Progress Strip + Interactive Manhattan Map:
	1. 3D Overhead Direction Arrow (`WODKidGuideArrow3D`):
	   - Glowing 3D Gold/Green Pointer Arrow (`WedgePart` arrow head + shaft, `CanCollide = false`, `Anchored = true`)
	     floating 6.5 studs above the player's car/character that smoothly rotates on RenderStepped to point
	     straight toward `ActiveMissionPos` (or toward the Speed Shop when the player can afford a new car).
	2. Self-Explanatory Visual Picture Progress Strip (Zero Reading Required!):
	   - At `UDim2.new(0.5, 0, 0, 96)`, `Size = UDim2.fromOffset(340, 42)`:
	     `[ CAR ] -> [ SMASH (Glowing Progress Dots) ] -> [ +$1,500 / NEW CAR! ]`
	   - Plus a Big Bouncing 3D Viewport Car Button (`150x110`) on the right side when enough Cash is earned:
	     1-click `[ GET NEW CAR! ]` immediately unlocks, equips, and spawns the new car around the player!
	3. Interactive Full-Screen Manhattan Map (M key or MAP & MISSIONS button below Top-Right Minimap):
	   - Visual 2D top-down map of Manhattan showing Snowy Central Park, 5th Avenue & Road Grid, East & West River Harbors,
	     Live Player Car Icon (Yellow), Main Mission (Pulsing Gold Star), and 6 Side Mission / Landmark Pins.
	   - Clicking any pin selects that mission and provides a big green [ GO THERE NOW! ] fast-travel button!
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local VehicleCatalog: any = nil
if Shared then
	local vcMod = Shared:FindFirstChild("VehicleCatalog")
	if vcMod and vcMod:IsA("ModuleScript") then
		local ok, mod = pcall(require, vcMod)
		if ok then
			VehicleCatalog = mod
		end
	end
end

local existingGui = playerGui:FindFirstChild("WODMissionMapAndVisualGuideGui")
if existingGui then
	existingGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "WODMissionMapAndVisualGuideGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 22
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Name = "ResponsiveScale"
uiScale.Scale = 1.0
uiScale.Parent = gui

local function updateResponsiveScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		uiScale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.62, 1.0)
	end
end
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
	updateResponsiveScale()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
		updateResponsiveScale()
	end
end)

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

--------------------------------------------------------------------------------
-- CAR PROGRESSION LADDER (MATCHES GAMEHUD TIER ORDER)
--------------------------------------------------------------------------------
type CarMilestone = {
	id: string,
	name: string,
	cost: number,
	tier: number,
}

local CAR_LADDER: { CarMilestone } = {
	{ id = "Sedan", name = "TIER 2 SEDAN", cost = 1500, tier = 2 },
	{ id = "Muscle", name = "TIER 2 MUSCLE", cost = 4500, tier = 2 },
	{ id = "SUV", name = "TIER 3 SUV", cost = 9000, tier = 3 },
	{ id = "Pickup", name = "TIER 3 PICKUP", cost = 15000, tier = 3 },
	{ id = "Sports", name = "TIER 3 HYPER GT", cost = 28000, tier = 3 },
	{ id = "MonsterTruck", name = "TIER 4 MONSTER", cost = 50000, tier = 4 },
	{ id = "Bulldozer", name = "TIER 5 DOZER", cost = 95000, tier = 5 },
}

local VEHICLE_BASE_TIER: { [string]: number } = {
	Compact = 1,
	Sedan = 2,
	Muscle = 2,
	SUV = 3,
	Pickup = 3,
	Sports = 3,
	MonsterTruck = 4,
	Bulldozer = 5,
}

local function getPlayerCash(): number
	local attr = player:GetAttribute("Cash")
	if typeof(attr) == "number" then
		return attr
	end
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Cash")
	if c and c:IsA("ValueBase") then
		return tonumber(c.Value) or 0
	end
	return 500
end

local function isCarOwned(carId: string, unlockedStr: string, equippedStr: string): boolean
	if carId == "Compact" or equippedStr == carId then
		return true
	end
	if player:GetAttribute("Unlocked_" .. carId) == true then
		return true
	end
	return string.find(unlockedStr, carId, 1, true) ~= nil
end

local function getNextLockedCar(): CarMilestone?
	local unlockedStr = tostring(player:GetAttribute("UnlockedVehicles") or "Compact")
	local equippedStr = tostring(player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle") or "Compact")
	local currentVeh = tostring(player:GetAttribute("CurrentVehicleType") or "")
	local highestTier = math.max(
		tonumber(player:GetAttribute("SmashPowerTier")) or 1,
		VEHICLE_BASE_TIER[equippedStr] or 1,
		VEHICLE_BASE_TIER[currentVeh] or 1
	)
	for _, spec in ipairs(CAR_LADDER) do
		if isCarOwned(spec.id, unlockedStr, equippedStr) and spec.tier > highestTier then
			highestTier = spec.tier
		end
	end
	for _, spec in ipairs(CAR_LADDER) do
		if not isCarOwned(spec.id, unlockedStr, equippedStr) and spec.tier > highestTier then
			return spec
		end
	end
	for _, spec in ipairs(CAR_LADDER) do
		if not isCarOwned(spec.id, unlockedStr, equippedStr) then
			return spec
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- 1. KID-FRIENDLY 3D OVERHEAD DIRECTION ARROW (`WODKidGuideArrow3D`)
--------------------------------------------------------------------------------
local oldArrow = Workspace:FindFirstChild("WODKidGuideArrow3D")
if oldArrow then
	oldArrow:Destroy()
end

local arrowModel = Instance.new("Model")
arrowModel.Name = "WODKidGuideArrow3D"
arrowModel.Parent = Workspace

local arrowShaft = Instance.new("Part")
arrowShaft.Name = "ArrowShaft"
arrowShaft.Size = Vector3.new(1.5, 0.55, 3.6)
arrowShaft.Color = Color3.fromRGB(255, 215, 35)
arrowShaft.Material = Enum.Material.Neon
arrowShaft.Anchored = true
arrowShaft.CanCollide = false
arrowShaft.CanQuery = false
arrowShaft.CanTouch = false
arrowShaft.CastShadow = false
arrowShaft.TopSurface = Enum.SurfaceType.Smooth
arrowShaft.BottomSurface = Enum.SurfaceType.Smooth
arrowShaft.Parent = arrowModel

local arrowHeadLeft = Instance.new("WedgePart")
arrowHeadLeft.Name = "ArrowHeadLeft"
arrowHeadLeft.Size = Vector3.new(0.65, 2.2, 2.6)
arrowHeadLeft.Color = Color3.fromRGB(255, 230, 65)
arrowHeadLeft.Material = Enum.Material.Neon
arrowHeadLeft.Anchored = true
arrowHeadLeft.CanCollide = false
arrowHeadLeft.CanQuery = false
arrowHeadLeft.CanTouch = false
arrowHeadLeft.CastShadow = false
arrowHeadLeft.Parent = arrowModel

local arrowHeadRight = Instance.new("WedgePart")
arrowHeadRight.Name = "ArrowHeadRight"
arrowHeadRight.Size = Vector3.new(0.65, 2.2, 2.6)
arrowHeadRight.Color = Color3.fromRGB(255, 230, 65)
arrowHeadRight.Material = Enum.Material.Neon
arrowHeadRight.Anchored = true
arrowHeadRight.CanCollide = false
arrowHeadRight.CanQuery = false
arrowHeadRight.CanTouch = false
arrowHeadRight.CastShadow = false
arrowHeadRight.Parent = arrowModel

local arrowPointLight = Instance.new("PointLight")
arrowPointLight.Color = Color3.fromRGB(255, 220, 55)
arrowPointLight.Brightness = 2.5
arrowPointLight.Range = 18
arrowPointLight.Parent = arrowShaft

arrowModel.PrimaryPart = arrowShaft

local function setArrowVisible(vis: boolean, tint: Color3)
	local tr = if vis then 0.08 else 1.0
	arrowShaft.Transparency = tr
	arrowHeadLeft.Transparency = tr
	arrowHeadRight.Transparency = tr
	arrowShaft.Color = tint
	arrowHeadLeft.Color = tint
	arrowHeadRight.Color = tint
	arrowPointLight.Enabled = vis
	arrowPointLight.Color = tint
end

--------------------------------------------------------------------------------
-- 2. SELF-EXPLANATORY VISUAL PICTURE PROGRESS STRIP (340x42 at (0.5, 0, 0, 96))
--------------------------------------------------------------------------------
local visualStrip = Instance.new("Frame")
visualStrip.Name = "KidVisualProgressStrip"
visualStrip.Size = UDim2.fromOffset(340, 42)
visualStrip.Position = UDim2.new(0.5, 0, 0, 96)
visualStrip.AnchorPoint = Vector2.new(0.5, 0)
visualStrip.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
visualStrip.BackgroundTransparency = 0.10
visualStrip.BorderSizePixel = 0
visualStrip.Parent = gui
addCorner(visualStrip, 12)
local stripStroke = addStroke(visualStrip, Color3.fromRGB(255, 215, 55), 2.0, 0.12)

-- Left Pill: [ 🚗 -> 🎄 ]
local leftIconPill = Instance.new("TextButton")
leftIconPill.Name = "CarAndLandmarkIconPill"
leftIconPill.Size = UDim2.fromOffset(78, 32)
leftIconPill.Position = UDim2.fromOffset(6, 5)
leftIconPill.BackgroundColor3 = Color3.fromRGB(22, 30, 48)
leftIconPill.BorderSizePixel = 0
leftIconPill.AutoButtonColor = false
leftIconPill.Font = Enum.Font.GothamBlack
leftIconPill.Text = "🚗 ➔ 🎄"
leftIconPill.TextSize = 16
leftIconPill.TextColor3 = Color3.fromRGB(255, 240, 120)
leftIconPill.Parent = visualStrip
addCorner(leftIconPill, 8)
addStroke(leftIconPill, Color3.fromRGB(85, 145, 235), 1.2, 0.25)

-- Center Pill: Visual Progress Dots (🟢🟢🟢⚪⚪)
local centerDotsPill = Instance.new("Frame")
centerDotsPill.Name = "VisualSmashDotsContainer"
centerDotsPill.Size = UDim2.fromOffset(152, 32)
centerDotsPill.Position = UDim2.fromOffset(90, 5)
centerDotsPill.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
centerDotsPill.BorderSizePixel = 0
centerDotsPill.Parent = visualStrip
addCorner(centerDotsPill, 8)
addStroke(centerDotsPill, Color3.fromRGB(70, 95, 145), 1.2, 0.3)

local smashEmojiLbl = Instance.new("TextLabel")
smashEmojiLbl.Name = "TargetEmojiLabel"
smashEmojiLbl.Size = UDim2.fromOffset(26, 32)
smashEmojiLbl.Position = UDim2.fromOffset(4, 0)
smashEmojiLbl.BackgroundTransparency = 1
smashEmojiLbl.Font = Enum.Font.GothamBlack
smashEmojiLbl.Text = "💥"
smashEmojiLbl.TextSize = 16
smashEmojiLbl.TextColor3 = Color3.new(1, 1, 1)
smashEmojiLbl.Parent = centerDotsPill

local dotsHolder = Instance.new("Frame")
dotsHolder.Name = "DotsRow"
dotsHolder.Size = UDim2.fromOffset(118, 24)
dotsHolder.Position = UDim2.fromOffset(30, 4)
dotsHolder.BackgroundTransparency = 1
dotsHolder.Parent = centerDotsPill

local dotsLayout = Instance.new("UIListLayout")
dotsLayout.FillDirection = Enum.FillDirection.Horizontal
dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dotsLayout.Padding = UDim.new(0, 4)
dotsLayout.Parent = dotsHolder

local MAX_VISUAL_DOTS = 8
local progressDotFrames: { { frame: Frame, stroke: UIStroke } } = {}
for i = 1, MAX_VISUAL_DOTS do
	local dot = Instance.new("Frame")
	dot.Name = "ProgressDot_" .. tostring(i)
	dot.Size = UDim2.fromOffset(11, 16)
	dot.BackgroundColor3 = Color3.fromRGB(42, 50, 72)
	dot.BorderSizePixel = 0
	dot.Parent = dotsHolder
	addCorner(dot, 5)
	local dStroke = addStroke(dot, Color3.fromRGB(95, 115, 155), 1.0, 0.35)
	table.insert(progressDotFrames, { frame = dot, stroke = dStroke })
end

-- Right Pill: [ 🏆 +$1,500 ]
local rightRewardPill = Instance.new("TextButton")
rightRewardPill.Name = "VisualRewardPill"
rightRewardPill.Size = UDim2.fromOffset(86, 32)
rightRewardPill.Position = UDim2.fromOffset(248, 5)
rightRewardPill.BackgroundColor3 = Color3.fromRGB(24, 115, 58)
rightRewardPill.BorderSizePixel = 0
rightRewardPill.AutoButtonColor = false
rightRewardPill.Font = Enum.Font.GothamBlack
rightRewardPill.Text = "🏆 +$1,500"
rightRewardPill.TextSize = 12
rightRewardPill.TextColor3 = Color3.fromRGB(165, 255, 185)
rightRewardPill.Parent = visualStrip
addCorner(rightRewardPill, 8)
addStroke(rightRewardPill, Color3.fromRGB(95, 255, 145), 1.3, 0.15)

--------------------------------------------------------------------------------
-- 2B. BIG BOUNCING 3D VIEWPORT CAR UNLOCK BUTTON (150x110 on Right Side)
--------------------------------------------------------------------------------
local instantCarCard = Instance.new("TextButton")
instantCarCard.Name = "InstantUnlock3DCarPopup"
instantCarCard.Size = UDim2.fromOffset(150, 110)
instantCarCard.Position = UDim2.new(1, -14, 0, 228)
instantCarCard.AnchorPoint = Vector2.new(1, 0)
instantCarCard.BackgroundColor3 = Color3.fromRGB(16, 48, 28)
instantCarCard.BorderSizePixel = 0
instantCarCard.AutoButtonColor = false
instantCarCard.Text = ""
instantCarCard.Visible = false
instantCarCard.Parent = gui
addCorner(instantCarCard, 12)
local instantCarStroke = addStroke(instantCarCard, Color3.fromRGB(85, 255, 130), 2.5, 0.05)

local instantViewport = Instance.new("ViewportFrame")
instantViewport.Name = "NewCar3DViewport"
instantViewport.Size = UDim2.new(1, -12, 0, 68)
instantViewport.Position = UDim2.fromOffset(6, 6)
instantViewport.BackgroundColor3 = Color3.fromRGB(12, 22, 34)
instantViewport.Ambient = Color3.fromRGB(195, 210, 235)
instantViewport.LightColor = Color3.fromRGB(255, 248, 225)
instantViewport.LightDirection = Vector3.new(-1, -1.2, -1)
instantViewport.Parent = instantCarCard
addCorner(instantViewport, 8)

local instantVpCam = Instance.new("Camera")
instantVpCam.FieldOfView = 42
instantVpCam.Parent = instantViewport
instantViewport.CurrentCamera = instantVpCam

local instantVpWorld = Instance.new("WorldModel")
instantVpWorld.Parent = instantViewport

local getNewCarBanner = Instance.new("Frame")
getNewCarBanner.Name = "GetNewCarCallToAction"
getNewCarBanner.Size = UDim2.new(1, -12, 0, 28)
getNewCarBanner.Position = UDim2.fromOffset(6, 77)
getNewCarBanner.BackgroundColor3 = Color3.fromRGB(32, 215, 95)
getNewCarBanner.BorderSizePixel = 0
getNewCarBanner.Parent = instantCarCard
addCorner(getNewCarBanner, 7)

local getNewCarLabel = Instance.new("TextLabel")
getNewCarLabel.Name = "GetNewCarText"
getNewCarLabel.Size = UDim2.fromScale(1, 1)
getNewCarLabel.BackgroundTransparency = 1
getNewCarLabel.Font = Enum.Font.GothamBlack
getNewCarLabel.Text = "🚗 GET NEW CAR!"
getNewCarLabel.TextSize = 13
getNewCarLabel.TextColor3 = Color3.fromRGB(12, 24, 16)
getNewCarLabel.Parent = getNewCarBanner

local currentPreviewVehicleId = ""
local activePopupCarModel: Model? = nil

local function updatePopup3DCarPreview(vehicleId: string)
	if currentPreviewVehicleId == vehicleId and activePopupCarModel then
		return
	end
	currentPreviewVehicleId = vehicleId
	if activePopupCarModel then
		activePopupCarModel:Destroy()
		activePopupCarModel = nil
	end
	if VehicleCatalog and VehicleCatalog.BuildVehicle then
		local ok, model = pcall(function()
			return VehicleCatalog.BuildVehicle(vehicleId, { CFrame = CFrame.identity })
		end)
		if ok and model then
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				elseif desc:IsA("ProximityPrompt") then
					desc:Destroy()
				end
			end
			model.Parent = instantVpWorld
			activePopupCarModel = model
		end
	end
end

local function triggerOneClickBuyAndEquipCar()
	local nextCar = getNextLockedCar()
	if not nextCar or getPlayerCash() < nextCar.cost then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local sel = remotes:FindFirstChild("SelectVehicle")
		if sel and sel:IsA("RemoteEvent") then
			sel:FireServer(nextCar.id)
		end
		local spw = remotes:FindFirstChild("SpawnVehicle")
		if spw and spw:IsA("RemoteEvent") then
			spw:FireServer(nextCar.id, true)
		end
	end
end

instantCarCard.MouseButton1Click:Connect(triggerOneClickBuyAndEquipCar)

--------------------------------------------------------------------------------
-- 3. INTERACTIVE FULL-SCREEN MANHATTAN MAP (`[M]` OR `[MAP & MISSIONS [M]]`)
--------------------------------------------------------------------------------
local mapOpenBtn = Instance.new("TextButton")
mapOpenBtn.Name = "OpenManhattanMapButton"
mapOpenBtn.Size = UDim2.fromOffset(150, 28)
mapOpenBtn.Position = UDim2.new(1, -14, 0, 190)
mapOpenBtn.AnchorPoint = Vector2.new(1, 0)
mapOpenBtn.BackgroundColor3 = Color3.fromRGB(22, 34, 58)
mapOpenBtn.BorderSizePixel = 0
mapOpenBtn.AutoButtonColor = false
mapOpenBtn.Font = Enum.Font.GothamBlack
mapOpenBtn.Text = "🗺️ MAP & MISSIONS [M]"
mapOpenBtn.TextSize = 11
mapOpenBtn.TextColor3 = Color3.fromRGB(255, 225, 75)
mapOpenBtn.Parent = gui
addCorner(mapOpenBtn, 8)
addStroke(mapOpenBtn, Color3.fromRGB(255, 205, 55), 1.5, 0.15)

-- Full-Screen Interactive Map Modal
local mapModal = Instance.new("Frame")
mapModal.Name = "InteractiveManhattanMapModal"
mapModal.Size = UDim2.fromOffset(840, 510)
mapModal.Position = UDim2.fromScale(0.5, 0.5)
mapModal.AnchorPoint = Vector2.new(0.5, 0.5)
mapModal.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
mapModal.BackgroundTransparency = 0.03
mapModal.BorderSizePixel = 0
mapModal.Visible = false
mapModal.Parent = gui
addCorner(mapModal, 16)
addStroke(mapModal, Color3.fromRGB(255, 210, 55), 2.2, 0.1)

local mapHeader = Instance.new("Frame")
mapHeader.Name = "MapHeader"
mapHeader.Size = UDim2.new(1, -24, 0, 48)
mapHeader.Position = UDim2.fromOffset(12, 10)
mapHeader.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
mapHeader.BorderSizePixel = 0
mapHeader.Parent = mapModal
addCorner(mapHeader, 10)

local mapTitle = Instance.new("TextLabel")
mapTitle.Size = UDim2.fromOffset(480, 48)
mapTitle.Position = UDim2.fromOffset(16, 0)
mapTitle.BackgroundTransparency = 1
mapTitle.Font = Enum.Font.GothamBlack
mapTitle.Text = "🗺️ MANHATTAN MISSIONS & FAST-TRAVEL MAP"
mapTitle.TextSize = 19
mapTitle.TextColor3 = Color3.fromRGB(255, 230, 85)
mapTitle.TextXAlignment = Enum.TextXAlignment.Left
mapTitle.Parent = mapHeader

local mapCloseBtn = Instance.new("TextButton")
mapCloseBtn.Name = "CloseMapButton"
mapCloseBtn.Size = UDim2.fromOffset(38, 38)
mapCloseBtn.Position = UDim2.new(1, -44, 0, 5)
mapCloseBtn.BackgroundColor3 = Color3.fromRGB(220, 55, 65)
mapCloseBtn.Font = Enum.Font.GothamBlack
mapCloseBtn.Text = "X"
mapCloseBtn.TextSize = 18
mapCloseBtn.TextColor3 = Color3.new(1, 1, 1)
mapCloseBtn.Parent = mapHeader
addCorner(mapCloseBtn, 8)

-- Left Side: 2D Top-Down Manhattan Map Canvas (480x426)
local mapCanvas = Instance.new("Frame")
mapCanvas.Name = "Manhattan2DMapCanvas"
mapCanvas.Size = UDim2.fromOffset(480, 426)
mapCanvas.Position = UDim2.fromOffset(12, 68)
mapCanvas.BackgroundColor3 = Color3.fromRGB(22, 30, 44)
mapCanvas.ClipsDescendants = true
mapCanvas.BorderSizePixel = 0
mapCanvas.Parent = mapModal
addCorner(mapCanvas, 12)
addStroke(mapCanvas, Color3.fromRGB(75, 110, 165), 1.6, 0.2)

-- West River (Hudson) & East River Harbor Water Strips
local westRiver = Instance.new("Frame")
westRiver.Name = "HudsonRiverWest"
westRiver.Size = UDim2.new(0.11, 0, 1, 0)
westRiver.Position = UDim2.fromScale(0, 0)
westRiver.BackgroundColor3 = Color3.fromRGB(20, 62, 108)
westRiver.BorderSizePixel = 0
westRiver.Parent = mapCanvas

local eastRiver = Instance.new("Frame")
eastRiver.Name = "EastRiverHarbor"
eastRiver.Size = UDim2.new(0.14, 0, 1, 0)
eastRiver.Position = UDim2.fromScale(0.86, 0)
eastRiver.BackgroundColor3 = Color3.fromRGB(20, 62, 108)
eastRiver.BorderSizePixel = 0
eastRiver.Parent = mapCanvas

-- Snowy Central Park Region
local centralParkBox = Instance.new("Frame")
centralParkBox.Name = "SnowyCentralParkMapZone"
centralParkBox.Size = UDim2.fromScale(0.28, 0.36)
centralParkBox.Position = UDim2.fromScale(0.16, 0.52)
centralParkBox.BackgroundColor3 = Color3.fromRGB(215, 236, 248)
centralParkBox.BackgroundTransparency = 0.15
centralParkBox.BorderSizePixel = 0
centralParkBox.Parent = mapCanvas
addCorner(centralParkBox, 8)
addStroke(centralParkBox, Color3.fromRGB(95, 215, 155), 1.5, 0.2)

local parkTitle = Instance.new("TextLabel")
parkTitle.Size = UDim2.fromScale(1, 0.25)
parkTitle.Position = UDim2.fromScale(0, 0.04)
parkTitle.BackgroundTransparency = 1
parkTitle.Font = Enum.Font.GothamBlack
parkTitle.Text = "❄️ CENTRAL PARK"
parkTitle.TextSize = 10
parkTitle.TextColor3 = Color3.fromRGB(28, 64, 92)
parkTitle.Parent = centralParkBox

-- Manhattan Road Grid Lines + 5th Avenue Gold-Trimmed Center Avenue
for g = 1, 7 do
	local frac = 0.14 + (g - 1) * 0.115
	local vRoad = Instance.new("Frame")
	vRoad.Size = UDim2.new(0, if g == 4 then 6 else 3, 1, 0)
	vRoad.Position = UDim2.fromScale(frac, 0)
	vRoad.AnchorPoint = Vector2.new(0.5, 0)
	vRoad.BackgroundColor3 = if g == 4 then Color3.fromRGB(65, 78, 102) else Color3.fromRGB(40, 48, 64)
	vRoad.BorderSizePixel = 0
	vRoad.Parent = mapCanvas

	local hRoad = Instance.new("Frame")
	hRoad.Size = UDim2.new(1, 0, 0, if g == 4 then 6 else 3)
	hRoad.Position = UDim2.fromScale(0, frac)
	hRoad.AnchorPoint = Vector2.new(0, 0.5)
	hRoad.BackgroundColor3 = if g == 4 then Color3.fromRGB(65, 78, 102) else Color3.fromRGB(40, 48, 64)
	hRoad.BorderSizePixel = 0
	hRoad.Parent = mapCanvas
end

-- World coordinate (-820..820) -> 2D Map UDim2 helper
local function worldToMapUDim2(worldPos: Vector3): UDim2
	local nx = math.clamp(0.48 + (worldPos.X / 1650), 0.07, 0.93)
	local nz = math.clamp(0.50 + (worldPos.Z / 1650), 0.08, 0.92)
	return UDim2.fromScale(nx, nz)
end

-- Right Side: Selected Mission Card + Big Green `[ GO THERE NOW! ]` Button (324x426)
local rightPanel = Instance.new("Frame")
rightPanel.Name = "SelectedMissionPanel"
rightPanel.Size = UDim2.fromOffset(324, 426)
rightPanel.Position = UDim2.fromOffset(504, 68)
rightPanel.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
rightPanel.BorderSizePixel = 0
rightPanel.Parent = mapModal
addCorner(rightPanel, 12)
local rightPanelStroke = addStroke(rightPanel, Color3.fromRGB(85, 165, 255), 1.6, 0.2)

local selectedEmojiBig = Instance.new("TextLabel")
selectedEmojiBig.Name = "SelectedBigEmoji"
selectedEmojiBig.Size = UDim2.new(1, -20, 0, 56)
selectedEmojiBig.Position = UDim2.fromOffset(10, 12)
selectedEmojiBig.BackgroundTransparency = 1
selectedEmojiBig.Font = Enum.Font.GothamBlack
selectedEmojiBig.Text = "🎄 ➔ 💥🎁 ➔ 💰"
selectedEmojiBig.TextSize = 30
selectedEmojiBig.TextColor3 = Color3.fromRGB(255, 235, 95)
selectedEmojiBig.Parent = rightPanel

local selectedTitleLbl = Instance.new("TextLabel")
selectedTitleLbl.Name = "SelectedMissionTitle"
selectedTitleLbl.Size = UDim2.new(1, -20, 0, 26)
selectedTitleLbl.Position = UDim2.fromOffset(10, 70)
selectedTitleLbl.BackgroundTransparency = 1
selectedTitleLbl.Font = Enum.Font.GothamBlack
selectedTitleLbl.Text = "CHRISTMAS PARTY CRASH"
selectedTitleLbl.TextSize = 16
selectedTitleLbl.TextColor3 = Color3.new(1, 1, 1)
selectedTitleLbl.TextScaled = true
selectedTitleLbl.Parent = rightPanel

local selectedRewardLbl = Instance.new("TextLabel")
selectedRewardLbl.Name = "SelectedMissionReward"
selectedRewardLbl.Size = UDim2.new(1, -20, 0, 24)
selectedRewardLbl.Position = UDim2.fromOffset(10, 98)
selectedRewardLbl.BackgroundTransparency = 1
selectedRewardLbl.Font = Enum.Font.GothamBlack
selectedRewardLbl.Text = "🏆 REWARD: +$1,500 CASH!"
selectedRewardLbl.TextSize = 15
selectedRewardLbl.TextColor3 = Color3.fromRGB(95, 255, 140)
selectedRewardLbl.Parent = rightPanel

local goThereNowBtn = Instance.new("TextButton")
goThereNowBtn.Name = "GoThereNowFastTravelBtn"
goThereNowBtn.Size = UDim2.new(1, -24, 0, 54)
goThereNowBtn.Position = UDim2.fromOffset(12, 130)
goThereNowBtn.BackgroundColor3 = Color3.fromRGB(32, 215, 95)
goThereNowBtn.BorderSizePixel = 0
goThereNowBtn.Font = Enum.Font.GothamBlack
goThereNowBtn.Text = "🚀 GO THERE NOW!"
goThereNowBtn.TextSize = 20
goThereNowBtn.TextColor3 = Color3.fromRGB(10, 24, 14)
goThereNowBtn.Parent = rightPanel
addCorner(goThereNowBtn, 12)
addStroke(goThereNowBtn, Color3.fromRGB(185, 255, 205), 2.0, 0.1)

-- Quick-Pick Landmark List inside Right Panel
local pinListScroll = Instance.new("ScrollingFrame")
pinListScroll.Name = "LandmarkQuickPickList"
pinListScroll.Size = UDim2.new(1, -20, 0, 220)
pinListScroll.Position = UDim2.fromOffset(10, 196)
pinListScroll.BackgroundTransparency = 1
pinListScroll.BorderSizePixel = 0
pinListScroll.ScrollBarThickness = 5
pinListScroll.CanvasSize = UDim2.fromOffset(0, 7 * 36)
pinListScroll.Parent = rightPanel

local pinListLayout = Instance.new("UIListLayout")
pinListLayout.Padding = UDim.new(0, 5)
pinListLayout.Parent = pinListScroll

type MapPinSpec = {
	id: string,
	label: string,
	emoji: string,
	targetEmoji: string,
	pos: Vector3,
	reward: number,
	color: Color3,
}

local LANDMARK_PINS: { MapPinSpec } = {
	{ id = "Side_ChristmasMarket", label = "CHRISTMAS PARTY", emoji = "🎄", targetEmoji = "🎁", pos = Vector3.new(-36, 0, 18), reward = 1500, color = Color3.fromRGB(65, 235, 115) },
	{ id = "Side_ConcertStage", label = "CONCERT STAGE", emoji = "🎸", targetEmoji = "🔊", pos = Vector3.new(0, 0, -180), reward = 3000, color = Color3.fromRGB(255, 85, 220) },
	{ id = "Side_GoldBank", label = "WALL ST BANK", emoji = "🏦", targetEmoji = "💰", pos = Vector3.new(180, 0, 0), reward = 6000, color = Color3.fromRGB(255, 215, 55) },
	{ id = "Side_UniversitySchool", label = "SCHOOL & UNI", emoji = "🎓", targetEmoji = "📚", pos = Vector3.new(-360, 0, 0), reward = 10000, color = Color3.fromRGB(70, 185, 255) },
	{ id = "Side_CityHospital", label = "CITY HOSPITAL", emoji = "🏥", targetEmoji = "🚑", pos = Vector3.new(-180, 0, -180), reward = 16000, color = Color3.fromRGB(255, 75, 85) },
	{ id = "Side_HarborBoats", label = "HARBOR & BOATS", emoji = "🚢", targetEmoji = "⚓", pos = Vector3.new(720, 0, 0), reward = 25000, color = Color3.fromRGB(55, 215, 255) },
	{ id = "Main_7_CentralParkFinale", label = "CENTRAL PARK", emoji = "🏆", targetEmoji = "⭐", pos = Vector3.new(-180, 0, 180), reward = 50000, color = Color3.fromRGB(255, 200, 45) },
}

local selectedPinSpec: MapPinSpec = LANDMARK_PINS[1]
local mapPinButtons: { [string]: { btn: TextButton, stroke: UIStroke } } = {}

local function selectLandmarkPin(spec: MapPinSpec, fireRemote: boolean)
	selectedPinSpec = spec
	selectedEmojiBig.Text = string.format("%s ➔ 💥%s ➔ 💰", spec.emoji, spec.targetEmoji)
	selectedTitleLbl.Text = spec.label
	selectedRewardLbl.Text = string.format("🏆 REWARD: +$%s CASH!", formatNumber(spec.reward))
	rightPanelStroke.Color = spec.color

	for id, ui in pairs(mapPinButtons) do
		local isSel = (id == spec.id)
		ui.stroke.Thickness = if isSel then 2.6 else 1.4
		ui.stroke.Color = if isSel then Color3.new(1, 1, 1) else spec.color
	end

	if fireRemote then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local selRemote = remotes and remotes:FindFirstChild("SelectMission")
		if selRemote and selRemote:IsA("RemoteEvent") then
			selRemote:FireServer(spec.id)
		end
	end
end

for _, spec in ipairs(LANDMARK_PINS) do
	-- Pin on 2D Map Canvas
	local pinBtn = Instance.new("TextButton")
	pinBtn.Name = "MapPin_" .. spec.id
	pinBtn.Size = UDim2.fromOffset(108, 30)
	pinBtn.Position = worldToMapUDim2(spec.pos)
	pinBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	pinBtn.BackgroundColor3 = Color3.fromRGB(16, 22, 36)
	pinBtn.BorderSizePixel = 0
	pinBtn.Font = Enum.Font.GothamBlack
	pinBtn.Text = spec.emoji .. " " .. spec.label
	pinBtn.TextSize = 10
	pinBtn.TextColor3 = spec.color
	pinBtn.ZIndex = 4
	pinBtn.Parent = mapCanvas
	addCorner(pinBtn, 8)
	local pStroke = addStroke(pinBtn, spec.color, 1.5, 0.1)
	mapPinButtons[spec.id] = { btn = pinBtn, stroke = pStroke }

	pinBtn.MouseButton1Click:Connect(function()
		selectLandmarkPin(spec, true)
	end)

	-- Quick-Pick Row in Right Panel
	local rowBtn = Instance.new("TextButton")
	rowBtn.Name = "QuickRow_" .. spec.id
	rowBtn.Size = UDim2.new(1, -6, 0, 31)
	rowBtn.BackgroundColor3 = Color3.fromRGB(24, 32, 50)
	rowBtn.BorderSizePixel = 0
	rowBtn.Font = Enum.Font.GothamBlack
	rowBtn.Text = string.format("  %s  %s   (+$%s)", spec.emoji, spec.label, formatNumber(spec.reward))
	rowBtn.TextSize = 11
	rowBtn.TextColor3 = spec.color
	rowBtn.TextXAlignment = Enum.TextXAlignment.Left
	rowBtn.Parent = pinListScroll
	addCorner(rowBtn, 7)

	rowBtn.MouseButton1Click:Connect(function()
		selectLandmarkPin(spec, true)
	end)
end

-- Pulsing Gold Star Pin for Active Main Mission on 2D Map
local activeMainMapPin = Instance.new("TextLabel")
activeMainMapPin.Name = "ActiveMainMissionStarPin"
activeMainMapPin.Size = UDim2.fromOffset(30, 30)
activeMainMapPin.Position = worldToMapUDim2(Vector3.new(-36, 0, 18))
activeMainMapPin.AnchorPoint = Vector2.new(0.5, 0.5)
activeMainMapPin.BackgroundColor3 = Color3.fromRGB(255, 215, 35)
activeMainMapPin.Font = Enum.Font.GothamBlack
activeMainMapPin.Text = "⭐"
activeMainMapPin.TextSize = 17
activeMainMapPin.TextColor3 = Color3.fromRGB(20, 24, 32)
activeMainMapPin.ZIndex = 6
activeMainMapPin.Parent = mapCanvas
addCorner(activeMainMapPin, 15)
addStroke(activeMainMapPin, Color3.new(1, 1, 1), 2.0, 0)

-- Live Player Car Icon (Yellow) on 2D Map
local playerMapPin = Instance.new("TextLabel")
playerMapPin.Name = "LivePlayerCarMapPin"
playerMapPin.Size = UDim2.fromOffset(32, 32)
playerMapPin.Position = UDim2.fromScale(0.48, 0.50)
playerMapPin.AnchorPoint = Vector2.new(0.5, 0.5)
playerMapPin.BackgroundColor3 = Color3.fromRGB(255, 235, 55)
playerMapPin.Font = Enum.Font.GothamBlack
playerMapPin.Text = "🚗"
playerMapPin.TextSize = 17
playerMapPin.TextColor3 = Color3.fromRGB(16, 20, 28)
playerMapPin.ZIndex = 8
playerMapPin.Parent = mapCanvas
addCorner(playerMapPin, 16)
addStroke(playerMapPin, Color3.new(1, 1, 1), 2.2, 0)

local function toggleManhattanMap(openState: boolean?)
	local nextOpen = if openState ~= nil then openState else not mapModal.Visible
	mapModal.Visible = nextOpen
end

mapOpenBtn.MouseButton1Click:Connect(function()
	toggleManhattanMap(nil)
end)
leftIconPill.MouseButton1Click:Connect(function()
	toggleManhattanMap(true)
end)
rightRewardPill.MouseButton1Click:Connect(function()
	toggleManhattanMap(true)
end)
mapCloseBtn.MouseButton1Click:Connect(function()
	toggleManhattanMap(false)
end)

goThereNowBtn.MouseButton1Click:Connect(function()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local tpRemote = remotes and remotes:FindFirstChild("TeleportToMission")
	if tpRemote and tpRemote:IsA("RemoteEvent") then
		tpRemote:FireServer(selectedPinSpec.id)
	end
	toggleManhattanMap(false)
end)

-- Bind `[M]` key via ContextActionService at high priority so `[M]` always opens/closes the Manhattan Map
ContextActionService:BindActionAtPriority(
	"WODToggleManhattanMissionMap",
	function(_actionName: string, inputState: Enum.UserInputState, _inputObj: InputObject)
		if inputState == Enum.UserInputState.Begin then
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			toggleManhattanMap(nil)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end,
	false,
	3000,
	Enum.KeyCode.M
)

--------------------------------------------------------------------------------
-- 4. REFRESH VISUAL PICTURE STRIP & 3D ARROW LOOP
--------------------------------------------------------------------------------
local function refreshVisualProgressStrip()
	local homeActive = (player:GetAttribute("HomeMenuActive") == true)
	gui.Enabled = not homeActive

	local iconEmoji = tostring(player:GetAttribute("ActiveMissionIcon") or "🎄")
	local targetEmoji = tostring(player:GetAttribute("ActiveMissionTargetEmoji") or "🎁")
	local progress = math.max(0, math.floor(tonumber(player:GetAttribute("ActiveMissionProgress")) or 0))
	local goal = math.max(1, math.floor(tonumber(player:GetAttribute("ActiveMissionGoal")) or 8))
	local reward = math.max(500, math.floor(tonumber(player:GetAttribute("ActiveMissionReward")) or 1500))
	local mColorAttr = player:GetAttribute("ActiveMissionColor")
	local mColor = if typeof(mColorAttr) == "Color3" then mColorAttr else Color3.fromRGB(255, 215, 55)

	leftIconPill.Text = "🚗 ➔ " .. iconEmoji
	smashEmojiLbl.Text = "💥" .. targetEmoji
	stripStroke.Color = mColor

	local litDots = math.clamp(math.round((progress / goal) * MAX_VISUAL_DOTS), 0, MAX_VISUAL_DOTS)
	if progress > 0 and litDots == 0 then
		litDots = 1
	end
	for i, dotEntry in ipairs(progressDotFrames) do
		local isLit = (i <= litDots)
		dotEntry.frame.BackgroundColor3 = if isLit then Color3.fromRGB(45, 240, 105) else Color3.fromRGB(42, 50, 72)
		dotEntry.stroke.Color = if isLit then Color3.fromRGB(165, 255, 195) else Color3.fromRGB(95, 115, 155)
	end

	local nextCar = getNextLockedCar()
	local cash = getPlayerCash()
	if nextCar and cash >= nextCar.cost then
		rightRewardPill.Text = "🚗 NEW CAR!"
		rightRewardPill.BackgroundColor3 = Color3.fromRGB(28, 205, 90)
		instantCarCard.Visible = true
		getNewCarLabel.Text = "🚗 GET " .. nextCar.name .. "!"
		updatePopup3DCarPreview(nextCar.id)
	else
		rightRewardPill.Text = "🏆 +$" .. formatNumber(reward)
		rightRewardPill.BackgroundColor3 = Color3.fromRGB(24, 115, 58)
		instantCarCard.Visible = false
	end
end

player.AttributeChanged:Connect(refreshVisualProgressStrip)

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return
	end
	local stateRemote = remotes:FindFirstChild("MissionStateUpdated")
	if stateRemote and stateRemote:IsA("RemoteEvent") then
		stateRemote.OnClientEvent:Connect(function(payload: any)
			refreshVisualProgressStrip()
			if type(payload) == "table" and type(payload.CompletedMission) == "table" then
				TweenService:Create(
					visualStrip,
					TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
					{ Size = UDim2.fromOffset(368, 48) }
				):Play()
			end
		end)
	end
end)

selectLandmarkPin(LANDMARK_PINS[1], false)
refreshVisualProgressStrip()

local animClock = 0
RunService.RenderStepped:Connect(function(dt: number)
	animClock += dt
	local homeActive = (player:GetAttribute("HomeMenuActive") == true)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Rotate 3D Viewport car inside the 1-Click Instant Car Popup
	if instantCarCard.Visible and activePopupCarModel then
		local yaw = math.rad((animClock * 42) % 360)
		local dist = 16.5
		local camPos = Vector3.new(math.sin(yaw) * dist, 5.5, -math.cos(yaw) * dist)
		instantVpCam.CFrame = CFrame.lookAt(camPos, Vector3.new(0, 0.8, 0))

		local bounce = math.sin(animClock * 5.0) * 3
		instantCarCard.Position = UDim2.new(1, -14, 0, 228 + bounce)
		local pulse = (math.sin(animClock * 6.0) + 1) * 0.5
		getNewCarBanner.BackgroundColor3 = Color3.fromRGB(
			math.floor(25 + pulse * 55),
			math.floor(205 + pulse * 50),
			math.floor(85 + pulse * 45)
		)
	end

	-- Update 2D Map Live Pins when Map is open
	local activePosAttr = player:GetAttribute("ActiveMissionPos")
	local targetWorldPos = if typeof(activePosAttr) == "Vector3" then activePosAttr else Vector3.new(-36, 0, 18)

	if mapModal.Visible then
		activeMainMapPin.Position = worldToMapUDim2(targetWorldPos)
		local starPulse = math.floor(28 + (math.sin(animClock * 5) + 1) * 3)
		activeMainMapPin.Size = UDim2.fromOffset(starPulse, starPulse)
		if root then
			playerMapPin.Position = worldToMapUDim2(root.Position)
		end
	end

	-- Update 3D Overhead Guide Arrow (`WODKidGuideArrow3D`) floating 6.5 studs above player's car/character
	if not root or homeActive then
		setArrowVisible(false, Color3.fromRGB(255, 215, 35))
		return
	end

	local nextCar = getNextLockedCar()
	local canBuyCar = (nextCar ~= nil and getPlayerCash() >= nextCar.cost)
	local arrowColor = if canBuyCar
		then Color3.fromRGB(55, 255, 115)
		else (typeof(player:GetAttribute("ActiveMissionColor")) == "Color3" and (player:GetAttribute("ActiveMissionColor") :: Color3) or Color3.fromRGB(255, 215, 35))

	setArrowVisible(true, arrowColor)

	local flatFrom = Vector3.new(root.Position.X, 0, root.Position.Z)
	local flatTo = Vector3.new(targetWorldPos.X, 0, targetWorldPos.Z)
	local dir = flatTo - flatFrom
	if dir.Magnitude < 1.0 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end

	local bobOffset = math.sin(animClock * 4.2) * 0.45
	local hoverOrigin = root.Position + Vector3.new(0, 6.5 + bobOffset, 0)
	local baseCF = CFrame.lookAt(hoverOrigin, hoverOrigin + dir)

	arrowShaft.CFrame = baseCF * CFrame.new(0, 0, 0.8)
	arrowHeadLeft.CFrame = baseCF * CFrame.new(-0.55, 0, -1.8) * CFrame.Angles(0, 0, math.rad(90))
	arrowHeadRight.CFrame = baseCF * CFrame.new(0.55, 0, -1.8) * CFrame.Angles(0, 0, math.rad(-90))
end)
