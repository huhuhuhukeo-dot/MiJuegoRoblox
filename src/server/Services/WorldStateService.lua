--[[
	WorldStateService
	Shared, replicated world state: power groups and the team's delivered loot.
	State lives as attributes on ReplicatedStorage.GameState so every client
	(including late joiners) reads the same values without extra remotes.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Contract = require(Shared.Interaction.Contract)
local Signal = require(Shared.Util.Signal)

local WorldStateService = {}
WorldStateService.PowerChanged = Signal.new() -- (group: string, on: boolean)
WorldStateService.ResetRequested = Signal.new() -- ()

local stateFolder: Folder

local function powerKey(group: string): string
	return "Power_" .. group
end

local function applyLight(part: BasePart, on: boolean)
	for _, d in part:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = on
		end
	end
	part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

function WorldStateService.Init()
	stateFolder = ReplicatedStorage:FindFirstChild(Contract.Names.GameState) :: Folder
	if stateFolder == nil then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = Contract.Names.GameState
		stateFolder.Parent = ReplicatedStorage
	end
	stateFolder:SetAttribute("TeamLoot", 0)

	local function onLight(inst: Instance)
		if inst:IsA("BasePart") then
			local group = inst:GetAttribute(Contract.Attributes.PowerGroup)
			if type(group) == "string" then
				applyLight(inst, WorldStateService.IsPowered(group))
			end
		end
	end
	for _, inst in CollectionService:GetTagged(Contract.Tags.PoweredLight) do
		onLight(inst)
	end
	CollectionService:GetInstanceAddedSignal(Contract.Tags.PoweredLight):Connect(onLight)
end

function WorldStateService.IsPowered(group: string?): boolean
	if group == nil or group == "" then
		return true -- ungrouped devices are always powered
	end
	return stateFolder:GetAttribute(powerKey(group)) == true
end

function WorldStateService.SetPower(group: string, on: boolean)
	if WorldStateService.IsPowered(group) == on then
		return
	end
	stateFolder:SetAttribute(powerKey(group), on)
	for _, inst in CollectionService:GetTagged(Contract.Tags.PoweredLight) do
		if inst:IsA("BasePart") and inst:GetAttribute(Contract.Attributes.PowerGroup) == group then
			applyLight(inst, on)
		end
	end
	WorldStateService.PowerChanged:Fire(group, on)
end

function WorldStateService.AddTeamLoot(amount: number)
	stateFolder:SetAttribute("TeamLoot", (stateFolder:GetAttribute("TeamLoot") or 0) + amount)
end

function WorldStateService.ResetAll()
	stateFolder:SetAttribute("TeamLoot", 0)
	for name in stateFolder:GetAttributes() do
		if string.sub(name, 1, 6) == "Power_" then
			WorldStateService.SetPower(string.sub(name, 7), false)
		end
	end
	WorldStateService.ResetRequested:Fire()
end

return WorldStateService
