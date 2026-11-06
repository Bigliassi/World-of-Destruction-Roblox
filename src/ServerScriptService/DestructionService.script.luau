--!strict
-- DestructionService.script.luau
-- High-impact Roblox physics destruction system for Leo City:
-- - Monitors collisions between vehicles/players/explosions and "Destructible" tagged props.
-- - Calculates impact speed & vehicle ram multiplier.
-- - Unanchors parts, applies dramatic impulse + angular velocity spin, and spawns VFX
--   (water geysers for FireHydrants, sparks for StreetLights/TrafficLights, chain-reaction
--   explosions for GasPumps & ExplosiveBarrels).
-- - Fires ServerStorage.ServerEvents.DestructionOccurred and ReplicatedStorage.Events.DestructionOccurred.
-- - Automatically respawns destroyed props after 45 seconds when players are far away.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

--------------------------------------------------------------------------------
-- EVENTS SETUP
--------------------------------------------------------------------------------
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ServerStorage
end

local DestructionBindable = ServerEvents:FindFirstChild("DestructionOccurred") :: BindableEvent?
if not DestructionBindable then
	DestructionBindable = Instance.new("BindableEvent")
	DestructionBindable.Name = "DestructionOccurred"
	DestructionBindable.Parent = ServerEvents
end

local RepEvents = ReplicatedStorage:FindFirstChild("Remotes")
if not RepEvents then
	RepEvents = Instance.new("Folder")
	RepEvents.Name = "Remotes"
	RepEvents.Parent = ReplicatedStorage
end

local DestructionRemote = RepEvents:FindFirstChild("DestructionOccurred") :: RemoteEvent?
if not DestructionRemote then
	DestructionRemote = Instance.new("RemoteEvent")
	DestructionRemote.Name = "DestructionOccurred"
	DestructionRemote.Parent = RepEvents
end

--------------------------------------------------------------------------------
-- CONSTANTS & STATE
--------------------------------------------------------------------------------
local RESPAWN_DELAY = 45.0
local SAFE_PLAYER_RESPAWN_DIST = 65.0
local EXPLOSION_BLAST_RADIUS = 38.0

type RespawnEntry = {
	template: Instance,
	parent: Instance,
	originCF: CFrame,
	destroyedAt: number,
	liveInstance: Instance,
}

local respawnQueue: { RespawnEntry } = {}
local boundInstances: { [Instance]: boolean } = {}

--------------------------------------------------------------------------------
-- DRIVER & VEHICLE RESOLUTION
--------------------------------------------------------------------------------
local function resolveAttacker(hitPart: BasePart): (Player?, number, Vector3)
	local vel = hitPart.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local ramMultiplier = 1.0
	local attacker: Player? = nil

	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model then
		-- Check if it's a player character
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			attacker = plr
		end

		-- Check if it's a vehicle with a Driver/VehicleSeat or Owner attribute
		local vehicleModel = model
		while vehicleModel.Parent and vehicleModel.Parent:IsA("Model") and vehicleModel.Parent ~= Workspace do
			vehicleModel = vehicleModel.Parent :: Model
		end

		local ramAttr = (vehicleModel:GetAttribute("RamMultiplier") :: number?)
			or (vehicleModel:GetAttribute("RamPower") :: number?)
			or (model:GetAttribute("RamMultiplier") :: number?)
		if ramAttr then
			ramMultiplier = ramAttr
		end

		local ownerUserId = (vehicleModel:GetAttribute("OwnerUserId") :: number?)
			or (vehicleModel:GetAttribute("DriverUserId") :: number?)
		if ownerUserId and not attacker then
			attacker = Players:GetPlayerByUserId(ownerUserId)
		end

		local ownerName = (vehicleModel:GetAttribute("Owner") :: string?)
			or (vehicleModel:GetAttribute("DriverName") :: string?)
		if ownerName and not attacker then
			attacker = Players:FindFirstChild(ownerName) :: Player?
		end

		if not attacker then
			local seat = vehicleModel:FindFirstChildWhichIsA("VehicleSeat", true) or vehicleModel:FindFirstChildWhichIsA("Seat", true)
			if seat and seat.Occupant then
				local char = seat.Occupant.Parent
				if char then
					attacker = Players:GetPlayerFromCharacter(char)
				end
			end
		end
	end

	-- Fallback: nearest player within 32 studs if hit by an unowned physics assembly
	if not attacker and speed > 10 then
		local bestDist = 32
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - hitPart.Position).Magnitude
				if d < bestDist then
					bestDist = d
					attacker = plr
				end
			end
		end
	end

	return attacker, ramMultiplier, vel
end

--------------------------------------------------------------------------------
-- SPECIAL PROP VFX (GEYSERS, SPARKS, DEBRIS, EXPLOSIONS)
--------------------------------------------------------------------------------
local function spawnWaterGeyser(pos: Vector3)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "HydrantWaterGeyser"
	emitterPart.Size = Vector3.new(1, 1, 1)
	emitterPart.Position = pos + Vector3.new(0, 0.5, 0)
	emitterPart.Anchored = true
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.Parent = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(165, 225, 255), Color3.fromRGB(240, 250, 255))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.6, 2.2),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(1.1, 1.6)
	pe.Rate = 85
	pe.Speed = NumberRange.new(34, 46)
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Acceleration = Vector3.new(0, -45, 0)
	pe.Parent = emitterPart

	Debris:AddItem(emitterPart, 8.0)
end

local function spawnElectricSparks(part: BasePart)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "ElectricSparks"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 230, 95), Color3.fromRGB(255, 120, 20))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.45, 0)
	pe.Lifetime = NumberRange.new(0.25, 0.55)
	pe.Rate = 60
	pe.Speed = NumberRange.new(16, 28)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -35, 0)
	pe.Parent = part

	task.delay(2.2, function()
		if pe and pe.Parent then
			pe.Enabled = false
		end
	end)
end

local destroyProp: (inst: Instance, attacker: Player?, hitVel: Vector3, isFromExplosion: boolean) -> ()

local function triggerChainExplosion(pos: Vector3, attacker: Player?)
	local exp = Instance.new("Explosion")
	exp.BlastRadius = EXPLOSION_BLAST_RADIUS
	exp.BlastPressure = 0 -- Custom impulse handling for predictable arcade feel
	exp.DestroyJointRadiusPercent = 0
	exp.Position = pos
	exp.Parent = Workspace

	-- Flash light burst
	local flashPart = Instance.new("Part")
	flashPart.Size = Vector3.new(1, 1, 1)
	flashPart.Position = pos
	flashPart.Anchored = true
	flashPart.CanCollide = false
	flashPart.Transparency = 1
	flashPart.Parent = Workspace

	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 150, 40)
	pl.Brightness = 6
	pl.Range = 55
	pl.Parent = flashPart
	Debris:AddItem(flashPart, 0.35)

	-- Blast nearby destructibles and vehicles in radius
	task.delay(0.08, function()
		for _, prop in ipairs(CollectionService:GetTagged("Destructible")) do
			if prop:GetAttribute("Destroyed") ~= true then
				local pPos: Vector3? = nil
				if prop:IsA("Model") and prop.PrimaryPart then
					pPos = prop.PrimaryPart.Position
				elseif prop:IsA("BasePart") then
					pPos = prop.Position
				end
				if pPos then
					local delta = pPos - pos
					local dist = delta.Magnitude
					if dist <= EXPLOSION_BLAST_RADIUS then
						local dir = if dist > 0.1 then delta.Unit else Vector3.new(0, 1, 0)
						destroyProp(prop, attacker, dir * 85 + Vector3.new(0, 35, 0), true)
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- CORE DESTRUCTION HANDLER
--------------------------------------------------------------------------------
destroyProp = function(inst: Instance, attacker: Player?, hitVel: Vector3, isFromExplosion: boolean)
	if inst:GetAttribute("Destroyed") == true then
		return
	end
	inst:SetAttribute("Destroyed", true)

	local primary: BasePart? = if inst:IsA("Model") then inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") else (inst :: BasePart)
	if not primary then
		return
	end

	local propPos = primary.Position
	local originCF = (inst:GetAttribute("OriginCFrame") :: CFrame?) or primary.CFrame
	local propType = (inst:GetAttribute("PropType") :: string?) or inst.Name
	local cashValue = (inst:GetAttribute("CashValue") :: number?) or 20
	local chaosPoints = (inst:GetAttribute("ChaosPoints") :: number?) or 15
	local isExplosive = (inst:GetAttribute("Explosive") :: boolean?) == true

	-- Clone clean template for respawning before unanchoring/modifying
	local cleanClone = inst:Clone()
	cleanClone:SetAttribute("Destroyed", false)
	if inst.Parent then
		table.insert(respawnQueue, {
			template = cleanClone,
			parent = inst.Parent,
			originCF = originCF,
			destroyedAt = os.clock(),
			liveInstance = inst,
		})
	end

	-- Unanchor and apply dramatic impulse + angular spin
	local launchDir = if hitVel.Magnitude > 1 then hitVel.Unit else Vector3.new(0, 1, 0)
	local launchSpeed = math.clamp(hitVel.Magnitude * 1.15, 32, 110)

	local parts: { BasePart } = {}
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	elseif inst:IsA("BasePart") then
		table.insert(parts, inst)
	end

	for _, p in ipairs(parts) do
		p.Anchored = false
		p.CanCollide = true
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.65 + 0.25, math.random() - 0.5) * 18
		p.AssemblyLinearVelocity = launchDir * launchSpeed + Vector3.new(0, 22, 0) + spread
		p.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 18,
			(math.random() - 0.5) * 18,
			(math.random() - 0.5) * 18
		)
	end

	-- Special Prop Effects
	if propType == "FireHydrant" then
		spawnWaterGeyser(originCF.Position)
	elseif propType == "StreetLight" or propType == "TrafficLight" or propType == "Billboard" then
		spawnElectricSparks(primary)
	end

	if isExplosive then
		triggerChainExplosion(propPos, attacker)
	end

	-- Broadcast DestructionOccurred to Economy/Combo systems and clients
	local payload = {
		player = attacker,
		Player = attacker,
		propType = propType,
		Type = propType,
		cashEarned = cashValue,
		CashReward = cashValue,
		chaosPoints = chaosPoints,
		position = propPos,
		Position = propPos,
		isExplosion = isExplosive or isFromExplosion,
		IsExplosion = isExplosive or isFromExplosion,
	}
	if DestructionBindable then
		DestructionBindable:Fire(payload)
	end
	local rootDestBindable = ServerStorage:FindFirstChild("DestructionEvent")
	if rootDestBindable and rootDestBindable:IsA("BindableEvent") and attacker then
		rootDestBindable:Fire(attacker, payload, cashValue, propPos)
	end
	if DestructionRemote then
		if attacker then
			DestructionRemote:FireClient(attacker, payload)
		else
			DestructionRemote:FireAllClients(payload)
		end
	end

	-- Fade out broken physics parts after 6 seconds to keep framerate fast
	task.delay(6.0, function()
		if inst and inst.Parent then
			for _, p in ipairs(parts) do
				if p and p.Parent then
					p.Transparency = 1
					p.CanCollide = false
					p.Anchored = true
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- COLLISION BINDING
--------------------------------------------------------------------------------
local function bindDestructible(inst: Instance)
	if boundInstances[inst] then
		return
	end
	boundInstances[inst] = true

	local function onTouched(otherPart: BasePart)
		if inst:GetAttribute("Destroyed") == true then
			return
		end
		if otherPart.Anchored then
			return
		end
		if CollectionService:HasTag(otherPart, "Destructible") then
			return
		end

		local attacker, ramMultiplier, hitVel = resolveAttacker(otherPart)
		local effectiveSpeed = hitVel.Magnitude * ramMultiplier
		local threshold = (inst:GetAttribute("BreakThreshold") :: number?) or 18

		if effectiveSpeed >= threshold then
			destroyProp(inst, attacker, hitVel, false)
		end
	end

	if inst:IsA("BasePart") then
		inst.Touched:Connect(onTouched)
	elseif inst:IsA("Model") then
		local pri = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
		if pri then
			pri.Touched:Connect(onTouched)
		end
	end
end

for _, inst in ipairs(CollectionService:GetTagged("Destructible")) do
	bindDestructible(inst)
end
CollectionService:GetInstanceAddedSignal("Destructible"):Connect(bindDestructible)

--------------------------------------------------------------------------------
-- AUTOMATIC PROP RESPAWNING LOOP (AFTER 45s WHEN PLAYERS ARE FAR AWAY)
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(3.0)
		local now = os.clock()
		for i = #respawnQueue, 1, -1 do
			local entry = respawnQueue[i]
			if now - entry.destroyedAt >= RESPAWN_DELAY then
				local farEnough = true
				for _, plr in ipairs(Players:GetPlayers()) do
					local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and (root.Position - entry.originCF.Position).Magnitude < SAFE_PLAYER_RESPAWN_DIST then
						farEnough = false
						break
					end
				end

				if farEnough then
					table.remove(respawnQueue, i)
					if entry.liveInstance and entry.liveInstance.Parent then
						boundInstances[entry.liveInstance] = nil
						entry.liveInstance:Destroy()
					end
					if entry.parent and entry.parent.Parent then
						local restored = entry.template
						if restored:IsA("Model") and restored.PrimaryPart then
							restored:PivotTo(entry.originCF)
						elseif restored:IsA("BasePart") then
							restored.CFrame = entry.originCF
						end
						restored.Parent = entry.parent
						CollectionService:AddTag(restored, "Destructible")
						bindDestructible(restored)
					end
				end
			end
		end
	end
end)

print("[DestructionService] Ready and monitoring destructible city props.")
