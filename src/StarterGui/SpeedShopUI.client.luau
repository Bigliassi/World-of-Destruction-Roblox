--!strict
-- SpeedShopUI.client.luau
-- Interactive 3D Speed Shop & Garage Modal for browsing/unlocking 8 vehicle classes and upgrading 5 performance tracks.
-- Features a live rotating 3D ViewportFrame showroom stage that renders the 3D vehicle AND visually displays
-- 3D upgrade attachments (Engine Supercharger, Armor Rollcage, Nitro Tanks, Demolition Plow, Cash Magnet) on the car!

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
	tagline: string,
}

type UpgradeTrackInfo = {
	id: string,
	name: string,
	baseCost: number,
	desc: string,
	partDesc: string,
	color: Color3,
}

local VEHICLE_CLASSES: { VehicleClassInfo } = {
	{ id = "Compact", name = "Spark Compact", price = 0, speed = 0.55, handling = 0.88, armor = 0.40, ram = 0.35, tagline = "Agile starter hatch built for tight alley drifts." },
	{ id = "Sedan", name = "Cruiser V8 Sedan", price = 1500, speed = 0.65, handling = 0.78, armor = 0.55, ram = 0.50, tagline = "Balanced street bruiser with reinforced bumpers." },
	{ id = "Muscle", name = "V8 Hellfire Muscle", price = 4500, speed = 0.82, handling = 0.68, armor = 0.65, ram = 0.72, tagline = "Supercharged torque monster made for smoky burnouts." },
	{ id = "SUV", name = "Titan 4x4 SUV", price = 9000, speed = 0.70, handling = 0.65, armor = 0.82, ram = 0.80, tagline = "Heavy AWD tactical rig that shrugs off roadblocks." },
	{ id = "Pickup", name = "Ranch Rammer 4x4", price = 15000, speed = 0.74, handling = 0.64, armor = 0.85, ram = 0.86, tagline = "Lifted steel-frame workhorse with battering torque." },
	{ id = "Sports", name = "Apex Hyper GT", price = 28000, speed = 0.98, handling = 0.94, armor = 0.58, ram = 0.65, tagline = "Twin-turbo carbon rocket for maximum velocity." },
	{ id = "MonsterTruck", name = "Crusher XL 6x6", price = 50000, speed = 0.78, handling = 0.60, armor = 0.94, ram = 0.96, tagline = "Oversized tires flatten traffic and street props." },
	{ id = "Bulldozer", name = "Goliath Dozer Mk.IV", price = 95000, speed = 0.58, handling = 0.52, armor = 1.00, ram = 1.00, tagline = "Unstoppable armored siege blade. Pure devastation." },
}

local UPGRADE_TRACKS: { UpgradeTrackInfo } = {
	{ id = "Engine", name = "Twin-Turbo Engine", baseCost = 400, desc = "+8% Top Speed & +10% Accel per level", partDesc = "3D Hood Supercharger & Intake Scoop", color = Color3.fromRGB(255, 130, 50) },
	{ id = "Armor", name = "Reinforced Chassis Armor", baseCost = 400, desc = "+25% Vehicle Health & Ram Resistance", partDesc = "3D Steel Exo-Rollcage & Side Bull-Bars", color = Color3.fromRGB(75, 225, 125) },
	{ id = "Nitro", name = "Liquid Nitrous System", baseCost = 400, desc = "+18% Nitro Boost Power & Recharge", partDesc = "3D Dual Rear Glowing Nitrous Tanks", color = Color3.fromRGB(55, 185, 255) },
	{ id = "Plow", name = "Heavy Wedge Ram Plow", baseCost = 400, desc = "+22% Prop Smash & Impact Force", partDesc = "3D Front Demolition Wedge Ram Blade", color = Color3.fromRGB(255, 75, 85) },
	{ id = "Magnet", name = "Cash & Gold Magnet", baseCost = 400, desc = "+15% to 2.0x Cash Drop Multiplier", partDesc = "3D Roof Golden Electromagnetic Coil", color = Color3.fromRGB(255, 215, 65) },
}

local UPGRADE_COSTS = { 400, 900, 1800, 3200, 5500 }

local unlockedVehicles: { [string]: boolean } = { Compact = true }
local selectedVehicleId: string = tostring(player:GetAttribute("SelectedVehicle") or player:GetAttribute("EquippedVehicle") or "Compact")
local previewTrackHighlight: string? = nil

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

local function addStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 0.22
	s.Parent = parent
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
titleLabel.Size = UDim2.fromOffset(360, 50)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = "3D SPEED SHOP & GARAGE"
titleLabel.TextSize = 21
titleLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local statusBanner = Instance.new("TextLabel")
statusBanner.Size = UDim2.fromOffset(340, 50)
statusBanner.Position = UDim2.new(1, -400, 0, 0)
statusBanner.BackgroundTransparency = 1
statusBanner.Font = Enum.Font.GothamBold
statusBanner.Text = "Inspect 3D vehicles & live 3D upgrade parts"
statusBanner.TextSize = 13
statusBanner.TextColor3 = Color3.fromRGB(120, 230, 155)
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

-- Tab Bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 38)
tabBar.Position = UDim2.fromOffset(12, 66)
tabBar.BackgroundTransparency = 1
tabBar.Parent = modal

local vehiclesTabBtn = Instance.new("TextButton")
vehiclesTabBtn.Name = "VehiclesTabBtn"
vehiclesTabBtn.Size = UDim2.fromOffset(210, 36)
vehiclesTabBtn.Position = UDim2.fromOffset(0, 0)
vehiclesTabBtn.BackgroundColor3 = Color3.fromRGB(45, 130, 235)
vehiclesTabBtn.Font = Enum.Font.GothamBlack
vehiclesTabBtn.Text = "3D VEHICLES (8)"
vehiclesTabBtn.TextSize = 14
vehiclesTabBtn.TextColor3 = Color3.new(1, 1, 1)
vehiclesTabBtn.Parent = tabBar
addCorner(vehiclesTabBtn, 8)

local upgradesTabBtn = Instance.new("TextButton")
upgradesTabBtn.Name = "UpgradesTabBtn"
upgradesTabBtn.Size = UDim2.fromOffset(230, 36)
upgradesTabBtn.Position = UDim2.fromOffset(220, 0)
upgradesTabBtn.BackgroundColor3 = Color3.fromRGB(32, 38, 54)
upgradesTabBtn.Font = Enum.Font.GothamBlack
upgradesTabBtn.Text = "3D UPGRADE PARTS (5 TRACKS)"
upgradesTabBtn.TextSize = 14
upgradesTabBtn.TextColor3 = Color3.fromRGB(185, 195, 215)
upgradesTabBtn.Parent = tabBar
addCorner(upgradesTabBtn, 8)

-- ==========================================
-- SHARED 3D SHOWROOM VIEWPORT STAGE (Middle/Right)
-- Visible on BOTH Vehicles Tab & Upgrades Tab!
-- ==========================================
local showroomCard = Instance.new("Frame")
showroomCard.Name = "Showroom3DCard"
showroomCard.Size = UDim2.fromOffset(330, 396)
showroomCard.Position = UDim2.fromOffset(12, 110)
showroomCard.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
showroomCard.BorderSizePixel = 0
showroomCard.Parent = modal
addCorner(showroomCard, 12)
addStroke(showroomCard, Color3.fromRGB(56, 189, 248), 1.5)

local viewport = Instance.new("ViewportFrame")
viewport.Name = "Vehicle3DViewport"
viewport.Size = UDim2.new(1, -16, 0, 210)
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
previewCarTitle.Size = UDim2.new(1, -20, 0, 24)
previewCarTitle.Position = UDim2.fromOffset(10, 222)
previewCarTitle.BackgroundTransparency = 1
previewCarTitle.Font = Enum.Font.GothamBlack
previewCarTitle.TextSize = 18
previewCarTitle.TextColor3 = Color3.fromRGB(255, 220, 65)
previewCarTitle.TextXAlignment = Enum.TextXAlignment.Left
previewCarTitle.Parent = showroomCard

local previewPartsBadge = Instance.new("TextLabel")
previewPartsBadge.Name = "PreviewPartsBadge"
previewPartsBadge.Size = UDim2.new(1, -20, 0, 18)
previewPartsBadge.Position = UDim2.fromOffset(10, 246)
previewPartsBadge.BackgroundTransparency = 1
previewPartsBadge.Font = Enum.Font.GothamBold
previewPartsBadge.TextSize = 11
previewPartsBadge.TextColor3 = Color3.fromRGB(115, 225, 255)
previewPartsBadge.TextXAlignment = Enum.TextXAlignment.Left
previewPartsBadge.Text = "3D PARTS: STANDARD FACTORY SPEC"
previewPartsBadge.Parent = showroomCard

local statBars: { [string]: Frame } = {}
local statDefs = {
	{ key = "speed", label = "TOP SPEED", color = Color3.fromRGB(65, 190, 255) },
	{ key = "handling", label = "HANDLING", color = Color3.fromRGB(120, 245, 140) },
	{ key = "armor", label = "ARMOR", color = Color3.fromRGB(255, 195, 60) },
	{ key = "ram", label = "SMASH POWER", color = Color3.fromRGB(255, 85, 75) },
}

for idx, st in ipairs(statDefs) do
	local yPos = 268 + (idx - 1) * 18
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
actionBtn.Position = UDim2.new(0, 10, 1, -50)
actionBtn.BackgroundColor3 = Color3.fromRGB(45, 180, 95)
actionBtn.Font = Enum.Font.GothamBlack
actionBtn.Text = "EQUIP & SPAWN"
actionBtn.TextSize = 15
actionBtn.TextColor3 = Color3.new(1, 1, 1)
actionBtn.Parent = showroomCard
addCorner(actionBtn, 10)

-- Right Side Content Containers (514px wide)
local vehiclesPage = Instance.new("Frame")
vehiclesPage.Name = "VehiclesPage"
vehiclesPage.Size = UDim2.new(1, -366, 0, 396)
vehiclesPage.Position = UDim2.fromOffset(354, 110)
vehiclesPage.BackgroundTransparency = 1
vehiclesPage.Parent = modal

local upgradesPage = Instance.new("Frame")
upgradesPage.Name = "UpgradesPage"
upgradesPage.Size = UDim2.new(1, -366, 0, 396)
upgradesPage.Position = UDim2.fromOffset(354, 110)
upgradesPage.BackgroundTransparency = 1
upgradesPage.Visible = false
upgradesPage.Parent = modal

-- ==========================================
-- REMOTE & STATE HELPERS
-- ==========================================
local function getPlayerCash(): number
	local c = player:GetAttribute("Cash")
	if typeof(c) == "number" then return c end
	local ls = player:FindFirstChild("leaderstats")
	local val = ls and ls:FindFirstChild("Cash")
	if val and val:IsA("ValueBase") then return tonumber(val.Value) or 0 end
	return 0
end

local function getUpgradeLevel(trackId: string): number
	local attr = player:GetAttribute(trackId .. "Level") or player:GetAttribute("Upgrade_" .. trackId)
	return math.clamp(tonumber(attr) or 1, 1, 5)
end

local function callRemote(names: { string }, ...: any): (boolean, any)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return false, nil end
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
	if classId == "Compact" or unlockedVehicles[classId] then return true end
	local attrStr = tostring(player:GetAttribute("UnlockedVehicles") or "")
	if string.find(attrStr, classId, 1, true) then
		unlockedVehicles[classId] = true
		return true
	end
	return false
end

-- ==========================================
-- 3D VIEWPORT CAR + 3D UPGRADE BUILDER
-- ==========================================
local currentFocusedClass: VehicleClassInfo = VEHICLE_CLASSES[1]
local activePreviewModel: Model? = nil
local turntableYaw = 28.0

local function rebuild3DShowroomCar()
	if activePreviewModel then
		activePreviewModel:Destroy()
		activePreviewModel = nil
	end

	-- Compute visual upgrade levels (0..4 steps above Lv.1, or previewed track on Upgrades tab)
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

	local carModel = VehicleCatalog.BuildVehicle(currentFocusedClass.id, {
		CFrame = CFrame.new(0, 0, 0),
		EngineLevel = engSteps,
		ArmorLevel = armSteps,
		NitroLevel = nitSteps,
		PlowLevel = plwSteps,
		MagnetLevel = magSteps,
	} :: any)

	for _, desc in ipairs(carModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		elseif desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end

	-- Showroom turntable pedestal disc beneath the car
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

	local activePartsList = {}
	if engSteps > 0 then table.insert(activePartsList, "BLOWER") end
	if armSteps > 0 then table.insert(activePartsList, "CAGE") end
	if nitSteps > 0 then table.insert(activePartsList, "NITRO") end
	if plwSteps > 0 or currentFocusedClass.id == "Bulldozer" then table.insert(activePartsList, "PLOW") end
	if magSteps > 0 then table.insert(activePartsList, "MAGNET") end

	if #activePartsList > 0 then
		previewPartsBadge.Text = "3D PARTS ON CAR: " .. table.concat(activePartsList, " + ")
	else
		previewPartsBadge.Text = "3D PARTS ON CAR: STOCK (UPGRADE TO ADD 3D PARTS)"
	end
end

-- ==========================================
-- 1. VEHICLES TAB UI
-- ==========================================
local vehicleList = Instance.new("ScrollingFrame")
vehicleList.Name = "VehicleList"
vehicleList.Size = UDim2.fromScale(1, 1)
vehicleList.BackgroundColor3 = Color3.fromRGB(20, 25, 38)
vehicleList.BorderSizePixel = 0
vehicleList.ScrollBarThickness = 6
vehicleList.CanvasSize = UDim2.fromOffset(0, #VEHICLE_CLASSES * 54)
vehicleList.Parent = vehiclesPage
addCorner(vehicleList, 10)

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 8)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.Parent = vehicleList

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = vehicleList

local rowButtons: { [string]: TextButton } = {}

local function refreshVehicleView()
	previewCarTitle.Text = string.upper(currentFocusedClass.name)

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
		actionBtn.Text = "EQUIPPED - CLICK TO RESPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(50, 135, 235)
	elseif unlocked then
		actionBtn.Text = "EQUIP & SPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(45, 185, 95)
	else
		actionBtn.Text = string.format("BUY & EQUIP  -  $%d", currentFocusedClass.price)
		actionBtn.BackgroundColor3 = Color3.fromRGB(230, 140, 35)
	end

	for _, v in ipairs(VEHICLE_CLASSES) do
		local btn = rowButtons[v.id]
		if btn then
			local vUnlocked = isVehicleUnlocked(v.id)
			local tag = (selectedVehicleId == v.id) and " [EQUIPPED]" or (vUnlocked and " [OWNED]" or string.format(" [$%d]", v.price))
			btn.Text = "  " .. v.name .. tag .. "  -  " .. v.tagline
			btn.BackgroundColor3 = (currentFocusedClass.id == v.id) and Color3.fromRGB(48, 95, 175) or Color3.fromRGB(28, 34, 50)
		end
	end

	rebuild3DShowroomCar()
end

for _, vInfo in ipairs(VEHICLE_CLASSES) do
	local row = Instance.new("TextButton")
	row.Name = vInfo.id .. "Row"
	row.Size = UDim2.new(1, -6, 0, 44)
	row.BackgroundColor3 = Color3.fromRGB(28, 34, 50)
	row.Font = Enum.Font.GothamBold
	row.TextSize = 13
	row.TextColor3 = Color3.new(1, 1, 1)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.Parent = vehicleList
	addCorner(row, 8)
	rowButtons[vInfo.id] = row

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
			statusBanner.Text = "Not enough cash to unlock " .. v.name .. "!"
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
	statusBanner.Text = "Equipped " .. v.name .. "!"
	statusBanner.TextColor3 = Color3.fromRGB(115, 255, 150)
	refreshVehicleView()
end)

-- ==========================================
-- 2. UPGRADES TAB UI (5 TRACKS, LV 1-5 WITH LIVE 3D PART PREVIEW)
-- ==========================================
local upgradeRows: { [string]: { lvlLabel: TextLabel, btn: TextButton, pips: { Frame } } } = {}

local function refreshUpgradesView()
	for _, track in ipairs(UPGRADE_TRACKS) do
		local ui = upgradeRows[track.id]
		if ui then
			local lvl = getUpgradeLevel(track.id)
			ui.lvlLabel.Text = string.format("%s  (LV. %d / 5)", string.upper(track.name), lvl)
			for i = 1, 5 do
				ui.pips[i].BackgroundColor3 = (i <= lvl) and track.color or Color3.fromRGB(35, 40, 56)
			end
			if lvl >= 5 then
				ui.btn.Text = "MAXED OUT"
				ui.btn.BackgroundColor3 = Color3.fromRGB(65, 75, 95)
			else
				local cost = UPGRADE_COSTS[lvl] or (track.baseCost * lvl)
				ui.btn.Text = string.format("UPGRADE - $%d", cost)
				ui.btn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
			end
		end
	end
	rebuild3DShowroomCar()
end

for idx, track in ipairs(UPGRADE_TRACKS) do
	local card = Instance.new("Frame")
	card.Name = track.id .. "Track"
	card.Size = UDim2.new(1, 0, 0, 74)
	card.Position = UDim2.fromOffset(0, (idx - 1) * 80)
	card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	card.BorderSizePixel = 0
	card.Parent = upgradesPage
	addCorner(card, 10)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromOffset(310, 22)
	nameLbl.Position = UDim2.fromOffset(14, 6)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = Color3.new(1, 1, 1)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = card

	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.fromOffset(310, 18)
	descLbl.Position = UDim2.fromOffset(14, 28)
	descLbl.BackgroundTransparency = 1
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.Text = track.desc
	descLbl.TextSize = 11
	descLbl.TextColor3 = Color3.fromRGB(165, 180, 205)
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.Parent = card

	local partTagLbl = Instance.new("TextLabel")
	partTagLbl.Size = UDim2.fromOffset(310, 16)
	partTagLbl.Position = UDim2.fromOffset(14, 48)
	partTagLbl.BackgroundTransparency = 1
	partTagLbl.Font = Enum.Font.GothamBold
	partTagLbl.Text = "3D PART: " .. track.partDesc
	partTagLbl.TextSize = 11
	partTagLbl.TextColor3 = track.color
	partTagLbl.TextXAlignment = Enum.TextXAlignment.Left
	partTagLbl.Parent = card

	local pips: { Frame } = {}
	for p = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(22, 10)
		pip.Position = UDim2.fromOffset(220 + (p - 1) * 26, 12)
		pip.BackgroundColor3 = Color3.fromRGB(35, 40, 56)
		pip.BorderSizePixel = 0
		pip.Parent = card
		addCorner(pip, 4)
		table.insert(pips, pip)
	end

	local upgBtn = Instance.new("TextButton")
	upgBtn.Name = "Upgrade" .. track.id .. "Btn"
	upgBtn.Size = UDim2.fromOffset(148, 46)
	upgBtn.Position = UDim2.new(1, -160, 0, 14)
	upgBtn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
	upgBtn.Font = Enum.Font.GothamBlack
	upgBtn.TextSize = 13
	upgBtn.TextColor3 = Color3.new(1, 1, 1)
	upgBtn.Parent = card
	addCorner(upgBtn, 8)

	upgradeRows[track.id] = { lvlLabel = nameLbl, btn = upgBtn, pips = pips }

	-- Hovering an upgrade button previews that 3D part on the car in the ViewportFrame!
	upgBtn.MouseEnter:Connect(function()
		previewTrackHighlight = track.id
		rebuild3DShowroomCar()
	end)
	upgBtn.MouseLeave:Connect(function()
		if previewTrackHighlight == track.id then
			previewTrackHighlight = nil
			rebuild3DShowroomCar()
		end
	end)

	upgBtn.MouseButton1Click:Connect(function()
		local lvl = getUpgradeLevel(track.id)
		if lvl >= 5 then return end
		local cost = UPGRADE_COSTS[lvl] or (track.baseCost * lvl)
		if getPlayerCash() < cost then
			statusBanner.Text = "Need $" .. tostring(cost) .. " for " .. track.name .. "!"
			statusBanner.TextColor3 = Color3.fromRGB(255, 95, 95)
			return
		end
		local ok, result = callRemote({ "PurchaseUpgrade", "BuyUpgrade", "UpgradeVehicle" }, track.id)
		if ok and result ~= false then
			player:SetAttribute(track.id .. "Level", lvl + 1)
			player:SetAttribute("Upgrade_" .. track.id, lvl + 1)
			statusBanner.Text = string.format("Installed 3D %s Lv.%d!", track.name, lvl + 1)
			statusBanner.TextColor3 = Color3.fromRGB(115, 255, 150)
		end
		previewTrackHighlight = nil
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
	previewTrackHighlight = nil
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

vehiclesTabBtn.MouseButton1Click:Connect(function() switchTab("Vehicles") end)
upgradesTabBtn.MouseButton1Click:Connect(function() switchTab("Upgrades") end)
closeBtn.MouseButton1Click:Connect(function() setShopOpen(false) end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
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
	if not remotes then return end
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
