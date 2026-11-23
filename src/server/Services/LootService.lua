--[[
	LootService (server)
	Small collectibles go to the player's pocket (Player attribute PocketLoot).
	Pocket loot is delivered by standing in an active delivery zone.
	Collected items are never destroyed: they are parked in ServerStorage so
	they can be returned to the world if the carrier dies / leaves, and
	restored by the arena reset.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Contract = require(Shared.Interaction.Contract)

local WorldStateService = require(script.Parent.WorldStateService)

local LootService = {}

type Stored = { item: Instance, parent: Instance, pivot: CFrame, value: number }

local pockets: { [Player]: { Stored } } = {}
local consumed: { Stored } = {}
local storage: Folder

local function pivotOf(item: Instance): CFrame
	if item:IsA("BasePart") then
		return item.CFrame
	elseif item:IsA("Model") then
		return item:GetPivot()
	end
	return CFrame.identity
end

local function restore(entry: Stored)
	if entry.parent.Parent == nil and entry.parent ~= workspace then
		entry.parent = workspace
	end
	entry.item.Parent = entry.parent
	if entry.item:IsA("BasePart") then
		entry.item.AssemblyLinearVelocity = Vector3.zero
		entry.item.CFrame = entry.pivot
	elseif entry.item:IsA("Model") then
		entry.item:PivotTo(entry.pivot)
	end
end

local function updateAttribute(player: Player)
	local total = 0
	for _, e in pockets[player] or {} do
		total += e.value
	end
	player:SetAttribute(Contract.Attributes.PocketLoot, total)
end

function LootService.Init()
	storage = Instance.new("Folder")
	storage.Name = "CollectedItems"
	storage.Parent = ServerStorage
	WorldStateService.ResetRequested:Connect(LootService.ResetAll)
end

-- Moves `item` into the player's pocket. Returns the value collected.
function LootService.Collect(player: Player, item: Instance): number
	local value = item:GetAttribute(Contract.Attributes.LootValue)
	value = if type(value) == "number" then math.max(0, value) else 0
	local entry: Stored = { item = item, parent = item.Parent :: Instance, pivot = pivotOf(item), value = value }
	pockets[player] = pockets[player] or {}
	table.insert(pockets[player], entry)
	item.Parent = storage
	updateAttribute(player)
	return value
end

-- Returns collected items to where they were found (death / disconnect).
function LootService.DropPocket(player: Player, _reason: string?)
	local list = pockets[player]
	pockets[player] = nil
	if list then
		for _, entry in list do
			restore(entry)
		end
	end
	if player.Parent then
		player:SetAttribute(Contract.Attributes.PocketLoot, 0)
	end
end

-- Converts pocket loot into team loot. Returns the amount delivered.
function LootService.DeliverPocket(player: Player): number
	local list = pockets[player]
	if list == nil or #list == 0 then
		return 0
	end
	pockets[player] = nil
	local total = 0
	for _, entry in list do
		total += entry.value
		table.insert(consumed, entry)
	end
	WorldStateService.AddTeamLoot(total)
	updateAttribute(player)
	return total
end

function LootService.ResetAll()
	for player in pockets do
		LootService.DropPocket(player, "Reset")
	end
	for _, entry in consumed do
		restore(entry)
	end
	table.clear(consumed)
end

return LootService
