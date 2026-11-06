--!strict
-- SpeedShopUI.client.luau
-- Interactive Speed Shop & Garage Modal for browsing/unlocking 8 vehicle classes and upgrading 5 performance tracks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
	color: Color3,
}

local VEHICLE_CLASSES: { VehicleClassInfo } = {
	{ id = "Compact", name = "Spark Compact", price = 0, speed = 0.55, handling = 0.88, armor = 0.40, ram = 0.35, tagline = "Agile starter hatch built for tight alley drifts." },
	{ id = "Sedan", name = "Crown Street Sedan", price = 1500, speed = 0.65, handling = 0.78, armor = 0.55, ram = 0.50, tagline = "Balanced street bruiser with reinforced bumpers." },
	{ id = "Muscle", name = "V8 Hellfire Muscle", price = 4500, speed = 0.82, handling = 0.68, armor = 0.65, ram = 0.72, tagline = "Supercharged torque monster made for smoky burnouts." },
	{ id = "SUV", name = "Titan Enforcer SUV", price = 9000, speed = 0.70, handling = 0.65, armor = 0.82, ram = 0.80, tagline = "Heavy AWD tactical rig that shrugs off roadblocks." },
	{ id = "Pickup", name = "Ironclad 4x4 Pickup", price = 15000, speed = 0.74, handling = 0.64, armor = 0.85, ram = 0.86, tagline = "Lifted steel-frame workhorse with battering torque." },
	{ id = "Sports", name = "Apex Hyper GT", price = 28000, speed = 0.98, handling = 0.94, armor = 0.58, ram = 0.65, tagline = "Twin-turbo carbon rocket for maximum velocity." },
	{ id = "MonsterTruck", name = "Colossus Crusher 6x6", price = 50000, speed = 0.78, handling = 0.60, armor = 0.94, ram = 0.96, tagline = "Oversized tires flatten traffic and street props." },
	{ id = "Bulldozer", name = "DoomDozer Mk.IV", price = 95000, speed = 0.58, handling = 0.52, armor = 1.00, ram = 1.00, tagline = "Unstoppable armored siege blade. Pure devastation." },
}

local UPGRADE_TRACKS: { UpgradeTrackInfo } = {
	{ id = "Engine", name = "Twin-Turbo Engine", baseCost = 800, desc = "+12% Top Speed & Acceleration per level", color = Color3.fromRGB(255, 130, 50) },
	{ id = "Armor", name = "Reinforced Chassis Armor", baseCost = 900, desc = "+25% Vehicle Health & Police Ram Resistance", color = Color3.fromRGB(75, 225, 125) },
	{ id = "Nitro", name = "Liquid Nitrous System", baseCost = 1000, desc = "+20% Nitro Capacity & Recharge Rate", color = Color3.fromRGB(55, 185, 255) },
	{ id = "Plow", name = "Heavy Wedge Ram Plow", baseCost = 1250, desc = "+22% Prop Smash & Structural Impact Force", color = Color3.fromRGB(255, 75, 85) },
	{ id = "Magnet", name = "Cash & Scrap Magnet", baseCost = 1100, desc = "+15% Cash Drop Multiplier & Pickup Radius", color = Color3.fromRGB(255, 215, 65) },
}

local unlockedVehicles: { [string]: boolean } = { Compact = true }
local selectedVehicleId: string = tostring(player:GetAttribute("SelectedVehicle") or "Compact")

local gui = Instance.new("ScreenGui")
gui.Name = "WorldOfDestructionShopGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
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
	s.Transparency = 0.25
	s.Parent = parent
end

local modal = Instance.new("Frame")
modal.Name = "SpeedShopModal"
modal.Size = UDim2.fromOffset(760, 480)
modal.Position = UDim2.fromScale(0.5, 0.5)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
modal.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
modal.BackgroundTransparency = 0.04
modal.BorderSizePixel = 0
modal.Visible = false
modal.Parent = gui
addCorner(modal, 14)
addStroke(modal, Color3.fromRGB(65, 165, 255), 2)

-- Header Bar
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, -24, 0, 52)
header.Position = UDim2.fromOffset(12, 10)
header.BackgroundColor3 = Color3.fromRGB(24, 29, 44)
header.BorderSizePixel = 0
header.Parent = modal
addCorner(header, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.fromOffset(320, 52)
titleLabel.Position = UDim2.fromOffset(16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = "SPEED SHOP & GARAGE"
titleLabel.TextSize = 22
titleLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local statusBanner = Instance.new("TextLabel")
statusBanner.Size = UDim2.fromOffset(280, 52)
statusBanner.Position = UDim2.new(1, -340, 0, 0)
statusBanner.BackgroundTransparency = 1
statusBanner.Font = Enum.Font.GothamBold
statusBanner.Text = "Select a vehicle or upgrade track"
statusBanner.TextSize = 13
statusBanner.TextColor3 = Color3.fromRGB(120, 230, 155)
statusBanner.TextXAlignment = Enum.TextXAlignment.Right
statusBanner.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.fromOffset(38, 38)
closeBtn.Position = UDim2.new(1, -45, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(215, 60, 65)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.Text = "X"
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Parent = header
addCorner(closeBtn, 8)

-- Tab Bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 40)
tabBar.Position = UDim2.fromOffset(12, 70)
tabBar.BackgroundTransparency = 1
tabBar.Parent = modal

local vehiclesTabBtn = Instance.new("TextButton")
vehiclesTabBtn.Name = "VehiclesTabBtn"
vehiclesTabBtn.Size = UDim2.fromOffset(190, 38)
vehiclesTabBtn.Position = UDim2.fromOffset(0, 0)
vehiclesTabBtn.BackgroundColor3 = Color3.fromRGB(45, 130, 235)
vehiclesTabBtn.Font = Enum.Font.GothamBlack
vehiclesTabBtn.Text = "VEHICLES (8)"
vehiclesTabBtn.TextSize = 14
vehiclesTabBtn.TextColor3 = Color3.new(1, 1, 1)
vehiclesTabBtn.Parent = tabBar
addCorner(vehiclesTabBtn, 8)

local upgradesTabBtn = Instance.new("TextButton")
upgradesTabBtn.Name = "UpgradesTabBtn"
upgradesTabBtn.Size = UDim2.fromOffset(190, 38)
upgradesTabBtn.Position = UDim2.fromOffset(200, 0)
upgradesTabBtn.BackgroundColor3 = Color3.fromRGB(32, 38, 54)
upgradesTabBtn.Font = Enum.Font.GothamBlack
upgradesTabBtn.Text = "UPGRADES (5 TRACKS)"
upgradesTabBtn.TextSize = 14
upgradesTabBtn.TextColor3 = Color3.fromRGB(185, 195, 215)
upgradesTabBtn.Parent = tabBar
addCorner(upgradesTabBtn, 8)

-- Content Containers
local vehiclesPage = Instance.new("Frame")
vehiclesPage.Name = "VehiclesPage"
vehiclesPage.Size = UDim2.new(1, -24, 1, -126)
vehiclesPage.Position = UDim2.fromOffset(12, 116)
vehiclesPage.BackgroundTransparency = 1
vehiclesPage.Parent = modal

local upgradesPage = Instance.new("Frame")
upgradesPage.Name = "UpgradesPage"
upgradesPage.Size = UDim2.new(1, -24, 1, -126)
upgradesPage.Position = UDim2.fromOffset(12, 116)
upgradesPage.BackgroundTransparency = 1
upgradesPage.Visible = false
upgradesPage.Parent = modal

-- ==========================================
-- REMOTE INVOCATION HELPER
-- ==========================================
local function getPlayerCash(): number
	local c = player:GetAttribute("Cash")
	if typeof(c) == "number" then return c end
	local ls = player:FindFirstChild("leaderstats")
	local val = ls and ls:FindFirstChild("Cash")
	if val and val:IsA("ValueBase") then return tonumber(val.Value) or 0 end
	return 0
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
-- 1. VEHICLES TAB UI
-- ==========================================
local vehicleList = Instance.new("ScrollingFrame")
vehicleList.Name = "VehicleList"
vehicleList.Size = UDim2.new(0.42, -8, 1, 0)
vehicleList.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
vehicleList.BorderSizePixel = 0
vehicleList.ScrollBarThickness = 6
vehicleList.CanvasSize = UDim2.fromOffset(0, #VEHICLE_CLASSES * 54)
vehicleList.Parent = vehiclesPage
addCorner(vehicleList, 10)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = vehicleList

local detailCard = Instance.new("Frame")
detailCard.Name = "VehicleDetailCard"
detailCard.Size = UDim2.new(0.58, -4, 1, 0)
detailCard.Position = UDim2.new(0.42, 4, 0, 0)
detailCard.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
detailCard.BorderSizePixel = 0
detailCard.Parent = vehiclesPage
addCorner(detailCard, 10)

local detailTitle = Instance.new("TextLabel")
detailTitle.Size = UDim2.new(1, -32, 0, 34)
detailTitle.Position = UDim2.fromOffset(16, 14)
detailTitle.BackgroundTransparency = 1
detailTitle.Font = Enum.Font.GothamBlack
detailTitle.TextSize = 22
detailTitle.TextColor3 = Color3.new(1, 1, 1)
detailTitle.TextXAlignment = Enum.TextXAlignment.Left
detailTitle.Parent = detailCard

local detailTagline = Instance.new("TextLabel")
detailTagline.Size = UDim2.new(1, -32, 0, 34)
detailTagline.Position = UDim2.fromOffset(16, 48)
detailTagline.BackgroundTransparency = 1
detailTagline.Font = Enum.Font.GothamMedium
detailTagline.TextSize = 13
detailTagline.TextWrapped = true
detailTagline.TextColor3 = Color3.fromRGB(175, 190, 215)
detailTagline.TextXAlignment = Enum.TextXAlignment.Left
detailTagline.Parent = detailCard

local statBars: { [string]: Frame } = {}
local statDefs = {
	{ key = "speed", label = "TOP SPEED", color = Color3.fromRGB(65, 190, 255) },
	{ key = "handling", label = "HANDLING & DRIFT", color = Color3.fromRGB(120, 245, 140) },
	{ key = "armor", label = "CHASSIS ARMOR", color = Color3.fromRGB(255, 195, 60) },
	{ key = "ram", label = "RAMMING POWER", color = Color3.fromRGB(255, 85, 75) },
}

for idx, st in ipairs(statDefs) do
	local yPos = 92 + (idx - 1) * 44
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -32, 0, 18)
	lbl.Position = UDim2.fromOffset(16, yPos)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = st.label
	lbl.TextSize = 12
	lbl.TextColor3 = Color3.fromRGB(210, 220, 240)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = detailCard

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -32, 0, 12)
	barBg.Position = UDim2.fromOffset(16, yPos + 20)
	barBg.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	barBg.BorderSizePixel = 0
	barBg.Parent = detailCard
	addCorner(barBg, 6)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0.5, 1)
	barFill.BackgroundColor3 = st.color
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	addCorner(barFill, 6)
	statBars[st.key] = barFill
end

local actionBtn = Instance.new("TextButton")
actionBtn.Name = "BuyOrEquipBtn"
actionBtn.Size = UDim2.new(1, -32, 0, 48)
actionBtn.Position = UDim2.new(0, 16, 1, -64)
actionBtn.BackgroundColor3 = Color3.fromRGB(45, 180, 95)
actionBtn.Font = Enum.Font.GothamBlack
actionBtn.Text = "EQUIP & SPAWN"
actionBtn.TextSize = 17
actionBtn.TextColor3 = Color3.new(1, 1, 1)
actionBtn.Parent = detailCard
addCorner(actionBtn, 10)

local currentFocusedClass: VehicleClassInfo = VEHICLE_CLASSES[1]
local rowButtons: { [string]: TextButton } = {}

local function refreshVehicleView()
	detailTitle.Text = string.upper(currentFocusedClass.name)
	detailTagline.Text = currentFocusedClass.tagline
	statBars.speed.Size = UDim2.fromScale(currentFocusedClass.speed, 1)
	statBars.handling.Size = UDim2.fromScale(currentFocusedClass.handling, 1)
	statBars.armor.Size = UDim2.fromScale(currentFocusedClass.armor, 1)
	statBars.ram.Size = UDim2.fromScale(currentFocusedClass.ram, 1)

	local unlocked = isVehicleUnlocked(currentFocusedClass.id)
	local equipped = (selectedVehicleId == currentFocusedClass.id)
	if equipped then
		actionBtn.Text = "EQUIPPED • CLICK TO RESPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(50, 135, 235)
	elseif unlocked then
		actionBtn.Text = "EQUIP & SPAWN"
		actionBtn.BackgroundColor3 = Color3.fromRGB(45, 185, 95)
	else
		actionBtn.Text = string.format("BUY & EQUIP  •  $%d", currentFocusedClass.price)
		actionBtn.BackgroundColor3 = Color3.fromRGB(230, 140, 35)
	end

	for _, v in ipairs(VEHICLE_CLASSES) do
		local btn = rowButtons[v.id]
		if btn then
			local vUnlocked = isVehicleUnlocked(v.id)
			local tag = (selectedVehicleId == v.id) and " [EQUIPPED]" or (vUnlocked and " [OWNED]" or string.format(" [$%d]", v.price))
			btn.Text = "  " .. v.name .. tag
			btn.BackgroundColor3 = (currentFocusedClass.id == v.id) and Color3.fromRGB(48, 95, 175) or Color3.fromRGB(30, 36, 52)
		end
	end
end

for _, vInfo in ipairs(VEHICLE_CLASSES) do
	local row = Instance.new("TextButton")
	row.Name = vInfo.id .. "Row"
	row.Size = UDim2.new(1, -10, 0, 46)
	row.BackgroundColor3 = Color3.fromRGB(30, 36, 52)
	row.Font = Enum.Font.GothamBold
	row.TextSize = 14
	row.TextColor3 = Color3.new(1, 1, 1)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = vehicleList
	addCorner(row, 8)
	rowButtons[vInfo.id] = row

	row.MouseButton1Click:Connect(function()
		currentFocusedClass = vInfo
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
-- 2. UPGRADES TAB UI (5 TRACKS, LV 1-5)
-- ==========================================
local upgradeRows: { [string]: { lvlLabel: TextLabel, btn: TextButton, pips: { Frame } } } = {}

local function getUpgradeLevel(trackId: string): number
	local attr = player:GetAttribute(trackId .. "Level") or player:GetAttribute("Upgrade_" .. trackId)
	return math.clamp(tonumber(attr) or 1, 1, 5)
end

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
				local cost = track.baseCost * lvl
				ui.btn.Text = string.format("UPGRADE • $%d", cost)
				ui.btn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
			end
		end
	end
end

for idx, track in ipairs(UPGRADE_TRACKS) do
	local card = Instance.new("Frame")
	card.Name = track.id .. "Track"
	card.Size = UDim2.new(1, 0, 0, 64)
	card.Position = UDim2.fromOffset(0, (idx - 1) * 70)
	card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
	card.BorderSizePixel = 0
	card.Parent = upgradesPage
	addCorner(card, 10)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromOffset(310, 24)
	nameLbl.Position = UDim2.fromOffset(14, 8)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextSize = 15
	nameLbl.TextColor3 = Color3.new(1, 1, 1)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = card

	local descLbl = Instance.new("TextLabel")
	descLbl.Size = UDim2.fromOffset(340, 20)
	descLbl.Position = UDim2.fromOffset(14, 34)
	descLbl.BackgroundTransparency = 1
	descLbl.Font = Enum.Font.GothamMedium
	descLbl.Text = track.desc
	descLbl.TextSize = 12
	descLbl.TextColor3 = Color3.fromRGB(165, 180, 205)
	descLbl.TextXAlignment = Enum.TextXAlignment.Left
	descLbl.Parent = card

	local pips: { Frame } = {}
	for p = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(26, 14)
		pip.Position = UDim2.fromOffset(375 + (p - 1) * 32, 25)
		pip.BackgroundColor3 = Color3.fromRGB(35, 40, 56)
		pip.BorderSizePixel = 0
		pip.Parent = card
		addCorner(pip, 4)
		table.insert(pips, pip)
	end

	local upgBtn = Instance.new("TextButton")
	upgBtn.Name = "Upgrade" .. track.id .. "Btn"
	upgBtn.Size = UDim2.fromOffset(165, 42)
	upgBtn.Position = UDim2.new(1, -178, 0, 11)
	upgBtn.BackgroundColor3 = Color3.fromRGB(45, 175, 95)
	upgBtn.Font = Enum.Font.GothamBlack
	upgBtn.TextSize = 13
	upgBtn.TextColor3 = Color3.new(1, 1, 1)
	upgBtn.Parent = card
	addCorner(upgBtn, 8)

	upgradeRows[track.id] = { lvlLabel = nameLbl, btn = upgBtn, pips = pips }

	upgBtn.MouseButton1Click:Connect(function()
		local lvl = getUpgradeLevel(track.id)
		if lvl >= 5 then return end
		local cost = track.baseCost * lvl
		if getPlayerCash() < cost then
			statusBanner.Text = "Need $" .. tostring(cost) .. " for " .. track.name .. "!"
			statusBanner.TextColor3 = Color3.fromRGB(255, 95, 95)
			return
		end
		local ok, result = callRemote({ "PurchaseUpgrade", "UpgradeVehicle" }, track.id)
		if ok and result ~= false then
			player:SetAttribute(track.id .. "Level", lvl + 1)
			statusBanner.Text = string.format("Upgraded %s to Lv.%d!", track.name, lvl + 1)
			statusBanner.TextColor3 = Color3.fromRGB(115, 255, 150)
		end
		refreshUpgradesView()
	end)
end

-- ==========================================
-- TAB & MODAL TOGGLE CONTROLS
-- ==========================================
local function switchTab(tab: string)
	local isVehicles = (tab == "Vehicles")
	vehiclesPage.Visible = isVehicles
	upgradesPage.Visible = not isVehicles
	vehiclesTabBtn.BackgroundColor3 = isVehicles and Color3.fromRGB(45, 130, 235) or Color3.fromRGB(32, 38, 54)
	upgradesTabBtn.BackgroundColor3 = (not isVehicles) and Color3.fromRGB(45, 130, 235) or Color3.fromRGB(32, 38, 54)
	refreshVehicleView()
	refreshUpgradesView()
end

local function setShopOpen(open: boolean)
	modal.Visible = open
	if open then
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
	end
end)

player:GetAttributeChangedSignal("ToggleShopUI"):Connect(function()
	setShopOpen(not modal.Visible)
end)
player.AttributeChanged:Connect(function()
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
end)

refreshVehicleView()
refreshUpgradesView()
