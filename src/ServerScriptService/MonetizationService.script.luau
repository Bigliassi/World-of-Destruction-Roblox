--!strict
--[[
	MonetizationService.script.luau
	World of Destruction (Roblox) — Version 1.0
	
	Complete Roblox MarketplaceService Integration for GamePasses & Developer Products,
	plus Studio Sandbox Purchase Mode:
	- GamePasses (Permanent Perks):
	  1. VIP2xCash            — 2x Cash & XP permanently
	  2. UnlimitedNitro       — Infinite Nitro boost + blue plasma flames
	  3. GoldenBulldozerPass  — Unlocks Special Golden Apex Bulldozer
	  4. HeatShieldScanner    — 50% slower Police Heat buildup + faster evade
	  5. MegaMagnetPass       — 2x Combo Timer window & +50% Cash Magnet
	- Developer Products (Repeatable Consumables):
	  1. CashPackStarter           — +$10,000 Cash
	  2. CashPackPro               — +$50,000 Cash
	  3. CashPackTycoon            — +$250,000 Cash
	  4. BribePoliceChief          — Instantly clear 5-Star Heat
	  5. InstantMaxRepairAndBoost  — Instant full repair + 60s Overdrive 2x Multiplier
	- Studio Sandbox Purchase Mode:
	  When running inside Roblox Studio (`RunService:IsStudio()`) or when placeholder
	  Asset IDs (`0`) are configured, players can test-grant any GamePass or DevProduct
	  for free via the "Store / VIP [M]" UI or remote so monetization can be tested
	  immediately before publishing Robux Asset IDs.
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

--------------------------------------------------------------------------------
-- GamePass & Developer Product Catalog
--------------------------------------------------------------------------------
export type GamePassEntry = {
	Key: string,
	PassId: number,
	Title: string,
	PriceRobux: number,
	Description: string,
	IconText: string,
	AccentColor: { number },
}

export type DevProductEntry = {
	Key: string,
	ProductId: number,
	Title: string,
	PriceRobux: number,
	Description: string,
	IconText: string,
	AccentColor: { number },
}

local GAMEPASS_CATALOG: { GamePassEntry } = {
	{
		Key = "VIP2xCash",
		PassId = 0, -- Replace 0 with live Roblox GamePass ID upon publishing
		Title = "VIP 2x Cash & XP",
		PriceRobux = 399,
		Description = "Permanently doubles all Cash and XP earned from smashing, stunts, combos, and missions!",
		IconText = "2X VIP",
		AccentColor = { 255, 210, 50 },
	},
	{
		Key = "UnlimitedNitro",
		PassId = 0,
		Title = "Unlimited Plasma Nitro",
		PriceRobux = 299,
		Description = "Infinite Nitro boost meter that never depletes + twin Blue Plasma exhaust flames!",
		IconText = "NITRO+",
		AccentColor = { 45, 200, 255 },
	},
	{
		Key = "GoldenBulldozerPass",
		PassId = 0,
		Title = "Golden Apex Bulldozer",
		PriceRobux = 499,
		Description = "Unlocks the heavily armored Golden Apex Bulldozer & Goliath Rig with 24K Gold trim!",
		IconText = "DOZER",
		AccentColor = { 255, 175, 25 },
	},
	{
		Key = "HeatShieldScanner",
		PassId = 0,
		Title = "Police Heat Shield Scanner",
		PriceRobux = 249,
		Description = "50% slower Police Heat buildup and 50% faster cooldown when evading pursuit!",
		IconText = "RADAR",
		AccentColor = { 90, 145, 255 },
	},
	{
		Key = "MegaMagnetPass",
		PassId = 0,
		Title = "Mega Combo & Cash Magnet",
		PriceRobux = 199,
		Description = "Doubles your Combo Timer window (9.0s) and grants a permanent +50% Cash Magnet boost!",
		IconText = "MAGNET",
		AccentColor = { 195, 85, 255 },
	},
}

local DEVPRODUCT_CATALOG: { DevProductEntry } = {
	{
		Key = "CashPackStarter",
		ProductId = 0, -- Replace 0 with live Roblox Developer Product ID upon publishing
		Title = "Starter Cash Pack (+$10,000)",
		PriceRobux = 49,
		Description = "Instantly adds $10,000 Destruction Cash to your wallet for Speed Shop upgrades!",
		IconText = "+$10K",
		AccentColor = { 80, 235, 130 },
	},
	{
		Key = "CashPackPro",
		ProductId = 0,
		Title = "Pro Cash Vault (+$50,000)",
		PriceRobux = 199,
		Description = "Instantly adds $50,000 Destruction Cash to unlock heavy vehicles & high-tier upgrades!",
		IconText = "+$50K",
		AccentColor = { 45, 220, 170 },
	},
	{
		Key = "CashPackTycoon",
		ProductId = 0,
		Title = "Tycoon Mega Crate (+$250,000)",
		PriceRobux = 699,
		Description = "Instantly adds $250,000 Destruction Cash — max out every Speed Shop track & vehicle!",
		IconText = "+$250K",
		AccentColor = { 255, 215, 55 },
	},
	{
		Key = "BribePoliceChief",
		ProductId = 0,
		Title = "Bribe Police Chief (Clear Heat)",
		PriceRobux = 35,
		Description = "Instantly calls off all pursuing Police units and resets 5-Star Heat to 0!",
		IconText = "BRIBE",
		AccentColor = { 100, 175, 255 },
	},
	{
		Key = "InstantMaxRepairAndBoost",
		ProductId = 0,
		Title = "Max Repair + 60s Overdrive",
		PriceRobux = 29,
		Description = "Instantly repairs your vehicle to 100% HP, refills Nitro, and triggers 60s 2x Overdrive!",
		IconText = "OVERDRIVE",
		AccentColor = { 255, 95, 65 },
	},
}

local GAMEPASS_BY_KEY: { [string]: GamePassEntry } = {}
local GAMEPASS_BY_ID: { [number]: GamePassEntry } = {}
for _, entry in ipairs(GAMEPASS_CATALOG) do
	GAMEPASS_BY_KEY[entry.Key] = entry
	if entry.PassId > 0 then
		GAMEPASS_BY_ID[entry.PassId] = entry
	end
end

local DEVPRODUCT_BY_KEY: { [string]: DevProductEntry } = {}
local DEVPRODUCT_BY_ID: { [number]: DevProductEntry } = {}
for _, entry in ipairs(DEVPRODUCT_CATALOG) do
	DEVPRODUCT_BY_KEY[entry.Key] = entry
	if entry.ProductId > 0 then
		DEVPRODUCT_BY_ID[entry.ProductId] = entry
	end
end

--------------------------------------------------------------------------------
-- Shared Infrastructure Helpers (Bindables & Remotes)
--------------------------------------------------------------------------------
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

local function ensureBindableEvent(parent: Instance, name: string): BindableEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
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

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end

local serverEventsFolder = ensureFolder(ServerStorage, "Events")
local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")

-- Server Bindables
local AddCashBindable = ensureBindableEvent(ServerStorage, "AddCashEvent")
local UpdatePlayerDataBindable = ensureBindableEvent(ServerStorage, "UpdatePlayerDataEvent")
local ClearHeatBindable = ensureBindableEvent(ServerStorage, "ClearHeatEvent")
local RepairVehicleBindable = ensureBindableEvent(ServerStorage, "RepairVehicleEvent")

ensureBindableEvent(serverEventsFolder, "AddCashEvent")
ensureBindableEvent(serverEventsFolder, "ClearHeatEvent")
ensureBindableEvent(serverEventsFolder, "RepairVehicleEvent")

-- Client Remotes
local RequestPurchaseRemote = ensureRemoteEvent(remotesFolder, "RequestMonetizationPurchase")
local MonetizationNotificationRemote = ensureRemoteEvent(remotesFolder, "MonetizationNotification")
local StyleCalloutRemote = ensureRemoteEvent(remotesFolder, "StyleCallout")
local GetMonetizationCatalogRemote = ensureRemoteFunction(remotesFolder, "GetMonetizationCatalog")

local RootStyleCalloutRemote = ensureRemoteEvent(ReplicatedStorage, "StyleCalloutEvent")

--------------------------------------------------------------------------------
-- Per-Player Owned GamePasses & Active Boosts
--------------------------------------------------------------------------------
local ownedGamePasses: { [number]: { [string]: boolean } } = {}
local overdriveEndTime: { [number]: number } = {}
local lastHeatProgress: { [number]: number } = {}
local isAdjustingHeat: { [number]: boolean } = {}

local function recomputePlayerMultipliers(player: Player)
	local owned = ownedGamePasses[player.UserId] or {}

	-- Base magnet multiplier from Speed Shop Upgrade_Magnet (1.0 .. 2.0)
	local magnetLvl = math.clamp(math.floor(tonumber(player:GetAttribute("Upgrade_Magnet") or player:GetAttribute("MagnetLevel")) or 1), 1, 5)
	local baseMagnetTable = { 1.0, 1.15, 1.35, 1.60, 2.0 }
	local magnetMult = baseMagnetTable[magnetLvl] or 1.0

	if owned["MegaMagnetPass"] then
		magnetMult += 0.5
		player:SetAttribute("ComboMaxTime", 9.0)
	else
		player:SetAttribute("ComboMaxTime", 4.5)
	end

	if owned["VIP2xCash"] then
		magnetMult *= 2.0
		player:SetAttribute("XPMultiplier", 2.0)
	else
		player:SetAttribute("XPMultiplier", 1.0)
	end

	local isOverdrive = (overdriveEndTime[player.UserId] or 0) > os.clock()
	player:SetAttribute("OverdriveBoostActive", isOverdrive)
	if isOverdrive then
		magnetMult *= 2.0
	end

	player:SetAttribute("CashMagnetMultiplier", tonumber(string.format("%.2f", magnetMult)))
end

local function applyGamePassBenefits(player: Player, passKey: string, silent: boolean?)
	local userId = player.UserId
	if not ownedGamePasses[userId] then
		ownedGamePasses[userId] = {}
	end
	ownedGamePasses[userId][passKey] = true

	-- Set both Pass_<Key> and <Key> attributes for seamless cross-script compatibility
	player:SetAttribute("Pass_" .. passKey, true)
	player:SetAttribute(passKey, true)

	if passKey == "VIP2xCash" then
		recomputePlayerMultipliers(player)
	elseif passKey == "UnlimitedNitro" then
		player:SetAttribute("UnlimitedNitro", true)
		player:SetAttribute("NitroFuel", 100)
		player:SetAttribute("MaxNitroFuel", 100)
		player:SetAttribute("NitroFlameColor", "BluePlasma")
	elseif passKey == "GoldenBulldozerPass" then
		player:SetAttribute("Unlocked_boxTruck", true)
		player:SetAttribute("Unlocked_goldenBulldozer", true)
		player:SetAttribute("GoldenBulldozerUnlocked", true)

		-- Also add boxTruck & goldenBulldozer to UnlockedVehicles JSON attribute + PlayerDataService
		local rawJson = tostring(player:GetAttribute("UnlockedVehicles") or '["sports","sedan"]')
		local ok, list = pcall(function()
			return HttpService:JSONDecode(rawJson)
		end)
		if ok and type(list) == "table" then
			if not table.find(list, "boxTruck") then
				table.insert(list, "boxTruck")
			end
			if not table.find(list, "goldenBulldozer") then
				table.insert(list, "goldenBulldozer")
			end
			local okEnc, encoded = pcall(function()
				return HttpService:JSONEncode(list)
			end)
			if okEnc then
				player:SetAttribute("UnlockedVehicles", encoded)
			end
		end
		UpdatePlayerDataBindable:Fire(player, {
			UnlockedVehicles = {
				boxTruck = true,
				goldenBulldozer = true,
			},
		})
	elseif passKey == "HeatShieldScanner" then
		player:SetAttribute("HeatBuildupMultiplier", 0.5)
		player:SetAttribute("HeatEvadeMultiplier", 1.5)
	elseif passKey == "MegaMagnetPass" then
		recomputePlayerMultipliers(player)
	end

	if not silent then
		local entry = GAMEPASS_BY_KEY[passKey]
		local title = if entry then entry.Title else passKey
		MonetizationNotificationRemote:FireClient(player, {
			Kind = "GamePass",
			Key = passKey,
			Title = title,
			Status = "Unlocked",
			Message = string.format("GAMEPASS UNLOCKED: %s!", title),
		})
		local calloutPayload = {
			Callout = string.format("VIP PERK ACTIVE: %s!", string.upper(title)),
			Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
			ComboCount = tonumber(player:GetAttribute("ComboCount")) or 1,
			CashAwarded = 0,
			ChaosAwarded = 250,
			IsMonetizationBanner = true,
		}
		StyleCalloutRemote:FireClient(player, calloutPayload)
		RootStyleCalloutRemote:FireClient(player, calloutPayload)
	end
end

local function executeDevProductGrant(player: Player, productKey: string): boolean
	local entry = DEVPRODUCT_BY_KEY[productKey]
	if not entry then
		return false
	end

	if productKey == "CashPackStarter" then
		AddCashBindable:Fire(player, 10000, "DevProduct_CashPackStarter")
	elseif productKey == "CashPackPro" then
		AddCashBindable:Fire(player, 50000, "DevProduct_CashPackPro")
	elseif productKey == "CashPackTycoon" then
		AddCashBindable:Fire(player, 250000, "DevProduct_CashPackTycoon")
	elseif productKey == "BribePoliceChief" then
		isAdjustingHeat[player.UserId] = true
		player:SetAttribute("HeatStars", 0)
		player:SetAttribute("HeatProgress", 0)
		player:SetAttribute("IsBusted", false)
		lastHeatProgress[player.UserId] = 0
		isAdjustingHeat[player.UserId] = false

		ClearHeatBindable:Fire(player, "BribePoliceChief")
		local folderClear = serverEventsFolder:FindFirstChild("ClearHeatEvent") :: BindableEvent?
		if folderClear then
			folderClear:Fire(player, "BribePoliceChief")
		end

		-- Also remove active police units targeting this player if present in Workspace
		local policeFolder = workspace:FindFirstChild("PoliceUnits") or workspace:FindFirstChild("Police")
		if policeFolder then
			for _, unit in ipairs(policeFolder:GetChildren()) do
				if unit:GetAttribute("TargetUserId") == player.UserId or unit:GetAttribute("TargetPlayer") == player.Name then
					unit:Destroy()
				end
			end
		end
	elseif productKey == "InstantMaxRepairAndBoost" then
		player:SetAttribute("VehicleHealth", 100)
		player:SetAttribute("MaxVehicleHealth", 100)
		player:SetAttribute("NitroFuel", 100)
		if player.Character then
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = hum.MaxHealth
			end
		end
		-- Repair active vehicle model if spawned in Workspace
		local vehiclesFolder = workspace:FindFirstChild("PlayerVehicles") or workspace:FindFirstChild("Vehicles")
		if vehiclesFolder then
			for _, veh in ipairs(vehiclesFolder:GetChildren()) do
				if veh:GetAttribute("OwnerUserId") == player.UserId or veh:GetAttribute("Owner") == player.Name or veh.Name == (player.Name .. "_Vehicle") then
					local maxHp = tonumber(veh:GetAttribute("MaxHealth")) or 100
					veh:SetAttribute("Health", maxHp)
					veh:SetAttribute("VehicleHealth", maxHp)
					veh:SetAttribute("NitroFuel", 100)
					veh:SetAttribute("GoldenTrim", ownedGamePasses[player.UserId] and ownedGamePasses[player.UserId]["GoldenBulldozerPass"] == true)
				end
			end
		end

		RepairVehicleBindable:Fire(player, "InstantMaxRepairAndBoost")
		overdriveEndTime[player.UserId] = os.clock() + 60
		player:SetAttribute("OverdriveRemaining", 60)
		recomputePlayerMultipliers(player)
	end

	MonetizationNotificationRemote:FireClient(player, {
		Kind = "DevProduct",
		Key = productKey,
		Title = entry.Title,
		Status = "Granted",
		Message = string.format("PURCHASE COMPLETE: %s!", entry.Title),
	})

	local calloutPayload = {
		Callout = string.format("UNLOCKED: %s!", string.upper(entry.Title)),
		Multiplier = tonumber(player:GetAttribute("ComboMultiplier")) or 1,
		ComboCount = tonumber(player:GetAttribute("ComboCount")) or 1,
		CashAwarded = 0,
		ChaosAwarded = 300,
		IsMonetizationBanner = true,
	}
	StyleCalloutRemote:FireClient(player, calloutPayload)
	RootStyleCalloutRemote:FireClient(player, calloutPayload)
	return true
end

--------------------------------------------------------------------------------
-- Studio Sandbox Purchase Mode & MarketplaceService Hooks
--------------------------------------------------------------------------------
local function handlePurchaseRequest(player: Player, kind: any, itemKey: any)
	local category = tostring(kind or "GamePass")
	local key = tostring(itemKey or "")

	if category == "GamePass" then
		local passEntry = GAMEPASS_BY_KEY[key]
		if not passEntry then
			return
		end
		if ownedGamePasses[player.UserId] and ownedGamePasses[player.UserId][key] then
			MonetizationNotificationRemote:FireClient(player, {
				Kind = "GamePass",
				Key = key,
				Title = passEntry.Title,
				Status = "AlreadyOwned",
				Message = string.format("You already own %s!", passEntry.Title),
			})
			return
		end

		-- Studio Sandbox Mode: If running in Roblox Studio or PassId is placeholder 0, grant immediately for testing
		if RunService:IsStudio() or passEntry.PassId <= 0 then
			applyGamePassBenefits(player, key, false)
		else
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passEntry.PassId)
			end)
		end
	elseif category == "DevProduct" then
		local prodEntry = DEVPRODUCT_BY_KEY[key]
		if not prodEntry then
			return
		end

		-- Studio Sandbox Mode: If running in Roblox Studio or ProductId is placeholder 0, grant immediately for testing
		if RunService:IsStudio() or prodEntry.ProductId <= 0 then
			executeDevProductGrant(player, key)
		else
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, prodEntry.ProductId)
			end)
		end
	end
end

RequestPurchaseRemote.OnServerEvent:Connect(handlePurchaseRequest)

-- Live Roblox MarketplaceService GamePass completion callback
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or not player then
		return
	end
	local entry = GAMEPASS_BY_ID[gamePassId]
	if entry then
		applyGamePassBenefits(player, entry.Key, false)
	end
end)

-- Live Roblox MarketplaceService ProcessReceipt callback for Developer Products
MarketplaceService.ProcessReceipt = function(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local entry = DEVPRODUCT_BY_ID[productId]
	if entry then
		local ok = executeDevProductGrant(player, entry.Key)
		if ok then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Client query for Store / VIP [M] modal
GetMonetizationCatalogRemote.OnServerInvoke = function(player: Player)
	local owned = ownedGamePasses[player.UserId] or {}
	local passesOut = {}
	for _, entry in ipairs(GAMEPASS_CATALOG) do
		table.insert(passesOut, {
			Key = entry.Key,
			PassId = entry.PassId,
			Title = entry.Title,
			PriceRobux = entry.PriceRobux,
			Description = entry.Description,
			IconText = entry.IconText,
			AccentColor = entry.AccentColor,
			Owned = owned[entry.Key] == true,
		})
	end

	local productsOut = {}
	for _, entry in ipairs(DEVPRODUCT_CATALOG) do
		table.insert(productsOut, {
			Key = entry.Key,
			ProductId = entry.ProductId,
			Title = entry.Title,
			PriceRobux = entry.PriceRobux,
			Description = entry.Description,
			IconText = entry.IconText,
			AccentColor = entry.AccentColor,
		})
	end

	return {
		IsStudioSandbox = RunService:IsStudio() or GAMEPASS_CATALOG[1].PassId == 0,
		GamePasses = passesOut,
		DevProducts = productsOut,
	}
end

--------------------------------------------------------------------------------
-- Player Initialization & Runtime Perk Enforcement Loop
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	ownedGamePasses[player.UserId] = {}
	overdriveEndTime[player.UserId] = 0
	lastHeatProgress[player.UserId] = 0

	for _, entry in ipairs(GAMEPASS_CATALOG) do
		player:SetAttribute("Pass_" .. entry.Key, false)
		if entry.PassId > 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.PassId)
				end)
				if ok and owns and player.Parent then
					applyGamePassBenefits(player, entry.Key, true)
				end
			end)
		end
	end

	recomputePlayerMultipliers(player)

	-- Recompute multipliers whenever Speed Shop Upgrade_Magnet changes
	player:GetAttributeChangedSignal("Upgrade_Magnet"):Connect(function()
		recomputePlayerMultipliers(player)
	end)

	-- Enforce HeatShieldScanner (50% slower Police Heat buildup)
	player:GetAttributeChangedSignal("HeatProgress"):Connect(function()
		if isAdjustingHeat[player.UserId] then
			return
		end
		local currentHeat = tonumber(player:GetAttribute("HeatProgress")) or 0
		local prevHeat = lastHeatProgress[player.UserId] or 0
		local owned = ownedGamePasses[player.UserId]
		if owned and owned["HeatShieldScanner"] and currentHeat > prevHeat then
			local delta = currentHeat - prevHeat
			isAdjustingHeat[player.UserId] = true
			local dampened = prevHeat + (delta * 0.5)
			player:SetAttribute("HeatProgress", dampened)
			lastHeatProgress[player.UserId] = dampened
			isAdjustingHeat[player.UserId] = false
		else
			lastHeatProgress[player.UserId] = currentHeat
		end
	end)

	-- Enforce MegaMagnetPass (9.0s Combo Timer window instead of 4.5s)
	player:GetAttributeChangedSignal("ComboCount"):Connect(function()
		local owned = ownedGamePasses[player.UserId]
		local chain = tonumber(player:GetAttribute("ComboCount")) or 0
		if owned and owned["MegaMagnetPass"] and chain > 0 then
			player:SetAttribute("ComboMaxTime", 9.0)
			local currentTimer = tonumber(player:GetAttribute("ComboTimer")) or 0
			if currentTimer > 4.0 and currentTimer <= 4.55 then
				player:SetAttribute("ComboTimer", 9.0)
			end
		end
	end)
end

local function onPlayerRemoving(player: Player)
	ownedGamePasses[player.UserId] = nil
	overdriveEndTime[player.UserId] = nil
	lastHeatProgress[player.UserId] = nil
	isAdjustingHeat[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Periodic enforcement for UnlimitedNitro & 60s Overdrive countdown
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			local owned = ownedGamePasses[userId]

			-- Keep UnlimitedNitro topped up at 100%
			if owned and owned["UnlimitedNitro"] then
				if (tonumber(player:GetAttribute("NitroFuel")) or 0) < 100 then
					player:SetAttribute("NitroFuel", 100)
				end
			end

			-- Update 60s Overdrive timer if active
			local endAt = overdriveEndTime[userId] or 0
			if endAt > 0 then
				if now < endAt then
					player:SetAttribute("OverdriveRemaining", math.ceil(endAt - now))
				else
					overdriveEndTime[userId] = 0
					player:SetAttribute("OverdriveRemaining", 0)
					recomputePlayerMultipliers(player)
				end
			end
		end
	end
end)
