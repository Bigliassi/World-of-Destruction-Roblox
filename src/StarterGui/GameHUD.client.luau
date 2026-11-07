--!strict
-- GameHUD.client.luau
-- Sleek, minimal, auto-scaled HUD for World of Destruction:
-- 1. Top-Left Compact Pill at (14, 62) [196x56] (below Roblox TopBar): ONLY Cash ($140,581) + Smash Tier Badge (SMASH TIER 1 • LV. 1)
-- 2. Top-Center Casino Jackpot & Next Car Unlock Bar at (0.5, 0, 0, 10) [380x68]:
--    - Row 1: JACKPOT SPIN ([ 7 | 7 | 7 ]) + glowing gold progress bar (0..100%)
--    - Row 2: NEXT CAR UNLOCK showing next car, what it smashes, and clickable green "GARAGE READY! UNLOCK NEW CAR [PRESS B]" button
-- 3. Top-Center Combo Container: strictly hidden (Visible = false) whenever ComboCount == 0 (hides after 1.2s max)
-- 4. Top-Right Compact Radar & Wanted Stars
-- 5. Bottom-Center Tactile 3D Action Dock & Bottom-Right Vehicle Speedometer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Immediately disable Roblox's overlapping default leaderboard
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
task.spawn(function()
	for _ = 1, 5 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local existingHud = playerGui:FindFirstChild("WorldOfDestructionHUD")
if existingHud then
	existingHud:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "WorldOfDestructionHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Automatic UIScale so the HUD stays sleek and proportional in any viewport size
local uiScale = Instance.new("UIScale")
uiScale.Name = "HUDAutoScale"
uiScale.Scale = 1.0
uiScale.Parent = gui

local cameraConn: RBXScriptConnection? = nil
local function updateHudScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		uiScale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.62, 1.0)
	end
end

local function bindCameraScale()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateHudScale)
		updateHudScale()
	end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraScale)
bindCameraScale()

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0.25
	s.Parent = parent
	return s
end

local function makeFrame(name: string, size: UDim2, pos: UDim2, anchor: Vector2, bg: Color3, trans: number, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = bg
	f.BackgroundTransparency = trans
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function makeLabel(name: string, text: string, size: UDim2, pos: UDim2, font: Enum.Font, textSize: number, color: Color3, xAlign: Enum.TextXAlignment, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = xAlign
	l.TextStrokeTransparency = 0.45
	l.Parent = parent
	return l
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

-- Vehicle Smash Tier & Next Car Unlock Ladder
type NextCarSpec = {
	id: string,
	shortName: string,
	cost: number,
	tier: number,
	targetDesc: string,
}

local CAR_PROGRESSION_LADDER: { NextCarSpec } = {
	{ id = "Sedan", shortName = "SEDAN", cost = 1500, tier = 2, targetDesc = "BREAKS GOLD ATMs & TAXIS!" },
	{ id = "Muscle", shortName = "MUSCLE", cost = 4500, tier = 2, targetDesc = "DRIFT & SMASH HYDRANTS!" },
	{ id = "SUV", shortName = "SUV", cost = 9000, tier = 3, targetDesc = "SMASH ARMORED CASH TRUCKS!" },
	{ id = "Pickup", shortName = "PICKUP", cost = 15000, tier = 3, targetDesc = "RAM GAS STATIONS & COPS!" },
	{ id = "Sports", shortName = "SPORTS", cost = 28000, tier = 3, targetDesc = "200 MPH HYPER SPEED!" },
	{ id = "MonsterTruck", shortName = "MONSTER", cost = 50000, tier = 4, targetDesc = "CRUSH BUSES & SWAT TRUCKS!" },
	{ id = "Bulldozer", shortName = "BULLDOZER", cost = 95000, tier = 5, targetDesc = "BREAK GOLDEN BANK VAULTS!" },
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

local function computeCurrentSmashTier(): number
	local attrTier = tonumber(player:GetAttribute("SmashPowerTier"))
	if attrTier and attrTier >= 1 then
		return math.clamp(math.floor(attrTier), 1, 5)
	end
	local eq = tostring(player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle") or "Compact")
	local baseTier = VEHICLE_BASE_TIER[eq] or 1
	local plowLvl = tonumber(player:GetAttribute("PlowLevel") or player:GetAttribute("Upgrade_Plow")) or 1
	local bonusTier = if plowLvl >= 4 then 1 else 0
	return math.clamp(baseTier + bonusTier, 1, 5)
end

local function getNextLockedCarSpec(): NextCarSpec?
	local unlockedStr = tostring(player:GetAttribute("UnlockedVehicles") or "Compact")
	local equippedStr = tostring(player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle") or "Compact")
	for _, spec in ipairs(CAR_PROGRESSION_LADDER) do
		local isOwned = (string.find(unlockedStr, spec.id, 1, true) ~= nil) or (equippedStr == spec.id)
		if not isOwned then
			return spec
		end
	end
	return nil
end

local function triggerQuickAction(actionId: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if actionId == "Shop" then
		player:SetAttribute("ToggleShopUI", not player:GetAttribute("ToggleShopUI"))
	elseif actionId == "Avatar" then
		player:SetAttribute("ToggleAvatarUI", not player:GetAttribute("ToggleAvatarUI"))
	elseif actionId == "VIP" then
		player:SetAttribute("ToggleVIPUI", not player:GetAttribute("ToggleVIPUI"))
	elseif actionId == "MenuSettings" then
		player:SetAttribute("ToggleSettingsUI", not player:GetAttribute("ToggleSettingsUI"))
	elseif actionId == "Help" then
		player:SetAttribute("ToggleHelpUI", not player:GetAttribute("ToggleHelpUI"))
	elseif actionId == "SpawnCar" and remotes then
		local r = remotes:FindFirstChild("SpawnVehicle") or remotes:FindFirstChild("RequestSpawnVehicle")
		if r and r:IsA("RemoteEvent") then
			r:FireServer(player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle") or "Compact")
		end
	elseif actionId == "Repair" and remotes then
		local r = remotes:FindFirstChild("RepairVehicle") or remotes:FindFirstChild("RequestRepair")
		if r and r:IsA("RemoteEvent") then
			r:FireServer()
		end
	end
end

-- ==========================================
-- 1. TOP-LEFT COMPACT PILL (196x56 at (14, 62) — below Roblox TopBar!)
-- Line 1: $140,581 (big green GothamBlack 24pt)
-- Line 2: SMASH TIER 1 • LV. 1 (gold badge showing current car's Smash Power Tier 1..5)
-- ==========================================
local topLeft = makeFrame("TopLeftPanel", UDim2.fromOffset(196, 56), UDim2.fromOffset(14, 62), Vector2.new(0, 0), Color3.fromRGB(14, 16, 24), 0.14, gui)
addCorner(topLeft, 10)
addStroke(topLeft, Color3.fromRGB(255, 190, 45), 1.6, 0.25)

local cashLabel = makeLabel("CashLabel", "$500", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 4), Enum.Font.GothamBlack, 24, Color3.fromRGB(85, 255, 130), Enum.TextXAlignment.Left, topLeft)
cashLabel.TextScaled = false

local smashTierBadge = makeLabel("SmashTierLabel", "SMASH TIER 1 • LV. 1", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 32), Enum.Font.GothamBlack, 12, Color3.fromRGB(255, 215, 65), Enum.TextXAlignment.Left, topLeft)
smashTierBadge.TextTruncate = Enum.TextTruncate.AtEnd

-- ==========================================
-- 2A. TOP-CENTER CASINO JACKPOT & NEXT CAR UNLOCK BAR (380x68 at (0.5, 0, 0, 10))
-- Row 1: JACKPOT SPIN ([ 7 | 7 | 7 ]) + glowing gold progress bar (JackpotCharge 0..100%)
-- Row 2: NEXT CAR UNLOCK showing what new targets it lets you smash + clickable emerald button when ready
-- ==========================================
local campaignTracker = makeFrame("CasinoJackpotHudCard", UDim2.fromOffset(380, 68), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0), Color3.fromRGB(14, 18, 30), 0.10, gui)
addCorner(campaignTracker, 12)
local campaignStroke = addStroke(campaignTracker, Color3.fromRGB(255, 200, 45), 2.0, 0.12)

-- Row 1 Left: 3-Reel Casino Slot Box ([ 7 | 7 | 7 ])
local slotBox = makeFrame("ThreeReelSlotBox", UDim2.fromOffset(88, 26), UDim2.fromOffset(8, 6), Vector2.new(0, 0), Color3.fromRGB(8, 10, 18), 0, campaignTracker)
addCorner(slotBox, 6)
local slotBoxStroke = addStroke(slotBox, Color3.fromRGB(255, 215, 55), 1.5, 0.15)

local reelLabels: { TextLabel } = {}
local REEL_SYMBOLS = { "7", "$", "3X", "LV", "GT" }
for r = 1, 3 do
	local reelCell = makeFrame("ReelCell_" .. tostring(r), UDim2.fromOffset(25, 20), UDim2.fromOffset(3 + (r - 1) * 28, 3), Vector2.new(0, 0), Color3.fromRGB(20, 25, 42), 0, slotBox)
	addCorner(reelCell, 4)
	addStroke(reelCell, Color3.fromRGB(95, 125, 185), 1, 0.4)
	local rLbl = makeLabel("ReelSymbol_" .. tostring(r), "7", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, 13, Color3.fromRGB(255, 220, 55), Enum.TextXAlignment.Center, reelCell)
	table.insert(reelLabels, rLbl)
end

-- Row 1 Right: Glowing Gold Jackpot Spin Progress Bar
local campaignBarBg = makeFrame("JackpotFeverBarBg", UDim2.new(1, -108, 0, 26), UDim2.fromOffset(100, 6), Vector2.new(0, 0), Color3.fromRGB(10, 12, 20), 0, campaignTracker)
addCorner(campaignBarBg, 6)
addStroke(campaignBarBg, Color3.fromRGB(255, 210, 60), 1.2, 0.35)

local campaignBarFill = makeFrame("JackpotFeverBarFill", UDim2.fromScale(0.15, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 195, 40), 0, campaignBarBg)
addCorner(campaignBarFill, 6)

local campaignBarText = makeLabel("JackpotFeverBarText", "JACKPOT SPIN • 0%", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, 10, Color3.fromRGB(255, 255, 255), Enum.TextXAlignment.Center, campaignBarBg)

-- Row 2: Next Car Unlock Bar (Clickable button that opens SpeedShopUI!)
local nextRideBtn = Instance.new("TextButton")
nextRideBtn.Name = "NextRideUnlockButton"
nextRideBtn.Size = UDim2.new(1, -16, 0, 26)
nextRideBtn.Position = UDim2.fromOffset(8, 36)
nextRideBtn.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
nextRideBtn.BorderSizePixel = 0
nextRideBtn.AutoButtonColor = false
nextRideBtn.Text = ""
nextRideBtn.Parent = campaignTracker
addCorner(nextRideBtn, 6)
local nextRideStroke = addStroke(nextRideBtn, Color3.fromRGB(65, 195, 255), 1.3, 0.25)

local nextRideBarFill = makeFrame("NextRideUnlockBarFill", UDim2.fromScale(0.35, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(38, 175, 95), 0, nextRideBtn)
addCorner(nextRideBarFill, 6)

local nextRideBarText = makeLabel(
	"NextRideUnlockBarText",
	"NEXT: SEDAN ($1,500) -> BREAKS GOLD ATMs & TAXIS!",
	UDim2.new(1, -10, 1, 0),
	UDim2.fromOffset(5, 0),
	Enum.Font.GothamBlack,
	9,
	Color3.fromRGB(255, 255, 255),
	Enum.TextXAlignment.Center,
	nextRideBtn
)
nextRideBarText.TextTruncate = Enum.TextTruncate.AtEnd

nextRideBtn.MouseButton1Click:Connect(function()
	triggerQuickAction("Shop")
end)

local isSpinningReels = false
local function triggerThreeReelSpinAnimation(prizeTitle: string, prizeId: string?)
	if isSpinningReels then
		return
	end
	isSpinningReels = true
	campaignStroke.Color = Color3.fromRGB(255, 235, 85)
	slotBoxStroke.Color = Color3.fromRGB(255, 255, 140)
	campaignBarText.Text = "SPINNING: " .. string.upper(prizeTitle)

	local finalSym = if prizeId == "GoldenFrenzy"
		then "3X"
		elseif prizeId == "InstantLevelUp" then "LV"
		elseif prizeId == "SuperNitroRepair" then "GT"
		elseif prizeId == "MegaCash" then "$"
		else "7"

	task.spawn(function()
		local startAt = os.clock()
		while os.clock() - startAt < 1.15 do
			local elapsed = os.clock() - startAt
			for r = 1, 3 do
				local lockTime = 0.45 + (r - 1) * 0.30
				if elapsed >= lockTime then
					reelLabels[r].Text = finalSym
					reelLabels[r].TextColor3 = Color3.fromRGB(95, 255, 145)
				else
					local sym = REEL_SYMBOLS[math.random(1, #REEL_SYMBOLS)]
					reelLabels[r].Text = sym
					reelLabels[r].TextColor3 = Color3.fromRGB(255, 220, 65)
				end
			end
			task.wait(0.06)
		end
		for r = 1, 3 do
			reelLabels[r].Text = finalSym
			reelLabels[r].TextColor3 = Color3.fromRGB(255, 235, 75)
		end
		campaignBarText.Text = "JACKPOT: " .. string.upper(prizeTitle)
		task.wait(2.4)
		isSpinningReels = false
		campaignStroke.Color = Color3.fromRGB(255, 200, 45)
		slotBoxStroke.Color = Color3.fromRGB(255, 215, 55)
	end)
end

-- ==========================================
-- 2B. TOP-CENTER COMBO BANNER (280x64 at (0.5, 0, 0, 84))
-- Strictly hidden (Visible = false) whenever ComboCount == 0 (hides after 1.2s when ComboCount == 0!)
-- ==========================================
local topCenter = makeFrame("ComboContainer", UDim2.fromOffset(280, 64), UDim2.new(0.5, 0, 0, 84), Vector2.new(0.5, 0), Color3.fromRGB(15, 15, 22), 0.22, gui)
topCenter.Visible = false
addCorner(topCenter, 10)
addStroke(topCenter, Color3.fromRGB(255, 95, 35), 1.8, 0.2)

local comboTitle = makeLabel("ComboMultiplier", "1.0x CHAOS COMBO", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 4), Enum.Font.GothamBlack, 17, Color3.fromRGB(255, 210, 65), Enum.TextXAlignment.Center, topCenter)
local comboHits = makeLabel("ComboHits", "1 HIT ACTIVE!", UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 23), Enum.Font.GothamBold, 11, Color3.fromRGB(255, 140, 80), Enum.TextXAlignment.Center, topCenter)
local comboTimerBg = makeFrame("ComboTimerBg", UDim2.new(1, -24, 0, 5), UDim2.fromOffset(12, 39), Vector2.new(0, 0), Color3.fromRGB(10, 10, 14), 0, topCenter)
addCorner(comboTimerBg, 3)
local comboTimerFill = makeFrame("ComboTimerFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 85, 40), 0, comboTimerBg)
addCorner(comboTimerFill, 3)
local styleCalloutLabel = makeLabel("StyleCallout", "", UDim2.new(1, -12, 0, 15), UDim2.fromOffset(6, 46), Enum.Font.GothamBlack, 12, Color3.fromRGB(255, 245, 130), Enum.TextXAlignment.Center, topCenter)

-- ==========================================
-- 3. TOP-RIGHT COMPACT RADAR & STARS (150x172 at (1, -14, 0, 14))
-- ==========================================
local topRight = makeFrame("TopRightPanel", UDim2.fromOffset(150, 172), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0), Color3.fromRGB(14, 16, 24), 0.18, gui)
addCorner(topRight, 10)
local heatStroke = addStroke(topRight, Color3.fromRGB(90, 130, 255), 1.5, 0.35)

local starLabels: { TextLabel } = {}
for i = 1, 5 do
	local star = makeLabel("Star" .. i, "★", UDim2.fromOffset(22, 20), UDim2.fromOffset(8 + (i - 1) * 27, 4), Enum.Font.GothamBlack, 18, Color3.fromRGB(55, 60, 75), Enum.TextXAlignment.Center, topRight)
	table.insert(starLabels, star)
end

local heatBarBg = makeFrame("HeatBarBg", UDim2.new(1, -16, 0, 4), UDim2.fromOffset(8, 28), Vector2.new(0, 0), Color3.fromRGB(10, 10, 16), 0, topRight)
addCorner(heatBarBg, 2)
local heatBarFill = makeFrame("HeatBarFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 70, 70), 0, heatBarBg)
addCorner(heatBarFill, 2)

local radarFrame = makeFrame("MinimapRadar", UDim2.fromOffset(134, 126), UDim2.fromOffset(8, 38), Vector2.new(0, 0), Color3.fromRGB(18, 24, 32), 0.05, topRight)
radarFrame.ClipsDescendants = true
addCorner(radarFrame, 8)
addStroke(radarFrame, Color3.fromRGB(70, 90, 120), 1, 0.3)

makeFrame("GridH", UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), Color3.fromRGB(45, 55, 72), 0.3, radarFrame)
makeFrame("GridV", UDim2.new(0, 1, 1, 0), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), Color3.fromRGB(45, 55, 72), 0.3, radarFrame)

local shopBlip = makeFrame("ShopBlip", UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(50, 220, 255), 0, radarFrame)
addCorner(shopBlip, 3)
local mechBlip = makeFrame("MechanicBlip", UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(80, 255, 110), 0, radarFrame)
addCorner(mechBlip, 3)
local playerBlip = makeFrame("PlayerBlip", UDim2.fromOffset(8, 8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(255, 230, 60), 0, radarFrame)
addCorner(playerBlip, 4)
addStroke(playerBlip, Color3.new(1, 1, 1), 1.2, 0)

local policeBlipPool: { Frame } = {}
for i = 1, 8 do
	local pBlip = makeFrame("PoliceBlip" .. i, UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(255, 60, 60), 0, radarFrame)
	pBlip.Visible = false
	addCorner(pBlip, 3)
	table.insert(policeBlipPool, pBlip)
end

-- ==========================================
-- 4. BOTTOM-CENTER 3D TACTILE ACTION DOCK (486x44 at (0.5, 0, 1, -12))
-- ==========================================
local actionDock = makeFrame("BottomActionDock", UDim2.fromOffset(486, 44), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1), Color3.fromRGB(14, 16, 26), 0.14, gui)
addCorner(actionDock, 12)
addStroke(actionDock, Color3.fromRGB(85, 115, 170), 1.5, 0.25)

local dockPadding = Instance.new("UIPadding")
dockPadding.PaddingLeft = UDim.new(0, 6)
dockPadding.PaddingRight = UDim.new(0, 6)
dockPadding.PaddingTop = UDim.new(0, 4)
dockPadding.PaddingBottom = UDim.new(0, 4)
dockPadding.Parent = actionDock

local dockLayout = Instance.new("UIListLayout")
dockLayout.FillDirection = Enum.FillDirection.Horizontal
dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dockLayout.Padding = UDim.new(0, 6)
dockLayout.Parent = actionDock

local function makeTactile3DDockButton(order: number, id: string, keyText: string, labelText: string, baseColor: Color3)
	local lip = Instance.new("Frame")
	lip.Name = id .. "BtnContainer"
	lip.LayoutOrder = order
	lip.Size = UDim2.fromOffset(74, 34)
	lip.BackgroundColor3 = Color3.new(baseColor.R * 0.5, baseColor.G * 0.5, baseColor.B * 0.5)
	lip.BorderSizePixel = 0
	lip.Parent = actionDock
	addCorner(lip, 9)

	local face = Instance.new("TextButton")
	face.Name = id .. "Btn"
	face.Size = UDim2.new(1, 0, 1, -4)
	face.Position = UDim2.fromOffset(0, 0)
	face.BackgroundColor3 = baseColor
	face.BorderSizePixel = 0
	face.AutoButtonColor = false
	face.Font = Enum.Font.GothamBlack
	face.Text = "[" .. keyText .. "] " .. labelText
	face.TextSize = 10
	face.TextColor3 = Color3.new(1, 1, 1)
	face.TextStrokeTransparency = 0.45
	face.Parent = lip
	addCorner(face, 8)
	addStroke(face, Color3.new(math.min(1, baseColor.R + 0.22), math.min(1, baseColor.G + 0.22), math.min(1, baseColor.B + 0.22)), 1.2, 0.25)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(math.min(1, baseColor.R + 0.15), math.min(1, baseColor.G + 0.15), math.min(1, baseColor.B + 0.15))),
		ColorSequenceKeypoint.new(1, Color3.new(baseColor.R * 0.85, baseColor.G * 0.85, baseColor.B * 0.85)),
	})
	grad.Parent = face

	local sheen = Instance.new("Frame")
	sheen.Name = "GlossSheen"
	sheen.Size = UDim2.new(1, -4, 0.38, 0)
	sheen.Position = UDim2.fromOffset(2, 1)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.84
	sheen.BorderSizePixel = 0
	sheen.Parent = face
	addCorner(sheen, 6)

	face.MouseEnter:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, -1),
		}):Play()
	end)
	face.MouseLeave:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		}):Play()
	end)
	face.MouseButton1Down:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 3),
		}):Play()
	end)
	face.MouseButton1Up:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		}):Play()
	end)
	face.MouseButton1Click:Connect(function()
		triggerQuickAction(id)
	end)
end

local dockButtons = {
	{ id = "SpawnCar", key = "V", text = "Car", color = Color3.fromRGB(36, 175, 95) },
	{ id = "Shop", key = "B", text = "Garage", color = Color3.fromRGB(42, 128, 225) },
	{ id = "Avatar", key = "C", text = "Avatar", color = Color3.fromRGB(138, 75, 220) },
	{ id = "Repair", key = "R", text = "Repair", color = Color3.fromRGB(220, 132, 35) },
	{ id = "Help", key = "H", text = "Guide", color = Color3.fromRGB(68, 115, 165) },
	{ id = "MenuSettings", key = "P", text = "Settings", color = Color3.fromRGB(195, 145, 38) },
}

for idx, info in ipairs(dockButtons) do
	makeTactile3DDockButton(idx, info.id, info.key, info.text, info.color)
end

-- ==========================================
-- 5. BOTTOM-RIGHT SPEEDOMETER (210x92 at (1, -14, 1, -12))
-- ONLY visible when the player is seated in a vehicle!
-- ==========================================
local bottomRight = makeFrame("BottomRightSpeedometer", UDim2.fromOffset(210, 92), UDim2.new(1, -14, 1, -12), Vector2.new(1, 1), Color3.fromRGB(14, 16, 24), 0.16, gui)
bottomRight.Visible = false
addCorner(bottomRight, 10)
addStroke(bottomRight, Color3.fromRGB(80, 175, 255), 1.5, 0.35)

local speedValueLabel = makeLabel("SpeedValue", "000", UDim2.fromOffset(74, 34), UDim2.fromOffset(12, 6), Enum.Font.GothamBlack, 30, Color3.fromRGB(245, 250, 255), Enum.TextXAlignment.Left, bottomRight)
makeLabel("SpeedUnit", "MPH", UDim2.fromOffset(38, 16), UDim2.fromOffset(86, 20), Enum.Font.GothamBold, 11, Color3.fromRGB(130, 185, 255), Enum.TextXAlignment.Left, bottomRight)
local gearBadge = makeLabel("GearBadge", "GEAR: N", UDim2.fromOffset(76, 20), UDim2.new(1, -88, 0, 12), Enum.Font.GothamBlack, 12, Color3.fromRGB(255, 200, 65), Enum.TextXAlignment.Right, bottomRight)

makeLabel("HealthTag", "ARMOR", UDim2.fromOffset(48, 14), UDim2.fromOffset(12, 46), Enum.Font.GothamBold, 10, Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Left, bottomRight)
local healthBarBg = makeFrame("HealthBarBg", UDim2.new(1, -74, 0, 8), UDim2.fromOffset(62, 49), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, bottomRight)
addCorner(healthBarBg, 4)
local healthBarFill = makeFrame("HealthBarFill", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(65, 235, 115), 0, healthBarBg)
addCorner(healthBarFill, 4)

makeLabel("NitroTag", "NITRO", UDim2.fromOffset(48, 14), UDim2.fromOffset(12, 66), Enum.Font.GothamBold, 10, Color3.fromRGB(90, 205, 255), Enum.TextXAlignment.Left, bottomRight)
local nitroBarBg = makeFrame("NitroBarBg", UDim2.new(1, -74, 0, 8), UDim2.fromOffset(62, 69), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, bottomRight)
addCorner(nitroBarBg, 4)
local nitroBarFill = makeFrame("NitroBarFill", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(50, 185, 255), 0, nitroBarBg)
addCorner(nitroBarFill, 4)

-- ==========================================
-- 6. MOBILE / TOUCH CONTROLS
-- ==========================================
local touchContainer: Frame? = nil
if UserInputService.TouchEnabled then
	local tc = makeFrame("TouchControls", UDim2.new(1, 0, 0, 150), UDim2.new(0, 0, 1, -54), Vector2.new(0, 1), Color3.new(0, 0, 0), 1, gui)
	tc.Visible = false
	touchContainer = tc
	local function makeTouchBtn(name: string, label: string, pos: UDim2, size: UDim2, bg: Color3, onHold: (boolean) -> ())
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = label
		b.Size = size
		b.Position = pos
		b.BackgroundColor3 = bg
		b.BackgroundTransparency = 0.3
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 14
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = tc
		addCorner(b, 10)
		b.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
				onHold(true)
			end
		end)
		b.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
				onHold(false)
			end
		end)
	end

	makeTouchBtn("SteerLeft", "◀", UDim2.fromOffset(18, 72), UDim2.fromOffset(64, 64), Color3.fromRGB(45, 55, 75), function(down)
		player:SetAttribute("TouchSteer", down and -1 or 0)
	end)
	makeTouchBtn("SteerRight", "▶", UDim2.fromOffset(90, 72), UDim2.fromOffset(64, 64), Color3.fromRGB(45, 55, 75), function(down)
		player:SetAttribute("TouchSteer", down and 1 or 0)
	end)
	makeTouchBtn("Throttle", "GAS", UDim2.new(1, -296, 0, 72), UDim2.fromOffset(68, 64), Color3.fromRGB(45, 180, 90), function(down)
		player:SetAttribute("TouchThrottle", down and 1 or 0)
	end)
	makeTouchBtn("Brake", "BRAKE", UDim2.new(1, -372, 0, 72), UDim2.fromOffset(68, 64), Color3.fromRGB(210, 65, 65), function(down)
		player:SetAttribute("TouchThrottle", down and -1 or 0)
	end)
	makeTouchBtn("Drift", "DRIFT", UDim2.new(1, -372, 0, 10), UDim2.fromOffset(68, 54), Color3.fromRGB(220, 145, 40), function(down)
		player:SetAttribute("TouchDrift", down)
	end)
	makeTouchBtn("Nitro", "NITRO", UDim2.new(1, -296, 0, 10), UDim2.fromOffset(68, 54), Color3.fromRGB(45, 165, 250), function(down)
		player:SetAttribute("TouchNitro", down)
	end)
end

-- ==========================================
-- 7. STATE UPDATES, POPUPS & REMOTES
-- ==========================================
local lastCash = -1
local calloutActiveUntil = 0
local lastComboHitAt = 0

local function updateComboVisibility()
	local hits = tonumber(player:GetAttribute("ComboCount")) or 0
	if hits > 0 then
		lastComboHitAt = os.clock()
		topCenter.Visible = true
		return
	end
	-- When ComboCount == 0, hide within 1.2s and never leave 0 HITS ACTIVE on screen
	local withinFadeWindow = (os.clock() - lastComboHitAt < 1.2) and (os.clock() < calloutActiveUntil) and (styleCalloutLabel.Text ~= "")
	if not withinFadeWindow then
		topCenter.Visible = false
		styleCalloutLabel.Text = ""
	else
		topCenter.Visible = true
	end
end

local function spawnCashPopup(delta: number)
	if delta <= 0 then
		return
	end
	local pop = makeLabel("CashPopup", "+$" .. formatNumber(delta), UDim2.fromOffset(110, 20), UDim2.fromOffset(96, 2), Enum.Font.GothamBlack, 15, Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Left, topLeft)
	TweenService:Create(pop, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(96, -18),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.9, function()
		pop:Destroy()
	end)
end

local function showStyleCallout(text: string)
	if #text == 0 then
		return
	end
	calloutActiveUntil = os.clock() + 1.2
	styleCalloutLabel.Text = string.upper(text)
	styleCalloutLabel.TextTransparency = 0
	updateComboVisibility()
	task.delay(1.2, function()
		if os.clock() >= calloutActiveUntil then
			styleCalloutLabel.Text = ""
			updateComboVisibility()
		end
	end)
end

local function readCashValue(): number
	local attrCash = player:GetAttribute("Cash")
	if typeof(attrCash) == "number" then
		return attrCash
	end
	local ls = player:FindFirstChild("leaderstats")
	local cashObj = ls and ls:FindFirstChild("Cash")
	if cashObj and cashObj:IsA("ValueBase") then
		return tonumber(cashObj.Value) or 0
	end
	return 500
end

local isGarageReadyState = false

local tutorialRingPart: Part? = nil
local function updateTutorial3DRing(targetPos: Vector3?)
	if not targetPos or player:GetAttribute("HomeMenuActive") == true then
		if tutorialRingPart then
			tutorialRingPart.Transparency = 1
		end
		return
	end
	if not tutorialRingPart or not tutorialRingPart.Parent then
		local p = Instance.new("Part")
		p.Name = "WODTutorialTargetRing"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.28, 12, 12)
		p.Color = Color3.fromRGB(65, 255, 130)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 0.35
		p.Parent = Workspace
		tutorialRingPart = p
	end
	if tutorialRingPart then
		tutorialRingPart.Transparency = 0.35
		tutorialRingPart.CFrame = CFrame.new(targetPos.X, 0.72, targetPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function refreshHUDStats()
	local currentCash = readCashValue()
	if lastCash >= 0 and currentCash > lastCash then
		spawnCashPopup(currentCash - lastCash)
	end
	lastCash = currentCash

	-- Top-Left Compact Pill: Line 1 = Cash, Line 2 = SMASH TIER X • LV. Y
	cashLabel.Text = "$" .. formatNumber(currentCash)
	local level = tonumber(player:GetAttribute("Level")) or 1
	local smashTier = computeCurrentSmashTier()
	local plowLvl = tonumber(player:GetAttribute("PlowLevel") or player:GetAttribute("Upgrade_Plow")) or 1
	local destCount = tonumber(player:GetAttribute("TotalDestructions")) or 0
	smashTierBadge.Text = string.format("SMASH TIER %d • LV. %d", smashTier, level)

	-- Top-Center Row 1: JACKPOT SPIN ([ 7 | 7 | 7 ]) + glowing gold progress bar (0..100%)
	local jackpotCharge = math.clamp(tonumber(player:GetAttribute("JackpotCharge")) or 0, 0, 100)
	local frenzyActive = player:GetAttribute("Golden3xFrenzyActive") == true
	local frenzyRem = math.ceil(tonumber(player:GetAttribute("Golden3xFrenzyRemaining")) or 0)
	local bossActive = player:GetAttribute("BossActive") == true

	if bossActive then
		local bHp = tonumber(player:GetAttribute("BossHealth")) or 1000
		local bMax = math.max(1, tonumber(player:GetAttribute("BossMaxHealth")) or 1000)
		campaignBarFill.BackgroundColor3 = Color3.fromRGB(255, 60, 70)
		campaignBarFill.Size = UDim2.fromScale(math.clamp(bHp / bMax, 0, 1), 1)
		campaignBarText.Text = string.format("BOSS GOLIATH: %d / %d HP", math.floor(bHp), math.floor(bMax))
	elseif frenzyActive and frenzyRem > 0 then
		campaignBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 35)
		campaignBarFill.Size = UDim2.fromScale(math.clamp(frenzyRem / 30, 0, 1), 1)
		campaignBarText.Text = string.format("3X CASH FRENZY • %ds", frenzyRem)
	elseif not isSpinningReels then
		campaignBarFill.BackgroundColor3 = Color3.fromRGB(255, 195, 40)
		campaignBarFill.Size = UDim2.fromScale(math.clamp(jackpotCharge / 100, 0.04, 1), 1)
		campaignBarText.Text = string.format("JACKPOT SPIN • %d%%", math.floor(jackpotCharge))
	end

	-- Top-Center Row 2: Interactive 3-Step Tutorial -> seamlessly transitions into Next Car Unlock Goal!
	local nextSpec = getNextLockedCarSpec()
	local hasUpgradedCarOrPlow = (smashTier >= 2) or (plowLvl >= 2)

	if not hasUpgradedCarOrPlow and destCount < 5 and currentCash < 1500 then
		-- Tutorial Step 1: Smash 5 objects right ahead on Grand Central Ave
		isGarageReadyState = false
		nextRideBarFill.Size = UDim2.fromScale(math.clamp(destCount / 5, 0.08, 1), 1)
		nextRideBarFill.BackgroundColor3 = Color3.fromRGB(45, 205, 110)
		nextRideStroke.Color = Color3.fromRGB(85, 255, 145)
		nextRideBarText.Text = string.format("STEP 1/3: PRESS [W] & SMASH 5 OBJECTS AHEAD! (%d/5)", destCount)
		updateTutorial3DRing(Vector3.new(0, 0.72, 4))
	elseif not hasUpgradedCarOrPlow and destCount < 10 and currentCash < 1500 then
		-- Tutorial Step 2: Hold Shift Nitro & hit the Grand Ave Ramp ahead (or smash 10 props)
		isGarageReadyState = false
		nextRideBarFill.Size = UDim2.fromScale(math.clamp(destCount / 10, 0.15, 1), 1)
		nextRideBarFill.BackgroundColor3 = Color3.fromRGB(45, 165, 245)
		nextRideStroke.Color = Color3.fromRGB(95, 215, 255)
		nextRideBarText.Text = string.format("STEP 2/3: HOLD [SHIFT] NITRO & HIT RAMP AHEAD! (%d/10)", destCount)
		updateTutorial3DRing(Vector3.new(0, 0.72, -56))
	elseif not hasUpgradedCarOrPlow and (destCount >= 10 or currentCash >= 400) then
		-- Tutorial Step 3: Open Garage [B] to upgrade Plow or buy Tier 2 Sedan
		isGarageReadyState = true
		nextRideBarFill.Size = UDim2.fromScale(1, 1)
		nextRideBarFill.BackgroundColor3 = Color3.fromRGB(28, 225, 105)
		nextRideStroke.Color = Color3.fromRGB(80, 255, 145)
		if currentCash >= 1500 then
			nextRideBarText.Text = "STEP 3/3: PRESS [B] OR CLICK HERE TO BUY TIER 2 SEDAN ($1,500)!"
		else
			nextRideBarText.Text = "STEP 3/3: PRESS [B] OR CLICK HERE TO UPGRADE YOUR PLOW ($400)!"
		end
		updateTutorial3DRing(Vector3.new(52, 0.72, -38))
	elseif nextSpec then
		updateTutorial3DRing(nil)
		local ratio = math.clamp(currentCash / math.max(1, nextSpec.cost), 0, 1)
		nextRideBarFill.Size = UDim2.fromScale(ratio, 1)
		if currentCash >= nextSpec.cost then
			isGarageReadyState = true
			nextRideBarFill.BackgroundColor3 = Color3.fromRGB(28, 225, 105)
			nextRideStroke.Color = Color3.fromRGB(80, 255, 145)
			nextRideBarText.Text = "GARAGE READY! UNLOCK " .. nextSpec.shortName .. " [PRESS B]"
		else
			isGarageReadyState = false
			nextRideBarFill.BackgroundColor3 = Color3.fromRGB(36, 145, 225)
			nextRideStroke.Color = Color3.fromRGB(65, 195, 255)
			nextRideBarText.Text = string.format(
				"NEXT: %s ($%s) -> %s",
				nextSpec.shortName,
				formatNumber(nextSpec.cost),
				nextSpec.targetDesc
			)
		end
	else
		updateTutorial3DRing(nil)
		isGarageReadyState = false
		nextRideBarFill.Size = UDim2.fromScale(1, 1)
		nextRideBarFill.BackgroundColor3 = Color3.fromRGB(235, 180, 35)
		nextRideStroke.Color = Color3.fromRGB(255, 215, 65)
		nextRideBarText.Text = "ALL TIER 5 CARS UNLOCKED • UPGRADE IN GARAGE [B]"
	end

	-- Hide HUD cleanly while Home Menu is active
	gui.Enabled = (player:GetAttribute("HomeMenuActive") ~= true)

	local mult = tonumber(player:GetAttribute("ComboMultiplier")) or 1.0
	local hits = tonumber(player:GetAttribute("ComboCount")) or 0
	local timerRatio = math.clamp(tonumber(player:GetAttribute("ComboTimerRatio") or player:GetAttribute("ComboTimer")) or 0, 0, 1)
	if hits > 0 then
		comboTitle.Text = string.format("%.1fx CHAOS COMBO", mult)
		comboHits.Text = string.format("%d %s ACTIVE!", hits, if hits == 1 then "HIT" else "HITS")
		comboTimerFill.Size = UDim2.fromScale(timerRatio, 1)
	end
	updateComboVisibility()

	local stars = math.clamp(tonumber(player:GetAttribute("HeatStars") or player:GetAttribute("WantedLevel")) or 0, 0, 5)
	local rawHeatProg = tonumber(player:GetAttribute("HeatProgressNormalized") or player:GetAttribute("HeatProgress")) or 0
	if rawHeatProg > 1 then
		rawHeatProg = rawHeatProg / 100
	end
	local heatProg = math.clamp(rawHeatProg, 0, 1)
	for i = 1, 5 do
		starLabels[i].TextColor3 = i <= stars and Color3.fromRGB(255, 205, 50) or Color3.fromRGB(55, 60, 75)
	end
	heatBarFill.Size = UDim2.fromScale(heatProg, 1)
end

player.AttributeChanged:Connect(refreshHUDStats)
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return
	end
	local function connectRemote(name: string, fn: (...any) -> ())
		local r = remotes:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(fn)
		end
	end
	connectRemote("StyleCallout", function(msg: any)
		if typeof(msg) == "string" then
			showStyleCallout(msg)
		elseif typeof(msg) == "table" then
			if msg.IsJackpotSpin == true then
				triggerThreeReelSpinAnimation(tostring(msg.PrizeTitle or msg.Callout or "JACKPOT!"), tostring(msg.PrizeId or ""))
			end
			if typeof(msg.Callout) == "string" then
				showStyleCallout(msg.Callout)
			end
		end
	end)
	connectRemote("ComboUpdated", function(mult: any, count: any, ratio: any, callout: any)
		if typeof(mult) == "number" then
			player:SetAttribute("ComboMultiplier", mult)
		end
		if typeof(count) == "number" then
			player:SetAttribute("ComboCount", count)
		end
		if typeof(ratio) == "number" then
			player:SetAttribute("ComboTimer", ratio)
		end
		if typeof(callout) == "string" and #callout > 0 then
			showStyleCallout(callout)
		end
		refreshHUDStats()
	end)
	connectRemote("DamageDealt", function(_pos: any, _dmg: any, callout: any)
		if typeof(callout) == "string" and #callout > 0 then
			showStyleCallout(callout)
		end
	end)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.V then
		triggerQuickAction("SpawnCar")
	elseif input.KeyCode == Enum.KeyCode.R then
		triggerQuickAction("Repair")
	end
end)

-- Real-time Vehicle Telemetry + Minimap Radar + Casino Ready Pulse Loop
local sirenClock = 0
RunService.RenderStepped:Connect(function(dt: number)
	sirenClock += dt * 7
	local stars = tonumber(player:GetAttribute("HeatStars") or player:GetAttribute("WantedLevel")) or 0
	if stars > 0 then
		local isRed = math.sin(sirenClock) >= 0
		heatStroke.Color = isRed and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 140, 255)
		heatStroke.Transparency = 0.05
	else
		heatStroke.Color = Color3.fromRGB(90, 130, 255)
		heatStroke.Transparency = 0.35
	end

	-- Pulse the Next Car Unlock bar bright emerald green when Cash >= Cost
	if isGarageReadyState then
		local pulse = (math.sin(sirenClock * 0.9) + 1) * 0.5
		nextRideBarFill.BackgroundColor3 = Color3.fromRGB(
			math.floor(24 + pulse * 45),
			math.floor(195 + pulse * 60),
			math.floor(90 + pulse * 45)
		)
	end

	updateComboVisibility()

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	local inVehicle = (humanoid ~= nil and (humanoid.Sit == true or humanoid.SeatPart ~= nil))
		or (player:GetAttribute("InVehicle") == true)
		or (player:GetAttribute("IsDriving") == true)

	bottomRight.Visible = inVehicle
	if touchContainer then
		touchContainer.Visible = inVehicle
	end

	if inVehicle then
		local speedMph = tonumber(player:GetAttribute("VehicleSpeedMPH") or player:GetAttribute("SpeedMPH")) or 0
		if root and speedMph == 0 then
			speedMph = math.floor(root.AssemblyLinearVelocity.Magnitude * 0.68)
		end
		speedValueLabel.Text = string.format("%03d", math.clamp(math.floor(speedMph), 0, 999))
		local gear = tostring(player:GetAttribute("CurrentGear") or player:GetAttribute("Gear") or (speedMph < 2 and "N" or tostring(math.clamp(math.ceil(speedMph / 22), 1, 5))))
		gearBadge.Text = "GEAR: " .. gear

		local maxVehHp = tonumber(player:GetAttribute("VehicleMaxHealth") or player:GetAttribute("MaxVehicleHealth")) or 100
		local vHealth = math.clamp((tonumber(player:GetAttribute("VehicleHealth")) or 100) / math.max(1, maxVehHp), 0, 1)
		local nitro = math.clamp((tonumber(player:GetAttribute("NitroFuel")) or 100) / math.max(1, tonumber(player:GetAttribute("MaxNitroFuel")) or 100), 0, 1)
		healthBarFill.Size = UDim2.fromScale(vHealth, 1)
		nitroBarFill.Size = UDim2.fromScale(nitro, 1)
	end

	-- Minimap coordinate projection (1 stud = 1/700 radar scale)
	if root then
		local pPos = root.Position
		local function mapOffset(worldPos: Vector3): UDim2
			local dx = math.clamp((worldPos.X - pPos.X) / 700, -0.45, 0.45)
			local dz = math.clamp((worldPos.Z - pPos.Z) / 700, -0.45, 0.45)
			return UDim2.fromScale(0.5 + dx, 0.5 + dz)
		end
		shopBlip.Position = mapOffset(Vector3.new(48, 0, -24))
		mechBlip.Position = mapOffset(Vector3.new(-48, 0, -24))

		local policeFolder = Workspace:FindFirstChild("PoliceUnits") or Workspace:FindFirstChild("ActivePolice")
		local children = policeFolder and policeFolder:GetChildren() or {}
		for i, blip in ipairs(policeBlipPool) do
			local unit = children[i]
			local unitPart = unit and (unit:IsA("BasePart") and unit or (unit:IsA("Model") and unit.PrimaryPart))
			if unitPart then
				blip.Visible = true
				blip.Position = mapOffset(unitPart.Position)
			else
				blip.Visible = false
			end
		end
	end
end)

refreshHUDStats()
