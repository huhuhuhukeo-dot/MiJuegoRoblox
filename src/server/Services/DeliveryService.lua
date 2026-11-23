--[[
	DeliveryService (server)
	Parts tagged "DeliveryZone" accept loot while their PowerGroup is powered
	(or always, if they have no PowerGroup):
	  * Loot props (tag "Loot", e.g. money bags) inside the zone are delivered:
	    released from any hand, value added to the team, prop removed (the
	    arena reset re-creates it from its template).
	  * Players standing inside deliver their pocket loot.
	Detection uses spatial queries on a fixed interval (robust, unlike .Touched).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Contract = require(Shared.Interaction.Contract)
local Targeting = require(Shared.Interaction.Targeting)

local GrabService = require(script.Parent.GrabService)
local LootService = require(script.Parent.LootService)
local WorldStateService = require(script.Parent.WorldStateService)

local DeliveryService = {}

local CHECK_INTERVAL = 0.25
local ACTIVE_COLOR = Color3.fromRGB(60, 200, 90)
local INACTIVE_COLOR = Color3.fromRGB(200, 60, 60)

local notifyAll: (kind: string, data: any) -> () = function(_kind: string, _data: any) end

local function isActive(zone: BasePart): boolean
	local group = zone:GetAttribute(Contract.Attributes.PowerGroup)
	return WorldStateService.IsPowered(if type(group) == "string" then group else nil)
end

local function paint(zone: BasePart)
	local active = isActive(zone)
	zone.Color = if active then ACTIVE_COLOR else INACTIVE_COLOR
	zone:SetAttribute("Active", active)
end

local function deliverProp(prop: BasePart)
	if prop:GetAttribute("Delivered") == true then
		return
	end
	prop:SetAttribute("Delivered", true)
	local holder = GrabService.GetHolder(prop)
	GrabService.ForceRelease(prop, "Delivered")
	local value = prop:GetAttribute(Contract.Attributes.LootValue)
	value = if type(value) == "number" then math.max(0, value) else 0
	WorldStateService.AddTeamLoot(value)
	notifyAll("LootDelivered", { amount = value, by = holder and holder.DisplayName or nil })
	prop:Destroy()
end

local function checkZone(zone: BasePart)
	if not isActive(zone) then
		return
	end
	local params = OverlapParams.new()
	params.RespectCanCollide = false
	params.MaxParts = 50
	local seen: { [BasePart]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, params) do
		if part == zone then
			continue
		end
		local prop = Targeting.findGrabbable(part)
		if prop and not seen[prop] and CollectionService:HasTag(prop, Contract.Tags.Loot) then
			seen[prop] = true
			deliverProp(prop)
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local rel = zone.CFrame:PointToObjectSpace(root.Position)
			local half = zone.Size * 0.5
			if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 3 and math.abs(rel.Z) <= half.Z then
				local amount = LootService.DeliverPocket(player)
				if amount > 0 then
					notifyAll("LootDelivered", { amount = amount, by = player.DisplayName })
				end
			end
		end
	end
end

function DeliveryService.Init(notifyAllFn: (kind: string, data: any) -> ())
	notifyAll = notifyAllFn
	local function onZone(inst: Instance)
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			paint(inst)
		end
	end
	for _, z in CollectionService:GetTagged(Contract.Tags.DeliveryZone) do
		onZone(z)
	end
	CollectionService:GetInstanceAddedSignal(Contract.Tags.DeliveryZone):Connect(onZone)
	WorldStateService.PowerChanged:Connect(function()
		for _, z in CollectionService:GetTagged(Contract.Tags.DeliveryZone) do
			onZone(z)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, z in CollectionService:GetTagged(Contract.Tags.DeliveryZone) do
				if z:IsA("BasePart") and z:IsDescendantOf(workspace) then
					checkZone(z)
				end
			end
		end
	end)
end

return DeliveryService
