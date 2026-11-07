--!strict
--[[
	OnFootController.client.luau
	Enhanced on-foot character movement & vehicle interaction controller
	for World of Destruction (Leo City).

	Features (inspired by OnFootController.swift & HeroCharacter.swift):
	  - Smooth Sprint (LeftShift / L3 / Touch) with speed ramp & subtle FOV boost
	  - Tactical Dodge / Roll (Q / ButtonB / Touch) with burst dash impulse & trail
	  - Super Jump (enhanced jump power + double-jump boost in mid-air)
	  - Quick Enter / Hijack nearby vehicle (E / ButtonX)
	  - Quick-Summon personal vehicle (V / DPadUp / Touch)
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Tuning Constants
--------------------------------------------------------------------------------
local WALK_SPEED = 18
local SPRINT_SPEED = 30
local ACCEL_RATE = 48
local DECEL_RATE = 64

local BASE_JUMP_POWER = 56
local SUPER_JUMP_BOOST = 42
local SUPER_JUMP_COOLDOWN = 0.85

local DODGE_SPEED = 68
local DODGE_DURATION = 0.24
local DODGE_COOLDOWN = 1.05

local SUMMON_COOLDOWN = 1.5
local ENTER_VEHICLE_RANGE = 22

local BASE_FOV = 70
local SPRINT_FOV = 77

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local isSprinting = false
local currentTargetSpeed = WALK_SPEED
local smoothedSpeed = WALK_SPEED

local lastDodgeAt = 0
local isDodging = false
local dodgeEndTime = 0
local dodgeDirection = Vector3.zero

local lastSummonAt = 0
local lastSuperJumpAt = 0
local canDoubleJump = false

local function getRemoteEvent(name: string): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local r = remotes:FindFirstChild(name)
		if r and r:IsA("RemoteEvent") then
			return r
		end
	end
	local root = ReplicatedStorage:FindFirstChild(name)
	if root and root:IsA("RemoteEvent") then
		return root
	end
	return nil
end

local function isPlayerSeated(): boolean
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return (hum ~= nil and (hum.SeatPart ~= nil or hum.Sit == true))
end

local function isUiModalBlockingAction(): boolean
	if localPlayer:GetAttribute("UIModalOpen") == true or localPlayer:GetAttribute("HomeMenuActive") == true then
		return true
	end
	local lastClosed = tonumber(localPlayer:GetAttribute("LastModalClosedAt")) or 0
	if (os.clock() - lastClosed) < 0.22 then
		return true
	end
	local pGui = localPlayer:FindFirstChild("PlayerGui")
	if pGui then
		for _, modalName in ipairs({
			"HomeMenuOverlay",
			"SettingsModal",
			"GrandFinaleVictoryModal",
			"SpeedShopModal",
			"CreatorModal",
			"ModalBackdrop",
		}) do
			local found = pGui:FindFirstChild(modalName, true)
			if found and found:IsA("GuiObject") and found.Visible then
				return true
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Actions: Dodge/Roll, Quick-Enter Vehicle, Quick-Summon Vehicle
--------------------------------------------------------------------------------
local function performDodgeRoll()
	if isPlayerSeated() then
		return
	end
	local now = os.clock()
	if now - lastDodgeAt < DODGE_COOLDOWN then
		return
	end

	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return
	end

	lastDodgeAt = now
	isDodging = true
	dodgeEndTime = now + DODGE_DURATION

	local moveDir = hum.MoveDirection
	if moveDir.Magnitude > 0.05 then
		dodgeDirection = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	else
		local look = hrp.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		dodgeDirection = if flatLook.Magnitude > 0.05 then flatLook.Unit else Vector3.new(0, 0, -1)
	end

	-- Apply initial burst velocity with a slight hop
	hrp.AssemblyLinearVelocity = dodgeDirection * DODGE_SPEED + Vector3.new(0, 14, 0)
	localPlayer:SetAttribute("IsDodging", true)

	-- Brief visual highlight streak during tactical dodge
	local highlight = Instance.new("Highlight")
	highlight.Name = "DodgeTrailHighlight"
	highlight.FillColor = Color3.fromRGB(120, 210, 255)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0.2
	highlight.Parent = char

	task.delay(DODGE_DURATION, function()
		isDodging = false
		localPlayer:SetAttribute("IsDodging", false)
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

local function findNearestVehicle(origin: Vector3): Model?
	local bestModel: Model? = nil
	local bestDist = ENTER_VEHICLE_RANGE

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

local function tryEnterOrHijackNearestVehicle()
	if isPlayerSeated() or isUiModalBlockingAction() then
		return
	end
	local now = os.clock()
	local sharedLast = tonumber(localPlayer:GetAttribute("LastVehicleEnterExitAt")) or 0
	if (now - sharedLast) < 0.35 then
		return
	end
	localPlayer:SetAttribute("LastVehicleEnterExitAt", now)

	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local nearest = findNearestVehicle(hrp.Position)
	if nearest then
		local enterRemote = getRemoteEvent("EnterNearestVehicle")
		if enterRemote then
			enterRemote:FireServer(nearest)
		end
	end
end

local function trySummonPersonalVehicle()
	if isUiModalBlockingAction() then
		return
	end
	local now = os.clock()
	local sharedLast = tonumber(localPlayer:GetAttribute("LastVehicleSummonAt")) or 0
	if (now - lastSummonAt) < SUMMON_COOLDOWN or (now - sharedLast) < 1.0 then
		return
	end
	lastSummonAt = now
	localPlayer:SetAttribute("LastVehicleSummonAt", now)

	local summonRemote = getRemoteEvent("SummonVehicle") or getRemoteEvent("SpawnVehicle")
	if summonRemote then
		summonRemote:FireServer(nil, true)
	end
end

--------------------------------------------------------------------------------
-- Input Bindings (Touch flag false so default grey buttons never clutter iPad)
--------------------------------------------------------------------------------
local function bindOnFootActions()
	-- Sprint (LeftShift / ButtonL3 / ButtonL2)
	ContextActionService:BindAction("OnFootSprint", function(_, state: Enum.UserInputState)
		if isPlayerSeated() then
			isSprinting = false
			return Enum.ContextActionResult.Pass
		end
		isSprinting = (state == Enum.UserInputState.Begin)
		localPlayer:SetAttribute("IsSprinting", isSprinting)
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3, Enum.KeyCode.ButtonL2)

	-- Tactical Dodge / Roll (Q / ButtonB when no UI modal is open)
	ContextActionService:BindAction("OnFootDodge", function(_, state: Enum.UserInputState)
		if isPlayerSeated() or isUiModalBlockingAction() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			performDodgeRoll()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)

	-- Quick Enter / Hijack Vehicle (E / ButtonY / ButtonX)
	ContextActionService:BindAction("OnFootEnterVehicle", function(_, state: Enum.UserInputState)
		if isPlayerSeated() or isUiModalBlockingAction() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			tryEnterOrHijackNearestVehicle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonX)

	-- Quick-Summon Personal Vehicle (V / DPadUp)
	ContextActionService:BindAction("OnFootSummonVehicle", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and not isUiModalBlockingAction() then
			trySummonPersonalVehicle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V, Enum.KeyCode.DPadUp)
end

localPlayer:GetAttributeChangedSignal("TriggerTacticalDodge"):Connect(function()
	if not isPlayerSeated() and not isUiModalBlockingAction() then
		performDodgeRoll()
	end
end)

localPlayer:GetAttributeChangedSignal("TouchDodge"):Connect(function()
	if localPlayer:GetAttribute("TouchDodge") == true and not isPlayerSeated() and not isUiModalBlockingAction() then
		performDodgeRoll()
	end
end)

-- Super Jump (Double-Jump in mid-air when pressing Jump again)
UserInputService.JumpRequest:Connect(function()
	if isPlayerSeated() then
		return
	end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return
	end

	local state = hum:GetState()
	local isAir = (state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping)
	local now = os.clock()

	if isAir and canDoubleJump and (now - lastSuperJumpAt) >= SUPER_JUMP_COOLDOWN then
		canDoubleJump = false
		lastSuperJumpAt = now
		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 1.12, math.max(vel.Y, 0) + SUPER_JUMP_BOOST, vel.Z * 1.12)
	end
end)

--------------------------------------------------------------------------------
-- Character Setup & Per-Frame Movement Smoothing
--------------------------------------------------------------------------------
local function setupCharacter(character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end

	hum.UseJumpPower = true
	hum.JumpPower = BASE_JUMP_POWER
	hum.WalkSpeed = WALK_SPEED
	smoothedSpeed = WALK_SPEED
	canDoubleJump = false

	hum.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Jumping then
			task.delay(0.12, function()
				canDoubleJump = true
			end)
		elseif newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
			canDoubleJump = false
		end
	end)
end

if localPlayer.Character then
	task.spawn(setupCharacter, localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(setupCharacter)
bindOnFootActions()

RunService.RenderStepped:Connect(function(dt: number)
	if dt <= 0 or dt > 0.15 then
		return
	end
	if isPlayerSeated() then
		return
	end

	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return
	end

	local now = os.clock()
	if isDodging and now < dodgeEndTime then
		local currentVel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(
			dodgeDirection.X * DODGE_SPEED,
			currentVel.Y,
			dodgeDirection.Z * DODGE_SPEED
		)
		return
	end

	-- Smooth acceleration/deceleration between Walk and Sprint (Keyboard LeftShift, Gamepad L2/L3, or iPad Touch)
	local kbSprint = not UserInputService:GetFocusedTextBox()
		and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
	local gamepadSprint = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2)
	if not gamepadSprint then
		local okPad, padState = pcall(function()
			return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		end)
		if okPad and padState then
			for _, stateObj in ipairs(padState) do
				if stateObj.KeyCode == Enum.KeyCode.ButtonL2 and stateObj.Position.Z > 0.25 then
					gamepadSprint = true
					break
				end
			end
		end
	end
	local touchSprint = (localPlayer:GetAttribute("TouchSprint") == true)
		or (localPlayer:GetAttribute("TouchNitro") == true)

	isSprinting = kbSprint or gamepadSprint or touchSprint
	localPlayer:SetAttribute("IsSprinting", isSprinting)

	local moving = hum.MoveDirection.Magnitude > 0.05
	currentTargetSpeed = if (isSprinting and moving) then SPRINT_SPEED else WALK_SPEED

	if smoothedSpeed < currentTargetSpeed then
		smoothedSpeed = math.min(currentTargetSpeed, smoothedSpeed + ACCEL_RATE * dt)
	else
		smoothedSpeed = math.max(currentTargetSpeed, smoothedSpeed - DECEL_RATE * dt)
	end

	hum.WalkSpeed = smoothedSpeed

	-- Subtle FOV widening while sprinting on foot
	local cam = Workspace.CurrentCamera
	if cam then
		local targetFov = if (isSprinting and moving) then SPRINT_FOV else BASE_FOV
		cam.FieldOfView = cam.FieldOfView + (targetFov - cam.FieldOfView) * math.min(1, dt * 8)
	end
end)
