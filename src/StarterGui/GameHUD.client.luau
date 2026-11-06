--!strict
-- GameHUD.client.luau
-- Sleek, minimal, auto-scaled HUD for World of Destruction:
-- Top-Left Compact Pill, Top-Center Dynamic Combo Banner, Top-Right Compact Radar & Stars,
-- Bottom-Center Compact Action Dock, and Bottom-Right Context-Sensitive Vehicle Speedometer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Immediately disable Roblox's overlapping default leaderboard
pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
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

-- ==========================================
-- 1. TOP-LEFT COMPACT PILL (230x78 at (14, 14))
-- ==========================================
local topLeft = makeFrame("TopLeftPanel", UDim2.fromOffset(230, 78), UDim2.fromOffset(14, 14), Vector2.new(0, 0), Color3.fromRGB(14, 16, 24), 0.18, gui)
addCorner(topLeft, 10)
addStroke(topLeft, Color3.fromRGB(255, 165, 40), 1.5, 0.35)

local cashLabel = makeLabel("CashLabel", "$500", UDim2.new(0.55, -10, 0, 20), UDim2.fromOffset(10, 4), Enum.Font.GothamBlack, 18, Color3.fromRGB(85, 255, 130), Enum.TextXAlignment.Left, topLeft)
local chaosLabel = makeLabel("ChaosLabel", "CHAOS: 0", UDim2.new(0.45, -10, 0, 16), UDim2.new(0.55, 0, 0, 6), Enum.Font.GothamBold, 10, Color3.fromRGB(255, 185, 65), Enum.TextXAlignment.Right, topLeft)

local levelLabel = makeLabel("LevelLabel", "LV.1 • STREET ROOKIE", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 24), Enum.Font.GothamBold, 11, Color3.fromRGB(220, 235, 255), Enum.TextXAlignment.Left, topLeft)
levelLabel.TextTruncate = Enum.TextTruncate.AtEnd

local xpBarBg = makeFrame("XPBarBg", UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 40), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, topLeft)
addCorner(xpBarBg, 2)
local xpBarFill = makeFrame("XPBarFill", UDim2.fromScale(0.15, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(70, 180, 255), 0, xpBarBg)
addCorner(xpBarFill, 2)

local missionRowLabel = makeLabel("ChallengeRow", "Smash 10 Hydrants: 0/10 • $1,000", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 49), Enum.Font.GothamMedium, 10, Color3.fromRGB(185, 235, 195), Enum.TextXAlignment.Left, topLeft)
missionRowLabel.TextTruncate = Enum.TextTruncate.AtEnd

local missionBarBg = makeFrame("MissionBarBg", UDim2.new(1, -20, 0, 4), UDim2.fromOffset(10, 66), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, topLeft)
addCorner(missionBarBg, 2)
local missionBarFill = makeFrame("MissionBarFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 150, 40), 0, missionBarBg)
addCorner(missionBarFill, 2)

-- ==========================================
-- 2. TOP-CENTER COMBO BANNER (280x64 at (0.5, 0, 0, 14))
-- Completely hidden when ComboCount == 0 and no callout is active!
-- ==========================================
local topCenter = makeFrame("ComboContainer", UDim2.fromOffset(280, 64), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0), Color3.fromRGB(15, 15, 22), 0.22, gui)
topCenter.Visible = false
addCorner(topCenter, 10)
local comboStroke = addStroke(topCenter, Color3.fromRGB(255, 95, 35), 1.8, 0.2)

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
-- 4. BOTTOM-CENTER COMPACT ACTION DOCK (420x36 at (0.5, 0, 1, -12))
-- ==========================================
local actionDock = makeFrame("BottomActionDock", UDim2.fromOffset(420, 36), UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1), Color3.fromRGB(14, 16, 24), 0.18, gui)
addCorner(actionDock, 10)
addStroke(actionDock, Color3.fromRGB(70, 95, 140), 1.2, 0.35)

local dockPadding = Instance.new("UIPadding")
dockPadding.PaddingLeft = UDim.new(0, 5)
dockPadding.PaddingRight = UDim.new(0, 5)
dockPadding.PaddingTop = UDim.new(0, 4)
dockPadding.PaddingBottom = UDim.new(0, 4)
dockPadding.Parent = actionDock

local dockLayout = Instance.new("UIListLayout")
dockLayout.FillDirection = Enum.FillDirection.Horizontal
dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dockLayout.Padding = UDim.new(0, 4)
dockLayout.Parent = actionDock

local function triggerQuickAction(actionId: string)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if actionId == "Shop" then
		player:SetAttribute("ToggleShopUI", not player:GetAttribute("ToggleShopUI"))
	elseif actionId == "Avatar" then
		player:SetAttribute("ToggleAvatarUI", not player:GetAttribute("ToggleAvatarUI"))
	elseif actionId == "VIP" then
		player:SetAttribute("ToggleVIPUI", not player:GetAttribute("ToggleVIPUI"))
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

local dockButtons = {
	{ id = "SpawnCar", text = "[V] Spawn Car", color = Color3.fromRGB(40, 165, 95) },
	{ id = "Shop", text = "[B] Garage", color = Color3.fromRGB(45, 125, 220) },
	{ id = "Avatar", text = "[C] Avatar", color = Color3.fromRGB(135, 75, 215) },
	{ id = "Repair", text = "[R] Repair", color = Color3.fromRGB(215, 130, 35) },
	{ id = "VIP", text = "[M] VIP", color = Color3.fromRGB(205, 160, 35) },
	{ id = "Help", text = "[H] Guide", color = Color3.fromRGB(70, 85, 115) },
}

for idx, info in ipairs(dockButtons) do
	local btn = Instance.new("TextButton")
	btn.Name = info.id .. "Btn"
	btn.LayoutOrder = idx
	btn.Size = UDim2.fromOffset(65, 28)
	btn.BackgroundColor3 = info.color
	btn.BackgroundTransparency = 0.15
	btn.Font = Enum.Font.GothamBold
	btn.Text = info.text
	btn.TextSize = 10
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent = actionDock
	addCorner(btn, 6)
	btn.MouseButton1Click:Connect(function()
		triggerQuickAction(info.id)
	end)
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
local speedUnitLabel = makeLabel("SpeedUnit", "MPH", UDim2.fromOffset(38, 16), UDim2.fromOffset(86, 20), Enum.Font.GothamBold, 11, Color3.fromRGB(130, 185, 255), Enum.TextXAlignment.Left, bottomRight)
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

local function updateComboVisibility()
	local hits = tonumber(player:GetAttribute("ComboCount")) or 0
	local calloutActive = (os.clock() < calloutActiveUntil) and (styleCalloutLabel.Text ~= "")
	topCenter.Visible = (hits > 0) or calloutActive
end

local function spawnCashPopup(delta: number)
	if delta <= 0 then
		return
	end
	local pop = makeLabel("CashPopup", "+$" .. formatNumber(delta), UDim2.fromOffset(110, 20), UDim2.fromOffset(110, 4), Enum.Font.GothamBlack, 15, Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Left, topLeft)
	TweenService:Create(pop, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(110, -18),
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
	calloutActiveUntil = os.clock() + 2.2
	styleCalloutLabel.Text = string.upper(text)
	styleCalloutLabel.TextTransparency = 0
	updateComboVisibility()
	task.delay(2.25, function()
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

local function refreshHUDStats()
	local currentCash = readCashValue()
	if lastCash >= 0 and currentCash > lastCash then
		spawnCashPopup(currentCash - lastCash)
	end
	lastCash = currentCash
	cashLabel.Text = "$" .. formatNumber(currentCash)

	local chaos = tonumber(player:GetAttribute("ChaosScore")) or 0
	chaosLabel.Text = "CHAOS: " .. formatNumber(chaos)

	local level = tonumber(player:GetAttribute("Level")) or 1
	local rankTitle = tostring(player:GetAttribute("RankTitle") or "STREET ROOKIE")
	local xpRatio = math.clamp(tonumber(player:GetAttribute("XPProgressRatio")) or 0.15, 0, 1)
	levelLabel.Text = string.format("LV.%d • %s", level, string.upper(rankTitle))
	xpBarFill.Size = UDim2.fromScale(xpRatio, 1)

	local mTitle = tostring(player:GetAttribute("MissionTitle") or "Smash 10 Hydrants")
	local mProg = tonumber(player:GetAttribute("MissionProgress")) or 0
	local mGoal = math.max(1, tonumber(player:GetAttribute("MissionGoal")) or 10)
	local mRew = tonumber(player:GetAttribute("MissionReward")) or 1000
	missionRowLabel.Text = string.format("%s: %d/%d • $%s", mTitle, math.floor(mProg), math.floor(mGoal), formatNumber(mRew))
	missionBarFill.Size = UDim2.fromScale(math.clamp(mProg / mGoal, 0, 1), 1)

	local mult = tonumber(player:GetAttribute("ComboMultiplier")) or 1.0
	local hits = tonumber(player:GetAttribute("ComboCount")) or 0
	local timerRatio = math.clamp(tonumber(player:GetAttribute("ComboTimerRatio") or player:GetAttribute("ComboTimer")) or 0, 0, 1)
	comboTitle.Text = string.format("%.1fx CHAOS COMBO", mult)
	comboHits.Text = string.format("%d %s ACTIVE!", hits, if hits == 1 then "HIT" else "HITS")
	comboTimerFill.Size = UDim2.fromScale(timerRatio, 1)
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
		elseif typeof(msg) == "table" and typeof(msg.Callout) == "string" then
			showStyleCallout(msg.Callout)
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

-- Real-time Vehicle Telemetry + Minimap Radar Loop
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
		local speedMph = tonumber(player:GetAttribute("SpeedMPH")) or 0
		if root and speedMph == 0 then
			speedMph = math.floor(root.AssemblyLinearVelocity.Magnitude * 0.68)
		end
		speedValueLabel.Text = string.format("%03d", math.clamp(math.floor(speedMph), 0, 999))
		local gear = speedMph < 2 and "N" or tostring(math.clamp(math.ceil(speedMph / 28), 1, 6))
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
