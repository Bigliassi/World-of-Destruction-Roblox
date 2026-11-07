--!strict
-- SpeedShopUI.client.luau
-- Visual 3D Speed Shop & Garage Modal with Clear Smash Tier Purpose & Minimal Text:
-- - Left Side: 8 Vehicle Cards with bold SMASH POWER TIER BADGES (TIER 1 -> TIER 5) or 5 Ultra-Simple Upgrade Rows
-- - Right Side: Large rotating 3D ViewportFrame Showroom (`Vehicle3DViewport`) that renders
--   `VehicleCatalog.BuildVehicle(selectedVehicleId, currentUpgrades)` and highlights the 3D upgrade parts
--   (`Plow`, `Engine`, `Armor`, `Nitro`, `Magnet`) directly on the 3D car as you click, hover, or upgrade them!

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VehicleCatalog = require(Shared:WaitForChild("VehicleCatalog"))

local existingShop = playerGui:FindFirstChild("WorldOfDestructionShopGui")
if existingShop then
	existingShop:Destroy()
end

type VehicleClassInfo = {
	id: string,
	name: string,
	price: number,
	speed: number,
	handling: number,
	armor: number,
	ram: number,
	tierBadge: string,
	tierColor: Color3,
}

type UpgradeTrackInfo = {
	id: string,
	shortName: string,
	iconTag: string,
	benefitTag: string,
	baseCost: number,
	color: Color3,
}

local VEHICLE_CLASSES: { VehicleClassInfo } = {
	{
		id = "Compact",
		name = "SPARK COMPACT",
		price = 0,
		speed = 0.55,
		handling = 0.88,
		armor = 0.40,
		ram = 0.35,
		tierBadge = "TIER 1 • SMASH CRATES & CARTS",
		tierColor = Color3.fromRGB(65, 205, 255),
	},
	{
		id = "Sedan",
		name = "CRUISER V8 SEDAN",
		price = 1500,
		speed = 0.65,
		handling = 0.78,
		armor = 0.55,
		ram = 0.50,
		tierBadge = "TIER 2 • SMASH GOLD ATMs & TAXIS",
		tierColor = Color3.fromRGB(75, 235, 130),
	},
	{
		id = "Muscle",
		name = "HELLFIRE MUSCLE",
		price = 4500,
		speed = 0.82,
		handling = 0.68,
		armor = 0.65,
		ram = 0.72,
		tierBadge = "TIER 2+ • DRIFT & SMASH HYDRANTS",
		tierColor = Color3.fromRGB(110, 245, 150),
	},
	{
		id = "SUV",
		name = "TITAN 4X4 SUV",
		price = 9000,
		speed = 0.70,
		handling = 0.65,
		armor = 0.82,
		ram = 0.80,
		tierBadge = "TIER 3 • SMASH ARMORED CASH TRUCKS",
		tierColor = Color3.fromRGB(255, 200, 50),
	},
	{
		id = "Pickup",
		name = "RANCH RAMMER 4X4",
		price = 15000,
		speed = 0.74,
		handling = 0.64,
		armor = 0.85,
		ram = 0.86,
		tierBadge = "TIER 3+ • RAM GAS STATIONS & COPS",
		tierColor = Color3.fromRGB(255, 175, 45),
	},
	{
		id = "Sports",
		name = "APEX HYPER GT",
		price = 28000,
		speed = 0.98,
		handling = 0.94,
		armor = 0.58,
		ram = 0.65,
		tierBadge = "TIER 3 MAX • 200 MPH HYPER SPEED",
		tierColor = Color3.fromRGB(255, 150, 40),
	},
	{
		id = "MonsterTruck",
		name = "CRUSHER XL 6X6",
		price = 50000,
		speed = 0.78,
		handling = 0.60,
		armor = 0.94,
		ram = 0.96,
		tierBadge = "TIER 4 • CRUSH BUSES & SWAT TRUCKS",
		tierColor = Color3.fromRGB(255, 105, 45),
	},
	{
		id = "Bulldozer",
		name = "GOLIATH BULLDOZER",
		price = 95000,
		speed = 0.58,
		handling = 0.52,
		armor = 1.00,
		ram = 1.00,
		tierBadge = "TIER 5 • BREAK GOLDEN BANK VAULTS",
		tierColor = Color3.fromRGB(255, 65, 85),
	},
}

local UPGRADE_TRACKS: { UpgradeTrackInfo } = {
	{ id = "Plow", shortName = "PLOW", iconTag = "3D PLOW", benefitTag = "+1 SMASH TIER", baseCost = 400, color = Color3.fromRGB(255, 75, 85) },
	{ id = "Engine", shortName = "ENGINE", iconTag = "3D TURBO", benefitTag = "+TOP SPEED", baseCost = 400, color = Color3.fromRGB(255, 130, 50) },
	{ id = "Armor", shortName = "ARMOR", iconTag = "3D CAGE", benefitTag = "+MAX ARMOR", baseCost = 400, color = Color3.fromRGB(75, 225, 125) },
	{ id = "Nitro", shortName = "NITRO", iconTag = "3D NOS", benefitTag = "+NITRO BOOST", baseCost = 400, color = Color3.fromRGB(55, 185, 255) },
	{ id = "Magnet", shortName = "MAGNET", iconTag = "3D COIL", benefitTag = "+2X CASH", baseCost = 400, color = Color3.fromRGB(255, 215, 65) },
}

local UPGRADE_COSTS = { 400, 900, 1800, 3200, 5500 }

local unlockedVehicles: { [string]: boolean } = { Compact = true }
local selectedVehicleId: string = tostring(player:GetAttribute("SelectedVehicle") or player:GetAttribute("EquippedVehicle") or "Compact")
local previewTrackHighlight: string? = nil

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

local gui = Instance.new("ScreenGui")
gui.Name = "WorldOfDestructionShopGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 26
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0.22
	s.Parent = parent
	return s
end

local modal = Instance.new("Frame")
modal.Name = "SpeedShopModal"
modal.Size = UDim2.fromOffset(880, 520)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
modal.BackgroundTransparency = 0.04
modal.BorderSizePixel = 0
modal.Visible = false
modal.Parent = gui
addCorner(modal, 14)
addStroke(modal, Color3.fromRGB(65, 165, 255), 2)

local modalScale = Instance.new("UIScale")
modalScale.Name = "ResponsiveScale"
modalScale.Parent = modal

local function updateModalScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		modalScale.Scale = math.clamp(math.min(vp.X / 940, vp.Y / 580), 0.58, 1.0)
	end
end

if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateModalScale)
	updateModalScale()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateModalScale)
		updateModalScale()
	end
end)

-- Header Bar
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, -24, 0, 50)
header.Position = UDim2.fromOffset(12, 10)
header.BackgroundColor3 = Color3.fromRGB(22, 28, 42)
header.BorderSizePixel = 0
header.Parent = modal
addCorner(header, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.fromOffset(340, 50)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = "GARAGE & SMASH TIERS"
titleLabel.TextSize = 21
titleLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local statusBanner = Instance.new("TextLabel")
statusBanner.Size = UDim2.fromOffset(360, 50)
statusBanner.Position = UDim2.new(1, -415, 0, 0)
statusBanner.BackgroundTransparency = 1
statusBanner.Font = Enum.Font.GothamBlack
statusBanner.Text = "HIGHER SMASH TIER = BIGGER TARGETS!"
statusBanner.TextSize = 13
statusBanner.TextColor3 = Color3.fromRGB(255, 215, 65)
statusBanner.TextXAlignment = Enum.TextXAlignment.Right
statusBanner.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.fromOffset(38, 38)
closeBtn.Position = UDim2.new(1, -45, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(215, 60, 65)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.Text = "X"
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Parent = header
addCorner(closeBtn, 8)

-- Tab Bar (Left Side)
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 38)
tabBar.Position = UDim2.fromOffset(12, 66)
tabBar.BackgroundTransparency = 1
tabBar.Parent = modal

local vehiclesTabBtn = Instance.new("TextButton")
vehiclesTabBtn.Name = "VehiclesTabBtn"
vehiclesTabBtn.Size = UDim2.fromOffset(244, 36)
vehiclesTabBtn.Position = UDim2.fromOffset(0, 0)
vehiclesTabBtn.BackgroundColor3 = Color3.fromRGB(45, 130, 235)
vehiclesTabBtn.Font = Enum.Font.GothamBlack
vehiclesTabBtn.Text = "CARS (TIER 1 -> TIER 5)"
vehiclesTabBtn.TextSize = 14
vehiclesTabBtn.TextColor3 = Color3.new(1, 1, 1)
vehiclesTabBtn.Parent = tabBar
addCorner(vehiclesTabBtn, 8)

local upgradesTabBtn = Instance.new("TextButton")
upgradesTabBtn.Name = "UpgradesTabBtn"
upgradesTabBtn.Size = UDim2.fromOffset(244, 36)
upgradesTabBtn.Position = UDim2.fromOffset(254, 0)
upgradesTabBtn.BackgroundColor3 = Color3.fromRGB(32, 38, 54)
upgradesTabBtn.Font = Enum.Font.GothamBlack
upgradesTabBtn.Text = "3D UPGRADES (5 PARTS)"
upgradesTabBtn.TextSize = 14
upgradesTabBtn.TextColor3 = Color3.fromRGB(185, 195, 215)
upgradesTabBtn.Parent = tabBar
addCorner(upgradesTabBtn, 8)

-- ==========================================
-- LEFT SIDE CONTENT CONTAINERS (500px wide)
-- ==========================================
local vehiclesPage = Instance.new("Frame")
vehiclesPage.Name = "VehiclesPage"
vehiclesPage.Size = UDim2.fromOffset(500, 396)
vehiclesPage.Position = UDim2.fromOffset(12, 110)
vehiclesPage.BackgroundTransparency = 1
vehiclesPage.Parent = modal

local upgradesPage = Instance.new("Frame")
upgradesPage.Name = "UpgradesPage"
upgradesPage.Size = UDim2.fromOffset(500, 396)
upgradesPage.Position = UDim2.fromOffset(12, 110)
upgradesPage.BackgroundTransparency = 1
upgradesPage.Visible = false
upgradesPage.Parent = modal

-- ==========================================
-- RIGHT SIDE: LARGE ROTATING 3D VIEWPORT SHOWROOM (`Vehicle3DViewport`)
-- ==========================================
local showroomCard = Instance.new("Frame")
showroomCard.Name = "Showroom3DCard"
showroomCard.Size = UDim2.fromOffset(344, 396)
showroomCard.Position = UDim2.fromOffset(524, 110)
showroomCard.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
showroomCard.BorderSizePixel = 0
showroomCard.Parent = modal
addCorner(showroomCard, 12)
local showroomStroke = addStroke(showroomCard, Color3.fromRGB(56, 189, 248), 1.6)

local viewport = Instance.new("ViewportFrame")
viewport.Name = "Vehicle3DViewport"
viewport.Size = UDim2.new(1, -16, 0, 194)
viewport.Position = UDim2.fromOffset(8, 8)
viewport.BackgroundColor3 = Color3.fromRGB(16, 22, 36)
viewport.Ambient = Color3.fromRGB(185, 198, 222)
viewport.LightColor = Color3.fromRGB(255, 248, 232)
viewport.LightDirection = Vector3.new(-1, -1.2, -1)
viewport.Parent = showroomCard
addCorner(viewport, 10)

local vpCam = Instance.new("Camera")
vpCam.FieldOfView = 42
vpCam.Parent = viewport
viewport.CurrentCamera = vpCam

local vpWorld = Instance.new("WorldModel")
vpWorld.Parent = viewport

local previewCarTitle = Instance.new("TextLabel")
previewCarTitle.Name = "PreviewCarTitle"
previewCarTitle.Size = UDim2.new(1, -20, 0, 22)
previewCarTitle.Position = UDim2.fromOffset(10, 206)
previewCarTitle.BackgroundTransparency = 1
previewCarTitle.Font = Enum.Font.GothamBlack
previewCarTitle.TextSize = 17
previewCarTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
previewCarTitle.TextXAlignment = Enum.TextXAlignment.Left
previewCarTitle.Parent = showroomCard

-- Bold SMASH POWER TIER BADGE on 3D Showroom
local showroomTierPill = Instance.new("Frame")
showroomTierPill.Name = "SmashTierShowroomBadge"
showroomTierPill.Size = UDim2.new(1, -20, 0, 24)
showroomTierPill.Position = UDim2.fromOffset(10, 230)
showroomTierPill.BackgroundColor3 = Color3.fromRGB(30, 42, 68)
showroomTierPill.BorderSizePixel = 0
showroomTierPill.Parent = showroomCard
addCorner(showroomTierPill, 6)
local showroomTierStroke = addStroke(showroomTierPill, Color3.fromRGB(255, 200, 50), 1.4)

local showroomTierText = Instance.new("TextLabel")
showroomTierText.Name = "TierText"
showroomTierText.Size = UDim2.new(1, -12, 1, 0)
showroomTierText.Position = UDim2.fromOffset(6, 0)
showroomTierText.BackgroundTransparency = 1
showroomTierText.Font = Enum.Font.GothamBlack
showroomTierText.Text = "TIER 1 • SMASH CRATES & CARTS"
showroomTierText.TextSize = 11
showroomTierText.TextColor3 = Color3.fromRGB(255, 220, 65)
showroomTierText.TextXAlignment = Enum.TextXAlignment.Center
showroomTierText.Parent = showroomTierPill

local previewPartsBadge = Instance.new("TextLabel")
previewPartsBadge.Name = "PreviewPartsBadge"
previewPartsBadge.Size = UDim2.new(1, -20, 0, 16)
previewPartsBadge.Position = UDim2.fromOffset(10, 256)
previewPartsBadge.BackgroundTransparency = 1
previewPartsBadge.Font = Enum.Font.GothamBold
previewPartsBadge.TextSize = 10
previewPartsBadge.TextColor3 = Color3.fromRGB(115, 225, 255)
previewPartsBadge.TextXAlignment = Enum.TextXAlignment.Left
previewPartsBadge.Text = "3D PARTS: STOCK"
previewPartsBadge.Parent = showroomCard

local statBars: { [string]: Frame } = {}
local statDefs = {
	{ key = "speed", label = "TOP SPEED", color = Color3.fromRGB(65, 190, 255) },
	{ key = "handling", label = "HANDLING", color = Color3.fromRGB(120, 245, 140) },
	{ key = "armor", label = "ARMOR", color = Color3.fromRGB(255, 195, 60) },
	{ key = "ram", label = "SMASH POWER", color = Color3.fromRGB(255, 85, 75) },
}

for idx, st in ipairs(statDefs) do
	local yPos = 274 + (idx - 1) * 16
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromOffset(92, 14)
	lbl.Position = UDim2.fromOffset(10, yPos)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = st.label
	lbl.TextSize = 10
	lbl.TextColor3 = Color3.fromRGB(205, 218, 238)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = showroomCard

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -114, 0, 8)
	barBg.Position = UDim2.fromOffset(104, yPos + 3)
	barBg.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
	barBg.BorderSizePixel = 0
	barBg.Parent = showroomCard
	addCorner(barBg, 4)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0.5, 1)
	barFill.BackgroundColor3 = st.color
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	addCorner(barFill, 4)
	statBars[st.key] = barFill
end

local actionBtn = Instance.new("TextButton")
actionBtn.Name = "ActionBtn"
actionBtn.Size = UDim2.new(1, -20, 0, 42)
actionBtn.Position = UDim2.new(0, 10, 1, -48)
actionBtn.BackgroundColor3 = Color3.fromRGB(45, 180, 95)
actionBtn.Font = Enum.Font.GothamBlack
actionBtn.Text = "EQUIP & SPAWN"
actionBtn.TextSize = 15
actionBtn.TextColor3 = Color3.new(1, 1, 1)
actionBtn.Parent = showroomCard
addCorner(actionBtn, 10)

-- ==========================================
-- REMOTE & STATE HELPERS
-- ==========================================
local function getPlayerCash(): number
	local c = player:GetAttribute("Cash")
	if typeof(c) == "number" then
		return c
	end
	local ls = player:FindFirstChild("leaderstats")
	local val = ls and ls:FindFirstChild("Cash")
	if val and val:IsA("ValueBase") then
		return tonumber(val.Value) or 0
	end
	return 0
end

local function getUpgradeLevel(trackId: string): number
	local attr = player:GetAttribute(trackId .. "Level") or player:GetAttribute("Upgrade_" .. trackId)
	return math.clamp(tonumber(attr) or 1, 1, 5)
end

local function callRemote(names: { string }, ...: any): (boolean, any)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return false, nil
	end
	for _, name in ipairs(names) do
		local r = remotes:FindFirstChild(name)
		if r then
			if r:IsA("RemoteFunction") then
				local ok, res = pcall(function(...)
					return r:InvokeServer(...)
				end, ...)
				return ok, res
			elseif r:IsA("RemoteEvent") then
				r:FireServer(...)
				return true, true
			end
		end
	end
	return false, nil
end

local function isVehicleUnlocked(classId: string): boolean
	if classId == "Compact" or unlockedVehicles[classId] then
		return true
	end
	local attrStr = tostring(player:GetAttribute("UnlockedVehicles") or "")
	if string.find(attrStr, classId, 1, true) then
		unlockedVehicles[classId] = true
		return true
	end
	return false
end

-- ==========================================
-- 3D VIEWPORT CAR + 3D UPGRADE PART HIGHLIGHTER
-- ==========================================
local currentFocusedClass: VehicleClassInfo = VEHICLE_CLASSES[1]
local activePreviewModel: Model? = nil
local turntableYaw = 28.0

local TRACK_PART_PREFIXES: { [string]: { string } } = {
	Plow = { "Plow", "BulldozerBlade" },
	Engine = { "EngineSupercharger", "EngineIntake", "Supercharger", "Blower" },
	Armor = { "ArmorSideBar", "ArmorRoofCage" },
	Nitro = { "NitroBottle", "NitroGlowBand" },
	Magnet = { "MagnetPedestal", "MagnetGoldCoil" },
}

local TRACK_HIGHLIGHT_COLORS: { [string]: Color3 } = {
	Plow = Color3.fromRGB(255, 75, 85),
	Engine = Color3.fromRGB(255, 145, 45),
	Armor = Color3.fromRGB(75, 255, 135),
	Nitro = Color3.fromRGB(65, 215, 255),
	Magnet = Color3.fromRGB(255, 225, 55),
}

local function highlight3DUpgradePartOnModel(carModel: Model, trackId: string)
	local prefixes = TRACK_PART_PREFIXES[trackId]
	local hColor = TRACK_HIGHLIGHT_COLORS[trackId] or Color3.fromRGB(255, 220, 65)
	if not prefixes then
		return
	end

	for _, desc in ipairs(carModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			local matched = false
			for _, pre in ipairs(prefixes) do
				if string.find(desc.Name, pre, 1, true) ~= nil or (desc.Parent and string.find(desc.Parent.Name, pre, 1, true) ~= nil) then
					matched = true
					break
				end
			end
			if matched then
				desc.Material = Enum.Material.Neon
				desc.Color = hColor
				local sel = Instance.new("SelectionBox")
				sel.Name = "UpgradePartHighlightBox"
				sel.Adornee = desc
				sel.Color3 = hColor
				sel.LineThickness = 0.08
				sel.SurfaceColor3 = hColor
				sel.SurfaceTransparency = 0.55
				sel.Parent = desc
			end
		end
	end
end

local function rebuild3DShowroomCar()
	if activePreviewModel then
		activePreviewModel:Destroy()
		activePreviewModel = nil
	end

	local engSteps = math.max(0, getUpgradeLevel("Engine") - 1)
	local armSteps = math.max(0, getUpgradeLevel("Armor") - 1)
	local nitSteps = math.max(0, getUpgradeLevel("Nitro") - 1)
	local plwSteps = math.max(0, getUpgradeLevel("Plow") - 1)
	local magSteps = math.max(0, getUpgradeLevel("Magnet") - 1)

	if previewTrackHighlight == "Engine" then
		engSteps = math.max(engSteps, 3)
	elseif previewTrackHighlight == "Armor" then
		armSteps = math.max(armSteps, 3)
	elseif previewTrackHighlight == "Nitro" then
		nitSteps = math.max(nitSteps, 3)
	elseif previewTrackHighlight == "Plow" then
		plwSteps = math.max(plwSteps, 3)
	elseif previewTrackHighlight == "Magnet" then
		magSteps = math.max(magSteps, 3)
	end

	local currentUpgrades = {
		CFrame = CFrame.new(0, 0, 0),
		EngineLevel = engSteps,
		ArmorLevel = armSteps,
		NitroLevel = nitSteps,
		PlowLevel = plwSteps,
		MagnetLevel = magSteps,
	}

	local carModel = VehicleCatalog.BuildVehicle(currentFocusedClass.id, currentUpgrades :: any)

	for _, desc in ipairs(carModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		elseif desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end

	if previewTrackHighlight then
		highlight3DUpgradePartOnModel(carModel, previewTrackHighlight)
	end

	local pedestal = Instance.new("Part")
	pedestal.Name = "ShowroomTurntable"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(0.4, 21, 21)
	pedestal.CFrame = CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Color = Color3.fromRGB(22, 30, 48)
	pedestal.Material = Enum.Material.Metal
	pedestal.Anchored = true
	pedestal.CanCollide = false
	pedestal.Parent = carModel

	carModel.Parent = vpWorld
	activePreviewModel = carModel

	if previewTrackHighlight then
		previewPartsBadge.Text = "HIGHLIGHTING 3D PART: " .. string.upper(previewTrackHighlight)
		previewPartsBadge.TextColor3 = TRACK_HIGHLIGHT_COLORS[previewTrackHighlight] or Color3.fromRGB(255, 220, 65)
	else
		local activePartsList = {}
		if plwSteps > 0 or currentFocusedClass.id == "Bulldozer" then
			table.insert(activePartsList, "PLOW")
		end
		if engSteps > 0 then
			table.insert(activePartsList, "ENGINE")
		end
		if armSteps > 0 then
			table.insert(activePartsList, "ARMOR")
		end
		if nitSteps > 0 then
			table.insert(activePartsList, "NITRO")
		end
		if magSteps > 0 then
			table.insert(activePartsList, "MAGNET")
		end

		if #activePartsList > 0 then
			previewPartsBadge.Text = "3D PARTS: " .. table.concat(activePartsList, " + ")
		else
			previewPartsBadge.Text = "3D PARTS: STOCK"
		end
		previewPartsBadge.TextColor3 = Color3.fromRGB(115, 225, 255)
	end
end

-- ==========================================
-- 1. VEHICLES TAB UI (Bold Smash Tier Badges, Zero Long Sentences)
-- ==========================================
local vehicleList = Instance.new("ScrollingFrame")
vehicleList.Name = "VehicleList"
vehicleList.Size = UDim2.fromScale(1, 1)
vehicleList.BackgroundColor3 = Color3.fromRGB(20, 25, 38)
vehicleList.BorderSizePixel = 0
vehicleList.ScrollBarThickness = 6
vehicleList.CanvasSize = UDim2.fromOffset(0, #VEHICLE_CLASSES * 54 + 12)
vehicleList.Parent = vehiclesPage
addCorner(vehicleList, 10)

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.Parent = vehicleList

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = vehicleList

type VehicleRowUI = {
	btn: TextButton,
	stroke: UIStroke,
	priceTag: TextLabel,
	tierBadge: TextLabel,
}
local vehicleRows: { [string]: VehicleRowUI } = {}

local function refreshVehicleView()
	previewCarTitle.Text = currentFocusedClass.name
	showroomTierText.Text = currentFocusedClass.tierBadge
	showroomTierText.TextColor3 = currentFocusedClass.tierColor
	showroomTierStroke.Color = currentFocusedClass.tierColor
	showroomStroke.Color = currentFocusedClass.tierColor

	local engBonus = (getUpgradeLevel("Engine") - 1) * 0.04
	local armBonus = (getUpgradeLevel("Armor") - 1) * 0.04
	local plwBonus = (getUpgradeLevel("Plow") - 1) * 0.04

	statBars.speed.Size = UDim2.fromScale(math.clamp(currentFocusedClass.speed + engBonus, 0, 1), 1)
	statBars.handling.Size = UDim2.fromScale(math.clamp(currentFocusedClass.handling, 0, 1), 1)
	statBars.armor.Size = UDim2.fromScale(math.clamp(currentFocusedClass.armor + armBonus, 0, 1), 1)
	statBars.ram.Size = UDim2.fromScale(math.clamp(currentFocusedClass.ram + plwBonus, 0, 1), 1)

	local unlocked = isVehicleUnlocked(currentFocusedClass.id)
	local equipped = (selectedVehicleId == currentFocusedClass.id)
	if equipped then
		actionBtn.Text = "EQUIPPED • RESPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(50, 135, 235)
	elseif unlocked then
		actionBtn.Text = "EQUIP & SPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(45, 185, 95)
	else
		actionBtn.Text = string.format("BUY & EQUIP • $%s", formatNumber(currentFocusedClass.price))
		actionBtn.BackgroundColor3 = Color3.fromRGB(230, 140, 35)
	end

	for _, v in ipairs(VEHICLE_CLASSES) do
		local rowUI = vehicleRows[v.id]
		if rowUI then
			local vUnlocked = isVehicleUnlocked(v.id)
			local isSelected = (currentFocusedClass.id == v.id)
			if selectedVehicleId == v.id then
				rowUI.priceTag.Text = "EQUIPPED"
				rowUI.priceTag.TextColor3 = Color3.fromRGB(95, 255, 145)
			elseif vUnlocked then
				rowUI.priceTag.Text = "OWNED"
				rowUI.priceTag.TextColor3 = Color3.fromRGB(130, 215, 255)
			elseif v.price == 0 then
				rowUI.priceTag.Text = "FREE"
				rowUI.priceTag.TextColor3 = Color3.fromRGB(95, 255, 145)
			else
				rowUI.priceTag.Text = "$" .. formatNumber(v.price)
				rowUI.priceTag.TextColor3 = Color3.fromRGB(255, 215, 65)
			end
			rowUI.btn.BackgroundColor3 = if isSelected then Color3.fromRGB(36, 56, 96) else Color3.fromRGB(26, 32, 48)
			rowUI.stroke.Color = if isSelected then v.tierColor else Color3.fromRGB(50, 64, 92)
		end
	end

	rebuild3DShowroomCar()
end

for _, vInfo in ipairs(VEHICLE_CLASSES) do
	local row = Instance.new("TextButton")
	row.Name = vInfo.id .. "Row"
	row.Size = UDim2.new(1, -6, 0, 46)
	row.BackgroundColor3 = Color3.fromRGB(26, 32, 48)
	row.AutoButtonColor = false
	row.Text = ""
	row.Parent = vehicleList
	addCorner(row, 8)
	local rStroke = addStroke(row, Color3.fromRGB(50, 64, 92), 1.4)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "CarName"
	nameLbl.Size = UDim2.fromOffset(180, 20)
	nameLbl.Position = UDim2.fromOffset(10, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.Text = vInfo.name
	nameLbl.TextSize = 13
	nameLbl.TextColor3 = Color3.new(1, 1, 1)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row

	local priceLbl = Instance.new("TextLabel")
	priceLbl.Name = "PriceStatus"
	priceLbl.Size = UDim2.fromOffset(96, 20)
	priceLbl.Position = UDim2.new(1, -106, 0, 4)
	priceLbl.BackgroundTransparency = 1
	priceLbl.Font = Enum.Font.GothamBlack
	priceLbl.Text = if vInfo.price == 0 then "FREE" else ("$" .. formatNumber(vInfo.price))
	priceLbl.TextSize = 13
	priceLbl.TextColor3 = Color3.fromRGB(255, 215, 65)
	priceLbl.TextXAlignment = Enum.TextXAlignment.Right
	priceLbl.Parent = row

	local tierLbl = Instance.new("TextLabel")
	tierLbl.Name = "SmashTierBadge"
	tierLbl.Size = UDim2.new(1, -20, 0, 18)
	tierLbl.Position = UDim2.fromOffset(10, 24)
	tierLbl.BackgroundTransparency = 1
	tierLbl.Font = Enum.Font.GothamBlack
	tierLbl.Text = vInfo.tierBadge
	tierLbl.TextSize = 11
	tierLbl.TextColor3 = vInfo.tierColor
	tierLbl.TextXAlignment = Enum.TextXAlignment.Left
	tierLbl.Parent = row

	vehicleRows[vInfo.id] = {
		btn = row,
		stroke = rStroke,
		priceTag = priceLbl,
		tierBadge = tierLbl,
	}

	row.MouseButton1Click:Connect(function()
		currentFocusedClass = vInfo
		previewTrackHighlight = nil
		refreshVehicleView()
	end)
end

actionBtn.MouseButton1Click:Connect(function()
	local v = currentFocusedClass
	local unlocked = isVehicleUnlocked(v.id)
	if not unlocked then
		if getPlayerCash() < v.price then
			statusBanner.Text = "NEED $" .. formatNumber(v.price) .. " FOR " .. v.name
			statusBanner.TextColor3 = Color3.fromRGB(255, 95, 95)
			return
		end
		callRemote({ "SelectVehicle", "UnlockVehicle", "PurchaseVehicle" }, v.id)
		unlockedVehicles[v.id] = true
	else
		callRemote({ "SelectVehicle", "EquipVehicle", "SpawnVehicle" }, v.id)
	end
	selectedVehicleId = v.id
	player:SetAttribute("SelectedVehicle", v.id)
	player:SetAttribute("EquippedVehicle", v.id)
	statusBanner.Text = "EQUIPPED " .. v.name
	statusBanner.TextColor3 = Color3.fromRGB(115, 255, 150)
	refreshVehicleView()
end)

-- ==========================================
-- 2. UPGRADES TAB UI
-- Ultra-Simple Row Layout: [3D Part Icon] | PLOW (LV. 2/5) | +1 SMASH TIER | [UPGRADE $1,250]
-- ==========================================
local upgradeRows: { [string]: { lvlLabel: TextLabel, btn: TextButton, pips: { Frame }, cardStroke: UIStroke } } = {}

local function refreshUpgradesView()
	for _, track in ipairs(UPGRADE_TRACKS) do
		local ui = upgradeRows[track.id]
		if ui then
			local lvl = getUpgradeLevel(track.id)
			ui.lvlLabel.Text = string.format("%s (LV. %d/5)", track.shortName, lvl)
			for i = 1, 5 do
				ui.pips[i].BackgroundColor3 = (i <= lvl) and track.color or Color3.fromRGB(35, 40, 56)
			end
			if lvl >= 5 then
				ui.btn.Text = "MAX LV. 5"
				ui.btn.BackgroundColor3 = Color3.fromRGB(65, 75, 95)
			else
				local cost = UPGRADE_COSTS[lvl] or (track.baseCost * lvl)
				ui.btn.Text = string.format("UPGRADE $%s", formatNumber(cost))
				ui.btn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
			end
			ui.cardStroke.Color = if previewTrackHighlight == track.id then track.color else Color3.fromRGB(45, 58, 84)
		end
	end
	rebuild3DShowroomCar()
end

for idx, track in ipairs(UPGRADE_TRACKS) do
	local card = Instance.new("TextButton")
	card.Name = track.id .. "Track"
	card.Size = UDim2.new(1, 0, 0, 72)
	card.Position = UDim2.fromOffset(0, (idx - 1) * 79)
	card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.Parent = upgradesPage
	addCorner(card, 10)
	local cardStroke = addStroke(card, Color3.fromRGB(45, 58, 84), 1.5)

	-- [3D Part Icon]
	local iconBox = Instance.new("Frame")
	iconBox.Name = "Part3DIcon"
	iconBox.Size = UDim2.fromOffset(72, 52)
	iconBox.Position = UDim2.fromOffset(10, 10)
	iconBox.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
	iconBox.BorderSizePixel = 0
	iconBox.Parent = card
	addCorner(iconBox, 8)
	addStroke(iconBox, track.color, 1.5)

	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size = UDim2.fromScale(1, 1)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font = Enum.Font.GothamBlack
	iconLbl.Text = track.iconTag
	iconLbl.TextColor3 = track.color
	iconLbl.TextSize = 11
	iconLbl.Parent = iconBox

	-- PLOW (LV. 2/5) + 5 Pips
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "TrackLevelLabel"
	nameLbl.Size = UDim2.fromOffset(140, 24)
	nameLbl.Position = UDim2.fromOffset(92, 12)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = Color3.new(1, 1, 1)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = card

	local pips: { Frame } = {}
	for p = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(22, 8)
		pip.Position = UDim2.fromOffset(92 + (p - 1) * 26, 42)
		pip.BackgroundColor3 = Color3.fromRGB(35, 40, 56)
		pip.BorderSizePixel = 0
		pip.Parent = card
		addCorner(pip, 4)
		table.insert(pips, pip)
	end

	-- +1 SMASH TIER (Short Benefit Pill)
	local benefitBadge = Instance.new("TextLabel")
	benefitBadge.Name = "BenefitBadge"
	benefitBadge.Size = UDim2.fromOffset(118, 28)
	benefitBadge.Position = UDim2.fromOffset(226, 22)
	benefitBadge.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
	benefitBadge.Font = Enum.Font.GothamBlack
	benefitBadge.Text = track.benefitTag
	benefitBadge.TextSize = 11
	benefitBadge.TextColor3 = track.color
	benefitBadge.Parent = card
	addCorner(benefitBadge, 6)

	-- [UPGRADE $1,250]
	local upgBtn = Instance.new("TextButton")
	upgBtn.Name = "Upgrade" .. track.id .. "Btn"
	upgBtn.Size = UDim2.fromOffset(136, 46)
	upgBtn.Position = UDim2.new(1, -146, 0, 13)
	upgBtn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
	upgBtn.Font = Enum.Font.GothamBlack
	upgBtn.TextSize = 13
	upgBtn.TextColor3 = Color3.new(1, 1, 1)
	upgBtn.Parent = card
	addCorner(upgBtn, 8)

	upgradeRows[track.id] = { lvlLabel = nameLbl, btn = upgBtn, pips = pips, cardStroke = cardStroke }

	local function selectTrackPreview()
		previewTrackHighlight = track.id
		refreshUpgradesView()
	end

	card.MouseButton1Click:Connect(selectTrackPreview)
	upgBtn.MouseEnter:Connect(selectTrackPreview)

	upgBtn.MouseButton1Click:Connect(function()
		previewTrackHighlight = track.id
		local lvl = getUpgradeLevel(track.id)
		if lvl >= 5 then
			refreshUpgradesView()
			return
		end
		local cost = UPGRADE_COSTS[lvl] or (track.baseCost * lvl)
		if getPlayerCash() < cost then
			statusBanner.Text = "NEED $" .. formatNumber(cost) .. " FOR " .. track.shortName
			statusBanner.TextColor3 = Color3.fromRGB(255, 95, 95)
			refreshUpgradesView()
			return
		end
		local ok, result = callRemote({ "PurchaseUpgrade", "BuyUpgrade", "UpgradeVehicle" }, track.id)
		if ok and result ~= false then
			player:SetAttribute(track.id .. "Level", lvl + 1)
			player:SetAttribute("Upgrade_" .. track.id, lvl + 1)
			statusBanner.Text = string.format("UPGRADED %s TO LV. %d!", track.shortName, lvl + 1)
			statusBanner.TextColor3 = Color3.fromRGB(115, 255, 150)
		end
		refreshUpgradesView()
		refreshVehicleView()
	end)
end

-- ==========================================
-- 3D TURNTABLE ROTATION & TAB CONTROLS
-- ==========================================
RunService.RenderStepped:Connect(function(dt: number)
	if not modal.Visible or not activePreviewModel then
		return
	end
	turntableYaw = (turntableYaw + dt * 28) % 360
	local rad = math.rad(turntableYaw)
	local dist = if currentFocusedClass.id == "MonsterTruck" or currentFocusedClass.id == "Bulldozer" then 21.5 else 17.5
	local camPos = Vector3.new(math.sin(rad) * dist, 6.2, -math.cos(rad) * dist)
	vpCam.CFrame = CFrame.lookAt(camPos, Vector3.new(0, 1.0, 0))
end)

local function switchTab(tab: string)
	local isVehicles = (tab == "Vehicles")
	vehiclesPage.Visible = isVehicles
	upgradesPage.Visible = not isVehicles
	vehiclesTabBtn.BackgroundColor3 = isVehicles and Color3.fromRGB(45, 130, 235) or Color3.fromRGB(32, 38, 54)
	upgradesTabBtn.BackgroundColor3 = (not isVehicles) and Color3.fromRGB(45, 130, 235) or Color3.fromRGB(32, 38, 54)
	previewTrackHighlight = if isVehicles then nil else "Plow"
	refreshVehicleView()
	refreshUpgradesView()
end

local function setShopOpen(open: boolean)
	modal.Visible = open
	if open then
		for _, v in ipairs(VEHICLE_CLASSES) do
			if v.id == selectedVehicleId then
				currentFocusedClass = v
				break
			end
		end
		refreshVehicleView()
		refreshUpgradesView()
	end
end

vehiclesTabBtn.MouseButton1Click:Connect(function()
	switchTab("Vehicles")
end)
upgradesTabBtn.MouseButton1Click:Connect(function()
	switchTab("Upgrades")
end)
closeBtn.MouseButton1Click:Connect(function()
	setShopOpen(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		setShopOpen(not modal.Visible)
	elseif modal.Visible and input.KeyCode == Enum.KeyCode.ButtonL1 then
		switchTab("Vehicles")
	elseif modal.Visible and input.KeyCode == Enum.KeyCode.ButtonR1 then
		switchTab("Upgrades")
	end
end)

player:GetAttributeChangedSignal("ToggleShopUI"):Connect(function()
	setShopOpen(not modal.Visible)
end)
player.AttributeChanged:Connect(function(attr: string)
	if attr == "SelectedVehicle" or attr == "EquippedVehicle" then
		selectedVehicleId = tostring(player:GetAttribute("SelectedVehicle") or player:GetAttribute("EquippedVehicle") or "Compact")
	end
	if modal.Visible then
		refreshVehicleView()
		refreshUpgradesView()
	end
end)

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return
	end
	local openRemote = remotes:FindFirstChild("OpenSpeedShop")
	if openRemote and openRemote:IsA("RemoteEvent") then
		openRemote.OnClientEvent:Connect(function()
			setShopOpen(true)
		end)
	end
	local toggleRemote = remotes:FindFirstChild("SpeedShopToggle")
	if toggleRemote and toggleRemote:IsA("RemoteEvent") then
		toggleRemote.OnClientEvent:Connect(function(openState: any)
			setShopOpen(openState ~= false)
		end)
	end
end)

refreshVehicleView()
refreshUpgradesView()
