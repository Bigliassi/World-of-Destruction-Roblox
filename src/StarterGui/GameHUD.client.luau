--!strict
-- GameHUD.client.luau
-- Main tactical HUD for World of Destruction: Cash/XP, Chaos Combo, Heat Stars, Minimap, Speedometer, and Touch Controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0.25
	s.Parent = parent
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
		if k == 0 then break end
	end
	return formatted
end

-- ==========================================
-- 1. TOP-LEFT: CASH, CHAOS, LEVEL & CHALLENGE
-- ==========================================
local topLeft = makeFrame("TopLeftPanel", UDim2.fromOffset(310, 210), UDim2.fromOffset(18, 52), Vector2.new(0, 0), Color3.fromRGB(14, 16, 24), 0.18, gui)
addCorner(topLeft, 10)
addStroke(topLeft, Color3.fromRGB(255, 165, 40), 1.5, 0.35)

local cashLabel = makeLabel("CashLabel", "$0", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(12, 8), Enum.Font.GothamBlack, 28, Color3.fromRGB(85, 255, 130), Enum.TextXAlignment.Left, topLeft)
local chaosLabel = makeLabel("ChaosLabel", "CHAOS: 0", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 42), Enum.Font.GothamBold, 15, Color3.fromRGB(255, 185, 65), Enum.TextXAlignment.Left, topLeft)

local rankBadge = makeFrame("RankBadge", UDim2.new(1, -24, 0, 38), UDim2.fromOffset(12, 68), Vector2.new(0, 0), Color3.fromRGB(24, 28, 42), 0.1, topLeft)
addCorner(rankBadge, 6)
local levelLabel = makeLabel("LevelLabel", "LV. 1 • ROOKIE WRECKER", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 3), Enum.Font.GothamBold, 13, Color3.fromRGB(220, 235, 255), Enum.TextXAlignment.Left, rankBadge)
local xpBarBg = makeFrame("XPBarBg", UDim2.new(1, -16, 0, 7), UDim2.fromOffset(8, 25), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, rankBadge)
addCorner(xpBarBg, 4)
local xpBarFill = makeFrame("XPBarFill", UDim2.fromScale(0.15, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(70, 180, 255), 0, xpBarBg)
addCorner(xpBarFill, 4)

local missionBanner = makeFrame("ChallengeBanner", UDim2.new(1, -24, 0, 82), UDim2.fromOffset(12, 114), Vector2.new(0, 0), Color3.fromRGB(28, 22, 34), 0.12, topLeft)
addCorner(missionBanner, 8)
addStroke(missionBanner, Color3.fromRGB(255, 120, 50), 1, 0.4)
local missionHeader = makeLabel("MissionHeader", "ACTIVE CHALLENGE", UDim2.new(0.65, 0, 0, 18), UDim2.fromOffset(10, 5), Enum.Font.GothamBlack, 11, Color3.fromRGB(255, 145, 55), Enum.TextXAlignment.Left, missionBanner)
local missionTimer = makeLabel("MissionTimer", "02:00", UDim2.new(0.35, -10, 0, 18), UDim2.new(0.65, 0, 0, 5), Enum.Font.GothamBold, 12, Color3.fromRGB(255, 220, 120), Enum.TextXAlignment.Right, missionBanner)
local missionTitle = makeLabel("MissionTitle", "Smash 15 Street Props", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 23), Enum.Font.GothamBold, 14, Color3.fromRGB(245, 245, 255), Enum.TextXAlignment.Left, missionBanner)
local missionSub = makeLabel("MissionSub", "0 / 15  •  Reward: $1,500", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 43), Enum.Font.GothamMedium, 12, Color3.fromRGB(175, 235, 185), Enum.TextXAlignment.Left, missionBanner)
local missionBarBg = makeFrame("MissionBarBg", UDim2.new(1, -20, 0, 8), UDim2.fromOffset(10, 64), Vector2.new(0, 0), Color3.fromRGB(12, 12, 18), 0, missionBanner)
addCorner(missionBarBg, 4)
local missionBarFill = makeFrame("MissionBarFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 150, 40), 0, missionBarBg)
addCorner(missionBarFill, 4)

-- ==========================================
-- 2. TOP-CENTER: CHAOS COMBO & STYLE CALLOUTS
-- ==========================================
local topCenter = makeFrame("ComboContainer", UDim2.fromOffset(340, 100), UDim2.new(0.5, 0, 0, 48), Vector2.new(0.5, 0), Color3.fromRGB(15, 15, 22), 0.25, gui)
addCorner(topCenter, 10)
local comboStroke = Instance.new("UIStroke")
comboStroke.Color = Color3.fromRGB(255, 95, 35)
comboStroke.Thickness = 2
comboStroke.Transparency = 0.2
comboStroke.Parent = topCenter

local comboTitle = makeLabel("ComboMultiplier", "1.0x CHAOS COMBO", UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 6), Enum.Font.GothamBlack, 24, Color3.fromRGB(255, 210, 65), Enum.TextXAlignment.Center, topCenter)
local comboHits = makeLabel("ComboHits", "0 HITS • READY TO WRECK", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 38), Enum.Font.GothamBold, 14, Color3.fromRGB(255, 140, 80), Enum.TextXAlignment.Center, topCenter)
local comboTimerBg = makeFrame("ComboTimerBg", UDim2.new(1, -28, 0, 9), UDim2.fromOffset(14, 62), Vector2.new(0, 0), Color3.fromRGB(10, 10, 14), 0, topCenter)
addCorner(comboTimerBg, 4)
local comboTimerFill = makeFrame("ComboTimerFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 85, 40), 0, comboTimerBg)
addCorner(comboTimerFill, 4)
local styleCalloutLabel = makeLabel("StyleCallout", "", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 74), Enum.Font.GothamBlack, 16, Color3.fromRGB(255, 245, 130), Enum.TextXAlignment.Center, topCenter)

-- ==========================================
-- 3. TOP-RIGHT: 5-STAR HEAT & MINIMAP RADAR
-- ==========================================
local topRight = makeFrame("TopRightPanel", UDim2.fromOffset(220, 248), UDim2.new(1, -18, 0, 52), Vector2.new(1, 0), Color3.fromRGB(14, 16, 24), 0.18, gui)
addCorner(topRight, 10)
local heatStroke = Instance.new("UIStroke")
heatStroke.Color = Color3.fromRGB(90, 130, 255)
heatStroke.Thickness = 1.5
heatStroke.Transparency = 0.35
heatStroke.Parent = topRight

local starLabels: { TextLabel } = {}
for i = 1, 5 do
	local star = makeLabel("Star" .. i, "★", UDim2.fromOffset(34, 30), UDim2.fromOffset(14 + (i - 1) * 38, 6), Enum.Font.GothamBlack, 26, Color3.fromRGB(55, 60, 75), Enum.TextXAlignment.Center, topRight)
	table.insert(starLabels, star)
end

local heatStatusLabel = makeLabel("HeatStatus", "HEAT CLEAR", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 36), Enum.Font.GothamBold, 11, Color3.fromRGB(140, 165, 210), Enum.TextXAlignment.Center, topRight)
local heatBarBg = makeFrame("HeatBarBg", UDim2.new(1, -24, 0, 6), UDim2.fromOffset(12, 54), Vector2.new(0, 0), Color3.fromRGB(10, 10, 16), 0, topRight)
addCorner(heatBarBg, 3)
local heatBarFill = makeFrame("HeatBarFill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(255, 70, 70), 0, heatBarBg)
addCorner(heatBarFill, 3)

local radarFrame = makeFrame("MinimapRadar", UDim2.fromOffset(196, 170), UDim2.fromOffset(12, 66), Vector2.new(0, 0), Color3.fromRGB(18, 24, 32), 0.05, topRight)
radarFrame.ClipsDescendants = true
addCorner(radarFrame, 8)
addStroke(radarFrame, Color3.fromRGB(70, 90, 120), 1, 0.3)

-- Static crosshairs for road grid reference
makeFrame("GridH", UDim2.new(1, 0, 0, 2), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), Color3.fromRGB(45, 55, 72), 0.3, radarFrame)
makeFrame("GridV", UDim2.new(0, 2, 1, 0), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), Color3.fromRGB(45, 55, 72), 0.3, radarFrame)

local shopBlip = makeFrame("ShopBlip", UDim2.fromOffset(8, 8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(50, 220, 255), 0, radarFrame)
addCorner(shopBlip, 4)
local mechBlip = makeFrame("MechanicBlip", UDim2.fromOffset(8, 8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(80, 255, 110), 0, radarFrame)
addCorner(mechBlip, 4)
local playerBlip = makeFrame("PlayerBlip", UDim2.fromOffset(10, 10), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(255, 230, 60), 0, radarFrame)
addCorner(playerBlip, 5)
addStroke(playerBlip, Color3.new(1, 1, 1), 1.5, 0)

local policeBlipPool: { Frame } = {}
for i = 1, 8 do
	local pBlip = makeFrame("PoliceBlip" .. i, UDim2.fromOffset(7, 7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Color3.fromRGB(255, 60, 60), 0, radarFrame)
	pBlip.Visible = false
	addCorner(pBlip, 4)
	table.insert(policeBlipPool, pBlip)
end

-- ==========================================
-- 4. BOTTOM-RIGHT: SPEEDOMETER, BARS & QUICK ACTIONS
-- ==========================================
local bottomRight = makeFrame("BottomRightPanel", UDim2.fromOffset(320, 195), UDim2.new(1, -18, 1, -18), Vector2.new(1, 1), Color3.fromRGB(14, 16, 24), 0.16, gui)
addCorner(bottomRight, 10)
addStroke(bottomRight, Color3.fromRGB(80, 175, 255), 1.5, 0.35)

local speedValueLabel = makeLabel("SpeedValue", "000", UDim2.fromOffset(120, 52), UDim2.fromOffset(14, 8), Enum.Font.GothamBlack, 44, Color3.fromRGB(245, 250, 255), Enum.TextXAlignment.Left, bottomRight)
local speedUnitLabel = makeLabel("SpeedUnit", "MPH", UDim2.fromOffset(50, 20), UDim2.fromOffset(132, 34), Enum.Font.GothamBold, 14, Color3.fromRGB(130, 185, 255), Enum.TextXAlignment.Left, bottomRight)
local gearBadge = makeLabel("GearBadge", "GEAR: N", UDim2.fromOffset(110, 26), UDim2.new(1, -124, 0, 16), Enum.Font.GothamBlack, 16, Color3.fromRGB(255, 200, 65), Enum.TextXAlignment.Right, bottomRight)

-- Vehicle Health Bar
makeLabel("HealthTag", "ARMOR", UDim2.fromOffset(60, 16), UDim2.fromOffset(14, 64), Enum.Font.GothamBold, 11, Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Left, bottomRight)
local healthBarBg = makeFrame("HealthBarBg", UDim2.new(1, -86, 0, 10), UDim2.fromOffset(72, 67), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, bottomRight)
addCorner(healthBarBg, 5)
local healthBarFill = makeFrame("HealthBarFill", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(65, 235, 115), 0, healthBarBg)
addCorner(healthBarFill, 5)

-- Nitro Bar
makeLabel("NitroTag", "NITRO", UDim2.fromOffset(60, 16), UDim2.fromOffset(14, 84), Enum.Font.GothamBold, 11, Color3.fromRGB(90, 205, 255), Enum.TextXAlignment.Left, bottomRight)
local nitroBarBg = makeFrame("NitroBarBg", UDim2.new(1, -86, 0, 10), UDim2.fromOffset(72, 87), Vector2.new(0, 0), Color3.fromRGB(10, 12, 18), 0, bottomRight)
addCorner(nitroBarBg, 5)
local nitroBarFill = makeFrame("NitroBarFill", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), Color3.fromRGB(50, 185, 255), 0, nitroBarBg)
addCorner(nitroBarFill, 5)

-- Quick Action Grid (2x3)
local actionsGrid = makeFrame("QuickActions", UDim2.new(1, -24, 0, 74), UDim2.fromOffset(12, 108), Vector2.new(0, 0), Color3.new(0, 0, 0), 1, bottomRight)
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.32, 0, 0, 32)
gridLayout.CellPadding = UDim2.new(0.02, 0, 0, 8)
gridLayout.Parent = actionsGrid

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
			r:FireServer(player:GetAttribute("SelectedVehicle") or "Muscle")
		end
	elseif actionId == "Repair" and remotes then
		local r = remotes:FindFirstChild("RepairVehicle") or remotes:FindFirstChild("RequestRepair")
		if r and r:IsA("RemoteEvent") then
			r:FireServer()
		end
	end
end

local quickButtons = {
	{ id = "Shop", text = "Shop [B]", color = Color3.fromRGB(45, 125, 220) },
	{ id = "Avatar", text = "Avatar [C]", color = Color3.fromRGB(135, 75, 215) },
	{ id = "SpawnCar", text = "Spawn Car [V]", color = Color3.fromRGB(40, 165, 95) },
	{ id = "Repair", text = "Repair [R]", color = Color3.fromRGB(215, 130, 35) },
	{ id = "VIP", text = "VIP Store [M]", color = Color3.fromRGB(205, 160, 35) },
	{ id = "Help", text = "Help [H]", color = Color3.fromRGB(70, 80, 105) },
}

for _, info in ipairs(quickButtons) do
	local btn = Instance.new("TextButton")
	btn.Name = info.id .. "Btn"
	btn.BackgroundColor3 = info.color
	btn.BackgroundTransparency = 0.15
	btn.Font = Enum.Font.GothamBold
	btn.Text = info.text
	btn.TextSize = 12
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent = actionsGrid
	addCorner(btn, 6)
	btn.MouseButton1Click:Connect(function()
		triggerQuickAction(info.id)
	end)
end

-- ==========================================
-- 5. MOBILE / TOUCH CONTROLS
-- ==========================================
if UserInputService.TouchEnabled then
	local touchContainer = makeFrame("TouchControls", UDim2.new(1, 0, 0, 170), UDim2.new(0, 0, 1, -18), Vector2.new(0, 1), Color3.new(0, 0, 0), 1, gui)
	local function makeTouchBtn(name: string, label: string, pos: UDim2, size: UDim2, bg: Color3, onHold: (boolean) -> ())
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = label
		b.Size = size
		b.Position = pos
		b.BackgroundColor3 = bg
		b.BackgroundTransparency = 0.3
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 16
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = touchContainer
		addCorner(b, 12)
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

	makeTouchBtn("SteerLeft", "◀", UDim2.fromOffset(22, 85), UDim2.fromOffset(72, 72), Color3.fromRGB(45, 55, 75), function(down)
		player:SetAttribute("TouchSteer", down and -1 or 0)
	end)
	makeTouchBtn("SteerRight", "▶", UDim2.fromOffset(106, 85), UDim2.fromOffset(72, 72), Color3.fromRGB(45, 55, 75), function(down)
		player:SetAttribute("TouchSteer", down and 1 or 0)
	end)
	makeTouchBtn("Throttle", "GAS", UDim2.new(1, -430, 0, 85), UDim2.fromOffset(78, 72), Color3.fromRGB(45, 180, 90), function(down)
		player:SetAttribute("TouchThrottle", down and 1 or 0)
	end)
	makeTouchBtn("Brake", "BRAKE", UDim2.new(1, -516, 0, 85), UDim2.fromOffset(78, 72), Color3.fromRGB(210, 65, 65), function(down)
		player:SetAttribute("TouchThrottle", down and -1 or 0)
	end)
	makeTouchBtn("Drift", "DRIFT", UDim2.new(1, -516, 0, 12), UDim2.fromOffset(78, 62), Color3.fromRGB(220, 145, 40), function(down)
		player:SetAttribute("TouchDrift", down)
	end)
	makeTouchBtn("Nitro", "NITRO", UDim2.new(1, -430, 0, 12), UDim2.fromOffset(78, 62), Color3.fromRGB(45, 165, 250), function(down)
		player:SetAttribute("TouchNitro", down)
	end)
end

-- ==========================================
-- 6. STATE UPDATES, POPUPS & REMOTES
-- ==========================================
local lastCash = -1

local function spawnCashPopup(delta: number)
	if delta <= 0 then return end
	local pop = makeLabel("CashPopup", "+$" .. formatNumber(delta), UDim2.fromOffset(140, 26), UDim2.fromOffset(160, 12), Enum.Font.GothamBlack, 20, Color3.fromRGB(120, 255, 150), Enum.TextXAlignment.Left, topLeft)
	TweenService:Create(pop, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(160, -22),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.9, function()
		pop:Destroy()
	end)
end

local function showStyleCallout(text: string)
	styleCalloutLabel.Text = string.upper(text)
	styleCalloutLabel.TextTransparency = 0
	styleCalloutLabel.Size = UDim2.new(1, 0, 0, 30)
	TweenService:Create(styleCalloutLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 0, 24),
	}):Play()
end

local function readCashValue(): number
	local attrCash = player:GetAttribute("Cash")
	if typeof(attrCash) == "number" then return attrCash end
	local ls = player:FindFirstChild("leaderstats")
	local cashObj = ls and ls:FindFirstChild("Cash")
	if cashObj and cashObj:IsA("ValueBase") then
		return tonumber(cashObj.Value) or 0
	end
	return 0
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
	local rankTitle = tostring(player:GetAttribute("RankTitle") or "ROOKIE WRECKER")
	local xpRatio = math.clamp(tonumber(player:GetAttribute("XPProgressRatio")) or 0.15, 0, 1)
	levelLabel.Text = string.format("LV. %d • %s", level, string.upper(rankTitle))
	xpBarFill.Size = UDim2.fromScale(xpRatio, 1)

	local mTitle = tostring(player:GetAttribute("MissionTitle") or "Smash Street Props & Vehicles")
	local mProg = tonumber(player:GetAttribute("MissionProgress")) or 0
	local mGoal = math.max(1, tonumber(player:GetAttribute("MissionGoal")) or 15)
	local mTime = math.max(0, tonumber(player:GetAttribute("MissionTimeRemaining") or player:GetAttribute("MissionTimeLeft")) or 60)
	local mRew = tonumber(player:GetAttribute("MissionReward")) or 1500
	missionTitle.Text = mTitle
	missionSub.Text = string.format("%d / %d  •  Reward: $%s", math.floor(mProg), math.floor(mGoal), formatNumber(mRew))
	missionTimer.Text = string.format("%02d:%02d", math.floor(mTime / 60), math.floor(mTime % 60))
	missionBarFill.Size = UDim2.fromScale(math.clamp(mProg / mGoal, 0, 1), 1)

	local mult = tonumber(player:GetAttribute("ComboMultiplier")) or 1.0
	local hits = tonumber(player:GetAttribute("ComboCount")) or 0
	local timerRatio = math.clamp(tonumber(player:GetAttribute("ComboTimerRatio") or player:GetAttribute("ComboTimer")) or 0, 0, 1)
	comboTitle.Text = string.format("%.1fx CHAOS COMBO", mult)
	comboHits.Text = hits > 0 and string.format("%d HITS ACTIVE!", hits) or "SMASH PROPS TO BUILD COMBO"
	comboTimerFill.Size = UDim2.fromScale(timerRatio, 1)

	local stars = math.clamp(tonumber(player:GetAttribute("HeatStars") or player:GetAttribute("WantedLevel")) or 0, 0, 5)
	local rawHeatProg = tonumber(player:GetAttribute("HeatProgressNormalized") or player:GetAttribute("HeatProgress")) or 0
	if rawHeatProg > 1 then
		rawHeatProg = rawHeatProg / 100
	end
	local heatProg = math.clamp(rawHeatProg, 0, 1)
	for i = 1, 5 do
		starLabels[i].TextColor3 = i <= stars and Color3.fromRGB(255, 205, 50) or Color3.fromRGB(55, 60, 75)
	end
	heatStatusLabel.Text = stars > 0 and string.format("WANTED LEVEL %d • POLICE PURSUIT", stars) or "HEAT CLEAR"
	heatBarFill.Size = UDim2.fromScale(heatProg, 1)
end

player.AttributeChanged:Connect(refreshHUDStats)
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then return end
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
		if typeof(mult) == "number" then player:SetAttribute("ComboMultiplier", mult) end
		if typeof(count) == "number" then player:SetAttribute("ComboCount", count) end
		if typeof(ratio) == "number" then player:SetAttribute("ComboTimer", ratio) end
		if typeof(callout) == "string" and #callout > 0 then showStyleCallout(callout) end
		refreshHUDStats()
	end)
	connectRemote("DamageDealt", function(_pos: any, _dmg: any, callout: any)
		if typeof(callout) == "string" and #callout > 0 then showStyleCallout(callout) end
	end)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
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

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speedMph = tonumber(player:GetAttribute("SpeedMPH")) or 0
	if root and speedMph == 0 then
		speedMph = math.floor(root.AssemblyLinearVelocity.Magnitude * 0.68)
	end
	speedValueLabel.Text = string.format("%03d", math.clamp(math.floor(speedMph), 0, 999))
	local gear = speedMph < 2 and "N" or tostring(math.clamp(math.ceil(speedMph / 28), 1, 6))
	gearBadge.Text = "GEAR: " .. gear

	local vHealth = math.clamp((tonumber(player:GetAttribute("VehicleHealth")) or 100) / math.max(1, tonumber(player:GetAttribute("MaxVehicleHealth")) or 100), 0, 1)
	local nitro = math.clamp((tonumber(player:GetAttribute("NitroFuel")) or 100) / math.max(1, tonumber(player:GetAttribute("MaxNitroFuel")) or 100), 0, 1)
	healthBarFill.Size = UDim2.fromScale(vHealth, 1)
	nitroBarFill.Size = UDim2.fromScale(nitro, 1)

	-- Minimap coordinate projection (1 stud = 1/700 radar scale)
	if root then
		local pPos = root.Position
		local function mapOffset(worldPos: Vector3): UDim2
			local dx = math.clamp((worldPos.X - pPos.X) / 700, -0.46, 0.46)
			local dz = math.clamp((worldPos.Z - pPos.Z) / 700, -0.46, 0.46)
			return UDim2.fromScale(0.5 + dx, 0.5 + dz)
		end
		shopBlip.Position = mapOffset(Vector3.new(120, 0, -90))
		mechBlip.Position = mapOffset(Vector3.new(-140, 0, 110))

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
