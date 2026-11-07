--!strict
--[[
	CrossPlatformController.client.luau
	Complete Cross-Platform Controller Compatibility & Haptic Feedback for World of Destruction (Leo City).

	Features:
	  1. Automatic Input Device Detection ("Keyboard", "Gamepad", "Touch"):
	     - Detects UserInputService:GetLastInputType() and TouchEnabled / GamepadEnabled
	     - Respects localPlayer:GetAttribute("ControlSchemeOverride") ("Auto", "PC Keyboard", "Console Gamepad", "iPad / Touch")
	     - Publishes localPlayer:SetAttribute("ActiveInputPlatform", platform) ("PC", "Console", or "Touch")
	  2. Console Gamepad Global Navigation, Shortcuts & Modal Focus Management (Xbox / PlayStation DualSense):
	     - ButtonY (Y / Triangle): Enter/Hijack nearest vehicle when on foot, or Exit vehicle when driving
	     - DPadUp: Summon Personal Vehicle (SpawnVehicle remote)
	     - DPadLeft: Toggle Garage & Speed Shop (ToggleShopUI attribute)
	     - DPadRight: Toggle Avatar Shop (ToggleAvatarUI attribute)
	     - DPadDown: Instant Repair Vehicle (RepairVehicle remote)
	     - ButtonSelect / ButtonStart: Toggle Home Menu / Settings (ToggleHomeMenu attribute)
	     - ButtonB (B / Circle): Close any open UI modal (HomeMenu, SpeedShop, AvatarShop, Guide), or Tactical Dodge when on foot
	     - Gamepad Modal Focus Management (GuiService.SelectedObject) for D-Pad / Left Stick menu navigation + ButtonA selection
	     - Controller Haptic Rumble (HapticService): Pulses Large/Small vibration motors on DestructionOccurred, IsBoosting, and StyleCallout
	  3. Ergonomic iPad & Mobile Touch Driving/On-Foot HUD (WorldOfDestructionTouchGui):
	     - Bottom-Left Analog Virtual Steering Thumbstick (140x140) writing continuous [-1.0 .. 1.0] to TouchSteer
	     - Bottom-Right Arcade Pedal Cluster: GAS PEDAL (TouchThrottle = true), BRAKE / REV PEDAL (TouchBrake = true),
	       NITRO BOOST (TouchNitro = true), DRIFT (TouchDrift = true), and Context ENTER CAR / EXIT CAR button
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

if localPlayer:GetAttribute("ControlSchemeOverride") == nil then
	localPlayer:SetAttribute("ControlSchemeOverride", "Auto")
end
if localPlayer:GetAttribute("TouchSteer") == nil then
	localPlayer:SetAttribute("TouchSteer", 0)
end
if localPlayer:GetAttribute("TouchThrottle") == nil then
	localPlayer:SetAttribute("TouchThrottle", false)
end
if localPlayer:GetAttribute("TouchBrake") == nil then
	localPlayer:SetAttribute("TouchBrake", false)
end
if localPlayer:GetAttribute("TouchNitro") == nil then
	localPlayer:SetAttribute("TouchNitro", false)
end
if localPlayer:GetAttribute("TouchDrift") == nil then
	localPlayer:SetAttribute("TouchDrift", false)
end

--------------------------------------------------------------------------------
-- Remote & Seat Helpers
--------------------------------------------------------------------------------
local function getRemoteEvent(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local found = remotes:FindFirstChild(name)
		if found and found:IsA("RemoteEvent") then
			return found
		end
	end
	local rootFound = ReplicatedStorage:FindFirstChild(name)
	if rootFound and rootFound:IsA("RemoteEvent") then
		return rootFound
	end
	return nil
end

local function getHumanoid(): Humanoid?
	local char = localPlayer.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

local function isPlayerSeated(): boolean
	local hum = getHumanoid()
	return (hum ~= nil and (hum.SeatPart ~= nil or hum.Sit == true))
end

local function findNearestVehicle(origin: Vector3, maxDist: number): Model?
	local bestModel: Model? = nil
	local bestDist = maxDist

	for _, veh in ipairs(CollectionService:GetTagged("Vehicle")) do
		if veh:IsA("Model") then
			local seat = veh:FindFirstChild("DriveSeat") :: VehicleSeat?
			local primary = seat or veh.PrimaryPart
			if primary then
				local dist = (primary.Position - origin).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestModel = veh
				end
			end
		end
	end

	return bestModel
end

local lastSummonAt = 0
local lastEnterExitAt = 0
local lastRepairAt = 0

local function summonPersonalVehicle()
	local now = os.clock()
	local sharedLast = tonumber(localPlayer:GetAttribute("LastVehicleSummonAt")) or 0
	if (now - lastSummonAt) < 1.0 or (now - sharedLast) < 1.0 then
		return
	end
	lastSummonAt = now
	localPlayer:SetAttribute("LastVehicleSummonAt", now)

	local equipped = localPlayer:GetAttribute("EquippedVehicle")
		or localPlayer:GetAttribute("SelectedVehicle")
		or "Compact"
	local spawnRemote = getRemoteEvent("SpawnVehicle") or getRemoteEvent("SummonVehicle")
	if spawnRemote then
		spawnRemote:FireServer(equipped, true)
	end
end

local function repairCurrentVehicle()
	local now = os.clock()
	if now - lastRepairAt < 0.8 then
		return
	end
	lastRepairAt = now

	local repairRemote = getRemoteEvent("RepairVehicle") or getRemoteEvent("RequestRepair")
	if repairRemote then
		repairRemote:FireServer()
	end
end

local function enterOrExitVehicleAction()
	local now = os.clock()
	local sharedLast = tonumber(localPlayer:GetAttribute("LastVehicleEnterExitAt")) or 0
	if (now - lastEnterExitAt) < 0.35 or (now - sharedLast) < 0.35 then
		return
	end
	lastEnterExitAt = now
	localPlayer:SetAttribute("LastVehicleEnterExitAt", now)

	local char = localPlayer.Character
	local hum = getHumanoid()
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hum or not hrp or hum.Health <= 0 then
		return
	end

	if hum.SeatPart ~= nil or hum.Sit == true then
		-- Exit vehicle cleanly
		hum.Sit = false
		hum.Jump = true
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		local exitRemote = getRemoteEvent("VehicleExited")
		if exitRemote then
			exitRemote:FireServer()
		end
	else
		-- Enter / Hijack nearest vehicle when on foot (or summon if none nearby on touch button)
		local nearest = findNearestVehicle(hrp.Position, 26)
		if nearest then
			local enterRemote = getRemoteEvent("EnterNearestVehicle")
			if enterRemote then
				enterRemote:FireServer(nearest)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- UI Modal Inspection & Gamepad Focus Management (GuiService.SelectedObject)
--------------------------------------------------------------------------------
local function getHomeMenuFrames(): (Frame?, Frame?, Frame?)
	local gui = playerGui:FindFirstChild("WorldOfDestructionHomeMenuGui")
		or playerGui:FindFirstChild("HomeMenuAndSettingsUI")
	if not gui then
		return nil, nil, nil
	end
	local homeOverlay = gui:FindFirstChild("HomeMenuOverlay") :: Frame?
	local settingsModal = gui:FindFirstChild("SettingsModal") :: Frame?
	local victoryModal = gui:FindFirstChild("GrandFinaleVictoryModal") :: Frame?
	return homeOverlay, settingsModal, victoryModal
end

local function getSpeedShopModal(): Frame?
	local gui = playerGui:FindFirstChild("WorldOfDestructionShopGui")
		or playerGui:FindFirstChild("SpeedShopUI")
	if not gui then
		return nil
	end
	return gui:FindFirstChild("SpeedShopModal") :: Frame?
end

local function getAvatarShopModal(): Frame?
	local gui = playerGui:FindFirstChild("CharacterCreatorAndWardrobeUI")
	if not gui then
		return nil
	end
	return gui:FindFirstChild("CreatorModal") :: Frame?
end

local function getGuideModal(): Frame?
	local gui = playerGui:FindFirstChild("TutorialAndGuideGui")
		or playerGui:FindFirstChild("TutorialAndGuideUI")
	if not gui then
		return nil
	end
	return gui:FindFirstChild("ModalBackdrop") :: Frame?
end

local function getActiveModalRoot(): GuiObject?
	local homeOverlay, settingsModal, victoryModal = getHomeMenuFrames()
	if victoryModal and victoryModal.Visible then
		return victoryModal
	end
	if settingsModal and settingsModal.Visible then
		return settingsModal
	end
	local avatarModal = getAvatarShopModal()
	if avatarModal and avatarModal.Visible then
		return avatarModal
	end
	local shopModal = getSpeedShopModal()
	if shopModal and shopModal.Visible then
		return shopModal
	end
	local guideModal = getGuideModal()
	if guideModal and guideModal.Visible then
		return guideModal
	end
	if homeOverlay and homeOverlay.Visible then
		return homeOverlay
	end
	return nil
end

local function isAnyModalOpen(): boolean
	return getActiveModalRoot() ~= nil
end

local function isGuiChainVisible(obj: GuiObject): boolean
	local cur: Instance? = obj
	while cur and cur ~= playerGui do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return false
			end
		elseif cur:IsA("LayerCollector") then
			if not cur.Enabled then
				return false
			end
		end
		cur = cur.Parent
	end
	return true
end

local function ensureButtonsSelectable(root: Instance)
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextButton") or desc:IsA("ImageButton") then
			desc.Selectable = true
		end
	end
end

local function findPrimaryButtonInModal(modalRoot: GuiObject): GuiObject?
	ensureButtonsSelectable(modalRoot)

	-- Priority primary button candidates by name across HomeMenu, Settings, SpeedShop, AvatarShop, Guide
	local preferredNames = {
		"PlayNowBtn",
		"PlayCampaignBtn",
		"ContinueOverdriveBtn",
		"ActionBtn",
		"PlayWreckerBtn",
		"SaveAndPlayBtn",
		"TabControls",
		"ToggleBtn_1",
		"CloseButton",
		"CloseBtn",
	}

	for _, name in ipairs(preferredNames) do
		local found = modalRoot:FindFirstChild(name, true)
		if found then
			if found:IsA("TextButton") and isGuiChainVisible(found) then
				return found
			end
			local face = found:FindFirstChild("ButtonFace")
			if face and face:IsA("TextButton") and isGuiChainVisible(face) then
				return face
			end
		end
	end

	for _, desc in ipairs(modalRoot:GetDescendants()) do
		if desc:IsA("TextButton") and desc.Visible and isGuiChainVisible(desc) then
			return desc
		end
	end

	return nil
end

local lastFocusedModal: GuiObject? = nil

local function updateGamepadModalFocus()
	local activePlatform = tostring(localPlayer:GetAttribute("ActiveInputPlatform") or "PC")
	local modalRoot = getActiveModalRoot()
	local modalOpen = (modalRoot ~= nil)
	localPlayer:SetAttribute("UIModalOpen", modalOpen)

	if activePlatform ~= "Console" then
		if GuiService.SelectedObject ~= nil then
			GuiService.SelectedObject = nil
		end
		lastFocusedModal = nil
		return
	end

	if not modalRoot then
		if GuiService.SelectedObject ~= nil then
			GuiService.SelectedObject = nil
		end
		lastFocusedModal = nil
		return
	end

	pcall(function()
		GuiService.GuiNavigationEnabled = true
		GuiService.AutoSelectGuiEnabled = true
	end)

	local currentSel = GuiService.SelectedObject
	local needsFocus = (modalRoot ~= lastFocusedModal)
		or (currentSel == nil)
		or (not currentSel:IsDescendantOf(modalRoot))
		or (not isGuiChainVisible(currentSel))

	if needsFocus then
		local primaryBtn = findPrimaryButtonInModal(modalRoot)
		if primaryBtn then
			GuiService.SelectedObject = primaryBtn
			lastFocusedModal = modalRoot
		end
	end
end

local function toggleHomeMenuModal()
	local homeOverlay, settingsModal, _ = getHomeMenuFrames()
	local wasOpen = if homeOverlay then homeOverlay.Visible else false

	local nextFlag = not (localPlayer:GetAttribute("ToggleHomeMenu") == true)
	localPlayer:SetAttribute("ToggleHomeMenu", nextFlag)

	-- Ensure compatibility if HomeMenuAndSettingsUI listens to ToggleHomeMenuUI
	if homeOverlay and homeOverlay.Visible == wasOpen then
		local nextUIFlag = not (localPlayer:GetAttribute("ToggleHomeMenuUI") == true)
		localPlayer:SetAttribute("ToggleHomeMenuUI", nextUIFlag)
	end
	if homeOverlay and homeOverlay.Visible == wasOpen then
		local targetState = not wasOpen
		homeOverlay.Visible = targetState
		localPlayer:SetAttribute("HomeMenuActive", targetState)
		localPlayer:SetAttribute("HomeMenuCameraActive", targetState)
	end
	if settingsModal and settingsModal.Visible and homeOverlay and not homeOverlay.Visible then
		settingsModal.Visible = false
	end

	task.defer(updateGamepadModalFocus)
end

local function closeAnyOpenModal(): boolean
	local closedAny = false
	local homeOverlay, settingsModal, victoryModal = getHomeMenuFrames()

	if victoryModal and victoryModal.Visible then
		victoryModal.Visible = false
		closedAny = true
	end
	if settingsModal and settingsModal.Visible then
		settingsModal.Visible = false
		closedAny = true
	end

	local avatarModal = getAvatarShopModal()
	if avatarModal and avatarModal.Visible then
		localPlayer:SetAttribute("ToggleAvatarUI", not (localPlayer:GetAttribute("ToggleAvatarUI") == true))
		if avatarModal.Visible then
			avatarModal.Visible = false
		end
		closedAny = true
	end

	local shopModal = getSpeedShopModal()
	if shopModal and shopModal.Visible then
		localPlayer:SetAttribute("ToggleShopUI", not (localPlayer:GetAttribute("ToggleShopUI") == true))
		if shopModal.Visible then
			shopModal.Visible = false
		end
		closedAny = true
	end

	local guideModal = getGuideModal()
	if guideModal and guideModal.Visible then
		guideModal.Visible = false
		closedAny = true
	end

	if not closedAny and homeOverlay and homeOverlay.Visible then
		toggleHomeMenuModal()
		if homeOverlay.Visible then
			homeOverlay.Visible = false
			localPlayer:SetAttribute("HomeMenuActive", false)
			localPlayer:SetAttribute("HomeMenuCameraActive", false)
		end
		closedAny = true
	end

	if closedAny then
		localPlayer:SetAttribute("LastModalClosedAt", os.clock())
		localPlayer:SetAttribute("UIModalOpen", isAnyModalOpen())
		task.defer(updateGamepadModalFocus)
	end

	return closedAny
end

--------------------------------------------------------------------------------
-- 1. Automatic Input Device Detection ("Keyboard", "Gamepad", "Touch")
--------------------------------------------------------------------------------
local touchGui: ScreenGui? = nil

local function detectRawInputDevice(inputType: Enum.UserInputType?): ("Keyboard" | "Gamepad" | "Touch")
	local lastType = inputType or UserInputService:GetLastInputType()
	local name = lastType.Name

	if string.find(name, "Gamepad") ~= nil then
		return "Gamepad"
	elseif lastType == Enum.UserInputType.Touch then
		return "Touch"
	elseif
		lastType == Enum.UserInputType.Keyboard
		or string.find(name, "Mouse") ~= nil
		or lastType == Enum.UserInputType.TextInput
	then
		return "Keyboard"
	end

	-- Startup fallback before first input event
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

local function resolveActiveInputPlatform(lastInputType: Enum.UserInputType?): ("PC" | "Console" | "Touch", "Keyboard" | "Gamepad" | "Touch")
	local override = tostring(localPlayer:GetAttribute("ControlSchemeOverride") or "Auto")
	local lower = string.lower(override)

	if string.find(lower, "console") ~= nil or string.find(lower, "gamepad") ~= nil then
		return "Console", "Gamepad"
	elseif string.find(lower, "ipad") ~= nil or string.find(lower, "touch") ~= nil or string.find(lower, "mobile") ~= nil then
		return "Touch", "Touch"
	elseif string.find(lower, "pc") ~= nil or string.find(lower, "keyboard") ~= nil then
		return "PC", "Keyboard"
	end

	local rawDevice = detectRawInputDevice(lastInputType)
	if rawDevice == "Gamepad" then
		return "Console", "Gamepad"
	elseif rawDevice == "Touch" then
		return "Touch", "Touch"
	else
		return "PC", "Keyboard"
	end
end

local function refreshInputPlatform(lastInputType: Enum.UserInputType?)
	local platform, device = resolveActiveInputPlatform(lastInputType)

	if localPlayer:GetAttribute("ActiveInputPlatform") ~= platform then
		localPlayer:SetAttribute("ActiveInputPlatform", platform)
	end
	if localPlayer:GetAttribute("InputDevice") ~= device then
		localPlayer:SetAttribute("InputDevice", device)
	end

	-- Hide legacy basic TouchControls in WorldOfDestructionHUD so only our ergonomic WorldOfDestructionTouchGui renders
	local mainHud = playerGui:FindFirstChild("WorldOfDestructionHUD")
	if mainHud then
		local legacyTouch = mainHud:FindFirstChild("TouchControls")
		if legacyTouch and legacyTouch:IsA("GuiObject") then
			legacyTouch.Visible = false
		end
	end

	if touchGui then
		local homeActive = localPlayer:GetAttribute("HomeMenuActive") == true
		touchGui.Enabled = (platform == "Touch") and (not homeActive)
	end

	updateGamepadModalFocus()
end

--------------------------------------------------------------------------------
-- 2. Controller Haptic Rumble (HapticService)
--------------------------------------------------------------------------------
local motorToken: { [Enum.VibrationMotor]: number } = {}
local wasBoosting = false

local function setMotorStrength(motor: Enum.VibrationMotor, intensity: number)
	local clamped = math.clamp(intensity, 0, 1)
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, motor, clamped)
	end)
end

local function pulseHapticMotor(motor: Enum.VibrationMotor, intensity: number, duration: number)
	local token = (motorToken[motor] or 0) + 1
	motorToken[motor] = token
	setMotorStrength(motor, intensity)

	task.delay(duration, function()
		if motorToken[motor] == token then
			-- Restore gentle boost vibration if still boosting, else 0
			if localPlayer:GetAttribute("IsBoosting") == true then
				setMotorStrength(
					motor,
					if motor == Enum.VibrationMotor.Small then 0.35 else 0.22
				)
			else
				setMotorStrength(motor, 0)
			end
		end
	end)
end

local function triggerSmashHaptics(intensityScale: number?)
	local scale = math.clamp(tonumber(intensityScale) or 1.0, 0.35, 1.0)
	pulseHapticMotor(Enum.VibrationMotor.Large, 0.78 * scale, 0.16)
	pulseHapticMotor(Enum.VibrationMotor.Small, 0.58 * scale, 0.12)
end

local function triggerJackpotOrCalloutHaptics(calloutText: string)
	local upper = string.upper(calloutText)
	local isJackpot = string.find(upper, "JACKPOT") ~= nil
		or string.find(upper, "OVERDRIVE") ~= nil
		or string.find(upper, "LIBERATED") ~= nil
		or string.find(upper, "BOSS") ~= nil

	if isJackpot then
		pulseHapticMotor(Enum.VibrationMotor.Large, 1.0, 0.28)
		pulseHapticMotor(Enum.VibrationMotor.Small, 0.95, 0.28)
		task.delay(0.34, function()
			pulseHapticMotor(Enum.VibrationMotor.Large, 1.0, 0.32)
			pulseHapticMotor(Enum.VibrationMotor.Small, 0.90, 0.32)
		end)
	else
		pulseHapticMotor(Enum.VibrationMotor.Large, 0.55, 0.14)
		pulseHapticMotor(Enum.VibrationMotor.Small, 0.65, 0.14)
	end
end

localPlayer:GetAttributeChangedSignal("IsBoosting"):Connect(function()
	local boostingNow = localPlayer:GetAttribute("IsBoosting") == true
	if boostingNow and not wasBoosting then
		wasBoosting = true
		pulseHapticMotor(Enum.VibrationMotor.Large, 0.62, 0.18)
		pulseHapticMotor(Enum.VibrationMotor.Small, 0.75, 0.22)
	elseif not boostingNow and wasBoosting then
		wasBoosting = false
		setMotorStrength(Enum.VibrationMotor.Large, 0)
		setMotorStrength(Enum.VibrationMotor.Small, 0)
	end
end)

local lastTotalDestructions = tonumber(localPlayer:GetAttribute("TotalDestructions")) or 0
localPlayer:GetAttributeChangedSignal("TotalDestructions"):Connect(function()
	local nowCount = tonumber(localPlayer:GetAttribute("TotalDestructions")) or 0
	if nowCount > lastTotalDestructions then
		triggerSmashHaptics(0.85)
	end
	lastTotalDestructions = nowCount
end)

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return
	end

	local function connectRemote(name: string, callback: (...any) -> ())
		local r = remotes:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			r.OnClientEvent:Connect(callback)
		end
	end

	connectRemote("DestructionOccurred", function(payload: any)
		local isHeavy = type(payload) == "table" and (payload.IsHeavy == true or (tonumber(payload.CashEarned) or 0) >= 250)
		triggerSmashHaptics(if isHeavy then 1.0 else 0.78)
	end)

	connectRemote("ExplosionEffect", function()
		pulseHapticMotor(Enum.VibrationMotor.Large, 1.0, 0.30)
		pulseHapticMotor(Enum.VibrationMotor.Small, 0.85, 0.26)
	end)

	connectRemote("StyleCallout", function(arg1: any, _arg2: any)
		local text = if type(arg1) == "table" then tostring(arg1.Text or arg1.Title or "JACKPOT") else tostring(arg1 or "")
		triggerJackpotOrCalloutHaptics(text)
	end)

	remotes.ChildAdded:Connect(function(child: Instance)
		if not child:IsA("RemoteEvent") then
			return
		end
		if child.Name == "DestructionOccurred" then
			child.OnClientEvent:Connect(function()
				triggerSmashHaptics(0.85)
			end)
		elseif child.Name == "StyleCallout" then
			child.OnClientEvent:Connect(function(arg1: any)
				local text = if type(arg1) == "table" then tostring(arg1.Text or arg1.Title or "JACKPOT") else tostring(arg1 or "")
				triggerJackpotOrCalloutHaptics(text)
			end)
		elseif child.Name == "ExplosionEffect" then
			child.OnClientEvent:Connect(function()
				pulseHapticMotor(Enum.VibrationMotor.Large, 1.0, 0.30)
				pulseHapticMotor(Enum.VibrationMotor.Small, 0.85, 0.26)
			end)
		end
	end)
end)

--------------------------------------------------------------------------------
-- 3. Ergonomic iPad & Mobile Touch Driving/On-Foot HUD (WorldOfDestructionTouchGui)
--------------------------------------------------------------------------------
local existingTouchGui = playerGui:FindFirstChild("WorldOfDestructionTouchGui")
if existingTouchGui then
	existingTouchGui:Destroy()
end

local createdTouchGui = Instance.new("ScreenGui")
createdTouchGui.Name = "WorldOfDestructionTouchGui"
createdTouchGui.IgnoreGuiInset = true
createdTouchGui.ResetOnSpawn = false
createdTouchGui.DisplayOrder = 12
createdTouchGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
createdTouchGui.Enabled = false
createdTouchGui.Parent = playerGui
touchGui = createdTouchGui

local touchScale = Instance.new("UIScale")
touchScale.Name = "TouchHUDAutoScale"
touchScale.Scale = 1.0
touchScale.Parent = createdTouchGui

local function updateTouchHudScale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X > 0 and vp.Y > 0 then
		touchScale.Scale = math.clamp(math.min(vp.X / 1180, vp.Y / 720), 0.72, 1.08)
	end
end
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTouchHudScale)
	updateTouchHudScale()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateTouchHudScale)
		updateTouchHudScale()
	end
end)

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

-- 3A. Bottom-Left Analog Virtual Steering Thumbstick (140x140)
local thumbstickBase = Instance.new("Frame")
thumbstickBase.Name = "VirtualSteeringThumbstick"
thumbstickBase.Size = UDim2.fromOffset(140, 140)
thumbstickBase.Position = UDim2.new(0, 28, 1, -68)
thumbstickBase.AnchorPoint = Vector2.new(0, 1)
thumbstickBase.BackgroundColor3 = Color3.fromRGB(16, 22, 36)
thumbstickBase.BackgroundTransparency = 0.24
thumbstickBase.BorderSizePixel = 0
thumbstickBase.Active = true
thumbstickBase.Parent = createdTouchGui
addCorner(thumbstickBase, 70)
local thumbstickStroke = addStroke(thumbstickBase, Color3.fromRGB(70, 185, 255), 2.5, 0.2)

-- Subtle horizontal axis guide & left/right chevrons inside the 140x140 wheel base
local axisBar = Instance.new("Frame")
axisBar.Name = "SteerAxisGuide"
axisBar.Size = UDim2.new(1, -28, 0, 3)
axisBar.Position = UDim2.fromScale(0.5, 0.5)
axisBar.AnchorPoint = Vector2.new(0.5, 0.5)
axisBar.BackgroundColor3 = Color3.fromRGB(70, 140, 210)
axisBar.BackgroundTransparency = 0.55
axisBar.BorderSizePixel = 0
axisBar.Parent = thumbstickBase
addCorner(axisBar, 2)

local leftHint = Instance.new("TextLabel")
leftHint.Size = UDim2.fromOffset(24, 24)
leftHint.Position = UDim2.new(0, 8, 0.5, 0)
leftHint.AnchorPoint = Vector2.new(0, 0.5)
leftHint.BackgroundTransparency = 1
leftHint.Font = Enum.Font.GothamBlack
leftHint.Text = "◀"
leftHint.TextColor3 = Color3.fromRGB(130, 205, 255)
leftHint.TextSize = 14
leftHint.Parent = thumbstickBase

local rightHint = Instance.new("TextLabel")
rightHint.Size = UDim2.fromOffset(24, 24)
rightHint.Position = UDim2.new(1, -8, 0.5, 0)
rightHint.AnchorPoint = Vector2.new(1, 0.5)
rightHint.BackgroundTransparency = 1
rightHint.Font = Enum.Font.GothamBlack
rightHint.Text = "▶"
rightHint.TextColor3 = Color3.fromRGB(130, 205, 255)
rightHint.TextSize = 14
rightHint.Parent = thumbstickBase

local steerCaption = Instance.new("TextLabel")
steerCaption.Name = "SteerCaption"
steerCaption.Size = UDim2.new(1, 0, 0, 16)
steerCaption.Position = UDim2.new(0.5, 0, 0, 10)
steerCaption.AnchorPoint = Vector2.new(0.5, 0)
steerCaption.BackgroundTransparency = 1
steerCaption.Font = Enum.Font.GothamBlack
steerCaption.Text = "STEER"
steerCaption.TextColor3 = Color3.fromRGB(150, 215, 255)
steerCaption.TextSize = 10
steerCaption.Parent = thumbstickBase

local thumbstickKnob = Instance.new("Frame")
thumbstickKnob.Name = "ThumbstickKnob"
thumbstickKnob.Size = UDim2.fromOffset(58, 58)
thumbstickKnob.Position = UDim2.fromScale(0.5, 0.5)
thumbstickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
thumbstickKnob.BackgroundColor3 = Color3.fromRGB(55, 175, 255)
thumbstickKnob.BackgroundTransparency = 0.08
thumbstickKnob.BorderSizePixel = 0
thumbstickKnob.Parent = thumbstickBase
addCorner(thumbstickKnob, 29)
addStroke(thumbstickKnob, Color3.fromRGB(220, 245, 255), 2, 0.15)

local activeSteerInput: InputObject? = nil
local MAX_STICK_RADIUS = 46

local function applyThumbstickScreenPosition(screenPos: Vector2)
	local absPos = thumbstickBase.AbsolutePosition
	local absSize = thumbstickBase.AbsoluteSize
	local center = absPos + absSize * 0.5
	local scale = math.max(0.5, touchScale.Scale)
	local delta = (screenPos - center) / scale

	local clampedX = math.clamp(delta.X, -MAX_STICK_RADIUS, MAX_STICK_RADIUS)
	local clampedY = math.clamp(delta.Y * 0.35, -16, 16)
	thumbstickKnob.Position = UDim2.new(0.5, clampedX, 0.5, clampedY)

	local normalizedX = clampedX / MAX_STICK_RADIUS
	if math.abs(normalizedX) < 0.06 then
		normalizedX = 0
	end
	local steerVal = tonumber(string.format("%.3f", math.clamp(normalizedX, -1.0, 1.0))) or 0
	localPlayer:SetAttribute("TouchSteer", steerVal)
	localPlayer:SetAttribute("TouchSteerLeft", steerVal < -0.18)
	localPlayer:SetAttribute("TouchSteerRight", steerVal > 0.18)
	thumbstickStroke.Color = if math.abs(steerVal) > 0.05
		then Color3.fromRGB(110, 235, 255)
		else Color3.fromRGB(70, 185, 255)
end

local function resetThumbstick()
	activeSteerInput = nil
	localPlayer:SetAttribute("TouchSteer", 0)
	localPlayer:SetAttribute("TouchSteerLeft", false)
	localPlayer:SetAttribute("TouchSteerRight", false)
	thumbstickStroke.Color = Color3.fromRGB(70, 185, 255)
	TweenService:Create(thumbstickKnob, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.5),
	}):Play()
end

thumbstickBase.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeSteerInput = input
		applyThumbstickScreenPosition(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if activeSteerInput ~= nil then
		if
			input == activeSteerInput
			or (
				activeSteerInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		then
			applyThumbstickScreenPosition(Vector2.new(input.Position.X, input.Position.Y))
		end
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if activeSteerInput ~= nil and input == activeSteerInput then
		resetThumbstick()
	end
end)

-- 3B. Bottom-Right Arcade Pedal Cluster
local pedalCluster = Instance.new("Frame")
pedalCluster.Name = "ArcadePedalCluster"
pedalCluster.Size = UDim2.fromOffset(250, 210)
pedalCluster.Position = UDim2.new(1, -24, 1, -110)
pedalCluster.AnchorPoint = Vector2.new(1, 1)
pedalCluster.BackgroundTransparency = 1
pedalCluster.Parent = createdTouchGui

local function createPedalButton(params: {
	name: string,
	title: string,
	subtitle: string?,
	size: UDim2,
	position: UDim2,
	baseColor: Color3,
	strokeColor: Color3,
	cornerRadius: number,
	onHoldChanged: ((boolean) -> ())?,
	onPressed: (() -> ())?,
}): (TextButton, TextLabel)
	local btn = Instance.new("TextButton")
	btn.Name = params.name
	btn.Size = params.size
	btn.Position = params.position
	btn.BackgroundColor3 = params.baseColor
	btn.BackgroundTransparency = 0.14
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = pedalCluster
	addCorner(btn, params.cornerRadius)
	local stroke = addStroke(btn, params.strokeColor, 2.2, 0.15)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(
			0,
			Color3.new(
				math.min(1, params.baseColor.R + 0.16),
				math.min(1, params.baseColor.G + 0.16),
				math.min(1, params.baseColor.B + 0.16)
			)
		),
		ColorSequenceKeypoint.new(
			1,
			Color3.new(params.baseColor.R * 0.78, params.baseColor.G * 0.78, params.baseColor.B * 0.78)
		),
	})
	grad.Parent = btn

	local mainLbl = Instance.new("TextLabel")
	mainLbl.Name = "TitleLabel"
	mainLbl.Size = UDim2.new(1, -8, if params.subtitle then 0.58 else 1, 0)
	mainLbl.Position = UDim2.fromOffset(4, if params.subtitle then 4 else 0)
	mainLbl.BackgroundTransparency = 1
	mainLbl.Font = Enum.Font.GothamBlack
	mainLbl.Text = params.title
	mainLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	mainLbl.TextSize = 14
	mainLbl.TextScaled = true
	mainLbl.Parent = btn

	if params.subtitle then
		local subLbl = Instance.new("TextLabel")
		subLbl.Name = "SubLabel"
		subLbl.Size = UDim2.new(1, -8, 0.34, 0)
		subLbl.Position = UDim2.new(0, 4, 0.60, 0)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.GothamBold
		subLbl.Text = params.subtitle
		subLbl.TextColor3 = Color3.fromRGB(225, 240, 255)
		subLbl.TextSize = 10
		subLbl.Parent = btn
	end

	local isDown = false
	local function setPressed(down: boolean)
		if isDown == down then
			return
		end
		isDown = down
		btn.BackgroundTransparency = if down then 0.0 else 0.14
		stroke.Thickness = if down then 3.2 else 2.2
		if params.onHoldChanged then
			params.onHoldChanged(down)
		end
		if down and params.onPressed then
			params.onPressed()
		end
	end

	btn.InputBegan:Connect(function(inp: InputObject)
		if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
			setPressed(true)
		end
	end)
	btn.InputEnded:Connect(function(inp: InputObject)
		if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
			setPressed(false)
		end
	end)
	btn.MouseLeave:Connect(function()
		if isDown and not UserInputService.TouchEnabled then
			setPressed(false)
		end
	end)

	return btn, mainLbl
end

-- 1. Tall Green GAS PEDAL (TouchThrottle = true)
createPedalButton({
	name = "GasPedal",
	title = "GAS",
	subtitle = "▲ THROTTLE",
	size = UDim2.fromOffset(78, 128),
	position = UDim2.new(1, -78, 1, -128),
	baseColor = Color3.fromRGB(34, 188, 92),
	strokeColor = Color3.fromRGB(115, 255, 165),
	cornerRadius = 14,
	onHoldChanged = function(down: boolean)
		localPlayer:SetAttribute("TouchThrottle", down)
	end,
})

-- 2. Red BRAKE / REV PEDAL (TouchBrake = true)
createPedalButton({
	name = "BrakePedal",
	title = "BRAKE",
	subtitle = "▼ REV",
	size = UDim2.fromOffset(78, 92),
	position = UDim2.new(1, -166, 1, -92),
	baseColor = Color3.fromRGB(218, 56, 64),
	strokeColor = Color3.fromRGB(255, 130, 135),
	cornerRadius = 14,
	onHoldChanged = function(down: boolean)
		localPlayer:SetAttribute("TouchBrake", down)
	end,
})

-- 3. Blue NITRO BOOST Button (TouchNitro = true)
createPedalButton({
	name = "NitroBoostButton",
	title = "🔥 NITRO",
	subtitle = "BOOST",
	size = UDim2.fromOffset(78, 66),
	position = UDim2.new(1, -78, 0, 8),
	baseColor = Color3.fromRGB(32, 152, 245),
	strokeColor = Color3.fromRGB(125, 225, 255),
	cornerRadius = 14,
	onHoldChanged = function(down: boolean)
		localPlayer:SetAttribute("TouchNitro", down)
		localPlayer:SetAttribute("TouchBoost", down)
		localPlayer:SetAttribute("TouchSprint", down)
	end,
})

-- 4. Orange DRIFT Button (TouchDrift = true)
createPedalButton({
	name = "DriftButton",
	title = "💨 DRIFT",
	subtitle = "SLIDE / ROLL",
	size = UDim2.fromOffset(78, 66),
	position = UDim2.new(1, -166, 0, 44),
	baseColor = Color3.fromRGB(235, 132, 32),
	strokeColor = Color3.fromRGB(255, 205, 95),
	cornerRadius = 14,
	onHoldChanged = function(down: boolean)
		localPlayer:SetAttribute("TouchDrift", down)
		if down and not isPlayerSeated() then
			localPlayer:SetAttribute("TouchDodge", true)
		else
			localPlayer:SetAttribute("TouchDodge", false)
		end
	end,
})

-- 5. Context Button: ENTER CAR / EXIT CAR (EnterNearestVehicle / jump out)
local contextCarBtn, contextCarLabel = createPedalButton({
	name = "EnterExitCarButton",
	title = "🚗 ENTER CAR",
	subtitle = nil,
	size = UDim2.fromOffset(166, 32),
	position = UDim2.new(1, -166, 0, -28),
	baseColor = Color3.fromRGB(128, 72, 225),
	strokeColor = Color3.fromRGB(195, 155, 255),
	cornerRadius = 10,
	onPressed = function()
		if isPlayerSeated() then
			enterOrExitVehicleAction()
		else
			local char = localPlayer.Character
			local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			local nearest = if hrp then findNearestVehicle(hrp.Position, 26) else nil
			if nearest then
				enterOrExitVehicleAction()
			else
				summonPersonalVehicle()
			end
		end
	end,
})

local function updateContextCarButtonVisual()
	if isPlayerSeated() then
		contextCarLabel.Text = "🚪 EXIT CAR"
		contextCarBtn.BackgroundColor3 = Color3.fromRGB(215, 95, 45)
	else
		contextCarLabel.Text = "🚗 ENTER CAR"
		contextCarBtn.BackgroundColor3 = Color3.fromRGB(128, 72, 225)
	end
end

--------------------------------------------------------------------------------
-- Console Gamepad Global Navigation & Shortcuts (Xbox / PlayStation DualSense)
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	refreshInputPlatform(input.UserInputType)

	if UserInputService:GetFocusedTextBox() then
		return
	end

	local key = input.KeyCode
	local modalOpen = isAnyModalOpen()

	-- 1. ButtonSelect / ButtonStart: Toggle Home Menu / Settings (ToggleHomeMenu attribute)
	if key == Enum.KeyCode.ButtonSelect or key == Enum.KeyCode.ButtonStart then
		toggleHomeMenuModal()
		return
	end

	-- 2. ButtonB (B / Circle): Close any open UI modal, or Tactical Dodge when on foot with no modal open!
	if key == Enum.KeyCode.ButtonB then
		if closeAnyOpenModal() then
			return
		end
		if not isPlayerSeated() then
			localPlayer:SetAttribute("TriggerTacticalDodge", os.clock())
		end
		return
	end

	-- 3. ButtonY (Y / Triangle): Enter/Hijack nearest vehicle when on foot, or Exit vehicle when driving!
	if key == Enum.KeyCode.ButtonY then
		if not modalOpen then
			enterOrExitVehicleAction()
		end
		return
	end

	-- 4. D-Pad Global Shortcuts (when not navigating inside an open UI modal with GuiService)
	if key == Enum.KeyCode.DPadLeft then
		if not modalOpen or (getSpeedShopModal() and (getSpeedShopModal() :: Frame).Visible) then
			localPlayer:SetAttribute("ToggleShopUI", not (localPlayer:GetAttribute("ToggleShopUI") == true))
			task.defer(updateGamepadModalFocus)
		end
		return
	elseif key == Enum.KeyCode.DPadRight then
		if not modalOpen or (getAvatarShopModal() and (getAvatarShopModal() :: Frame).Visible) then
			localPlayer:SetAttribute("ToggleAvatarUI", not (localPlayer:GetAttribute("ToggleAvatarUI") == true))
			task.defer(updateGamepadModalFocus)
		end
		return
	elseif key == Enum.KeyCode.DPadUp then
		if not modalOpen and not gameProcessed then
			summonPersonalVehicle()
		end
		return
	elseif key == Enum.KeyCode.DPadDown then
		if not modalOpen and not gameProcessed then
			repairCurrentVehicle()
		end
		return
	end
end)

UserInputService.LastInputTypeChanged:Connect(function(lastInputType: Enum.UserInputType)
	refreshInputPlatform(lastInputType)
end)

localPlayer:GetAttributeChangedSignal("ControlSchemeOverride"):Connect(function()
	refreshInputPlatform(nil)
end)

localPlayer:GetAttributeChangedSignal("HomeMenuActive"):Connect(function()
	refreshInputPlatform(nil)
end)

-- Periodic lightweight sync for modal focus & context button label
local focusPollAccum = 0
RunService.RenderStepped:Connect(function(dt: number)
	focusPollAccum += dt
	if focusPollAccum < 0.12 then
		return
	end
	focusPollAccum = 0

	updateContextCarButtonVisual()
	updateGamepadModalFocus()
end)

refreshInputPlatform(nil)
