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

local DRIFT_MIN_SPEED = 24            -- studs/s minimum forward speed to hold drift
local DRIFT_STEER_MULTIPLIER = 1.45   -- sharper yaw rate while drifting
local DRIFT_SLIP_ANGLE_MAX = math.rad(22)
local DRIFT_LATERAL_GRIP = 0.14       -- lower = longer sideways slide
local NORMAL_LATERAL_GRIP = 0.86      -- crisp lateral grip when not drifting

local AIR_PITCH_TORQUE = 1.8          -- rad/s^2 bounded air pitch control
local AIR_ROLL_TORQUE = 2.4           -- rad/s^2 bounded air roll control
local MIN_STUNT_AIRTIME = 0.65        -- seconds in air to trigger MEGA AIR bonus
local MIN_DRIFT_SCORE_TIME = 0.65     -- seconds of drift to trigger DRIFT KING bonus

local NEAR_MISS_MIN_SPEED = 42        -- studs/s required for near-miss detection
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
local smoothedThrottle = 0            -- smooth throttle ramp [-1, 1] over ~0.45s
local smoothedSteer = 0               -- filtered steer input [-1, 1]
local smoothedSlipAngle = 0           -- visual tail-out angle (rad)
local wheelSpinAngle = 0              -- accumulated wheel rotation (rad)
local visualBodyPitch = 0             -- nose lift/dip angle (rad)
local visualBodyRoll = 0              -- body lean angle in turns/drifts (rad)
local latestThrottleInput = 0         -- latest combined throttle [-1, 1]
local currentGear = "N"               -- "R", "N", "1", "2", "3", "4", "5"

local isDrifting = false
local driftDuration = 0
local driftReportTimer = 0

local isBoosting = false
local nitroFuel = 4.0
local nitroMax = 4.0
local lastBoostUsedAt = 0

local isAirborne = false
local airTime = 0
local wasOnRamp = false
local onRampTimer = 0
local rampLaunchGraceTimer = 0
local lastRampSlopeForward = Vector3.new(0, 0.34, -0.94)
local lastRampSurfaceNormal = Vector3.yAxis

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
raycastParams.RespectCanCollide = true

local TILT_BODY_PARTS = {
	"Cabin",
	"DriverHeadrest",
	"DriverSilhouetteTorso",
	"DriverSilhouetteHelmet",
	"DriverHelmetVisor",
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

	-- Read Console Gamepad Analog Triggers (R2/L2 Position.Z 0..1) & Left Thumbstick (Thumbstick1 Position.X)
	local gamepadThrottle = 0
	local gamepadSteer = 0
	local r2Analog = 0
	local l2Analog = 0

	local okGamepad, gamepadState = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if okGamepad and gamepadState then
		for _, stateObj in ipairs(gamepadState) do
			if stateObj.KeyCode == Enum.KeyCode.ButtonR2 then
				r2Analog = math.clamp(stateObj.Position.Z, 0, 1)
			elseif stateObj.KeyCode == Enum.KeyCode.ButtonL2 then
				l2Analog = math.clamp(stateObj.Position.Z, 0, 1)
			elseif stateObj.KeyCode == Enum.KeyCode.Thumbstick1 then
				local stickX = stateObj.Position.X
				if math.abs(stickX) > 0.14 then
					gamepadSteer = math.sign(stickX) * (math.abs(stickX) ^ 1.35)
				end
			end
		end
	end

	-- Digital trigger fallback for controllers that report button-down without analog Z axis
	if r2Analog < 0.05 and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2) then
		r2Analog = 1
	end
	if l2Analog < 0.05 and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2) then
		l2Analog = 1
	end
	gamepadThrottle = math.clamp(r2Analog - l2Analog, -1, 1)

	-- Read iPad / Mobile Touch Pedals (TouchThrottle / TouchBrake booleans or numbers) & Analog Virtual Thumbstick (TouchSteer)
	local touchThrottle = 0
	local rawTouchThrottle = localPlayer:GetAttribute("TouchThrottle")
	local rawTouchBrake = localPlayer:GetAttribute("TouchBrake")
	if rawTouchThrottle == true then
		touchThrottle += 1
	elseif type(rawTouchThrottle) == "number" then
		touchThrottle += rawTouchThrottle
	end
	if rawTouchBrake == true then
		touchThrottle -= 1
	elseif type(rawTouchBrake) == "number" and math.abs(rawTouchBrake) > 0 then
		touchThrottle -= math.abs(rawTouchBrake)
	end

	local touchSteer = tonumber(localPlayer:GetAttribute("TouchSteer")) or 0
	if math.abs(touchSteer) < 0.01 then
		if localPlayer:GetAttribute("TouchSteerLeft") == true then
			touchSteer -= 1
		end
		if localPlayer:GetAttribute("TouchSteerRight") == true then
			touchSteer += 1
		end
	end

	local seatThrottle = seat.ThrottleFloat
	local seatSteer = seat.SteerFloat

	local finalThrottle = kbThrottle
	if math.abs(gamepadThrottle) > math.abs(finalThrottle) then
		finalThrottle = gamepadThrottle
	end
	if math.abs(touchThrottle) > math.abs(finalThrottle) then
		finalThrottle = touchThrottle
	end
	if math.abs(seatThrottle) > math.abs(finalThrottle) then
		finalThrottle = seatThrottle
	end

	local finalSteer = kbSteer
	if math.abs(gamepadSteer) > math.abs(finalSteer) then
		finalSteer = gamepadSteer
	end
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
	-- Touch flag is false so Roblox's default grey ContextActionGui buttons never overlap our custom iPad pedals
	ContextActionService:BindAction("VehicleDriftAction", function(_, state: Enum.UserInputState)
		handbrakeHeld = (state == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonA)

	ContextActionService:BindAction("VehicleNitroAction", function(_, state: Enum.UserInputState)
		boostHeld = (state == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonX)

	ContextActionService:BindAction("VehicleHeadlightsAction", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and activeModel then
			manualHeadlightOverride = true
			applyHeadlightState(activeModel, not headlightsOn)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.L, Enum.KeyCode.ButtonR3)
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
-- Seated Character Head-Clipping Fix & Cabin Silhouette Helper
--------------------------------------------------------------------------------
local function ensureClientCabinSilhouette(model: Model?)
	if not model then
		return
	end
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end
	if model:FindFirstChild("DriverSilhouetteHelmet") then
		return
	end
	local h = chassis.Size.Y
	local cabH = math.max(3.4, h * 1.38)
	local seat = model:FindFirstChild("DriveSeat") :: BasePart?
	local seatZ = if seat then chassis.CFrame:PointToObjectSpace(seat.Position).Z else 0

	local helmet = Instance.new("Part")
	helmet.Name = "DriverSilhouetteHelmet"
	helmet.Shape = Enum.PartType.Ball
	helmet.Size = Vector3.new(1.22, 1.24, 1.28)
	helmet.Color = Color3.fromRGB(18, 22, 28)
	helmet.Material = Enum.Material.SmoothPlastic
	helmet.TopSurface = Enum.SurfaceType.Smooth
	helmet.BottomSurface = Enum.SurfaceType.Smooth
	helmet.CanCollide = false
	helmet.Massless = true
	helmet.CFrame = chassis.CFrame * CFrame.new(0, h * 0.5 + cabH * 0.56, seatZ + 0.04)
	helmet.Parent = model

	local weld = Instance.new("Weld")
	weld.Name = "DriverSilhouetteHelmet_Weld"
	weld.Part0 = chassis
	weld.Part1 = helmet
	weld.C0 = CFrame.new(0, h * 0.5 + cabH * 0.56, seatZ + 0.04)
	weld.Parent = helmet
end

local function shouldHideClientCharacterPart(inst: Instance, character: Model): boolean
	if inst:IsA("BasePart") then
		if inst.Name == "HumanoidRootPart" then
			return false
		end
		if inst.Name == "Head"
			or inst.Name == "UpperTorso"
			or inst.Name == "Torso"
			or inst.Name:find("Arm") ~= nil
			or inst.Name:find("Hand") ~= nil
		then
			return true
		end
		if inst:FindFirstAncestorOfClass("Accessory") or inst:FindFirstAncestorOfClass("Hat") then
			return true
		end
		local wodFolder = character:FindFirstChild("WODAvatarAttachments")
		if wodFolder and inst:IsDescendantOf(wodFolder) then
			return true
		end
		if inst.Name:find("AvatarCustomAccessory") ~= nil or inst:GetAttribute("AvatarCustomAccessory") == true then
			return true
		end
		if CollectionService:HasTag(inst, "AvatarCustomAccessory") then
			return true
		end
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		local parent = inst.Parent
		if parent and (parent.Name == "Head" or parent:FindFirstAncestorOfClass("Accessory") ~= nil) then
			return true
		end
	end
	return false
end

local function setClientSeatedCharacterHidden(character: Model?, vehicleModel: Model?, hide: boolean)
	if vehicleModel and hide then
		ensureClientCabinSilhouette(vehicleModel)
	end
	if not character then
		return
	end
	for _, desc in ipairs(character:GetDescendants()) do
		if shouldHideClientCharacterPart(desc, character) then
			if desc:IsA("BasePart") then
				if hide then
					if desc:GetAttribute("PreSeatTransparency") == nil and desc.Transparency < 0.99 then
						desc:SetAttribute("PreSeatTransparency", desc.Transparency)
					end
					desc.Transparency = 1
					desc.LocalTransparencyModifier = 1
				else
					local saved = tonumber(desc:GetAttribute("PreSeatTransparency"))
					if saved == nil or saved >= 0.99 then
						saved = 0
					end
					desc.Transparency = saved
					desc.LocalTransparencyModifier = 0
					desc:SetAttribute("PreSeatTransparency", nil)
				end
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				if hide then
					if desc:GetAttribute("PreSeatTransparency") == nil and desc.Transparency < 0.99 then
						desc:SetAttribute("PreSeatTransparency", desc.Transparency)
					end
					desc.Transparency = 1
				else
					local saved = tonumber(desc:GetAttribute("PreSeatTransparency"))
					if saved == nil or saved >= 0.99 then
						saved = 0
					end
					desc.Transparency = saved
					desc:SetAttribute("PreSeatTransparency", nil)
				end
			end
		end
	end
end

local function isRampSurfaceHit(hit: RaycastResult?): boolean
	if not hit or not hit.Instance then
		return false
	end
	local inst = hit.Instance
	if inst.Name == "RampWedge" or inst.Name == "JumpTrigger" then
		return true
	end
	if CollectionService:HasTag(inst, "StuntRamp") or CollectionService:HasTag(inst, "StuntRampSurface") then
		return true
	end
	local parent = inst.Parent
	if parent then
		if CollectionService:HasTag(parent, "StuntRamp") or CollectionService:HasTag(parent, "StuntRampSurface") then
			return true
		end
		if parent:FindFirstChild("JumpTrigger") ~= nil or parent:FindFirstChild("RampWedge") ~= nil then
			return true
		end
	end
	if inst:IsA("WedgePart") and hit.Normal.Y < 0.97 and hit.Normal.Y > 0.45 then
		return true
	end
	return false
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
	smoothedThrottle = 0
	smoothedSteer = 0
	smoothedSlipAngle = 0
	visualBodyPitch = 0
	visualBodyRoll = 0
	latestThrottleInput = 0
	currentGear = "1"
	isDrifting = false
	driftDuration = 0
	driftReportTimer = 0
	isAirborne = false
	airTime = 0
	wasOnRamp = false
	onRampTimer = 0
	rampLaunchGraceTimer = 0

	nitroMax = tonumber(model:GetAttribute("NitroCapacity")) or 4.0
	nitroFuel = nitroMax
	lastVfxNitro = false
	lastVfxDrift = false
	lastCollisionCheckSpeed = 0

	setClientSeatedCharacterHidden(localPlayer.Character, model, true)
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
	setClientSeatedCharacterHidden(localPlayer.Character, activeModel, false)
	unbindDrivingActions()

	activeSeat = nil
	activeModel = nil
	activeChassis = nil
	currentSpeed = 0
	smoothedThrottle = 0
	latestThrottleInput = 0
	currentGear = "N"
	isDrifting = false
	isBoosting = false
	isAirborne = false
	wasOnRamp = false
	onRampTimer = 0
	rampLaunchGraceTimer = 0

	localPlayer:SetAttribute("VehicleSpeed", 0)
	localPlayer:SetAttribute("VehicleSpeedMPH", 0)
	localPlayer:SetAttribute("CurrentGear", "N")
	localPlayer:SetAttribute("Gear", "N")
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

	-- 1. Read Vehicle Tuning Attributes & DrivingMode ("Progressive" default vs "Arcade" +18%)
	local drivingMode = tostring(localPlayer:GetAttribute("DrivingMode") or "Progressive")
	local modeMultiplier = if drivingMode == "Arcade" then 1.18 else 1.0

	local maxSpeed = (tonumber(model:GetAttribute("MaxSpeed")) or 64) * modeMultiplier
	local reverseMax = (tonumber(model:GetAttribute("ReverseSpeed")) or 28) * modeMultiplier
	local accelRate = (tonumber(model:GetAttribute("Acceleration")) or 28) * modeMultiplier
	local brakeDecel = tonumber(model:GetAttribute("BrakeDecel")) or 95
	local turnSpeed = tonumber(model:GetAttribute("TurnSpeed")) or 2.4
	local driftFactor = tonumber(model:GetAttribute("DriftFactor")) or 1.25
	local hoverHeight = tonumber(model:GetAttribute("HoverHeight")) or 2.2
	nitroMax = tonumber(model:GetAttribute("NitroCapacity")) or 4.0

	-- Keep seated character head/accessories hidden while driving
	if localPlayer.Character then
		local headPart = localPlayer.Character:FindFirstChild("Head") :: BasePart?
		if headPart and headPart.LocalTransparencyModifier < 0.99 then
			setClientSeatedCharacterHidden(localPlayer.Character, model, true)
		end
	end

	-- Damage penalty only when severely hurt (<25% health)
	local hp = tonumber(model:GetAttribute("Health")) or 100
	local maxHp = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)
	local healthFactor = if (hp / maxHp) < 0.25 then 0.80 else 1.0

	-- 2. Read Direct Keyboard + Gamepad + Touch + VehicleSeat Inputs & Smooth Throttle Ramp
	local rawThrottle, rawSteer = readCombinedDrivingInput(seat)
	latestThrottleInput = rawThrottle

	-- Smooth throttle ramp over ~0.45s (dt * 2.2) when pressing W so tapping W allows gentle low-speed cruising & parking
	if math.abs(rawThrottle) > 0.05 then
		smoothedThrottle = moveToward(smoothedThrottle, rawThrottle, dt * 2.2)
	else
		smoothedThrottle = moveToward(smoothedThrottle, 0, dt * 4.8)
	end

	-- Check Keyboard + Console Gamepad (ButtonX/ButtonL1 Nitro, ButtonA/ButtonR1 Drift) + iPad Touch pedals
	if not UserInputService:GetFocusedTextBox() then
		local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space)

		local modalOpen = localPlayer:GetAttribute("UIModalOpen") == true
		local gamepadNitro = not modalOpen
			and (
				UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX)
				or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1)
			)
		local gamepadDrift = not modalOpen
			and (
				UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
				or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR1)
			)

		local touchNitro = (localPlayer:GetAttribute("TouchNitro") == true)
			or (localPlayer:GetAttribute("TouchBoost") == true)
		local touchDrift = (localPlayer:GetAttribute("TouchDrift") == true)

		boostHeld = shiftDown or gamepadNitro or touchNitro
		handbrakeHeld = spaceDown or gamepadDrift or touchDrift
	end

	-- Smooth steering input
	smoothedSteer += (rawSteer - smoothedSteer) * math.min(1, dt * 14)

	local forwardVec = chassis.CFrame.LookVector
	local flatForward = Vector3.new(forwardVec.X, 0, forwardVec.Z)
	if flatForward.Magnitude < 0.01 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end
	local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)

	-- 3. Multi-Ray Ground & Ramp Detection (Front, Rear, Center)
	updateRaycastFilter(model)
	local rayLength = hoverHeight + chassis.Size.Y * 0.5 + 5.5
	local rayDir = Vector3.new(0, -rayLength, 0)

	local frontOrigin = chassis.CFrame * Vector3.new(0, 2.5, -chassis.Size.Z * 0.38)
	local rearOrigin = chassis.CFrame * Vector3.new(0, 2.5, chassis.Size.Z * 0.38)
	local centerOrigin = chassis.Position + Vector3.new(0, 2.5, 0)

	local frontHit = Workspace:Raycast(frontOrigin, rayDir, raycastParams)
	local rearHit = Workspace:Raycast(rearOrigin, rayDir, raycastParams)
	local centerHit = Workspace:Raycast(centerOrigin, rayDir, raycastParams)

	-- Filter out vertical wall hits so walls are never treated as drivable floors
	if frontHit and frontHit.Normal.Y < 0.35 then
		frontHit = nil
	end
	if rearHit and rearHit.Normal.Y < 0.35 then
		rearHit = nil
	end
	if centerHit and centerHit.Normal.Y < 0.35 then
		centerHit = nil
	end

	if rampLaunchGraceTimer > 0 then
		rampLaunchGraceTimer = math.max(0, rampLaunchGraceTimer - dt)
		frontHit = nil
		rearHit = nil
		centerHit = nil
	end

	-- Track ramp presence when centerHit or frontHit hits a ramp surface
	local onRampNow = isRampSurfaceHit(centerHit) or isRampSurfaceHit(frontHit)
	if onRampNow then
		onRampTimer = 0.25
		wasOnRamp = true
	elseif onRampTimer > 0 then
		onRampTimer = math.max(0, onRampTimer - dt)
		if onRampTimer <= 0 then
			wasOnRamp = false
		end
	end

	-- When crossing the top lip of a ramp (centerHit is still on the ramp, or onRampTimer > 0, and frontHit drops off the cliff lip),
	-- ignore a low frontHit so the cliff drop-off never pulls the nose down before launch
	local referenceRampY = if centerHit then centerHit.Position.Y elseif rearHit then rearHit.Position.Y else nil
	if onRampTimer > 0 and frontHit and referenceRampY and (referenceRampY - frontHit.Position.Y) > 1.6 and not isRampSurfaceHit(frontHit) then
		frontHit = nil
	end

	local groundedNow = (centerHit ~= nil) or (frontHit ~= nil) or (rearHit ~= nil)

	-- Compute blended Surface Normal from centerHit.Normal and (frontHit.Position - rearHit.Position).Unit pitch slope
	local surfaceNormal = Vector3.yAxis
	if groundedNow then
		local normalAccum = Vector3.zero
		if centerHit then
			normalAccum += centerHit.Normal * 1.4
		end
		if frontHit then
			normalAccum += frontHit.Normal * 1.15
		end
		if rearHit then
			normalAccum += rearHit.Normal * 0.85
		end
		if normalAccum.Magnitude > 0.001 then
			surfaceNormal = normalAccum.Unit
		end

		if frontHit and rearHit then
			local spanVec = frontHit.Position - rearHit.Position
			if spanVec.Magnitude > 0.1 then
				local pitchSlopeUnit = spanVec.Unit
				local pitchNormal = flatRight:Cross(pitchSlopeUnit)
				if pitchNormal.Y < 0 then
					pitchNormal = -pitchNormal
				end
				if pitchNormal.Magnitude > 0.001 then
					surfaceNormal = (surfaceNormal + pitchNormal.Unit * 1.35).Unit
				end
			end
		elseif onRampTimer > 0 and not frontHit and lastRampSurfaceNormal.Y < 0.99 then
			-- Preserve ramp upward normal as front axle crosses the top lip of the ramp
			surfaceNormal = lastRampSurfaceNormal
		end
	end

	-- Project forward tangent along surface slope
	local slopeForward = flatForward - surfaceNormal * flatForward:Dot(surfaceNormal)
	if slopeForward.Magnitude > 0.001 then
		slopeForward = slopeForward.Unit
	else
		slopeForward = flatForward
	end

	if onRampNow and slopeForward.Y > 0.06 then
		lastRampSlopeForward = slopeForward
		lastRampSurfaceNormal = surfaceNormal
	end

	-- Check if leaving the top lip of the ramp (either all rays left ground, or frontHit & centerHit left ramp lip at speed)
	local leavingRampLip = (onRampTimer > 0 and currentSpeed > 28)
		and ((not groundedNow) or (wasOnRamp and not onRampNow and frontHit == nil and centerHit == nil))

	-- 4. Drift State & Scoring
	local vel = chassis.AssemblyLinearVelocity
	local measuredForwardSpeed = vel:Dot(slopeForward)

	-- Blend our kinematic target speed with physical velocity only on hard wall impacts
	if math.abs(measuredForwardSpeed - currentSpeed) > 28 and math.abs(rawThrottle) < 0.1 and onRampTimer <= 0 then
		currentSpeed = measuredForwardSpeed * 0.6 + currentSpeed * 0.4
	end

	-- Detect hard wall collision to apply minor vehicle damage (ignore ramp transitions)
	local speedDrop = lastCollisionCheckSpeed - math.abs(measuredForwardSpeed)
	if speedDrop > 42 and lastCollisionCheckSpeed > 50 and onRampTimer <= 0 then
		local dmgRemote = ensureRemoteEvent("VehicleDamage")
		if dmgRemote then
			dmgRemote:FireServer(math.clamp(math.round(speedDrop * 0.18), 3, 18))
		end
	end
	lastCollisionCheckSpeed = math.abs(measuredForwardSpeed)

	local wantsDrift = groundedNow
		and onRampTimer <= 0
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

	-- 6. Progressive 5-Gear Torque Curve, Smooth Throttle Ramp & Aerodynamic Drag
	local effectiveTopSpeed = maxSpeed * (if isBoosting then BOOST_SPEED_MULTIPLIER else 1.0) * healthFactor
	local baseEffectiveAccel = accelRate * (if isBoosting then BOOST_ACCEL_MULTIPLIER else 1.0) * healthFactor
	local absSpeedBefore = math.abs(currentSpeed)

	-- Gear 1 (0..18 studs/s): torque builds smoothly from 0.55x to 1.0x
	local lowSpeedTorque = if absSpeedBefore < 18
		then (0.55 + 0.45 * math.clamp(absSpeedBefore / 18, 0, 1))
		else 1.0
	-- High-speed taper: acceleration tapers off naturally as speed rises toward effectiveTopSpeed (~4-5s to top speed)
	local accelFactor = math.clamp(
		1.0 - math.pow(math.clamp(absSpeedBefore / math.max(1, effectiveTopSpeed), 0, 1), 1.6),
		0.12,
		1.0
	)
	local progressiveAccel = baseEffectiveAccel
		* lowSpeedTorque
		* (if isBoosting then math.max(accelFactor, 0.65) else accelFactor)

	if handbrakeHeld and not isDrifting then
		currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
	elseif math.abs(rawThrottle) < 0.05 then
		local aeroDragDecel = (absSpeedBefore * absSpeedBefore) * 0.0024 + (brakeDecel * 0.18)
		currentSpeed = moveToward(currentSpeed, 0, aeroDragDecel * dt)
	elseif rawThrottle > 0 then
		if currentSpeed < -1 then
			currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
		else
			local throttleDrive = math.max(0, smoothedThrottle)
			local driftScrub = if isDrifting and not isBoosting then 6.0 else 0.0
			currentSpeed = math.clamp(
				currentSpeed + (progressiveAccel * throttleDrive - driftScrub) * dt,
				-reverseMax,
				effectiveTopSpeed
			)
		end
	elseif rawThrottle < 0 then
		if currentSpeed > 2 then
			currentSpeed = moveToward(currentSpeed, 0, brakeDecel * dt)
		else
			local reverseDrive = math.min(0, smoothedThrottle)
			currentSpeed = math.clamp(
				currentSpeed + (accelRate * 0.82 * reverseDrive) * dt,
				-reverseMax * healthFactor,
				effectiveTopSpeed
			)
		end
	end

	-- Compute active gear ("R", "N", "1", "2", "3", "4", "5")
	local absSpeed = math.abs(currentSpeed)
	if currentSpeed < -1.0 or (currentSpeed <= 0.5 and rawThrottle < -0.05) then
		currentGear = "R"
	elseif absSpeed < 1.0 and math.abs(rawThrottle) < 0.05 then
		currentGear = "N"
	else
		local gearRatio = absSpeed / math.max(1, maxSpeed)
		if absSpeed < 18 or gearRatio < 0.26 then
			currentGear = "1"
		elseif gearRatio < 0.46 then
			currentGear = "2"
		elseif gearRatio < 0.66 then
			currentGear = "3"
		elseif gearRatio < 0.85 then
			currentGear = "4"
		else
			currentGear = "5"
		end
	end

	-- 7. Update Steering, Surface-Aligned Pitch/Roll, Slope Velocity & Ballistic Ramp Launch
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
		then (-smoothedSteer * DRIFT_SLIP_ANGLE_MAX * math.clamp(absSpeed / 40, 0.3, 1.0))
		else 0
	smoothedSlipAngle += (targetSlip - smoothedSlipAngle) * math.min(1, dt * 9.0)

	if leavingRampLip then
		-- Clean ballistic ramp launch at the top lip of the ramp!
		groundedNow = false
		onRampTimer = 0
		wasOnRamp = false
		rampLaunchGraceTimer = 0.28
		if not isAirborne then
			isAirborne = true
			airTime = 0
		end
		local launchSlope = if lastRampSlopeForward.Magnitude > 0.01 then lastRampSlopeForward.Unit else slopeForward.Unit
		chassis.AssemblyLinearVelocity = launchSlope * currentSpeed * 1.12
			+ Vector3.new(0, math.clamp(currentSpeed * 0.42, 18, 38), 0)
		chassis.AssemblyAngularVelocity = Vector3.new(0, targetYawRate * 0.25, 0)
	elseif groundedNow then
		if isAirborne then
			local completedAir = airTime
			isAirborne = false
			airTime = 0
			if completedAir >= MIN_STUNT_AIRTIME then
				fireStuntToServer("Air", completedAir, chassis.Position)
			end
		end

		-- Align vehicle pitch and roll stabilization target to surfaceNormal (NOT flat world Vector3.yAxis!)
		-- so when front wheels touch a ramp or hill, the car pitches its nose up smoothly along the ramp angle!
		local currentAngVel = chassis.AssemblyAngularVelocity
		local rightVec = chassis.CFrame.RightVector
		local upVec = chassis.CFrame.UpVector
		local alignCross = upVec:Cross(surfaceNormal)

		local stabilizePitch = math.clamp(alignCross:Dot(rightVec) * 9.5, -6.0, 6.0)
		local stabilizeRoll = math.clamp(alignCross:Dot(forwardVec) * 9.5, -6.0, 6.0)

		local desiredAngVel = Vector3.new(0, targetYawRate, 0)
			+ rightVec * stabilizePitch
			+ forwardVec * stabilizeRoll
		chassis.AssemblyAngularVelocity = currentAngVel:Lerp(desiredAngVel, math.min(1, dt * 22))

		-- Project velocity vector along the surface slope tangent (slopeForward) + controlled lateral drift slip
		local currentLateralSpeed = vel:Dot(flatRight)
		local grip = if isDrifting then DRIFT_LATERAL_GRIP else NORMAL_LATERAL_GRIP
		local nextLateralSpeed = currentLateralSpeed * math.max(0, 1 - grip * dt * 12)
		if isDrifting then
			nextLateralSpeed += smoothedSteer * currentSpeed * 0.22 * driftFactor * dt * 6
		end

		local targetVel = slopeForward.Unit * currentSpeed + flatRight * nextLateralSpeed

		-- Multi-ray ground height with smooth ramp-approach elevation
		local groundY = chassis.Position.Y - hoverHeight
		if centerHit and frontHit and rearHit then
			groundY = math.max(centerHit.Position.Y, (frontHit.Position.Y * 0.55 + rearHit.Position.Y * 0.45))
		elseif centerHit and frontHit then
			groundY = math.max(centerHit.Position.Y, frontHit.Position.Y - chassis.Size.Z * 0.38 * math.max(0, slopeForward.Y))
		elseif centerHit then
			groundY = centerHit.Position.Y
		elseif frontHit and rearHit then
			groundY = (frontHit.Position.Y + rearHit.Position.Y) * 0.5
		elseif frontHit then
			groundY = frontHit.Position.Y
		elseif rearHit then
			groundY = rearHit.Position.Y
		end

		local targetY = groundY + hoverHeight
		local springVy = math.clamp((targetY - chassis.Position.Y) * 16 - (vel.Y - targetVel.Y) * 0.35, -30, 42)
		local vy = targetVel.Y + springVy
		if slopeForward.Y > 0.04 and currentSpeed > 5 then
			vy = math.max(vy, targetVel.Y)
		end

		chassis.AssemblyLinearVelocity = Vector3.new(targetVel.X, vy, targetVel.Z)
	else
		if not isAirborne then
			isAirborne = true
			airTime = 0
		end
		airTime += dt

		-- Parabolic mid-air flight stabilization: keep roll level and follow a clean jump pitch arc without flipping upside down!
		local rightVec = chassis.CFrame.RightVector
		local lookVec = chassis.CFrame.LookVector
		local arcPitchTargetY = math.clamp(vel.Y / math.max(38, absSpeed), -0.24, 0.36)
			+ math.clamp(rawThrottle * 0.08, -0.10, 0.10)
		local airPitchErr = lookVec.Y - math.clamp(arcPitchTargetY, -0.30, 0.42)
		local airRollErr = rightVec.Y

		local pitchTorque = math.clamp(-airPitchErr * 5.0, -AIR_PITCH_TORQUE, AIR_PITCH_TORQUE)
		local rollTorque = math.clamp(airRollErr * 6.5 - rawSteer * 0.35, -AIR_ROLL_TORQUE, AIR_ROLL_TORQUE)
		local yawInput = -rawSteer * 0.85

		local airAngVel = rightVec * pitchTorque + lookVec * rollTorque + Vector3.new(0, yawInput, 0)
		chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity:Lerp(airAngVel, math.min(1, dt * 8))
	end

	-- 8. VFX, Near-Miss Checks & HUD Live Attributes
	setLocalVFX(model, isBoosting, isDrifting or (handbrakeHeld and absSpeed > 22))
	checkNearMisses(model, chassis.Position, absSpeed)

	local mph = math.round(absSpeed * 1.15)
	local ratio = math.clamp(nitroFuel / math.max(0.1, nitroMax), 0, 1)
	localPlayer:SetAttribute("VehicleSpeed", math.round(absSpeed))
	localPlayer:SetAttribute("VehicleSpeedMPH", mph)
	localPlayer:SetAttribute("SpeedMPH", mph)
	localPlayer:SetAttribute("CurrentGear", currentGear)
	localPlayer:SetAttribute("Gear", currentGear)
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
