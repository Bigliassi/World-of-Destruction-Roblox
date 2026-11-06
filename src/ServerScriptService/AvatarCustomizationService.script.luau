--!strict
-- AvatarCustomizationService.script.luau
-- Manages player character customization, free/cash/Robux item unlocks, presets, Boutique Kiosk, and 3D character application.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarCatalog = require(Shared:WaitForChild("AvatarCatalog"))

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemote(name: string, className: string): Instance
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotesFolder
	return r
end

local getAvatarWardrobeRF = ensureRemote("GetAvatarWardrobe", "RemoteFunction") :: RemoteFunction
local equipAvatarItemRF = ensureRemote("EquipAvatarItem", "RemoteFunction") :: RemoteFunction
local purchaseAvatarItemRF = ensureRemote("PurchaseAvatarItem", "RemoteFunction") :: RemoteFunction
local applyCharacterPresetRE = ensureRemote("ApplyCharacterPreset", "RemoteEvent") :: RemoteEvent
local avatarUpdatedRE = ensureRemote("AvatarUpdated", "RemoteEvent") :: RemoteEvent
local openAvatarEditorRE = ensureRemote("OpenAvatarEditor", "RemoteEvent") :: RemoteEvent

type PlayerAvatarState = {
	Loadout: AvatarCatalog.AvatarLoadout,
	Unlocked: { [string]: boolean },
	HasCustomized: boolean,
}

local playerStates: { [Player]: PlayerAvatarState } = {}

local function getDefaultUnlocked(): { [string]: boolean }
	local unlocked: { [string]: boolean } = {}
	for id, item in pairs(AvatarCatalog.Items) do
		if item.Currency == "Free" then
			unlocked[id] = true
		end
	end
	return unlocked
end

local function getPlayerCash(player: Player): number
	local attrCash = player:GetAttribute("Cash")
	if typeof(attrCash) == "number" then
		return attrCash
	end
	local ls = player:FindFirstChild("leaderstats")
	local cashVal = ls and ls:FindFirstChild("Cash") :: IntValue?
	if cashVal then
		return cashVal.Value
	end
	return 0
end

local function setPlayerCash(player: Player, newCash: number)
	local clamped = math.max(0, math.floor(newCash))
	player:SetAttribute("Cash", clamped)
	local ls = player:FindFirstChild("leaderstats")
	local cashVal = ls and ls:FindFirstChild("Cash") :: IntValue?
	if cashVal then
		cashVal.Value = clamped
	end
end

local function applyToCharacter(player: Player)
	local state = playerStates[player]
	if not state then return end
	local character = player.Character
	if not character then return end

	AvatarCatalog.ApplyLoadoutToCharacter(character, state.Loadout)
	local perks = AvatarCatalog.ComputePerks(state.Loadout)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = math.floor(16 * perks.SprintMult + 0.5)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = math.floor(50 * perks.SprintMult + 0.5)
	end
end

local function syncStateToPlayer(player: Player)
	local state = playerStates[player]
	if not state then return end

	local perks = AvatarCatalog.ComputePerks(state.Loadout)
	player:SetAttribute("AvatarLoadoutJson", HttpService:JSONEncode(state.Loadout))
	player:SetAttribute("UnlockedAvatarItemsJson", HttpService:JSONEncode(state.Unlocked))
	player:SetAttribute("HasCustomizedCharacter", state.HasCustomized)
	player:SetAttribute("AvatarPerkCashMult", perks.CashMult)
	player:SetAttribute("AvatarPerkXPMult", perks.XPMult)
	player:SetAttribute("AvatarPerkSprintMult", perks.SprintMult)

	applyToCharacter(player)
	avatarUpdatedRE:FireClient(player, {
		Loadout = state.Loadout,
		Unlocked = state.Unlocked,
		Perks = perks,
		HasCustomized = state.HasCustomized,
	})
end

local function initPlayer(player: Player)
	local state: PlayerAvatarState = {
		Loadout = AvatarCatalog.GetDefaultLoadout(),
		Unlocked = getDefaultUnlocked(),
		HasCustomized = false,
	}
	playerStates[player] = state
	syncStateToPlayer(player)

	player.CharacterAdded:Connect(function()
		task.wait(0.15)
		applyToCharacter(player)
	end)
	if player.Character then
		task.spawn(function()
			task.wait(0.15)
			applyToCharacter(player)
		end)
	end
end

local function unlockMegaBundleForPlayer(player: Player)
	local state = playerStates[player]
	if not state then return end
	for id, _ in pairs(AvatarCatalog.Items) do
		state.Unlocked[id] = true
	end
	state.Unlocked[AvatarCatalog.VIPAvatarMegaBundle.Id] = true
	-- Equip Golden VIP signature set automatically on Mega Bundle unlock
	state.Loadout = {
		Outfit = "GoldenSovereignArmor",
		Headgear = "CrownOfDestruction",
		BackAccessory = "ArchangelChaosWings",
		HeldGear = "GoldenWreckingHammer",
		AuraTrail = "SupernovaChaosAura",
		SkinTone = state.Loadout.SkinTone or "SkinWarmTan",
	}
	state.HasCustomized = true
	syncStateToPlayer(player)
end

getAvatarWardrobeRF.OnServerInvoke = function(player: Player)
	local state = playerStates[player]
	if not state then
		initPlayer(player)
		state = playerStates[player]
	end
	return {
		Loadout = state.Loadout,
		Unlocked = state.Unlocked,
		Perks = AvatarCatalog.ComputePerks(state.Loadout),
		HasCustomized = state.HasCustomized,
		Cash = getPlayerCash(player),
	}
end

equipAvatarItemRF.OnServerInvoke = function(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then
		return { Success = false, Message = "Invalid item ID." }
	end
	local state = playerStates[player]
	if not state then
		return { Success = false, Message = "Profile not ready." }
	end
	local item = AvatarCatalog.Items[itemId]
	if not item then
		return { Success = false, Message = "Item not found in catalog." }
	end
	if not state.Unlocked[itemId] and item.Currency ~= "Free" then
		return { Success = false, Message = "Unlock this item first!" }
	end

	state.Unlocked[itemId] = true
	(state.Loadout :: any)[item.Category] = itemId
	state.HasCustomized = true
	syncStateToPlayer(player)
	return {
		Success = true,
		Message = "Equipped " .. item.Name .. "!",
		Loadout = state.Loadout,
		Unlocked = state.Unlocked,
	}
end

purchaseAvatarItemRF.OnServerInvoke = function(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then
		return { Success = false, Message = "Invalid item ID." }
	end
	local state = playerStates[player]
	if not state then
		return { Success = false, Message = "Profile not ready." }
	end

	-- Handle VIP Mega Bundle (599 Robux)
	if itemId == AvatarCatalog.VIPAvatarMegaBundle.Id then
		local bundle = AvatarCatalog.VIPAvatarMegaBundle
		if state.Unlocked[bundle.Id] then
			return { Success = true, Message = "VIP Mega Bundle already owned!" }
		end
		if bundle.ProductId and bundle.ProductId > 0 and not RunService:IsStudio() then
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, bundle.ProductId)
			end)
			return { Success = true, PromptedRobux = true, Message = "Complete Robux purchase in prompt!" }
		end
		-- Studio Sandbox / Placeholder ID immediate unlock so players & testers can enjoy Robux items immediately
		unlockMegaBundleForPlayer(player)
		return {
			Success = true,
			Message = "VIP ALL-ACCESS MEGA BUNDLE UNLOCKED! (Robux Sandbox Grant)",
			Loadout = state.Loadout,
			Unlocked = state.Unlocked,
		}
	end

	local item = AvatarCatalog.Items[itemId]
	if not item then
		return { Success = false, Message = "Unknown item." }
	end

	if state.Unlocked[itemId] or item.Currency == "Free" then
		state.Unlocked[itemId] = true
		;(state.Loadout :: any)[item.Category] = itemId
		state.HasCustomized = true
		syncStateToPlayer(player)
		return {
			Success = true,
			Message = "Equipped " .. item.Name .. "!",
			Loadout = state.Loadout,
			Unlocked = state.Unlocked,
		}
	end

	if item.Currency == "Cash" then
		local cash = getPlayerCash(player)
		if cash < item.Price then
			return {
				Success = false,
				Message = string.format("Need $%d Destruction Cash! (You have $%d)", item.Price, cash),
			}
		end
		setPlayerCash(player, cash - item.Price)
		state.Unlocked[itemId] = true
		;(state.Loadout :: any)[item.Category] = itemId
		state.HasCustomized = true
		syncStateToPlayer(player)
		return {
			Success = true,
			Message = string.format("Purchased & Equipped %s for $%d!", item.Name, item.Price),
			Loadout = state.Loadout,
			Unlocked = state.Unlocked,
		}
	elseif item.Currency == "Robux" then
		if item.ProductId and item.ProductId > 0 and not RunService:IsStudio() then
			pcall(function()
				MarketplaceService:PromptProductPurchase(player, item.ProductId)
			end)
			return { Success = true, PromptedRobux = true, Message = "Complete Robux purchase in prompt!" }
		end
		-- Studio Sandbox / Placeholder ID instant Robux unlock
		state.Unlocked[itemId] = true
		;(state.Loadout :: any)[item.Category] = itemId
		state.HasCustomized = true
		syncStateToPlayer(player)
		return {
			Success = true,
			Message = string.format("UNLOCKED ROBUX ITEM: %s (%d R$ Sandbox Grant)!", item.Name, item.Price),
			Loadout = state.Loadout,
			Unlocked = state.Unlocked,
		}
	end

	return { Success = false, Message = "Purchase failed." }
end

applyCharacterPresetRE.OnServerEvent:Connect(function(player: Player, presetId: any)
	local state = playerStates[player]
	if not state or typeof(presetId) ~= "string" then return end

	if presetId == "MarkCustomized" then
		state.HasCustomized = true
		syncStateToPlayer(player)
		return
	end

	for _, preset in ipairs(AvatarCatalog.Presets) do
		if preset.Id == presetId then
			for category, itemId in pairs(preset.Loadout) do
				local item = AvatarCatalog.Items[itemId]
				if item and (item.Currency == "Free" or state.Unlocked[itemId]) then
					state.Unlocked[itemId] = true
					;(state.Loadout :: any)[category] = itemId
				end
			end
			state.HasCustomized = true
			syncStateToPlayer(player)
			break
		end
	end
end)

-- Spawn Leo City Fashion & Gear Boutique Kiosk near Spawn Plaza
local function buildAvatarBoutiqueKiosk()
	if Workspace:FindFirstChild("LeoAvatarBoutiqueKiosk") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "LeoAvatarBoutiqueKiosk"

	local pad = Instance.new("Part")
	pad.Name = "BoutiquePlatform"
	pad.Size = Vector3.new(12, 0.8, 12)
	pad.Position = Vector3.new(-32, 0.5, 28)
	pad.Anchored = true
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(236, 72, 153)
	pad.Parent = model

	local pedestal = Instance.new("Part")
	pedestal.Name = "BoutiqueKioskTower"
	pedestal.Size = Vector3.new(5, 8, 2.5)
	pedestal.Position = Vector3.new(-32, 4.9, 24)
	pedestal.Anchored = true
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Color = Color3.fromRGB(15, 23, 42)
	pedestal.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 74)
	bb.StudsOffset = Vector3.new(0, 6.2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = pedestal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
	title.BackgroundTransparency = 0.15
	title.TextColor3 = Color3.fromRGB(250, 204, 21)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Text = "LEO FASHION & ROBUX GEAR\n[Customize Character]"
	title.Parent = bb
	Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Leo Fashion & Gear Boutique"
	prompt.ActionText = "Customize Character [C]"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.Parent = pedestal

	prompt.Triggered:Connect(function(player: Player)
		openAvatarEditorRE:FireClient(player)
	end)

	model.Parent = Workspace
end

buildAvatarBoutiqueKiosk()

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayer, player)
end
Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	playerStates[player] = nil
end)
