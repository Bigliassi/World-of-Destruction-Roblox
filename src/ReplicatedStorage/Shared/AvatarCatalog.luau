--!strict
-- AvatarCatalog.luau
-- Shared catalog of Free, Cash, and Robux character customization items, presets, and 3D procedural attachment builder.

local AvatarCatalog = {}

export type CurrencyType = "Free" | "Cash" | "Robux"
export type CategoryName = "Outfit" | "Headgear" | "BackAccessory" | "HeldGear" | "AuraTrail" | "SkinTone"

export type AvatarItem = {
	Id: string,
	Name: string,
	Category: CategoryName,
	Currency: CurrencyType,
	Price: number,
	ProductId: number?,
	Rarity: string,
	PrimaryColor: Color3,
	AccentColor: Color3,
	Description: string,
	PerkLabel: string?,
	CashMultiplierBonus: number?,
	XPMultiplierBonus: number?,
	SprintBonus: number?,
	ChaosBonus: number?,
}

export type AvatarLoadout = {
	Outfit: string,
	Headgear: string,
	BackAccessory: string,
	HeldGear: string,
	AuraTrail: string,
	SkinTone: string,
}

AvatarCatalog.Categories = {
	{ Id = "Presets", Label = "Presets" },
	{ Id = "Outfit", Label = "Outfits" },
	{ Id = "Headgear", Label = "Headgear" },
	{ Id = "BackAccessory", Label = "Backpacks" },
	{ Id = "HeldGear", Label = "Held Gear" },
	{ Id = "AuraTrail", Label = "Auras" },
	{ Id = "SkinTone", Label = "Skin Tone" },
}

AvatarCatalog.VIPAvatarMegaBundle = {
	Id = "VIPAvatarMegaBundle",
	Name = "VIP All-Access Robux Mega Bundle",
	Currency = "Robux",
	Price = 599,
	ProductId = 0, -- 0 triggers Studio/Sandbox instant unlock or replaces with live GamePass/Product ID
	Description = "Instantly unlocks ALL Robux & Cash outfits, crowns, jetpacks, wings, hammers, and supernova auras!",
}

AvatarCatalog.Items = {
	-- ================= OUTFITS =================
	StreetRookieHoodie = {
		Id = "StreetRookieHoodie", Name = "Street Rookie Hoodie", Category = "Outfit",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(45, 55, 72), AccentColor = Color3.fromRGB(56, 189, 248),
		Description = "Classic urban streetwear hoodie built for everyday drifting and smashing.",
	},
	LeoCreatorJacket = {
		Id = "LeoCreatorJacket", Name = "Leo Creator Jacket", Category = "Outfit",
		Currency = "Free", Price = 0, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(220, 38, 38), AccentColor = Color3.fromRGB(250, 204, 21),
		Description = "Signature Leo varsity stunt jacket with gold trim and reinforced shoulders.",
	},
	DemolitionJumpsuit = {
		Id = "DemolitionJumpsuit", Name = "Demolition Jumpsuit", Category = "Outfit",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(234, 88, 12), AccentColor = Color3.fromRGB(30, 41, 59),
		Description = "High-visibility heavy crew jumpsuit with reflective hazard striping.",
	},
	AsphaltBikerLeather = {
		Id = "AsphaltBikerLeather", Name = "Asphalt Biker Leather", Category = "Outfit",
		Currency = "Cash", Price = 1500, Rarity = "Uncommon",
		PrimaryColor = Color3.fromRGB(24, 24, 27), AccentColor = Color3.fromRGB(161, 161, 170),
		Description = "Studded midnight leather jacket with chrome shoulder plates.",
	},
	TacticalSWATSet = {
		Id = "TacticalSWATSet", Name = "Tactical SWAT Set", Category = "Outfit",
		Currency = "Cash", Price = 4500, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(30, 58, 138), AccentColor = Color3.fromRGB(96, 165, 250),
		Description = "Heavy armored tactical vest and knee guards built for high-heat pursuits.",
	},
	NeonCyberSuit = {
		Id = "NeonCyberSuit", Name = "Neon Cyber Suit", Category = "Outfit",
		Currency = "Cash", Price = 9000, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(17, 24, 39), AccentColor = Color3.fromRGB(34, 211, 238),
		Description = "Glowing synthwave exosuit lined with pulsing cyan circuit plates.",
	},
	InfernoStuntSuit = {
		Id = "InfernoStuntSuit", Name = "Inferno Stunt Suit", Category = "Outfit",
		Currency = "Robux", Price = 99, ProductId = 0, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(153, 27, 27), AccentColor = Color3.fromRGB(251, 146, 60),
		Description = "Blazing daredevil racing suit with molten neon chest plates.",
	},
	GoldenSovereignArmor = {
		Id = "GoldenSovereignArmor", Name = "Golden Sovereign Armor", Category = "Outfit",
		Currency = "Robux", Price = 249, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(234, 179, 8), AccentColor = Color3.fromRGB(254, 240, 138),
		Description = "Solid 24K gold battle armor worn by Leo City royalty.",
		PerkLabel = "+10% CASH", CashMultiplierBonus = 0.10,
	},

	-- ================= HEADGEAR =================
	None = {
		Id = "None", Name = "None", Category = "Headgear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(100, 116, 139), AccentColor = Color3.fromRGB(148, 163, 184),
		Description = "Clean default look with no extra accessory.",
	},
	NoneHeadgear = {
		Id = "NoneHeadgear", Name = "No Headgear", Category = "Headgear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(100, 116, 139), AccentColor = Color3.fromRGB(148, 163, 184),
		Description = "Clean hair/head look with no helmet or hat.",
	},
	StreetSnapback = {
		Id = "StreetSnapback", Name = "Street Snapback", Category = "Headgear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(220, 38, 38), AccentColor = Color3.fromRGB(255, 255, 255),
		Description = "Forward-facing Leo City flat-brim snapback cap.",
	},
	HardHatYellow = {
		Id = "HardHatYellow", Name = "Site Boss Hard Hat", Category = "Headgear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(250, 204, 21), AccentColor = Color3.fromRGB(30, 41, 59),
		Description = "OSHA-approved demolition crew hard hat.",
	},
	StuntCrashHelmet = {
		Id = "StuntCrashHelmet", Name = "Stunt Crash Helmet", Category = "Headgear",
		Currency = "Cash", Price = 1200, Rarity = "Uncommon",
		PrimaryColor = Color3.fromRGB(248, 250, 252), AccentColor = Color3.fromRGB(239, 68, 68),
		Description = "Full-face racing helmet with tinted visor stripe.",
	},
	PoliceChiefCap = {
		Id = "PoliceChiefCap", Name = "Police Chief Cap", Category = "Headgear",
		Currency = "Cash", Price = 3000, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(30, 41, 59), AccentColor = Color3.fromRGB(250, 204, 21),
		Description = "Gold-badged commander peaked cap from Leo PD.",
	},
	NeonVisorHelm = {
		Id = "NeonVisorHelm", Name = "Neon Visor Helm", Category = "Headgear",
		Currency = "Cash", Price = 6500, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(15, 23, 42), AccentColor = Color3.fromRGB(56, 189, 248),
		Description = "Futuristic cyber helmet with a holographic LED visor.",
	},
	CyberKitsuneMask = {
		Id = "CyberKitsuneMask", Name = "Cyber Kitsune Mask", Category = "Headgear",
		Currency = "Robux", Price = 125, ProductId = 0, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(24, 24, 27), AccentColor = Color3.fromRGB(236, 72, 153),
		Description = "Neon-eared cybernetic fox mask with glowing magenta eyes.",
	},
	CrownOfDestruction = {
		Id = "CrownOfDestruction", Name = "Crown of Destruction", Category = "Headgear",
		Currency = "Robux", Price = 299, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(250, 204, 21), AccentColor = Color3.fromRGB(239, 68, 68),
		Description = "Jeweled golden sovereign crown forged from wrecked supercars.",
		PerkLabel = "+10% XP", XPMultiplierBonus = 0.10,
	},

	-- ================= BACK ACCESSORIES =================
	NoneBack = {
		Id = "NoneBack", Name = "No Back Gear", Category = "BackAccessory",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(100, 116, 139), AccentColor = Color3.fromRGB(148, 163, 184),
		Description = "No backpack or wings equipped.",
	},
	WreckingToolPack = {
		Id = "WreckingToolPack", Name = "Wrecking Tool Pack", Category = "BackAccessory",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(71, 85, 105), AccentColor = Color3.fromRGB(249, 115, 22),
		Description = "Utility rig stocked with prybars, flares, and repair cells.",
	},
	BoomboxSpeaker = {
		Id = "BoomboxSpeaker", Name = "Street Bass Boombox", Category = "BackAccessory",
		Currency = "Cash", Price = 2500, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(30, 41, 59), AccentColor = Color3.fromRGB(34, 211, 238),
		Description = "Dual-subwoofer shoulder boombox with neon equalizer bars.",
	},
	GoldBullionDuffel = {
		Id = "GoldBullionDuffel", Name = "Gold Bullion Duffel", Category = "BackAccessory",
		Currency = "Cash", Price = 5500, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(20, 83, 45), AccentColor = Color3.fromRGB(250, 204, 21),
		Description = "Heist duffel bag overflowing with solid gold bars.",
	},
	NitroThrusterJetpack = {
		Id = "NitroThrusterJetpack", Name = "Nitro Thruster Jetpack", Category = "BackAccessory",
		Currency = "Robux", Price = 175, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(30, 41, 59), AccentColor = Color3.fromRGB(249, 115, 22),
		Description = "Twin-turbine nitro booster pack with live exhaust flames.",
		PerkLabel = "+15% SPEED", SprintBonus = 0.15,
	},
	ArchangelChaosWings = {
		Id = "ArchangelChaosWings", Name = "Archangel Chaos Wings", Category = "BackAccessory",
		Currency = "Robux", Price = 349, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(250, 204, 21), AccentColor = Color3.fromRGB(56, 189, 248),
		Description = "Massive articulated cyber-feathered wings that radiate light.",
	},

	-- ================= HELD GEAR =================
	NoneHeld = {
		Id = "NoneHeld", Name = "Empty Hands", Category = "HeldGear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(100, 116, 139), AccentColor = Color3.fromRGB(148, 163, 184),
		Description = "Keep hands free.",
	},
	NeonWrench = {
		Id = "NeonWrench", Name = "Neon Mechanic Wrench", Category = "HeldGear",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(148, 163, 184), AccentColor = Color3.fromRGB(56, 189, 248),
		Description = "Heavy torque wrench for tuning rides or bashing crates.",
	},
	DemolitionSledge = {
		Id = "DemolitionSledge", Name = "Demolition Sledge", Category = "HeldGear",
		Currency = "Cash", Price = 2000, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(51, 65, 85), AccentColor = Color3.fromRGB(239, 68, 68),
		Description = "Reinforced steel sledgehammer built for concrete barriers.",
	},
	PlasmaFlareTorch = {
		Id = "PlasmaFlareTorch", Name = "Plasma Flare Blade", Category = "HeldGear",
		Currency = "Cash", Price = 4000, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(15, 23, 42), AccentColor = Color3.fromRGB(168, 85, 247),
		Description = "Superheated plasma cutter that leaves violet light streaks.",
	},
	GoldenWreckingHammer = {
		Id = "GoldenWreckingHammer", Name = "Golden Wrecking Hammer", Category = "HeldGear",
		Currency = "Robux", Price = 149, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(234, 179, 8), AccentColor = Color3.fromRGB(254, 240, 138),
		Description = "Colossal solid-gold warhammer of the Destruction King.",
	},

	-- ================= AURA TRAILS =================
	NoneAura = {
		Id = "NoneAura", Name = "No Aura", Category = "AuraTrail",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(100, 116, 139), AccentColor = Color3.fromRGB(148, 163, 184),
		Description = "Standard character appearance with no particle aura.",
	},
	TireSmokeTrail = {
		Id = "TireSmokeTrail", Name = "Burnout Drift Smoke", Category = "AuraTrail",
		Currency = "Cash", Price = 1800, Rarity = "Uncommon",
		PrimaryColor = Color3.fromRGB(203, 213, 225), AccentColor = Color3.fromRGB(249, 115, 22),
		Description = "Billowing burnout smoke and hot road embers at your feet.",
	},
	NeonVoltTrail = {
		Id = "NeonVoltTrail", Name = "Neon Volt Lightning", Category = "AuraTrail",
		Currency = "Cash", Price = 4800, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(34, 211, 238), AccentColor = Color3.fromRGB(168, 85, 247),
		Description = "Crackling high-voltage electric arcs surging around your body.",
	},
	CashShowerAura = {
		Id = "CashShowerAura", Name = "Tycoon Cash Shower", Category = "AuraTrail",
		Currency = "Robux", Price = 199, ProductId = 0, Rarity = "Epic",
		PrimaryColor = Color3.fromRGB(34, 197, 94), AccentColor = Color3.fromRGB(250, 204, 21),
		Description = "Swirling vortex of green bills and golden sparkles.",
	},
	SupernovaChaosAura = {
		Id = "SupernovaChaosAura", Name = "Supernova Chaos Aura", Category = "AuraTrail",
		Currency = "Robux", Price = 299, ProductId = 0, Rarity = "Legendary",
		PrimaryColor = Color3.fromRGB(249, 115, 22), AccentColor = Color3.fromRGB(250, 204, 21),
		Description = "Blazing solar flares and rising plasma rings.",
		PerkLabel = "+15% CHAOS", ChaosBonus = 0.15,
	},

	-- ================= SKIN TONES =================
	SkinWarmTan = {
		Id = "SkinWarmTan", Name = "Warm Tan", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(217, 160, 115), AccentColor = Color3.fromRGB(217, 160, 115),
		Description = "Warm sun-kissed tone.",
	},
	SkinLightPeach = {
		Id = "SkinLightPeach", Name = "Light Peach", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(245, 205, 174), AccentColor = Color3.fromRGB(245, 205, 174),
		Description = "Light classic tone.",
	},
	SkinGoldenOlive = {
		Id = "SkinGoldenOlive", Name = "Golden Olive", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(198, 134, 66), AccentColor = Color3.fromRGB(198, 134, 66),
		Description = "Golden Mediterranean tone.",
	},
	SkinDeepBronze = {
		Id = "SkinDeepBronze", Name = "Deep Bronze", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(141, 85, 36), AccentColor = Color3.fromRGB(141, 85, 36),
		Description = "Rich deep bronze tone.",
	},
	SkinRichEbony = {
		Id = "SkinRichEbony", Name = "Rich Ebony", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Common",
		PrimaryColor = Color3.fromRGB(78, 46, 28), AccentColor = Color3.fromRGB(78, 46, 28),
		Description = "Deep espresso tone.",
	},
	SkinRobotChrome = {
		Id = "SkinRobotChrome", Name = "Cyber Chrome", Category = "SkinTone",
		Currency = "Free", Price = 0, Rarity = "Rare",
		PrimaryColor = Color3.fromRGB(148, 163, 184), AccentColor = Color3.fromRGB(56, 189, 248),
		Description = "Synthetic metallic android chassis finish.",
	},
}

AvatarCatalog.Presets = {
	{
		Id = "LeoStar", Name = "Leo Star", Badge = "FREE STARTER",
		Loadout = {
			Outfit = "LeoCreatorJacket", Headgear = "StreetSnapback", BackAccessory = "WreckingToolPack",
			HeldGear = "NeonWrench", AuraTrail = "NoneAura", SkinTone = "SkinWarmTan",
		},
	},
	{
		Id = "StreetDrifter", Name = "Street Drifter", Badge = "STREET",
		Loadout = {
			Outfit = "AsphaltBikerLeather", Headgear = "StuntCrashHelmet", BackAccessory = "BoomboxSpeaker",
			HeldGear = "NeonWrench", AuraTrail = "TireSmokeTrail", SkinTone = "SkinLightPeach",
		},
	},
	{
		Id = "DemoMechanic", Name = "Demo Mechanic", Badge = "FREE CREW",
		Loadout = {
			Outfit = "DemolitionJumpsuit", Headgear = "HardHatYellow", BackAccessory = "WreckingToolPack",
			HeldGear = "NeonWrench", AuraTrail = "NoneAura", SkinTone = "SkinDeepBronze",
		},
	},
	{
		Id = "CyberRacer", Name = "Cyber Racer", Badge = "PRO TECH",
		Loadout = {
			Outfit = "NeonCyberSuit", Headgear = "NeonVisorHelm", BackAccessory = "BoomboxSpeaker",
			HeldGear = "PlasmaFlareTorch", AuraTrail = "NeonVoltTrail", SkinTone = "SkinRobotChrome",
		},
	},
	{
		Id = "GoldenVIP", Name = "Golden VIP", Badge = "ROBUX VIP",
		Loadout = {
			Outfit = "GoldenSovereignArmor", Headgear = "CrownOfDestruction", BackAccessory = "ArchangelChaosWings",
			HeldGear = "GoldenWreckingHammer", AuraTrail = "CashShowerAura", SkinTone = "SkinGoldenOlive",
		},
	},
	{
		Id = "InfernoKing", Name = "Inferno King", Badge = "ROBUX BOSS",
		Loadout = {
			Outfit = "InfernoStuntSuit", Headgear = "CyberKitsuneMask", BackAccessory = "NitroThrusterJetpack",
			HeldGear = "GoldenWreckingHammer", AuraTrail = "SupernovaChaosAura", SkinTone = "SkinWarmTan",
		},
	},
}

function AvatarCatalog.GetDefaultLoadout(): AvatarLoadout
	return {
		Outfit = "LeoCreatorJacket",
		Headgear = "StreetSnapback",
		BackAccessory = "WreckingToolPack",
		HeldGear = "NeonWrench",
		AuraTrail = "NoneAura",
		SkinTone = "SkinWarmTan",
	}
end

function AvatarCatalog.GetItemsByCategory(category: string): { AvatarItem }
	local list = {}
	for _, item in pairs(AvatarCatalog.Items) do
		if item.Category == category then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		local order = { Free = 1, Cash = 2, Robux = 3 }
		if order[a.Currency] ~= order[b.Currency] then
			return order[a.Currency] < order[b.Currency]
		end
		if a.Price ~= b.Price then
			return a.Price < b.Price
		end
		return a.Name < b.Name
	end)
	return list
end

function AvatarCatalog.ComputePerks(loadout: AvatarLoadout)
	local cashMult = 1.0
	local xpMult = 1.0
	local sprintMult = 1.0
	local chaosMult = 1.0
	for _, itemId in pairs(loadout :: any) do
		local item = AvatarCatalog.Items[itemId]
		if item then
			cashMult += (item.CashMultiplierBonus or 0)
			xpMult += (item.XPMultiplierBonus or 0)
			sprintMult += (item.SprintBonus or 0)
			chaosMult += (item.ChaosBonus or 0)
		end
	end
	return {
		CashMult = cashMult,
		XPMult = xpMult,
		SprintMult = sprintMult,
		ChaosMult = chaosMult,
	}
end

local function weldPart(
	parent: Instance,
	target: BasePart,
	name: string,
	size: Vector3,
	color: Color3,
	mat: Enum.Material,
	offset: CFrame,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Massless = true
	p.Anchored = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = target.CFrame * offset
	p.Parent = parent
	local w = Instance.new("WeldConstraint")
	w.Part0 = target
	w.Part1 = p
	w.Parent = p
	return p
end

function AvatarCatalog.ApplyLoadoutToCharacter(character: Model, loadout: AvatarLoadout)
	if not character then return end
	local oldFolder = character:FindFirstChild("WODAvatarAttachments")
	if oldFolder then
		oldFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "WODAvatarAttachments"
	folder.Parent = character

	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	local rightHand = (character:FindFirstChild("RightHand") or character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")) :: BasePart?
	local leftArm = (character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")) :: BasePart?
	local rightArm = (character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")) :: BasePart?
	local leftLeg = (character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("Left Leg")) :: BasePart?
	local rightLeg = (character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("Right Leg")) :: BasePart?

	local skinItem = AvatarCatalog.Items[loadout.SkinTone or "SkinWarmTan"] or AvatarCatalog.Items.SkinWarmTan
	local outfitItem = AvatarCatalog.Items[loadout.Outfit or "LeoCreatorJacket"] or AvatarCatalog.Items.LeoCreatorJacket

	-- Apply skin tone & outfit colors across character limbs
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			local n = child.Name
			if n == "Head" or n:find("Hand") then
				child.Color = skinItem.PrimaryColor
			elseif n:find("Torso") or n:find("Arm") then
				child.Color = outfitItem.PrimaryColor
			elseif n:find("Leg") or n:find("Foot") then
				child.Color = outfitItem.PrimaryColor:Lerp(Color3.fromRGB(20, 24, 32), 0.35)
			end
		end
	end

	-- 1. Dramatic 3D Chest Cuirass Armor, Glowing Reactor Core, Shoulder Pauldrons & Limb Armor
	if torso then
		local tw = math.clamp(torso.Size.X, 1.6, 2.1)
		local th = math.clamp(torso.Size.Y, 1.4, 2.0)
		local td = math.clamp(torso.Size.Z, 0.85, 1.15)
		local armorMat = if outfitItem.Id == "GoldenSovereignArmor" or outfitItem.Id == "TacticalSWATSet" or outfitItem.Id == "NeonCyberSuit"
			then Enum.Material.Metal
			else Enum.Material.SmoothPlastic

		-- Contoured 3D Front & Back Armor Chestplate
		weldPart(
			folder,
			torso,
			"ChestArmorFront",
			Vector3.new(tw * 0.94, th * 0.82, 0.16),
			outfitItem.PrimaryColor,
			armorMat,
			CFrame.new(0, 0.06, -(td * 0.5 + 0.06))
		)
		weldPart(
			folder,
			torso,
			"ChestArmorCore",
			Vector3.new(0.46, 0.46, 0.22),
			outfitItem.AccentColor,
			Enum.Material.Neon,
			CFrame.new(0, th * 0.14, -(td * 0.5 + 0.09)) * CFrame.Angles(0, 0, math.rad(45))
		)
		weldPart(
			folder,
			torso,
			"ChestStripe",
			Vector3.new(tw * 0.88, 0.16, 0.18),
			outfitItem.AccentColor,
			Enum.Material.Neon,
			CFrame.new(0, th * 0.14, -(td * 0.5 + 0.07))
		)
		weldPart(
			folder,
			torso,
			"UtilityBelt",
			Vector3.new(tw * 1.04, 0.24, td * 1.06),
			outfitItem.AccentColor,
			Enum.Material.Metal,
			CFrame.new(0, -th * 0.42, 0)
		)

		-- Dramatic 3D Shoulder Pauldrons & Raised Collar Trim
		for _, sx in ipairs({ -1, 1 }) do
			weldPart(
				folder,
				torso,
				if sx < 0 then "CollarTrimL" else "CollarTrimR",
				Vector3.new(0.18, 0.28, td * 0.82),
				outfitItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(sx * (tw * 0.30), th * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-sx * 14))
			)
			weldPart(
				folder,
				torso,
				if sx < 0 then "LeftPauldron" else "RightPauldron",
				Vector3.new(0.68, 0.36, td * 1.08),
				outfitItem.PrimaryColor,
				Enum.Material.Metal,
				CFrame.new(sx * (tw * 0.58), th * 0.46, 0) * CFrame.Angles(0, 0, math.rad(-sx * 15))
			)
			weldPart(
				folder,
				torso,
				if sx < 0 then "LeftPauldronTrim" else "RightPauldronTrim",
				Vector3.new(0.72, 0.14, td * 1.12),
				outfitItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(sx * (tw * 0.60), th * 0.56, 0) * CFrame.Angles(0, 0, math.rad(-sx * 15))
			)
		end
	end

	-- 3D Arm Gauntlets & Shin Greaves so equipping any outfit visibly transforms the entire body!
	for _, armPart in ipairs({ leftArm, rightArm }) do
		if armPart then
			weldPart(
				folder,
				armPart,
				"ArmGauntlet",
				Vector3.new(armPart.Size.X + 0.14, 0.42, armPart.Size.Z + 0.14),
				outfitItem.AccentColor,
				Enum.Material.Metal,
				CFrame.new(0, -0.15, 0)
			)
		end
	end
	for _, legPart in ipairs({ leftLeg, rightLeg }) do
		if legPart then
			weldPart(
				folder,
				legPart,
				"ShinGreave",
				Vector3.new(legPart.Size.X + 0.12, 0.55, legPart.Size.Z + 0.14),
				outfitItem.AccentColor,
				Enum.Material.Metal,
				CFrame.new(0, 0, -0.04)
			)
		end
	end

	-- 2. Properly Scaled Headgear on Head
	local headItem = AvatarCatalog.Items[loadout.Headgear or "NoneHeadgear"]
	if head and headItem and headItem.Id ~= "NoneHeadgear" and headItem.Id ~= "None" then
		if headItem.Id == "CrownOfDestruction" then
			weldPart(
				folder,
				head,
				"CrownBand",
				Vector3.new(1.08, 0.24, 1.08),
				headItem.PrimaryColor,
				Enum.Material.Metal,
				CFrame.new(0, 0.56, 0)
			)
			for i = 0, 3 do
				local angle = math.rad(i * 90)
				weldPart(
					folder,
					head,
					"CrownSpire_" .. tostring(i),
					Vector3.new(0.20, 0.30, 0.12),
					headItem.PrimaryColor,
					Enum.Material.Metal,
					CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.72, -0.48)
				)
				weldPart(
					folder,
					head,
					"CrownGem_" .. tostring(i),
					Vector3.new(0.14, 0.14, 0.14),
					headItem.AccentColor,
					Enum.Material.Neon,
					CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.62, -0.53)
				)
			end
		elseif headItem.Id == "CyberKitsuneMask" then
			weldPart(
				folder,
				head,
				"MaskPlate",
				Vector3.new(1.06, 0.88, 0.22),
				headItem.PrimaryColor,
				Enum.Material.SmoothPlastic,
				CFrame.new(0, 0.04, -0.52)
			)
			weldPart(
				folder,
				head,
				"MaskVisorEyes",
				Vector3.new(0.88, 0.20, 0.08),
				headItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, 0.12, -0.62)
			)
			for _, sx in ipairs({ -1, 1 }) do
				weldPart(
					folder,
					head,
					if sx < 0 then "KitsuneEarL" else "KitsuneEarR",
					Vector3.new(0.22, 0.42, 0.16),
					headItem.AccentColor,
					Enum.Material.Neon,
					CFrame.new(sx * 0.38, 0.64, -0.25) * CFrame.Angles(math.rad(-10), 0, math.rad(-sx * 16))
				)
			end
		elseif headItem.Id == "NeonVisorHelm" or headItem.Id == "StuntCrashHelmet" then
			weldPart(
				folder,
				head,
				"HelmShell",
				Vector3.new(1.22, 1.16, 1.24),
				headItem.PrimaryColor,
				Enum.Material.SmoothPlastic,
				CFrame.new(0, 0.06, 0)
			)
			weldPart(
				folder,
				head,
				"HelmCrest",
				Vector3.new(0.22, 0.14, 1.12),
				headItem.AccentColor,
				Enum.Material.Metal,
				CFrame.new(0, 0.64, 0)
			)
			weldPart(
				folder,
				head,
				"HelmVisor",
				Vector3.new(1.06, 0.32, 0.14),
				headItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, 0.10, -0.58)
			)
		else
			-- Cap / HardHat
			weldPart(
				folder,
				head,
				"HatDome",
				Vector3.new(1.14, 0.42, 1.14),
				headItem.PrimaryColor,
				Enum.Material.SmoothPlastic,
				CFrame.new(0, 0.48, 0)
			)
			weldPart(
				folder,
				head,
				"HatBrim",
				Vector3.new(1.10, 0.10, 0.65),
				headItem.AccentColor,
				Enum.Material.SmoothPlastic,
				CFrame.new(0, 0.32, -0.62) * CFrame.Angles(math.rad(6), 0, 0)
			)
		end
	end

	-- 3. Compact Twin-Thruster Jetpack, Angled Cyber Wings & Sleek Backpacks on UpperTorso
	local backItem = AvatarCatalog.Items[loadout.BackAccessory or "NoneBack"]
	if torso and backItem and backItem.Id ~= "NoneBack" and backItem.Id ~= "None" then
		local td = math.clamp(torso.Size.Z, 0.85, 1.15)
		local backZ = td * 0.5 + 0.22

		if backItem.Id == "ArchangelChaosWings" then
			weldPart(
				folder,
				torso,
				"WingCore",
				Vector3.new(0.55, 0.78, 0.24),
				backItem.PrimaryColor,
				Enum.Material.Metal,
				CFrame.new(0, 0.15, backZ)
			)
			for _, sx in ipairs({ -1, 1 }) do
				local sideTag = if sx < 0 then "L" else "R"
				weldPart(
					folder,
					torso,
					"UpperWing_" .. sideTag,
					Vector3.new(1.65, 0.42, 0.10),
					backItem.PrimaryColor,
					Enum.Material.Metal,
					CFrame.new(sx * 0.95, 0.42, backZ + 0.10)
						* CFrame.Angles(0, math.rad(sx * 16), math.rad(sx * 22))
				)
				weldPart(
					folder,
					torso,
					"WingBladePrimary_" .. sideTag,
					Vector3.new(1.55, 0.24, 0.08),
					backItem.AccentColor,
					Enum.Material.Neon,
					CFrame.new(sx * 1.05, 0.16, backZ + 0.14)
						* CFrame.Angles(0, math.rad(sx * 16), math.rad(sx * 8))
				)
				weldPart(
					folder,
					torso,
					"WingBladeLower_" .. sideTag,
					Vector3.new(1.20, 0.20, 0.08),
					backItem.AccentColor,
					Enum.Material.Neon,
					CFrame.new(sx * 0.85, -0.12, backZ + 0.14)
						* CFrame.Angles(0, math.rad(sx * 16), math.rad(-sx * 8))
				)
			end
		elseif backItem.Id == "NitroThrusterJetpack" then
			weldPart(
				folder,
				torso,
				"JetCore",
				Vector3.new(0.95, 1.05, 0.36),
				backItem.PrimaryColor,
				Enum.Material.Metal,
				CFrame.new(0, 0.08, backZ)
			)
			weldPart(
				folder,
				torso,
				"JetCoreVents",
				Vector3.new(0.52, 0.65, 0.40),
				backItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, 0.12, backZ + 0.02)
			)
			for _, sx in ipairs({ -1, 1 }) do
				local sideTag = if sx < 0 then "L" else "R"
				local thruster = weldPart(
					folder,
					torso,
					"Thruster" .. sideTag,
					Vector3.new(1.12, 0.34, 0.34),
					backItem.PrimaryColor,
					Enum.Material.Metal,
					CFrame.new(sx * 0.36, 0.04, backZ + 0.12) * CFrame.Angles(0, 0, math.rad(90)),
					Enum.PartType.Cylinder
				)
				local nozzle = weldPart(
					folder,
					torso,
					"ThrusterNozzle" .. sideTag,
					Vector3.new(0.22, 0.28, 0.28),
					backItem.AccentColor,
					Enum.Material.Neon,
					CFrame.new(sx * 0.36, -0.56, backZ + 0.12) * CFrame.Angles(0, 0, math.rad(90)),
					Enum.PartType.Cylinder
				)
				local fire = Instance.new("ParticleEmitter")
				fire.Color = ColorSequence.new(backItem.AccentColor, Color3.fromRGB(255, 255, 255))
				fire.LightEmission = 1
				fire.Rate = 22
				fire.Speed = NumberRange.new(2.5, 5)
				fire.Lifetime = NumberRange.new(0.2, 0.4)
				fire.Size = NumberSequence.new(0.28, 0)
				fire.EmissionDirection = Enum.NormalId.Bottom
				fire.Parent = nozzle
				local _ = thruster
			end
		else
			-- Compact Tactical Pack / Boombox / Duffel
			weldPart(
				folder,
				torso,
				"BackpackMain",
				Vector3.new(1.08, 1.12, 0.42),
				backItem.PrimaryColor,
				Enum.Material.SmoothPlastic,
				CFrame.new(0, 0.06, backZ)
			)
			weldPart(
				folder,
				torso,
				"BackpackTrim",
				Vector3.new(1.12, 0.20, 0.45),
				backItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, 0.22, backZ + 0.02)
			)
		end
	end

	-- 4. Sleek Proportioned Tools in RightHand
	local heldItem = AvatarCatalog.Items[loadout.HeldGear or "NoneHeld"]
	if rightHand and heldItem and heldItem.Id ~= "NoneHeld" and heldItem.Id ~= "None" then
		-- Grip handle aligned cleanly in the hand extending forward (-Z)
		weldPart(
			folder,
			rightHand,
			"GearHandle",
			Vector3.new(0.14, 0.14, 1.55),
			heldItem.PrimaryColor,
			Enum.Material.Metal,
			CFrame.new(0, -0.12, -0.55)
		)
		weldPart(
			folder,
			rightHand,
			"GearPommel",
			Vector3.new(0.20, 0.20, 0.18),
			heldItem.AccentColor,
			Enum.Material.Metal,
			CFrame.new(0, -0.12, 0.24)
		)
		if heldItem.Id == "PlasmaFlareTorch" then
			weldPart(
				folder,
				rightHand,
				"GearBlade",
				Vector3.new(0.10, 0.24, 1.15),
				heldItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, -0.12, -1.55)
			)
		elseif heldItem.Id == "NeonWrench" then
			weldPart(
				folder,
				rightHand,
				"GearHead",
				Vector3.new(0.38, 0.16, 0.42),
				heldItem.AccentColor,
				Enum.Material.Neon,
				CFrame.new(0, -0.12, -1.35)
			)
		else
			-- DemolitionSledge or GoldenWreckingHammer
			weldPart(
				folder,
				rightHand,
				"GearHead",
				Vector3.new(0.58, 0.34, 0.36),
				heldItem.AccentColor,
				Enum.Material.Metal,
				CFrame.new(0, -0.12, -1.35)
			)
			weldPart(
				folder,
				rightHand,
				"GearHeadTrim",
				Vector3.new(0.62, 0.14, 0.16),
				heldItem.PrimaryColor,
				Enum.Material.Neon,
				CFrame.new(0, -0.12, -1.35)
			)
		end
	end

	-- 5. 3D Orbiting Aura Rings, Floating Shards & Particle Trail
	local auraItem = AvatarCatalog.Items[loadout.AuraTrail or "NoneAura"]
	if torso and auraItem and auraItem.Id ~= "NoneAura" and auraItem.Id ~= "None" then
		-- 3D Neon Halo Rings & Floating Energy Shards around the character (renders cleanly inside ViewportFrames too!)
		local ringLower = weldPart(
			folder,
			torso,
			"WODAura3D_LowerRing",
			Vector3.new(0.16, 3.6, 3.6),
			auraItem.PrimaryColor,
			Enum.Material.Neon,
			CFrame.new(0, -1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Enum.PartType.Cylinder
		)
		ringLower.Transparency = 0.45

		local ringMid = weldPart(
			folder,
			torso,
			"WODAura3D_OrbitRing",
			Vector3.new(0.12, 3.1, 3.1),
			auraItem.AccentColor,
			Enum.Material.Neon,
			CFrame.new(0, 0.1, 0) * CFrame.Angles(math.rad(22), 0, math.rad(72)),
			Enum.PartType.Cylinder
		)
		ringMid.Transparency = 0.35

		for idx = 1, 4 do
			local ang = math.rad(idx * 90)
			weldPart(
				folder,
				torso,
				"WODAura3D_Shard_" .. tostring(idx),
				Vector3.new(0.24, 0.58, 0.24),
				if idx % 2 == 0 then auraItem.PrimaryColor else auraItem.AccentColor,
				Enum.Material.Neon,
				CFrame.Angles(0, ang, 0) * CFrame.new(0, 0.3 + (idx % 2) * 0.4, -1.65) * CFrame.Angles(math.rad(18), 0, math.rad(25))
			)
		end

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "WODAuraEmitter"
		emitter.Color = ColorSequence.new(auraItem.PrimaryColor, auraItem.AccentColor)
		emitter.LightEmission = 0.85
		emitter.Rate = 24
		emitter.Lifetime = NumberRange.new(0.55, 1.0)
		emitter.Speed = NumberRange.new(1.5, 3.8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.42),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = torso
	end
end

-- Builds a standalone 3D Model preview for any AvatarItem or Preset to display inside an item card's ViewportFrame!
function AvatarCatalog.BuildItemPreviewModel(itemIdOrPresetId: string): Model
	local m = Instance.new("Model")
	m.Name = "Preview_" .. tostring(itemIdOrPresetId)

	local function makeAnchoredPart(name: string, size: Vector3, cf: CFrame, col: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = col
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p.Parent = m
		return p
	end

	-- Check if it's a Preset first
	for _, preset in ipairs(AvatarCatalog.Presets) do
		if preset.Id == itemIdOrPresetId then
			local torso = makeAnchoredPart("UpperTorso", Vector3.new(1.6, 1.4, 0.85), CFrame.new(0, 0, 0), Color3.fromRGB(45, 55, 72), Enum.Material.SmoothPlastic, nil)
			makeAnchoredPart("Head", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 1.35, 0), Color3.fromRGB(217, 160, 115), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			makeAnchoredPart("LeftUpperArm", Vector3.new(0.55, 1.2, 0.55), CFrame.new(-1.15, 0.05, 0), Color3.fromRGB(45, 55, 72), Enum.Material.SmoothPlastic, nil)
			makeAnchoredPart("RightUpperArm", Vector3.new(0.55, 1.2, 0.55), CFrame.new(1.15, 0.05, 0), Color3.fromRGB(45, 55, 72), Enum.Material.SmoothPlastic, nil)
			makeAnchoredPart("RightHand", Vector3.new(0.45, 0.45, 0.45), CFrame.new(1.15, -0.65, -0.2), Color3.fromRGB(217, 160, 115), Enum.Material.SmoothPlastic, nil)
			m.PrimaryPart = torso
			AvatarCatalog.ApplyLoadoutToCharacter(m, preset.Loadout)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			return m
		end
	end

	local item = AvatarCatalog.Items[itemIdOrPresetId]
	if not item then
		local fallback = makeAnchoredPart("Core", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0, 0), Color3.fromRGB(56, 189, 248), Enum.Material.Neon, Enum.PartType.Ball)
		m.PrimaryPart = fallback
		return m
	end

	local loadout = AvatarCatalog.GetDefaultLoadout()
	loadout.Headgear = "NoneHeadgear"
	loadout.BackAccessory = "NoneBack"
	loadout.HeldGear = "NoneHeld"
	loadout.AuraTrail = "NoneAura"
	(loadout :: any)[item.Category] = item.Id

	if item.Category == "Headgear" then
		local head = makeAnchoredPart("Head", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, -0.2, 0), Color3.fromRGB(70, 80, 98), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		m.PrimaryPart = head
		AvatarCatalog.ApplyLoadoutToCharacter(m, loadout)
	elseif item.Category == "BackAccessory" then
		local torso = makeAnchoredPart("UpperTorso", Vector3.new(1.4, 1.3, 0.75), CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(38, 46, 62), Enum.Material.SmoothPlastic, nil)
		torso.Transparency = 0.55
		m.PrimaryPart = torso
		AvatarCatalog.ApplyLoadoutToCharacter(m, loadout)
	elseif item.Category == "HeldGear" then
		local hand = makeAnchoredPart("RightHand", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 0.1, 0.65) * CFrame.Angles(math.rad(-35), math.rad(35), 0), Color3.fromRGB(60, 70, 88), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		hand.Transparency = 0.65
		m.PrimaryPart = hand
		AvatarCatalog.ApplyLoadoutToCharacter(m, loadout)
	else
		-- Outfit, AuraTrail, or SkinTone: build 3D upper mannequin bust
		local torso = makeAnchoredPart("UpperTorso", Vector3.new(1.65, 1.45, 0.85), CFrame.new(0, 0, 0), item.PrimaryColor, Enum.Material.SmoothPlastic, nil)
		makeAnchoredPart("Head", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.32, 0), Color3.fromRGB(217, 160, 115), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		makeAnchoredPart("LeftUpperArm", Vector3.new(0.56, 1.2, 0.56), CFrame.new(-1.18, 0.05, 0), item.PrimaryColor, Enum.Material.SmoothPlastic, nil)
		makeAnchoredPart("RightUpperArm", Vector3.new(0.56, 1.2, 0.56), CFrame.new(1.18, 0.05, 0), item.PrimaryColor, Enum.Material.SmoothPlastic, nil)
		m.PrimaryPart = torso
		AvatarCatalog.ApplyLoadoutToCharacter(m, loadout)
	end

	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return m
end

return AvatarCatalog
