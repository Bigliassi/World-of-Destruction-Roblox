--!strict
--[[
	VehicleClientController.client.luau
	High-playability arcade driving controller for World of Destruction (Leo City).

	Features:
	  - Instant-response keyboard (W/A/S/D + Arrow keys), gamepad, touch, and VehicleSeat inputs
	  - Physics velocity & critically-damped hover suspension updated in RunService.Heartbeat
	  - Smooth curb/sidewalk/ramp climb assist so vehicles never snag on seams
	  - Handbrake drifting (Space / R1 / Touch) with lateral slip & drift angle scoring
	  - Regenerating Nitro boost (LeftShift / L1 / Touch) with flame particles & camera FOV surge
	  - Mid-air pitch/roll stunt control (W/A/S/D) + airtime tracker reporting "MEGA AIR!" to server
	  - High-speed near-miss detector against traffic & police vehicles ("NEAR MISS!")
	  - Real-time 4-wheel spin, front-axle steering, and visual body pitch/roll suspension tilt in RenderStepped
	  - Headlight toggle (L key + automatic night activation based on Lighting.ClockTime)
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
local VehicleCatalog: any = nil
if sharedFolder then
	pcall(function()
		VehicleCatalog = require(sharedFolder:WaitForChild("VehicleCatalog", 5))
	end)
end

local function ensureRemoteEvent(name: string): RemoteEvent?
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

--------------------------------------------------------------------------------
-- Arcade Driving Constants (tuned from Swift VehicleConfig & VehicleController)
--------------------------------------------------------------------------------
local BASE_FOV = 70
local BOOST_FOV_ADD = 14
local SPEED_FOV_ADD = 6

local BOOST_SPEED_MULTIPLIER = 1.62
local BOOST_ACCEL_MULTIPLIER = 2.15
local NITRO_REGEN_RATE = 0.42         -- seconds of fuel recovered per second
local NITRO_REGEN_DELAY = 1.1         -- delay after releasing boost before regen

local DRIFT_MIN_SPEED = 28            -- studs/s minimum forward speed to hold drift
local DRIFT_STEER_MULTIPLIER = 1.45   -- sharper yaw rate while drifting
local DRIFT_SLIP_ANGLE_MAX = math.rad(22)
local DRIFT_LATERAL_GRIP = 0.14       -- lower = longer sideways slide
local NORMAL_LATERAL_GRIP = 0.86      -- crisp lateral grip when not drifting

local AIR_PITCH_TORQUE = 2.6          -- rad/s^2 air pitch control
local AIR_ROLL_TORQUE = 3.0           -- rad/s^2 air roll control
local MIN_STUNT_AIRTIME = 0.65        -- seconds in air to trigger MEGA AIR bonus
local MIN_DRIFT_SCORE_TIME = 0.65     -- seconds of drift to trigger DRIFT KING bonus

local NEAR_MISS_MIN_SPEED = 54        -- studs/s required for near-miss detection
local NEAR_MISS_MAX_DIST = 14.5       -- studs center-to-center threshold
local NEAR_MISS_MIN_DIST = 5.2        -- closer than this counts as a scrape/hit
local NEAR_MISS_COOLDOWN = 2.5        -- per-vehicle cooldown (seconds)

--------------------------------------------------------------------------------
-- Active Driving State
--------------------------------------------------------------------------------
local activeSeat: VehicleSeat? = nil
local activeModel: Model? = nil
local activeChassis: BasePart? = nil

local currentSpeed = 0                -- signed forward speed (studs/s)
local smoothedSteer = 0               -- filtered steer input [-1, 1]
local smoothedSlipAngle = 0           -- visual tail-out angle (rad)
local wheelSpinAngle = 0              -- accumulated wheel rotation (rad)
local visualBodyPitch = 0             -- nose lift/dip angle (rad)
local visualBodyRoll = 0              -- body lean angle in turns/drifts (rad)
local latestThrottleInput = 0         -- latest combined throttle [-1, 1]

local isDrifting = false
local driftDuration = 0
local driftReportTimer = 0

local isBoosting = false
local nitroFuel = 4.0
local nitroMax = 4.0
local lastBoostUsedAt = 0

local isAirborne = false
local airTime = 0

local handbrakeHeld = false
local boostHeld = false
local headlightsOn = true
local manualHeadlightOverride = false

local lastVfxNitro = false
local lastVfxDrift = false
local nearMissTimestamps: { [Model]: number } = {}
local lastCollisionCheckSpeed = 0

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local TILT_BODY_PARTS = {
	"Cabin",
	"Hood",
	"HoodNoseWedge",
	"HoodPowerDome",
	"RoofCap",
	"Windshield",
	"RearWindow",
	"TrunkDeck",
	"SpoilerWing",
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------
local function moveToward(current: number, target: number, maxDelta: number): number
	local diff = target - current
	if math.abs(diff) <= maxDelta then
		return target
	end
	return current + (if diff > 0 then maxDelta else -maxDelta)
end

local function updateRaycastFilter(model: Model?)
	local filterList: { Instance } = {}
	if model then
		table.insert(filterList, model)
	end
	if localPlayer.Character then
		table.insert(filterList, localPlayer.Character)
	end
	local vehiclesFolder = Workspace:FindFirstChild("Vehicles")
	if vehiclesFolder then
		table.insert(filterList, vehiclesFolder)
	end
	local parkedFolder = Workspace:FindFirstChild("ParkedVehicles")
	if parkedFolder then
		table.insert(filterList, parkedFolder)
	end
	raycastParams.FilterDescendantsInstances = filterList
end

local function readCombinedDrivingInput(seat: VehicleSeat): (number, number)
	local kbThrottle = 0
	local kbSteer = 0

	if not UserInputService:GetFocusedTextBox() then
		local forwardDown = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		local backwardDown = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
		local leftDown = UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left)
		local rightDown = UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right)

		if forwardDown then
			kbThrottle += 1
		end
		if backwardDown then
			kbThrottle -= 1
		end
		if leftDown then
			kbSteer -= 1
		end
		if rightDown then
			kbSteer += 1
		end
	end

	local touchThrottle = tonumber(localPlayer:GetAttribute("TouchThrottle")) or 0
	local touchSteer = tonumber(localPlayer:GetAttribute("TouchSteer")) or 0

	local seatThrottle = seat.ThrottleFloat
	local seatSteer = seat.SteerFloat

	local finalThrottle = kbThrottle
	if math.abs(touchThrottle) > math.abs(finalThrottle) then
		finalThrottle = touchThrottle
	end
	if math.abs(seatThrottle) > math.abs(finalThrottle) then
		finalThrottle = seatThrottle
	end

	local finalSteer = kbSteer
	if math.abs(touchSteer) > math.abs(finalSteer) then
		finalSteer = touchSteer
	end
	if math.abs(seatSteer) > math.abs(finalSteer) then
		finalSteer = seatSteer
	end

	return math.clamp(finalThrottle, -1, 1), math.clamp(finalSteer, -1, 1)
end

local function fireStuntToServer(stuntType: string, value: number, pos: Vector3)
	local reportStunt = ensureRemoteEvent("ReportStunt") or ensureRemoteEvent("StuntEvent")
	if reportStunt then
		reportStunt:FireServer(stuntType, value, pos)
	end
end

local function setLocalVFX(model: Model?, nitroActive: boolean, driftActive: boolean)
	if not model then
		return
	end
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end

	if nitroActive ~= lastVfxNitro then
		lastVfxNitro = nitroActive
		for _, attName in ipairs({ "ExhaustAttachmentL", "ExhaustAttachmentR" }) do
			local att = chassis:FindFirstChild(attName)
			local flame = att and att:FindFirstChild("NitroFlame") :: ParticleEmitter?
			if flame then
				flame.Enabled = nitroActive
			end
		end
		local vfxRemote = ensureRemoteEvent("VehicleVFX")
		if vfxRemote then
			vfxRemote:FireServer("Nitro", nitroActive)
		end
	end

	if driftActive ~= lastVfxDrift then
		lastVfxDrift = driftActive
		for _, attName in ipairs({ "DriftAttachmentL", "DriftAttachmentR" }) do
			local att = chassis:FindFirstChild(attName)
			local smoke = att and att:FindFirstChild("DriftSmoke") :: ParticleEmitter?
			if smoke then
				smoke.Enabled = driftActive
			end
		end
		for _, trailName in ipairs({ "SkidTrailL", "SkidTrailR" }) do
			local trail = chassis:FindFirstChild(trailName) :: Trail?
			if trail then
				trail.Enabled = driftActive
			end
		end
		local vfxRemote = ensureRemoteEvent("VehicleVFX")
		if vfxRemote then
			vfxRemote:FireServer("Drift", driftActive)
		end
	end
end

local function applyHeadlightState(model: Model?, isOn: boolean)
	if not model then
		return
	end
	headlightsOn = isOn
	for _, partName in ipairs({ "HeadlightL", "HeadlightR" }) do
		local hl = model:FindFirstChild(partName) :: BasePart?
		if hl then
			hl.Material = if isOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local spot = hl:FindFirstChildOfClass("SpotLight")
			if spot then
				spot.Enabled = isOn
			end
		end
	end
	local hlRemote = ensureRemoteEvent("ToggleHeadlights")
	if hlRemote then
		hlRemote:FireServer(isOn)
	end
end

--------------------------------------------------------------------------------
-- Input Actions (Handbrake Drift, Nitro Boost, Headlights)
--------------------------------------------------------------------------------
local function bindDrivingActions()
	ContextActionService:BindAction("VehicleDriftAction", function(_, state: Enum.UserInputState)
		handbrakeHeld = (state == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.Space, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("VehicleDriftAction", "DRIFT")
	ContextActionService:SetPosition("VehicleDriftAction", UDim2.new(1, -165, 1, -125))

	ContextActionService:BindAction("VehicleNitroAction", function(_, state: Enum.UserInputState)
		boostHeld = (state == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle("VehicleNitroAction", "NITRO")
	ContextActionService:SetPosition("VehicleNitroAction", UDim2.new(1, -95, 1, -185))

	ContextActionService:BindAction("VehicleHeadlightsAction", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and activeModel then
			manualHeadlightOverride = true
			applyHeadlightState(activeModel, not headlightsOn)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.L)
end

local function unbindDrivingActions()
	ContextActionService:UnbindAction("VehicleDriftAction")
	ContextActionService:UnbindAction("VehicleNitroAction")
	ContextActionService:UnbindAction("VehicleHeadlightsAction")
	handbrakeHeld = false
	boostHeld = false
end

--------------------------------------------------------------------------------
-- Visual Wheel Spin, Steering & Springy Body Pitch/Roll Suspension Animation
--------------------------------------------------------------------------------
local function animateWheelsAndSuspension(model: Model, dt: number, forwardSpeed: number, steerAmount: number)
	local wheelRadius = 1.5
	local fl = model:FindFirstChild("WheelFL") :: BasePart?
	if fl then
		wheelRadius = math.max(0.8, fl.Size.Y * 0.5)
	end

	wheelSpinAngle = (wheelSpinAngle - (forwardSpeed / wheelRadius) * dt) % (math.pi * 2)
	local maxSteerAngle = math.rad(28)
	local steerYaw = -steerAmount * maxSteerAngle

	-- Animate subtle visual body pitch (nose lifts on accel/nitro, dips on braking) and body roll (leans into turns/drifts)
	local targetPitch = 0
	if latestThrottleInput > 0.1 then
		targetPitch = math.rad(if isBoosting then 2.8 else 1.5) * latestThrottleInput
	elseif latestThrottleInput < -0.1 or (handbrakeHeld and forwardSpeed > 15) then
		targetPitch = -math.rad(1.8)
	end

	local speedRatio = math.clamp(math.abs(forwardSpeed) / 75, 0, 1.2)
	local targetRoll = steerAmount * speedRatio * math.rad(if isDrifting then 5.2 else 2.8)

	visualBodyPitch += (targetPitch - visualBodyPitch) * math.min(1, dt * 10)
	visualBodyRoll += (targetRoll - visualBodyRoll) * math.min(1, dt * 10)

	local suspBounceY = math.sin(wheelSpinAngle * 2) * 0.03 * math.clamp(math.abs(forwardSpeed) / 60, 0, 1)

	for _, wheelName in ipairs({ "WheelFL", "WheelFR", "WheelRL", "WheelRR" }) do
		local wheel = model:FindFirstChild(wheelName) :: BasePart?
		if wheel then
			local weld = wheel:FindFirstChild("WheelWeld") :: Weld?
			if weld then
				local bx = tonumber(wheel:GetAttribute("BaseX")) or weld.C0.Position.X
				local by = (tonumber(wheel:GetAttribute("BaseY")) or weld.C0.Position.Y) + suspBounceY
				local bz = tonumber(wheel:GetAttribute("BaseZ")) or weld.C0.Position.Z
				local isFront = wheel:GetAttribute("IsFrontWheel") == true
				if isFront then
					weld.C0 = CFrame.new(bx, by, bz)
						* CFrame.Angles(0, steerYaw, 0)
						* CFrame.Angles(wheelSpinAngle, 0, 0)
				else
					weld.C0 = CFrame.new(bx, by, bz) * CFrame.Angles(wheelSpinAngle, 0, 0)
				end
			end
		end
	end

	-- Apply subtle pitch/roll tilt to visual upper-body parts (Cabin, Hood, RoofCap, Windshield, RearWindow)
	local tiltRotation = CFrame.Angles(visualBodyPitch, 0, visualBodyRoll)
	for _, partName in ipairs(TILT_BODY_PARTS) do
		local part = model:FindFirstChild(partName) :: BasePart?
		if part then
			local weld = part:FindFirstChild(partName .. "_Weld") :: Weld?
			if weld then
				local baseC0 = part:GetAttribute("BaseC0")
				if typeof(baseC0) ~= "CFrame" then
					baseC0 = weld.C0
					part:SetAttribute("BaseC0", baseC0)
				end
				weld.C0 = (baseC0 :: CFrame) * tiltRotation
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Near-Miss Detection
--------------------------------------------------------------------------------
local function checkNearMisses(myModel: Model, myPos: Vector3, absSpeed: number)
	if absSpeed < NEAR_MISS_MIN_SPEED then
		return
	end

	local now = os.clock()
	for _, other in ipairs(CollectionService:GetTagged("Vehicle")) do
		if other ~= myModel and other:IsA("Model") and other.PrimaryPart then
			local lastAt = nearMissTimestamps[other]
			if not lastAt or (now - lastAt) >= NEAR_MISS_COOLDOWN then
				local dist = (other.PrimaryPart.Position - myPos).Magnitude
				if dist >= NEAR_MISS_MIN_DIST and dist <= NEAR_MISS_MAX_DIST then
					nearMissTimestamps[other] = now
					fireStuntToServer("NearMiss", 1, myPos)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Seat Session Management
--------------------------------------------------------------------------------
local function startDrivingSession(seat: VehicleSeat, model: Model, chassis: BasePart)
	activeSeat = seat
	activeModel = model
	activeChassis = chassis

	local forwardDir = chassis.CFrame.LookVector
	currentSpeed = chassis.AssemblyLinearVelocity:Dot(forwardDir)
	smoothedSteer = 0
	smoothedSlipAngle = 0
	visualBodyPitch = 0
	visualBodyRoll = 0
	latestThrottleInput = 0
	isDrifting = false
	driftDuration = 0
	driftReportTimer = 0
	isAirborne = false
	airTime = 0

	nitroMax = tonumber(model:GetAttribute("NitroCapacity")) or 4.0
	nitroFuel = nitroMax
	lastVfxNitro = false
	lastVfxDrift = false
	lastCollisionCheckSpeed = 0

	updateRaycastFilter(model)
	bindDrivingActions()

	-- Automatic night-time headlights check
	if not manualHeadlightOverride then
		local clock = Lighting.ClockTime
		local shouldBeOn = (clock >= 17.5 or clock <= 6.5) or (model:GetAttribute("HeadlightsOn") == true)
		applyHeadlightState(model, shouldBeOn)
	end
end

local function stopDrivingSession()
	if activeModel then
		setLocalVFX(activeModel, false, false)
	end
	unbindDrivingActions()

	activeSeat = nil
	activeModel = nil
	activeChassis = nil
	currentSpeed = 0
	latestThrottleInput = 0
	isDrifting = false
	isBoosting = false
	isAirborne = false

	localPlayer:SetAttribute("VehicleSpeed", 0)
	localPlayer:SetAttribute("VehicleSpeedMPH", 0)
	localPlayer:SetAttribute("IsDrifting", false)
	localPlayer:SetAttribute("IsBoosting", false)
	localPlayer:SetAttribute("AirTime", 0)

	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = BASE_FOV
	end
end

local function inspectCharacterSeat(character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end

	local function checkSeat()
		local seatPart = hum.SeatPart
		if seatPart and seatPart:IsA("VehicleSeat") then
			local model = seatPart:FindFirstAncestorOfClass("Model")
			local chassis = model and (model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?)
			if model and chassis then
				if activeSeat ~= seatPart then
					startDrivingSession(seatPart, model, chassis)
				end
				return
			end
		end
		if activeSeat ~= nil then
			stopDrivingSession()
		end
	end

	hum:GetPropertyChangedSignal("SeatPart"):Connect(checkSeat)
	checkSeat()
end

if localPlayer.Character then
	task.spawn(inspectCharacterSeat, localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(inspectCharacterSeat)

--------------------------------------------------------------------------------
-- 1. Heartbeat Physics Loop: Velocity, Steering & Springy Curb-Climb Suspension
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	if not activeSeat or not activeModel or not activeChassis then
		return
	end
	if not activeModel.Parent or not activeSeat.Parent then
		stopDrivingSession()
		return
	end
	if dt <= 0 or dt > 0.15 then
		return
	end

	local seat = activeSeat
	local model = activeModel
	local chassis = activeChassis

	if model:GetAttribute("IsWrecked") == true then
		setLocalVFX(model, false, false)
		return
	end

	-- 1. Read Vehicle Tuning Attributes
	local maxSpeed = tonumber(model:GetAttribute("MaxSpeed")) or 85
	local reverseMax = tonumber(model:GetAttribute("ReverseSpeed")) or 40
	local accelRate = tonumber(model:GetAttribute("Acceleration")) or 65
	local brakeDecel = tonumber(model:GetAttribute("BrakeDecel")) or 115
	local turnSpeed = tonumber(model:GetAttribute("TurnSpeed")) or 2.85
	local driftFactor = tonumber(model:GetAttribute("DriftFactor")) or 1.25
	local hoverHeight = tonumber(model:GetAttribute("HoverHeight")) or 2.2
	nitroMax = tonumber(model:GetAttribute("NitroCapacity")) or 4.0

	-- Damage penalty only when severely hurt (<25% health)
	local hp = tonumber(model:GetAttribute("Health")) or 100
	local maxHp = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)
	local healthFactor = if (hp / maxHp) < 0.25 then 0.80 else 1.0

	-- 2. Read Direct Keyboard + Gamepad + Touch + VehicleSeat Inputs (Instant Zero-Delay Response!)
	local rawThrottle, rawSteer = readCombinedDrivingInput(seat)
	latestThrottleInput = rawThrottle

	-- Also check if LeftShift/Space are held directly via keyboard for instant response
	if not UserInputService:GetFocusedTextBox() then
		local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space)
		boostHeld = shiftDown or (localPlayer:GetAttribute("TouchBoost") == true)
		handbrakeHeld = spaceDown or (localPlayer:GetAttribute("TouchDrift") == true)
	end

	-- Smooth steering input
	smoothedSteer += (rawSteer - smoothedSteer) * math.min(1, dt * 16)

	-- 3. Ground Detection Raycast & Springy Curb-Climb Hover Suspension
	updateRaycastFilter(model)
	local rayOrigin = chassis.Position + Vector3.new(0, 3, 0)
	local rayLength = hoverHeight + chassis.Size.Y * 0.5 + 5.0
	local groundHit = Workspace:Raycast(rayOrigin, Vector3.new(0, -rayLength, 0), raycastParams)
	local groundedNow = groundHit ~= nil

	if not groundedNow then
		if not isAirborne then
			isAirborne = true
			airTime = 0
		end
		airTime += dt
	else
		if isAirborne then
			local completedAir = airTime
			isAirborne = false
			airTime = 0
			if completedAir >= MIN_STUNT_AIRTIME then
				fireStuntToServer("Air", completedAir, chassis.Position)
			end
		end
	end

	-- 4. Drift State & Scoring
	local forwardVec = chassis.CFrame.LookVector
	local flatForward = Vector3.new(forwardVec.X, 0, forwardVec.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end
	local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)

	local vel = chassis.AssemblyLinearVelocity
	local measuredForwardSpeed = vel:Dot(flatForward)

	-- Blend our kinematic target speed with physical velocity only on hard wall impacts
	if math.abs(measuredForwardSpeed - currentSpeed) > 28 and math.abs(rawThrottle) < 0.1 then
		currentSpeed = measuredForwardSpeed * 0.6 + currentSpeed * 0.4
	end

	-- Detect hard wall collision to apply minor vehicle damage
	local speedDrop = lastCollisionCheckSpeed - math.abs(measuredForwardSpeed)
	if speedDrop > 42 and lastCollisionCheckSpeed > 50 then
		local dmgRemote = ensureRemoteEvent("VehicleDamage")
		if dmgRemote then
			dmgRemote:FireServer(math.clamp(math.round(speedDrop * 0.18), 3, 18))
		end
	end
	lastCollisionCheckSpeed = math.abs(measuredForwardSpeed)

	local wantsDrift = groundedNow
		and currentSpeed > DRIFT_MIN_SPEED
		and math.abs(smoothedSteer) > 0.22
		and (handbrakeHeld or (math.abs(smoothedSteer) > 0.85 and currentSpeed > maxSpeed * 0.72 and rawThrottle > 0.4))

	if wantsDrift then
		isDrifting = true
		driftDuration += dt
		driftReportTimer += dt
		if driftReportTimer >= 1.4 then
			driftReportTimer = 0
			fireStuntToServer("Drift", 1.4, chassis.Position)
		end
	else
		if isDrifting then
			local finishedDrift = driftDuration
			isDrifting = false
			driftDuration = 0
			driftReportTimer = 0
			if finishedDrift >= MIN_DRIFT_SCORE_TIME then
				fireStuntToServer("Drift", finishedDrift, chassis.Position)
			end
		end
	end

	-- 5. Nitro Boost State & Fuel Meter
	local now = os.clock()
	local canBoost = boostHeld and nitroFuel > 0.05 and (rawThrottle > 0 or isDrifting)
	if canBoost then
		isBoosting = true
		nitroFuel = math.max(0, nitroFuel - dt)
		lastBoostUsedAt = now
	else
		isBoosting = false
		if now - lastBoostUsedAt >= NITRO_REGEN_DELAY then
			nitroFuel = math.min(nitroMax, nitroFuel + nitroMax * NITRO_REGEN_RATE * dt)
		end
	end

	-- 6. Update Longitudinal Speed (Forward / Reverse / Brake / Coast)
	local effectiveTopSpeed = maxSpeed * (if isBoosting then BOOST_SPEED_MULTIPLIER else 1.0) * healthFactor
	local effectiveAccel = accelRate * (if isBoosting then BOOST_ACCEL_MULTIPLIER else 1.0) * healthFactor

	if handbrakeHeld and not isDrifting then
		currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
	elseif math.abs(rawThrottle) < 0.05 then
		currentSpeed = moveToward(currentSpeed, 0, (brakeDecel * 0.24) * dt)
	elseif rawThrottle > 0 then
		if currentSpeed < -1 then
			currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
		else
			local driftScrub = if isDrifting and not isBoosting then 8.0 else 0.0
			currentSpeed = math.clamp(
				currentSpeed + (effectiveAccel * rawThrottle - driftScrub) * dt,
				-reverseMax,
				effectiveTopSpeed
			)
		end
	elseif rawThrottle < 0 then
		if currentSpeed > 2 then
			currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
		else
			currentSpeed = math.clamp(
				currentSpeed + (accelRate * 0.85 * rawThrottle) * dt,
				-reverseMax * healthFactor,
				effectiveTopSpeed
			)
		end
	end

	-- 7. Update Steering, Angular Velocity & Critically-Damped Vertical Hover Spring
	local absSpeed = math.abs(currentSpeed)
	local motionGate = math.clamp(absSpeed / 3.5, 0, 1)
	if rawThrottle ~= 0 then
		motionGate = math.max(motionGate, 0.45)
	end

	local driftBoost = if isDrifting then (DRIFT_STEER_MULTIPLIER * math.clamp(driftFactor, 0.9, 1.6)) else 1.0
	local speedScale = 0.0085
	local effectiveTurnRate = (turnSpeed * driftBoost) / (1 + absSpeed * speedScale)
	local steerDir = if currentSpeed < -1.0 then 1 else -1
	local targetYawRate = smoothedSteer * effectiveTurnRate * steerDir * motionGate

	local targetSlip = if isDrifting
		then (-smoothedSteer * DRIFT_SLIP_ANGLE_MAX * math.clamp(absSpeed / 45, 0.3, 1.0))
		else 0
	smoothedSlipAngle += (targetSlip - smoothedSlipAngle) * math.min(1, dt * 9.0)

	if groundedNow and groundHit then
		-- Align roll/pitch gently with road/ramp surface normal while stabilizing against flipping
		local currentAngVel = chassis.AssemblyAngularVelocity
		local rightVec = chassis.CFrame.RightVector
		local surfaceNormal = groundHit.Normal

		local desiredPitchY = math.clamp(-surfaceNormal:Dot(flatForward), -0.45, 0.45)
		local rollErr = rightVec.Y - math.clamp(surfaceNormal:Dot(flatRight), -0.25, 0.25)
		local pitchErr = forwardVec.Y - desiredPitchY
		local stabilizePitch = math.clamp(-pitchErr * 5.5, -4.0, 4.0)
		local stabilizeRoll = math.clamp(rollErr * 7.5, -5.0, 5.0)

		local desiredAngVel = Vector3.new(0, targetYawRate, 0)
			+ rightVec * stabilizePitch
			+ forwardVec * stabilizeRoll
		chassis.AssemblyAngularVelocity = currentAngVel:Lerp(desiredAngVel, math.min(1, dt * 20))

		-- Compute horizontal velocity with controlled lateral drift slip
		local currentLateralSpeed = vel:Dot(flatRight)
		local grip = if isDrifting then DRIFT_LATERAL_GRIP else NORMAL_LATERAL_GRIP
		local nextLateralSpeed = currentLateralSpeed * math.max(0, 1 - grip * dt * 12)
		if isDrifting then
			nextLateralSpeed += smoothedSteer * currentSpeed * 0.22 * driftFactor * dt * 6
		end

		local targetHorizontalVel = flatForward * currentSpeed + flatRight * nextLateralSpeed

		-- Critically-damped vertical spring velocity so the chassis floats smoothly at groundY + hoverHeight
		-- and climbs effortlessly over curbs, sidewalks, and stunt ramps without ever snagging!
		local groundY = groundHit.Position.Y
		local targetY = groundY + hoverHeight
		local vy = (targetY - chassis.Position.Y) * 18 - vel.Y * 0.45
		vy = math.clamp(vy, -35, 45)

		-- Ramp launch & slope climb assist
		if forwardVec.Y >= 0.14 and currentSpeed > 25 then
			vy = math.max(vy, currentSpeed * forwardVec.Y * 1.15)
		end

		chassis.AssemblyLinearVelocity = Vector3.new(targetHorizontalVel.X, vy, targetHorizontalVel.Z)
	else
		-- Mid-air stunt control: W/S pitches nose, A/D rolls/yaws vehicle!
		local rightVec = chassis.CFrame.RightVector
		local lookVec = chassis.CFrame.LookVector
		local pitchInput = rawThrottle * AIR_PITCH_TORQUE
		local rollInput = -rawSteer * AIR_ROLL_TORQUE
		local yawInput = -rawSteer * 1.2

		local airAngVel = rightVec * pitchInput + lookVec * rollInput + Vector3.new(0, yawInput, 0)
		chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity:Lerp(airAngVel, math.min(1, dt * 6))
	end

	-- 8. VFX, Near-Miss Checks & HUD Live Attributes
	setLocalVFX(model, isBoosting, isDrifting or (handbrakeHeld and absSpeed > 25))
	checkNearMisses(model, chassis.Position, absSpeed)

	local mph = math.round(absSpeed * 1.15)
	local ratio = math.clamp(nitroFuel / math.max(0.1, nitroMax), 0, 1)
	localPlayer:SetAttribute("VehicleSpeed", math.round(absSpeed))
	localPlayer:SetAttribute("VehicleSpeedMPH", mph)
	localPlayer:SetAttribute("SpeedMPH", mph)
	localPlayer:SetAttribute("NitroRatio", ratio)
	localPlayer:SetAttribute("NitroFuel", math.round(ratio * 100))
	localPlayer:SetAttribute("MaxNitroFuel", 100)
	localPlayer:SetAttribute("IsDrifting", isDrifting)
	localPlayer:SetAttribute("IsBoosting", isBoosting)
	localPlayer:SetAttribute("DriftAngle", math.round(math.deg(math.abs(smoothedSlipAngle))))
	localPlayer:SetAttribute("AirTime", tonumber(string.format("%.1f", airTime)))
end)

--------------------------------------------------------------------------------
-- 2. RenderStepped Visual Loop: Wheel Spin, Steering, Suspension Tilt & Camera FOV
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt: number)
	if not activeSeat or not activeModel or not activeChassis then
		return
	end
	if not activeModel.Parent or not activeSeat.Parent then
		return
	end
	if dt <= 0 or dt > 0.15 then
		return
	end

	animateWheelsAndSuspension(activeModel, dt, currentSpeed, smoothedSteer)

	local cam = Workspace.CurrentCamera
	if cam then
		local maxSpeed = tonumber(activeModel:GetAttribute("MaxSpeed")) or 85
		local absSpeed = math.abs(currentSpeed)
		local speedRatio = math.clamp(absSpeed / math.max(1, maxSpeed), 0, 1.4)
		local targetFov = BASE_FOV + speedRatio * SPEED_FOV_ADD + (if isBoosting then BOOST_FOV_ADD else 0)
		cam.FieldOfView = cam.FieldOfView + (targetFov - cam.FieldOfView) * math.min(1, dt * 8)
	end
end)
