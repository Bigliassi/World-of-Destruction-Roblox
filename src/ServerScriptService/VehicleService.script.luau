--!strict
--[[
	VehicleService.script.luau
	Server-side vehicle lifecycle, physics ownership, upgrade integration,
	damage/smoke/fire states, Mechanic Spot repairs, and city parked cars
	for World of Destruction (Leo City).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
if not sharedFolder then
	sharedFolder = Instance.new("Folder")
	sharedFolder.Name = "Shared"
	sharedFolder.Parent = ReplicatedStorage
end

local VehicleCatalog = require(sharedFolder:WaitForChild("VehicleCatalog"))

-- Optional GameConfig & Remotes modules (resilient fallback if still loading)
local GameConfig: any = nil
pcall(function()
	local mod = sharedFolder:FindFirstChild("GameConfig")
	if mod and mod:IsA("ModuleScript") then
		GameConfig = require(mod)
	end
end)

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = parent
	return re
end

local function ensureBindableEvent(parent: Instance, name: string): BindableEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local be = Instance.new("BindableEvent")
	be.Name = name
	be.Parent = parent
	return be
end

local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
local vehiclesFolder = ensureFolder(Workspace, "Vehicles")
local parkedVehiclesFolder = ensureFolder(Workspace, "ParkedVehicles")
local serverEventsFolder = ensureFolder(ServerStorage, "Events")

-- Core RemoteEvents
local VehicleEnteredRemote = ensureRemoteEvent(remotesFolder, "VehicleEntered")
local VehicleExitedRemote = ensureRemoteEvent(remotesFolder, "VehicleExited")
local SpawnVehicleRemote = ensureRemoteEvent(remotesFolder, "SpawnVehicle")
local SummonVehicleRemote = ensureRemoteEvent(remotesFolder, "SummonVehicle")
local RepairVehicleRemote = ensureRemoteEvent(remotesFolder, "RepairVehicle")
local EnterNearestVehicleRemote = ensureRemoteEvent(remotesFolder, "EnterNearestVehicle")
local ToggleHeadlightsRemote = ensureRemoteEvent(remotesFolder, "ToggleHeadlights")
local VehicleDamageRemote = ensureRemoteEvent(remotesFolder, "VehicleDamage")
local VehicleVFXRemote = ensureRemoteEvent(remotesFolder, "VehicleVFX")
local NotificationRemote = ensureRemoteEvent(remotesFolder, "Notification")
local ExplosionEffectRemote = ensureRemoteEvent(remotesFolder, "ExplosionEffect")

-- Server BindableEvents for inter-service communication
local DamageVehicleBindable = ensureBindableEvent(ServerStorage, "DamageVehicleEvent")
local SpawnPlayerVehicleBindable = ensureBindableEvent(ServerStorage, "SpawnPlayerVehicleEvent")
local RepairPlayerVehicleBindable = ensureBindableEvent(ServerStorage, "RepairPlayerVehicleEvent")
local DestructionBindable = ensureBindableEvent(ServerStorage, "DestructionEvent")
ensureBindableEvent(serverEventsFolder, "DamageVehicleEvent")
ensureBindableEvent(serverEventsFolder, "SpawnPlayerVehicleEvent")

--------------------------------------------------------------------------------
-- State & Constants
--------------------------------------------------------------------------------
local playerVehicles: { [number]: Model } = {}
local hookedVehicles: { [Model]: { RBXScriptConnection } } = {}
local lastMechanicHealAt: { [number]: number } = {}
local lastSummonAt: { [number]: number } = {}
local lastDamageAt: { [Model]: number } = {}

local MECHANIC_HEAL_RADIUS = (GameConfig and GameConfig.City and GameConfig.City.MechanicHealRadius) or 28
local MECHANIC_COOLDOWN = (GameConfig and GameConfig.City and GameConfig.City.RepairCooldown) or 4.5

-- Default Mechanic & Service bay coordinates in Leo City (aligned with WorldBuilderService 180-stud grid)
local DEFAULT_MECHANIC_SPOTS: { { Name: string, Position: Vector3 } } = {
	{ Name = "Leo Plaza Mechanic Garage", Position = Vector3.new(-52, 2, -22) },
	{ Name = "West Midtown Service Bay", Position = Vector3.new(-180, 2, 0) },
	{ Name = "North Gas & Service Bay", Position = Vector3.new(-44, 2, -360) },
}

-- Curated parked vehicle spawn spots along Leo City curbs (clear of Grand Central Ave driving lanes)
local PARKED_SPAWN_SPOTS: { { Archetype: string, CFrame: CFrame, Color: Color3? } } = {
	{
		Archetype = "Sports",
		CFrame = CFrame.new(34, 3.2, 48) * CFrame.Angles(0, math.rad(15), 0),
		Color = VehicleCatalog.PlayerPalette.ElectricBlue,
	},
	{
		Archetype = "Muscle",
		CFrame = CFrame.new(-34, 3.2, 48) * CFrame.Angles(0, math.rad(-15), 0),
		Color = VehicleCatalog.PlayerPalette.SolarOrange,
	},
	{
		Archetype = "SUV",
		CFrame = CFrame.new(76, 3.5, 42) * CFrame.Angles(0, 0, 0),
		Color = VehicleCatalog.PlayerPalette.ToxicGreen,
	},
	{
		Archetype = "Pickup",
		CFrame = CFrame.new(-76, 3.5, 42) * CFrame.Angles(0, 0, 0),
		Color = VehicleCatalog.PlayerPalette.CrimsonRed,
	},
	{
		Archetype = "Sedan",
		CFrame = CFrame.new(104, 3.2, 22) * CFrame.Angles(0, math.rad(180), 0),
		Color = nil,
	},
	{
		Archetype = "Compact",
		CFrame = CFrame.new(-104, 3.2, -22) * CFrame.Angles(0, 0, 0),
		Color = nil,
	},
	{
		Archetype = "MonsterTruck",
		CFrame = CFrame.new(-254, 5.2, 24) * CFrame.Angles(0, 0, 0),
		Color = VehicleCatalog.PlayerPalette.CyberPurple,
	},
	{
		Archetype = "Bulldozer",
		CFrame = CFrame.new(-254, 4.5, -155) * CFrame.Angles(0, 0, 0),
		Color = VehicleCatalog.PlayerPalette.GoldRush,
	},
}

--------------------------------------------------------------------------------
-- Helper Functions: Player Upgrades & Paint
--------------------------------------------------------------------------------
local PAINT_LIST: { Color3 } = {
	VehicleCatalog.PlayerPalette.CrimsonRed,
	VehicleCatalog.PlayerPalette.ElectricBlue,
	VehicleCatalog.PlayerPalette.SolarOrange,
	VehicleCatalog.PlayerPalette.ToxicGreen,
	VehicleCatalog.PlayerPalette.CyberPurple,
	VehicleCatalog.PlayerPalette.GoldRush,
	VehicleCatalog.PlayerPalette.StealthBlack,
	VehicleCatalog.PlayerPalette.PearlWhite,
}

local function getPlayerUpgradeLevel(player: Player, track: string): number
	local val = player:GetAttribute("Upgrade_" .. track) or player:GetAttribute(track .. "Level")
	local n = tonumber(val) or 1
	return math.clamp(math.floor(n), 0, 5)
end

local function getPlayerEquippedArchetype(player: Player): string
	local raw = player:GetAttribute("EquippedVehicle") or player:GetAttribute("SelectedVehicle")
	if type(raw) == "string" and raw ~= "" then
		return VehicleCatalog.ResolveArchetypeId(raw)
	end
	return "Compact"
end

local function getPlayerPaintColor(player: Player, defaultColor: Color3): Color3
	local paintIdx = tonumber(player:GetAttribute("SelectedPaint"))
	if paintIdx and paintIdx >= 1 and paintIdx <= #PAINT_LIST then
		return PAINT_LIST[math.floor(paintIdx)]
	end
	return defaultColor
end

local function unanchorModel(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
		end
	end
end

local function setModelNetworkOwner(model: Model, owner: Player?)
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis or chassis.Anchored then
		return
	end
	pcall(function()
		if owner then
			chassis:SetNetworkOwner(owner)
		else
			chassis:SetNetworkOwnershipAuto()
		end
	end)
end

--------------------------------------------------------------------------------
-- Damage, Smoke/Fire VFX & Repair Logic
--------------------------------------------------------------------------------
local function updateDamageVFX(model: Model)
	local health = tonumber(model:GetAttribute("Health")) or 100
	local maxHealth = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)
	local ratio = math.clamp(health / maxHealth, 0, 1)

	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end

	local engineAtt = chassis:FindFirstChild("EngineVFXAttachment")
	if not engineAtt then
		return
	end

	local smoke = engineAtt:FindFirstChild("DamageSmoke") :: ParticleEmitter?
	local fire = engineAtt:FindFirstChild("DamageFire") :: ParticleEmitter?

	if smoke then
		smoke.Enabled = ratio <= 0.55
		if ratio <= 0.25 then
			smoke.Rate = 45
			smoke.Color = ColorSequence.new(Color3.fromRGB(25, 25, 30))
		else
			smoke.Rate = 22
			smoke.Color = ColorSequence.new(Color3.fromRGB(95, 95, 105))
		end
	end

	if fire then
		fire.Enabled = ratio <= 0.25
	end
end

local function getDriverFromVehicle(model: Model): Player?
	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat?
	if not seat or not seat.Occupant then
		return nil
	end
	local char = seat.Occupant.Parent
	if not char then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function repairVehicle(model: Model, notifyDriver: boolean?)
	if not model or not model.Parent then
		return
	end
	local maxHealth = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or 100)
	model:SetAttribute("Health", maxHealth)
	model:SetAttribute("IsWrecked", false)
	updateDamageVFX(model)

	local driver = getDriverFromVehicle(model)
	if driver then
		driver:SetAttribute("VehicleHealth", maxHealth)
		driver:SetAttribute("VehicleMaxHealth", maxHealth)
		if notifyDriver then
			NotificationRemote:FireClient(driver, {
				Title = "MECHANIC GARAGE",
				Message = "Vehicle Fully Repaired & Tuned!",
				Category = "Success",
				Color = Color3.fromRGB(65, 240, 120),
				Duration = 2.5,
			})
		end
	end

	-- Brief green repair highlight flash
	local highlight = Instance.new("Highlight")
	highlight.Name = "RepairFlash"
	highlight.FillColor = Color3.fromRGB(60, 255, 130)
	highlight.OutlineColor = Color3.fromRGB(180, 255, 210)
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.1
	highlight.Parent = model
	task.delay(0.8, function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

-- Applies live Garage Upgrades to an existing vehicle Model
function ApplyUpgradesToVehicle(player: Player, model: Model)
	if not model or not model.Parent then
		return
	end
	local vehicleType = tostring(model:GetAttribute("VehicleType") or "Compact")
	local cfg = VehicleCatalog.GetConfig(vehicleType)

	local engineLvl = getPlayerUpgradeLevel(player, "Engine")
	local armorLvl = getPlayerUpgradeLevel(player, "Armor")
	local nitroLvl = getPlayerUpgradeLevel(player, "Nitro")
	local plowLvl = getPlayerUpgradeLevel(player, "Plow")

	-- Level 1 is baseline (0 bonus steps), levels 2..5 add strong bonuses
	local engineSteps = math.max(0, engineLvl - 1)
	local armorSteps = math.max(0, armorLvl - 1)
	local nitroSteps = math.max(0, nitroLvl - 1)
	local plowSteps = math.max(0, plowLvl - 1)

	local effectiveMaxSpeed = math.round(cfg.MaxSpeed * (1 + engineSteps * 0.08))
	local effectiveAccel = math.round(cfg.Acceleration * (1 + engineSteps * 0.10))
	local effectiveMaxHealth = math.round(cfg.MaxHealth * (1 + armorSteps * 0.15))
	local effectiveNitroCap = cfg.NitroCapacity * (1 + nitroSteps * 0.15)
	local effectiveRamMult = cfg.RamMultiplier + plowSteps * 0.30

	local prevMax = tonumber(model:GetAttribute("MaxHealth")) or cfg.MaxHealth
	local prevHealth = tonumber(model:GetAttribute("Health")) or prevMax
	local healthRatio = math.clamp(prevHealth / math.max(1, prevMax), 0.1, 1)
	local newHealth = math.round(effectiveMaxHealth * healthRatio)

	model:SetAttribute("EngineLevel", engineLvl)
	model:SetAttribute("ArmorLevel", armorLvl)
	model:SetAttribute("NitroLevel", nitroLvl)
	model:SetAttribute("PlowLevel", plowSteps)
	model:SetAttribute("MaxSpeed", effectiveMaxSpeed)
	model:SetAttribute("Acceleration", effectiveAccel)
	model:SetAttribute("MaxHealth", effectiveMaxHealth)
	model:SetAttribute("Health", newHealth)
	model:SetAttribute("NitroCapacity", effectiveNitroCap)
	model:SetAttribute("RamMultiplier", effectiveRamMult)

	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat?
	if seat then
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = cfg.TurnSpeed
	end

	-- Attach or upgrade all 5 visual 3D upgrade tracks (Engine, Armor, Nitro, Plow, Magnet)
	local magnetLvl = getPlayerUpgradeLevel(player, "Magnet")
	local magnetSteps = math.max(0, magnetLvl - 1)
	local visualPlowLevel = if cfg.HasBulldozerBlade then math.max(2, plowSteps) else plowSteps
	if VehicleCatalog.AttachVisualUpgrades then
		VehicleCatalog.AttachVisualUpgrades(model, {
			Engine = engineSteps,
			Armor = armorSteps,
			Nitro = nitroSteps,
			Plow = visualPlowLevel,
			Magnet = magnetSteps,
			AccentColor = cfg.AccentColor,
		})
	else
		VehicleCatalog.AttachRamPlow(model, visualPlowLevel, cfg.AccentColor)
	end

	local driver = getDriverFromVehicle(model)
	if driver == player then
		player:SetAttribute("VehicleMaxHealth", effectiveMaxHealth)
		player:SetAttribute("VehicleHealth", newHealth)
	end
end

local function applyDamageToVehicle(model: Model, amount: number, attacker: Player?)
	if not model or not model.Parent then
		return
	end
	if model:GetAttribute("IsWrecked") == true then
		return
	end

	local now = os.clock()
	if lastDamageAt[model] and now - lastDamageAt[model] < 0.08 then
		return
	end
	lastDamageAt[model] = now

	local armorLvl = tonumber(model:GetAttribute("ArmorLevel")) or 1
	local damageReduction = math.clamp(1.0 - (armorLvl - 1) * 0.08, 0.55, 1.0)
	local finalDamage = math.max(1, math.round(amount * damageReduction))

	local currentHealth = tonumber(model:GetAttribute("Health")) or 100
	local maxHealth = tonumber(model:GetAttribute("MaxHealth")) or 100
	local newHealth = math.max(0, currentHealth - finalDamage)
	model:SetAttribute("Health", newHealth)

	updateDamageVFX(model)

	local driver = getDriverFromVehicle(model)
	if driver then
		driver:SetAttribute("VehicleHealth", newHealth)
		driver:SetAttribute("VehicleMaxHealth", maxHealth)
	end

	if newHealth <= 0 then
		model:SetAttribute("IsWrecked", true)
		local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
		local pos = if chassis then chassis.Position else Vector3.new(0, 5, 0)

		ExplosionEffectRemote:FireAllClients(pos, 18)

		if attacker then
			local coinReward = tonumber(model:GetAttribute("CoinReward")) or 25
			DestructionBindable:Fire(attacker, {
				Type = tostring(model:GetAttribute("DisplayName") or model.Name),
				CashReward = coinReward * 2,
				Position = pos,
				IsExplosion = true,
				Heat = 15,
			})
		end

		-- Eject occupant safely
		local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat?
		if seat and seat.Occupant then
			local hum = seat.Occupant
			hum.Sit = false
			local hrp = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				hrp.AssemblyLinearVelocity = Vector3.new(0, 42, 0)
			end
		end

		if chassis then
			chassis.AssemblyLinearVelocity = Vector3.new(math.random(-18, 18), 32, math.random(-18, 18))
		end

		-- Auto-restore personal vehicle after 4 seconds
		local ownerId = tonumber(model:GetAttribute("OwnerUserId")) or 0
		if ownerId > 0 then
			task.delay(4.0, function()
				if model.Parent then
					repairVehicle(model, true)
				end
			end)
		else
			task.delay(8.0, function()
				if model.Parent then
					repairVehicle(model, false)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Seated Driver Head-Clipping Fix & Cabin Silhouette Helper
--------------------------------------------------------------------------------
local function ensureCabinDriverSilhouette(model: Model)
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

local function shouldHideSeatedCharacterPart(inst: Instance, character: Model): boolean
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

local function setSeatedCharacterHidden(character: Model?, vehicleModel: Model?, hide: boolean)
	if vehicleModel and hide then
		ensureCabinDriverSilhouette(vehicleModel)
	end
	if not character then
		return
	end
	for _, desc in ipairs(character:GetDescendants()) do
		if shouldHideSeatedCharacterPart(desc, character) then
			if desc:IsA("BasePart") then
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

--------------------------------------------------------------------------------
-- Hook Vehicle Seat Occupancy & Prompts
--------------------------------------------------------------------------------
local function hookVehicleModel(model: Model)
	if hookedVehicles[model] then
		return
	end
	local conns: { RBXScriptConnection } = {}
	hookedVehicles[model] = conns

	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat?
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis") :: BasePart?
	if not seat or not chassis then
		return
	end

	unanchorModel(model)
	ensureCabinDriverSilhouette(model)

	local prompt = seat:FindFirstChild("EnterVehiclePrompt") :: ProximityPrompt?
	if prompt then
		table.insert(
			conns,
			prompt.Triggered:Connect(function(player: Player)
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 then
					return
				end
				if seat.Occupant and seat.Occupant ~= hum then
					-- Hijack if occupied by NPC traffic
					local occPlayer = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
					if not occPlayer then
						seat.Occupant.Sit = false
					else
						return
					end
				end
				seat:Sit(hum)
			end)
		)
	end

	local currentDriver: Player? = nil
	local currentDriverChar: Model? = nil
	local charDescendantConn: RBXScriptConnection? = nil

	table.insert(
		conns,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seat.Occupant
			if occupant then
				local char = occupant.Parent :: Model?
				local player = if char then Players:GetPlayerFromCharacter(char) else nil
				if char then
					currentDriverChar = char
					setSeatedCharacterHidden(char, model, true)
					if charDescendantConn then
						charDescendantConn:Disconnect()
					end
					charDescendantConn = char.DescendantAdded:Connect(function()
						if seat.Occupant == occupant then
							task.defer(setSeatedCharacterHidden, char, model, true)
						end
					end)
				end
				if player then
					currentDriver = player
					if prompt then
						prompt.Enabled = false
					end

					unanchorModel(model)
					setModelNetworkOwner(model, player)

					-- If this is the player's vehicle or unclaimed, apply their Garage Upgrades
					local ownerId = tonumber(model:GetAttribute("OwnerUserId")) or 0
					if ownerId == 0 or ownerId == player.UserId then
						model:SetAttribute("OwnerUserId", player.UserId)
						playerVehicles[player.UserId] = model
						ApplyUpgradesToVehicle(player, model)
					end

					local vType = tostring(model:GetAttribute("VehicleType") or model.Name)
					local vName = tostring(model:GetAttribute("DisplayName") or vType)
					local hp = tonumber(model:GetAttribute("Health")) or 100
					local maxHp = tonumber(model:GetAttribute("MaxHealth")) or 100
					local topSpeed = tonumber(model:GetAttribute("MaxSpeed")) or 64
					local nitroCap = tonumber(model:GetAttribute("NitroCapacity")) or 4.0

					player:SetAttribute("InVehicle", true)
					player:SetAttribute("CurrentVehicleType", vType)
					player:SetAttribute("CurrentVehicleName", vName)
					player:SetAttribute("VehicleHealth", hp)
					player:SetAttribute("VehicleMaxHealth", maxHp)

					VehicleEnteredRemote:FireClient(player, {
						VehicleClass = vType,
						VehicleName = vName,
						Health = hp,
						MaxHealth = maxHp,
						TopSpeed = topSpeed,
						NitroDuration = nitroCap,
						NitroCooldown = 4.0,
						Model = model,
					})
				end
			else
				if charDescendantConn then
					charDescendantConn:Disconnect()
					charDescendantConn = nil
				end
				if currentDriverChar and currentDriverChar.Parent then
					setSeatedCharacterHidden(currentDriverChar, model, false)
				end
				currentDriverChar = nil

				if prompt then
					prompt.Enabled = true
				end
				setModelNetworkOwner(model, nil)

				if currentDriver and currentDriver.Parent then
					currentDriver:SetAttribute("InVehicle", false)
					VehicleExitedRemote:FireClient(currentDriver, model)
				end
				currentDriver = nil
			end
		end)
	)

	table.insert(
		conns,
		model:GetAttributeChangedSignal("Health"):Connect(function()
			updateDamageVFX(model)
		end)
	)

	table.insert(
		conns,
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				if charDescendantConn then
					charDescendantConn:Disconnect()
					charDescendantConn = nil
				end
				if currentDriverChar and currentDriverChar.Parent then
					setSeatedCharacterHidden(currentDriverChar, model, false)
					currentDriverChar = nil
				end
				local list = hookedVehicles[model]
				if list then
					for _, c in ipairs(list) do
						c:Disconnect()
					end
					hookedVehicles[model] = nil
				end
				lastDamageAt[model] = nil
			end
		end)
	)
end

--------------------------------------------------------------------------------
-- Spawning Player Vehicles & Parked City Fleet
--------------------------------------------------------------------------------
function SpawnPlayerVehicle(
	player: Player,
	requestedType: string?,
	spawnCFrame: CFrame?,
	autoSit: boolean?
): Model?
	if not player or not player.Parent then
		return nil
	end

	local archetypeId = if requestedType and requestedType ~= ""
		then VehicleCatalog.ResolveArchetypeId(requestedType)
		else getPlayerEquippedArchetype(player)

	local cfg = VehicleCatalog.GetConfig(archetypeId)
	local paintColor = getPlayerPaintColor(player, cfg.PrimaryColor)

	-- Compute spawn CFrame near player character or open Grand Central Avenue default
	local targetCF = spawnCFrame
	if not targetCF then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local look = hrp.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude < 0.05 then
				flatLook = Vector3.new(0, 0, -1)
			else
				flatLook = flatLook.Unit
			end
			-- If player is standing in Leo Plaza near SpawnLocation / fountain, snap onto open Grand Central Avenue
			local candidatePos = if autoSit
				then hrp.Position
				else hrp.Position + flatLook * 14
			if math.abs(candidatePos.X) < 16 and candidatePos.Z > -28 and candidatePos.Z < 32 and not autoSit then
				targetCF = CFrame.new(0, cfg.HoverHeight + 1.2, -10)
			else
				local spawnPos = Vector3.new(candidatePos.X, math.max(hrp.Position.Y, 1.5) + cfg.HoverHeight + 1.0, candidatePos.Z)
				targetCF = CFrame.lookAt(spawnPos, spawnPos + flatLook)
			end
		else
			targetCF = CFrame.new(0, cfg.HoverHeight + 1.2, -10)
		end
	end

	-- Remove old personal vehicle for this player
	local existing = playerVehicles[player.UserId]
	if existing and existing.Parent then
		local seat = existing:FindFirstChild("DriveSeat") :: VehicleSeat?
		if seat and seat.Occupant then
			seat.Occupant.Sit = false
		end
		existing:Destroy()
	end

	local engineLvl = getPlayerUpgradeLevel(player, "Engine")
	local armorLvl = getPlayerUpgradeLevel(player, "Armor")
	local nitroLvl = getPlayerUpgradeLevel(player, "Nitro")
	local plowLvl = getPlayerUpgradeLevel(player, "Plow")

	local vehicle = VehicleCatalog.BuildVehicle(archetypeId, {
		PrimaryColor = paintColor,
		OwnerUserId = player.UserId,
		EngineLevel = math.max(0, engineLvl - 1),
		ArmorLevel = math.max(0, armorLvl - 1),
		NitroLevel = math.max(0, nitroLvl - 1),
		PlowLevel = math.max(0, plowLvl - 1),
		CFrame = targetCF,
	})
	vehicle.Name = player.Name .. "_" .. archetypeId
	vehicle.Parent = vehiclesFolder

	playerVehicles[player.UserId] = vehicle
	hookVehicleModel(vehicle)
	ApplyUpgradesToVehicle(player, vehicle)
	setModelNetworkOwner(vehicle, player)

	if autoSit then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = vehicle:FindFirstChild("DriveSeat") :: VehicleSeat?
		if hum and hum.Health > 0 and seat then
			task.defer(function()
				if seat.Parent and hum.Parent then
					seat:Sit(hum)
				end
			end)
		end
	end

	return vehicle
end

local function spawnParkedCityVehicles()
	for idx, spec in ipairs(PARKED_SPAWN_SPOTS) do
		local color = spec.Color or VehicleCatalog.GetRandomTrafficColor()
		local model = VehicleCatalog.BuildVehicle(spec.Archetype, {
			PrimaryColor = color,
			IsTraffic = false,
			CFrame = spec.CFrame,
		})
		model.Name = string.format("Parked_%s_%d", spec.Archetype, idx)
		model.Parent = parkedVehiclesFolder
		hookVehicleModel(model)
	end
end

--------------------------------------------------------------------------------
-- Remote & Bindable Listeners
--------------------------------------------------------------------------------
SpawnVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleType: any, autoSit: any)
	local now = os.clock()
	if lastSummonAt[player.UserId] and now - lastSummonAt[player.UserId] < 1.0 then
		return
	end
	lastSummonAt[player.UserId] = now

	local reqType = if type(vehicleType) == "string" then vehicleType else nil
	local shouldSit = if type(autoSit) == "boolean" then autoSit else true
	SpawnPlayerVehicle(player, reqType, nil, shouldSit)
end)

SummonVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleType: any, autoSit: any)
	local now = os.clock()
	if lastSummonAt[player.UserId] and now - lastSummonAt[player.UserId] < 1.0 then
		return
	end
	lastSummonAt[player.UserId] = now

	local reqType = if type(vehicleType) == "string" then vehicleType else nil
	local shouldSit = if type(autoSit) == "boolean" then autoSit else true
	local model = SpawnPlayerVehicle(player, reqType, nil, shouldSit)
	if model then
		NotificationRemote:FireClient(player, {
			Title = "VEHICLE DELIVERED",
			Message = string.format("%s summoned!", tostring(model:GetAttribute("DisplayName") or model.Name)),
			Category = "Info",
			Color = Color3.fromRGB(80, 195, 255),
			Duration = 2.0,
		})
	end
end)

RepairVehicleRemote.OnServerEvent:Connect(function(player: Player)
	local vehicle = playerVehicles[player.UserId]
	if vehicle and vehicle.Parent then
		repairVehicle(vehicle, true)
	end
end)

EnterNearestVehicleRemote.OnServerEvent:Connect(function(player: Player, targetModel: any)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 or hum.Sit then
		return
	end

	local bestSeat: VehicleSeat? = nil
	local bestDist = 24

	if typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
		local s = targetModel:FindFirstChild("DriveSeat") :: VehicleSeat?
		if s and (s.Position - hrp.Position).Magnitude <= 26 then
			bestSeat = s
		end
	end

	if not bestSeat then
		for _, veh in ipairs(CollectionService:GetTagged("Vehicle")) do
			if veh:IsA("Model") then
				local s = veh:FindFirstChild("DriveSeat") :: VehicleSeat?
				if s then
					local d = (s.Position - hrp.Position).Magnitude
					if d < bestDist then
						bestDist = d
						bestSeat = s
					end
				end
			end
		end
	end

	if bestSeat then
		if bestSeat.Occupant and bestSeat.Occupant ~= hum then
			local occPlayer = Players:GetPlayerFromCharacter(bestSeat.Occupant.Parent)
			if not occPlayer then
				bestSeat.Occupant.Sit = false
			else
				return
			end
		end
		bestSeat:Sit(hum)
	end
end)

ToggleHeadlightsRemote.OnServerEvent:Connect(function(player: Player, stateOverride: any)
	local vehicle = playerVehicles[player.UserId]
	if not vehicle or not vehicle.Parent then
		return
	end
	local current = vehicle:GetAttribute("HeadlightsOn") == true
	local nextState = if type(stateOverride) == "boolean" then stateOverride else not current
	vehicle:SetAttribute("HeadlightsOn", nextState)

	for _, partName in ipairs({ "HeadlightL", "HeadlightR" }) do
		local hl = vehicle:FindFirstChild(partName) :: BasePart?
		if hl then
			hl.Material = if nextState then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local spot = hl:FindFirstChildOfClass("SpotLight")
			if spot then
				spot.Enabled = nextState
			end
		end
	end
end)

VehicleDamageRemote.OnServerEvent:Connect(function(player: Player, amount: any)
	local vehicle = playerVehicles[player.UserId]
	if not vehicle or not vehicle.Parent then
		return
	end
	local dmg = math.clamp(tonumber(amount) or 5, 1, 80)
	applyDamageToVehicle(vehicle, dmg, nil)
end)

VehicleVFXRemote.OnServerEvent:Connect(function(player: Player, vfxKind: any, enabled: any)
	local vehicle = playerVehicles[player.UserId]
	if not vehicle or not vehicle.Parent then
		return
	end
	local chassis = vehicle.PrimaryPart or vehicle:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end
	local isOn = enabled == true
	local kind = tostring(vfxKind or "")

	if kind == "Nitro" then
		for _, attName in ipairs({ "ExhaustAttachmentL", "ExhaustAttachmentR" }) do
			local att = chassis:FindFirstChild(attName)
			local emitter = att and att:FindFirstChild("NitroFlame") :: ParticleEmitter?
			if emitter then
				emitter.Enabled = isOn
			end
		end
	elseif kind == "Drift" then
		for _, attName in ipairs({ "DriftAttachmentL", "DriftAttachmentR" }) do
			local att = chassis:FindFirstChild(attName)
			local emitter = att and att:FindFirstChild("DriftSmoke") :: ParticleEmitter?
			if emitter then
				emitter.Enabled = isOn
			end
		end
		for _, trailName in ipairs({ "SkidTrailL", "SkidTrailR" }) do
			local trail = chassis:FindFirstChild(trailName) :: Trail?
			if trail then
				trail.Enabled = isOn
			end
		end
	end
end)

DamageVehicleBindable.Event:Connect(function(vehicle: Model, amount: number, attacker: Player?)
	if typeof(vehicle) == "Instance" and vehicle:IsA("Model") then
		applyDamageToVehicle(vehicle, tonumber(amount) or 10, attacker)
	end
end)

SpawnPlayerVehicleBindable.Event:Connect(function(player: Player, vehicleType: string?, spawnCF: CFrame?, autoSit: boolean?)
	if typeof(player) == "Instance" and player:IsA("Player") then
		SpawnPlayerVehicle(player, vehicleType, spawnCF, autoSit)
	end
end)

RepairPlayerVehicleBindable.Event:Connect(function(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		local veh = playerVehicles[player.UserId]
		if veh then
			repairVehicle(veh, true)
		end
	end
end)

--------------------------------------------------------------------------------
-- Player Lifecycle & Garage Attribute Sync
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.wait(0.25)
		if not player.Parent or player.Character ~= character then
			return
		end
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local spawnCF: CFrame
			if math.abs(hrp.Position.X) < 32 and math.abs(hrp.Position.Z - 22) < 36 then
				spawnCF = CFrame.new(0, 3.2, 22)
			else
				local look = hrp.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude < 0.05 then
					flatLook = Vector3.new(0, 0, -1)
				else
					flatLook = flatLook.Unit
				end
				local spawnPos = Vector3.new(hrp.Position.X, 3.2, hrp.Position.Z)
				spawnCF = CFrame.lookAt(spawnPos, spawnPos + flatLook)
			end
			-- Auto-seat the player in their vehicle on spawn so pressing [W] immediately drives!
			local veh = SpawnPlayerVehicle(player, nil, spawnCF, true)
			if veh then
				setModelNetworkOwner(veh, player)
			end
		end
	end)

	-- Live-update vehicle stats/plow whenever player upgrades change
	for _, attr in ipairs({ "Upgrade_Engine", "Upgrade_Armor", "Upgrade_Nitro", "Upgrade_Plow", "EngineLevel", "ArmorLevel", "NitroLevel", "PlowLevel" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			local veh = playerVehicles[player.UserId]
			if veh and veh.Parent then
				ApplyUpgradesToVehicle(player, veh)
			end
		end)
	end

	-- Respawn/swap vehicle when EquippedVehicle changes in Speed Shop and auto-sit the player!
	player:GetAttributeChangedSignal("EquippedVehicle"):Connect(function()
		local newType = getPlayerEquippedArchetype(player)
		local currentVeh = playerVehicles[player.UserId]
		if currentVeh and currentVeh.Parent then
			local currentType = tostring(currentVeh:GetAttribute("VehicleType") or "")
			if currentType ~= newType then
				local chassis = currentVeh.PrimaryPart
				local cf = if chassis then chassis.CFrame else nil
				SpawnPlayerVehicle(player, newType, cf, true)
			end
		else
			SpawnPlayerVehicle(player, newType, nil, true)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local veh = playerVehicles[player.UserId]
	if veh and veh.Parent then
		veh:Destroy()
	end
	playerVehicles[player.UserId] = nil
	lastMechanicHealAt[player.UserId] = nil
	lastSummonAt[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Hook any vehicles added dynamically by other services
CollectionService:GetInstanceAddedSignal("Vehicle"):Connect(function(inst: Instance)
	if inst:IsA("Model") then
		task.defer(hookVehicleModel, inst)
	end
end)

spawnParkedCityVehicles()

--------------------------------------------------------------------------------
-- Heartbeat: Mechanic Spot Auto-Repair Proximity Check
--------------------------------------------------------------------------------
local mechanicCheckAccumulator = 0

RunService.Heartbeat:Connect(function(dt: number)
	mechanicCheckAccumulator += dt
	if mechanicCheckAccumulator < 0.35 then
		return
	end
	mechanicCheckAccumulator = 0

	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local veh = playerVehicles[player.UserId]
		if not veh or not veh.Parent then
			continue
		end
		local chassis = veh.PrimaryPart
		if not chassis then
			continue
		end

		local hp = tonumber(veh:GetAttribute("Health")) or 100
		local maxHp = tonumber(veh:GetAttribute("MaxHealth")) or 100
		if hp >= maxHp and veh:GetAttribute("IsWrecked") ~= true then
			continue
		end

		if lastMechanicHealAt[player.UserId] and now - lastMechanicHealAt[player.UserId] < MECHANIC_COOLDOWN then
			continue
		end

		local pos = chassis.Position
		local nearMechanic = false

		for _, spot in ipairs(DEFAULT_MECHANIC_SPOTS) do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(spot.Position.X, 0, spot.Position.Z)).Magnitude <= MECHANIC_HEAL_RADIUS then
				nearMechanic = true
				break
			end
		end

		if not nearMechanic then
			for _, tagged in ipairs(CollectionService:GetTagged("MechanicSpot")) do
				local spotPos: Vector3? = nil
				if tagged:IsA("BasePart") then
					spotPos = tagged.Position
				elseif tagged:IsA("Model") and tagged.PrimaryPart then
					spotPos = tagged.PrimaryPart.Position
				end
				if spotPos and (pos - spotPos).Magnitude <= MECHANIC_HEAL_RADIUS then
					nearMechanic = true
					break
				end
			end
		end

		if nearMechanic then
			lastMechanicHealAt[player.UserId] = now
			repairVehicle(veh, true)
		end
	end
end)
