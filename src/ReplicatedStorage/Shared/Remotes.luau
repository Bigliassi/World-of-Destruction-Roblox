--!strict
--[[
	Remotes.luau
	Auto-creates (on Server) or fetches (on Client) the `Remotes` folder in
	`ReplicatedStorage` with all RemoteEvent and RemoteFunction instances needed
	across World of Destruction.

	All 13 core remotes:
	  - DamageDealt       (RemoteEvent)
	  - ComboUpdated      (RemoteEvent)
	  - WalletUpdated     (RemoteEvent)
	  - HeatUpdated       (RemoteEvent)
	  - VehicleEntered    (RemoteEvent)
	  - VehicleExited     (RemoteEvent)
	  - PurchaseUpgrade   (RemoteFunction)
	  - SelectVehicle     (RemoteFunction)
	  - SpawnVehicle      (RemoteEvent)
	  - RepairVehicle     (RemoteEvent)
	  - Notification      (RemoteEvent)
	  - ExplosionEffect   (RemoteEvent)
	  - PoliceBusted      (RemoteEvent)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local IS_SERVER = RunService:IsServer()

export type RemoteSpec = {
	Name: string,
	ClassName: "RemoteEvent" | "RemoteFunction",
}

local REMOTE_SPECS: { RemoteSpec } = {
	{ Name = "DamageDealt", ClassName = "RemoteEvent" },
	{ Name = "ComboUpdated", ClassName = "RemoteEvent" },
	{ Name = "WalletUpdated", ClassName = "RemoteEvent" },
	{ Name = "HeatUpdated", ClassName = "RemoteEvent" },
	{ Name = "VehicleEntered", ClassName = "RemoteEvent" },
	{ Name = "VehicleExited", ClassName = "RemoteEvent" },
	{ Name = "PurchaseUpgrade", ClassName = "RemoteFunction" },
	{ Name = "SelectVehicle", ClassName = "RemoteFunction" },
	{ Name = "SpawnVehicle", ClassName = "RemoteEvent" },
	{ Name = "RepairVehicle", ClassName = "RemoteEvent" },
	{ Name = "Notification", ClassName = "RemoteEvent" },
	{ Name = "ExplosionEffect", ClassName = "RemoteEvent" },
	{ Name = "PoliceBusted", ClassName = "RemoteEvent" },
}

local SPEC_BY_NAME: { [string]: RemoteSpec } = {}
for _, spec in ipairs(REMOTE_SPECS) do
	SPEC_BY_NAME[spec.Name] = spec
end

local Remotes = {}
Remotes.Names = {
	DamageDealt = "DamageDealt",
	ComboUpdated = "ComboUpdated",
	WalletUpdated = "WalletUpdated",
	HeatUpdated = "HeatUpdated",
	VehicleEntered = "VehicleEntered",
	VehicleExited = "VehicleExited",
	PurchaseUpgrade = "PurchaseUpgrade",
	SelectVehicle = "SelectVehicle",
	SpawnVehicle = "SpawnVehicle",
	RepairVehicle = "RepairVehicle",
	Notification = "Notification",
	ExplosionEffect = "ExplosionEffect",
	PoliceBusted = "PoliceBusted",
}

Remotes.Events = {} :: { [string]: RemoteEvent }
Remotes.Functions = {} :: { [string]: RemoteFunction }

local remotesFolder: Folder? = nil

local function normalizeName(arg1: any, arg2: any): string
	if type(arg1) == "table" and type(arg2) == "string" then
		return arg2
	end
	return tostring(arg1)
end

local function ensureFolder(): Folder
	if remotesFolder and remotesFolder.Parent then
		return remotesFolder
	end

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end

	if IS_SERVER then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		remotesFolder = folder
		return folder
	else
		local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)
		if waited and waited:IsA("Folder") then
			remotesFolder = waited
			return waited
		end
		local fallback = Instance.new("Folder")
		fallback.Name = FOLDER_NAME
		fallback.Parent = ReplicatedStorage
		remotesFolder = fallback
		return fallback
	end
end

local function ensureRemote(name: string, className: ("RemoteEvent" | "RemoteFunction")?): Instance
	local folder = ensureFolder()
	local targetClass = className or (SPEC_BY_NAME[name] and SPEC_BY_NAME[name].ClassName) or "RemoteEvent"

	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end

	if IS_SERVER then
		local inst = Instance.new(targetClass)
		inst.Name = name
		inst.Parent = folder
		return inst
	else
		local waited = folder:WaitForChild(name, 10)
		if waited then
			return waited
		end
		local inst = Instance.new(targetClass)
		inst.Name = name
		inst.Parent = folder
		return inst
	end
end

function Remotes.GetFolder(_self: any?): Folder
	return ensureFolder()
end

function Remotes.Get(arg1: any, arg2: any): any
	local name = normalizeName(arg1, arg2)
	return ensureRemote(name, nil)
end

function Remotes.GetEvent(arg1: any, arg2: any): RemoteEvent
	local name = normalizeName(arg1, arg2)
	local inst = ensureRemote(name, "RemoteEvent")
	return inst :: RemoteEvent
end

function Remotes.GetFunction(arg1: any, arg2: any): RemoteFunction
	local name = normalizeName(arg1, arg2)
	local inst = ensureRemote(name, "RemoteFunction")
	return inst :: RemoteFunction
end

function Remotes.Init(_self: any?)
	local folder = ensureFolder()
	Remotes.Folder = folder

	for _, spec in ipairs(REMOTE_SPECS) do
		local inst = ensureRemote(spec.Name, spec.ClassName)
		rawset(Remotes :: any, spec.Name, inst)
		if inst:IsA("RemoteEvent") then
			Remotes.Events[spec.Name] = inst
		elseif inst:IsA("RemoteFunction") then
			Remotes.Functions[spec.Name] = inst
		end
	end

	return Remotes
end

-- Auto-initialize on require so scripts can immediately access `Remotes.DamageDealt`, etc.
Remotes.Init()

-- Dynamic fallback lookup so `Remotes.<AnyCustomRemote>` resolves from ReplicatedStorage.Remotes
setmetatable(Remotes :: any, {
	__index = function(tbl, key)
		if type(key) == "string" then
			local inst = ensureRemote(key, nil)
			rawset(tbl, key, inst)
			return inst
		end
		return nil
	end,
})

return Remotes
