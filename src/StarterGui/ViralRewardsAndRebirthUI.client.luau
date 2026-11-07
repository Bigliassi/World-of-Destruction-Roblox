--!strict
-- ViralRewardsAndRebirthUI.client.luau
-- Compact, zero-clutter Playtime Gift & Rebirth Pill (180x32) at UDim2.fromOffset(14, 124)
-- plus a clean [G] modal for 6 timed Playtime Chests and +1.0x Permanent Cash Rebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
local claimPlaytimeGiftRF = remotes and remotes:WaitForChild("ClaimPlaytimeGift", 15) :: RemoteFunction?
local requestRebirthRF = remotes and remotes:WaitForChild("RequestRebirth", 15) :: RemoteFunction?

local GIFT_DEFS = {
	{ Index = 1, Seconds = 45, Reward = 500 },
	{ Index = 2, Seconds = 120, Reward = 1200 },
	{ Index = 3, Seconds = 240, Reward = 2500 },
	{ Index = 4, Seconds = 420, Reward = 5000 },
	{ Index = 5, Seconds = 600, Reward = 10000 },
	{ Index = 6, Seconds = 900, Reward = 25000 },
}

local function formatMMSS(sec: number): string
	local clamped = math.max(0, math.floor(sec))
	return string.format("%02d:%02d", math.floor(clamped / 60), clamped % 60)
end

local function parseClaimedSet(csv: string): { [number]: boolean }
	local set: { [number]: boolean } = {}
	for token in string.gmatch(csv, "([^,]+)") do
		local n = tonumber(token)
		if n then
			set[n] = true
		end
	end
	return set
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ViralRewardsAndRebirthUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 12
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local function updateScale()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.78, 1.15)
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
updateScale()

-- Compact 180x32 Pill below TopLeftPanel at (14, 124)
local pillButton = Instance.new("TextButton")
pillButton.Name = "PlaytimeGiftPill"
pillButton.Size = UDim2.fromOffset(180, 32)
pillButton.Position = UDim2.fromOffset(14, 124)
pillButton.BackgroundColor3 = Color3.fromRGB(18, 23, 34)
pillButton.BackgroundTransparency = 0.12
pillButton.BorderSizePixel = 0
pillButton.Font = Enum.Font.GothamBlack
pillButton.TextSize = 12
pillButton.TextColor3 = Color3.fromRGB(240, 246, 255)
pillButton.Text = "GIFT IN 00:45 [G]"
pillButton.AutoButtonColor = true
pillButton.Parent = screenGui
Instance.new("UICorner", pillButton).CornerRadius = UDim.new(0, 8)

local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(70, 130, 255)
pillStroke.Thickness = 1.6
pillStroke.Parent = pillButton

-- Subtle floating callout toast right next to pill for Drive Paychecks / Vault smashes
local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "ViralBonusToast"
toastLabel.Size = UDim2.fromOffset(220, 24)
toastLabel.Position = UDim2.fromOffset(202, 128)
toastLabel.BackgroundTransparency = 1
toastLabel.Font = Enum.Font.GothamBlack
toastLabel.TextSize = 13
toastLabel.TextXAlignment = Enum.TextXAlignment.Left
toastLabel.TextColor3 = Color3.fromRGB(80, 245, 140)
toastLabel.TextStrokeTransparency = 0.35
toastLabel.Text = ""
toastLabel.Parent = screenGui

-- Clean Modal (hidden by default, toggled by [G] or clicking pill)
local modalFrame = Instance.new("Frame")
modalFrame.Name = "GiftsAndRebirthModal"
modalFrame.Size = UDim2.fromOffset(470, 320)
modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
modalFrame.Position = UDim2.fromScale(0.5, 0.5)
modalFrame.BackgroundColor3 = Color3.fromRGB(15, 19, 28)
modalFrame.BackgroundTransparency = 0.04
modalFrame.BorderSizePixel = 0
modalFrame.Visible = false
modalFrame.Parent = screenGui
Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 12)

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Color3.fromRGB(255, 200, 60)
modalStroke.Thickness = 2
modalStroke.Parent = modalFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -56, 0, 36)
titleLabel.Position = UDim2.fromOffset(16, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
titleLabel.Text = "PLAYTIME GIFTS & REBIRTH"
titleLabel.Parent = modalFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -40, 0, 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
closeBtn.Font = Enum.Font.GothamBlack
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(240, 240, 250)
closeBtn.Text = "X"
closeBtn.Parent = modalFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local gridContainer = Instance.new("Frame")
gridContainer.Size = UDim2.new(1, -32, 0, 178)
gridContainer.Position = UDim2.fromOffset(16, 48)
gridContainer.BackgroundTransparency = 1
gridContainer.Parent = modalFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(138, 82)
gridLayout.CellPadding = UDim2.fromOffset(12, 10)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridContainer

local chestButtons: { [number]: { Card: TextButton, Status: TextLabel, Stroke: UIStroke } } = {}
for _, g in ipairs(GIFT_DEFS) do
	local card = Instance.new("TextButton")
	card.Name = "GiftChest_" .. g.Index
	card.LayoutOrder = g.Index
	card.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = true
	card.Parent = gridContainer
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Color3.fromRGB(60, 75, 105)
	cStroke.Thickness = 1.5
	cStroke.Parent = card

	local rewardLbl = Instance.new("TextLabel")
	rewardLbl.Size = UDim2.new(1, -8, 0, 34)
	rewardLbl.Position = UDim2.fromOffset(4, 8)
	rewardLbl.BackgroundTransparency = 1
	rewardLbl.Font = Enum.Font.GothamBlack
	rewardLbl.TextSize = 17
	rewardLbl.TextColor3 = Color3.fromRGB(255, 220, 75)
	rewardLbl.Text = string.format("+$%d", g.Reward)
	rewardLbl.Parent = card

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(1, -8, 0, 26)
	statusLbl.Position = UDim2.fromOffset(4, 46)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.TextSize = 13
	statusLbl.TextColor3 = Color3.fromRGB(190, 205, 230)
	statusLbl.Text = formatMMSS(g.Seconds)
	statusLbl.Parent = card

	chestButtons[g.Index] = { Card = card, Status = statusLbl, Stroke = cStroke }
	card.Activated:Connect(function()
		if not claimPlaytimeGiftRF then
			return
		end
		local res = claimPlaytimeGiftRF:InvokeServer(g.Index)
		if type(res) == "table" and res.Success then
			statusLbl.Text = "CLAIMED"
		end
	end)
end

-- Rebirth Prestige Bar at bottom of Modal
local rebirthBar = Instance.new("Frame")
rebirthBar.Size = UDim2.new(1, -32, 0, 68)
rebirthBar.Position = UDim2.fromOffset(16, 236)
rebirthBar.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
rebirthBar.BorderSizePixel = 0
rebirthBar.Parent = modalFrame
Instance.new("UICorner", rebirthBar).CornerRadius = UDim.new(0, 8)

local rebirthInfo = Instance.new("TextLabel")
rebirthInfo.Size = UDim2.new(0.6, -12, 1, -12)
rebirthInfo.Position = UDim2.fromOffset(12, 6)
rebirthInfo.BackgroundTransparency = 1
rebirthInfo.Font = Enum.Font.GothamBold
rebirthInfo.TextSize = 13
rebirthInfo.TextXAlignment = Enum.TextXAlignment.Left
rebirthInfo.TextColor3 = Color3.fromRGB(235, 240, 255)
rebirthInfo.Text = "REBIRTH 0 (1.0x CASH)\nNext: +1.0x Permanent Cash ($25,000)"
rebirthInfo.Parent = rebirthBar

local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Name = "RebirthActionButton"
rebirthBtn.Size = UDim2.fromOffset(162, 46)
rebirthBtn.Position = UDim2.new(1, -174, 0.5, -23)
rebirthBtn.BackgroundColor3 = Color3.fromRGB(255, 190, 35)
rebirthBtn.Font = Enum.Font.GothamBlack
rebirthBtn.TextSize = 14
rebirthBtn.TextColor3 = Color3.fromRGB(20, 22, 28)
rebirthBtn.Text = "REBIRTH (+1.0x)"
rebirthBtn.Parent = rebirthBar
Instance.new("UICorner", rebirthBtn).CornerRadius = UDim.new(0, 8)

local function refreshUI()
	local playSec = tonumber(player:GetAttribute("PlaytimeSeconds")) or 0
	local claimedCSV = tostring(player:GetAttribute("ClaimedGiftsCSV") or "")
	local claimed = parseClaimedSet(claimedCSV)
	local readyCount = tonumber(player:GetAttribute("ReadyGiftCount")) or 0
	local nextLeft = tonumber(player:GetAttribute("NextGiftSecondsLeft")) or 0

	if readyCount > 0 then
		pillButton.Text = "FREE GIFT READY! [G]"
		pillButton.BackgroundColor3 = Color3.fromRGB(22, 120, 58)
		pillStroke.Color = Color3.fromRGB(80, 255, 140)
	elseif nextLeft > 0 then
		pillButton.Text = string.format("GIFT IN %s [G]", formatMMSS(nextLeft))
		pillButton.BackgroundColor3 = Color3.fromRGB(18, 23, 34)
		pillStroke.Color = Color3.fromRGB(70, 130, 255)
	else
		pillButton.Text = "ALL GIFTS CLAIMED [G]"
		pillButton.BackgroundColor3 = Color3.fromRGB(18, 23, 34)
		pillStroke.Color = Color3.fromRGB(255, 205, 65)
	end

	for _, g in ipairs(GIFT_DEFS) do
		local slot = chestButtons[g.Index]
		if claimed[g.Index] then
			slot.Status.Text = "CLAIMED"
			slot.Status.TextColor3 = Color3.fromRGB(130, 145, 165)
			slot.Card.BackgroundColor3 = Color3.fromRGB(19, 23, 32)
			slot.Stroke.Color = Color3.fromRGB(55, 65, 85)
		elseif playSec >= g.Seconds then
			slot.Status.Text = "CLAIM!"
			slot.Status.TextColor3 = Color3.fromRGB(90, 255, 145)
			slot.Card.BackgroundColor3 = Color3.fromRGB(22, 72, 42)
			slot.Stroke.Color = Color3.fromRGB(80, 255, 140)
		else
			slot.Status.Text = formatMMSS(g.Seconds - playSec)
			slot.Status.TextColor3 = Color3.fromRGB(195, 210, 235)
			slot.Card.BackgroundColor3 = Color3.fromRGB(24, 30, 44)
			slot.Stroke.Color = Color3.fromRGB(60, 75, 105)
		end
	end

	local rebirths = tonumber(player:GetAttribute("RebirthCount")) or 0
	local mult = tonumber(player:GetAttribute("RebirthMultiplier")) or 1
	local cost = 25000 * (rebirths + 1)
	rebirthInfo.Text = string.format("REBIRTH %d (%.1fx CASH)\nNext: +1.0x Permanent Cash ($%d)", rebirths, mult, cost)
end

local function showToast(msg: string)
	toastLabel.Text = msg
	toastLabel.TextTransparency = 0
	TweenService:Create(toastLabel, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

local function toggleModal()
	modalFrame.Visible = not modalFrame.Visible
	if modalFrame.Visible then
		refreshUI()
	end
end

pillButton.Activated:Connect(toggleModal)
closeBtn.Activated:Connect(function()
	modalFrame.Visible = false
end)

rebirthBtn.Activated:Connect(function()
	if not requestRebirthRF then
		return
	end
	local res = requestRebirthRF:InvokeServer()
	if type(res) == "table" then
		if res.Success then
			showToast(string.format("REBIRTH %d UNLOCKED! %.1fx CASH!", res.RebirthCount or 1, res.RebirthMultiplier or 2))
		elseif res.Message then
			showToast(tostring(res.Message))
		end
		refreshUI()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		toggleModal()
	end
end)

for _, attr in ipairs({ "PlaytimeSeconds", "ClaimedGiftsCSV", "ReadyGiftCount", "NextGiftSecondsLeft", "RebirthCount", "RebirthMultiplier" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshUI)
end
player:GetAttributeChangedSignal("LastViralBonusText"):Connect(function()
	local msg = tostring(player:GetAttribute("LastViralBonusText") or "")
	if msg ~= "" then
		showToast(msg)
	end
end)

refreshUI()
