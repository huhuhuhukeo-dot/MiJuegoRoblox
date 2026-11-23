--[[
	RecoveryService (server)
	Keeps physical props from being lost:
	  * remembers each Grabbable prop's spawn CFrame and a pristine template
	  * returns props that fall out of the world (below KillY)
	  * ResetAll(): every prop back to its spawn, delivered/destroyed props are
	    re-created from their template, props spawned at runtime are removed
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local GrabService = require(script.Parent.GrabService)
local WorldStateService = require(script.Parent.WorldStateService)

local RecoveryService = {}

type Entry = { id: string, current: BasePart?, spawn: CFrame, parent: Instance, template: BasePart }

local entries: { [string]: Entry } = {}
local spawned: { [BasePart]: CFrame } = {}
local templates: Folder

local function resetPhysics(part: BasePart, cf: CFrame)
	GrabService.ForceRelease(part, "Recovered")
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = cf
	if not part.Anchored then
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end
end

local function register(inst: Instance)
	if not inst:IsA("BasePart") or not inst:IsDescendantOf(workspace) then
		return -- templates/collected items in storage are ignored
	end
	if inst:GetAttribute(Contract.Attributes.Articulated) == true then
		return -- doors & drawers are anchored to their frames
	end
	if inst:GetAttribute("Spawned") == true then
		if spawned[inst] == nil then
			spawned[inst] = inst.CFrame
		end
		return
	end
	local id = inst:GetAttribute(Contract.Attributes.PropId)
	if type(id) ~= "string" or id == "" then
		id = HttpService:GenerateGUID(false)
		inst:SetAttribute(Contract.Attributes.PropId, id)
	end
	local existing = entries[id]
	if existing then
		existing.current = inst -- re-created from template
		return
	end
	local template = inst:Clone()
	template.Parent = templates
	entries[id] = {
		id = id,
		current = inst,
		spawn = inst.CFrame,
		parent = inst.Parent :: Instance,
		template = template,
	}
end

function RecoveryService.Init()
	templates = Instance.new("Folder")
	templates.Name = "PropTemplates"
	templates.Parent = ServerStorage

	for _, inst in CollectionService:GetTagged(Contract.Tags.Grabbable) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Contract.Tags.Grabbable):Connect(register)
	WorldStateService.ResetRequested:Connect(RecoveryService.ResetAll)

	task.spawn(function()
		while true do
			task.wait(Config.Recovery.CheckInterval)
			for _, entry in entries do
				local part = entry.current
				if part and part.Parent and part:IsDescendantOf(workspace) and part.Position.Y < Config.Recovery.KillY then
					resetPhysics(part, entry.spawn)
				end
			end
			for part, cf in spawned do
				if part.Parent == nil then
					spawned[part] = nil
				elseif part.Position.Y < Config.Recovery.KillY then
					resetPhysics(part, cf)
				end
			end
		end
	end)
end

-- Marks a runtime-spawned prop (e.g. container contents) before parenting it.
function RecoveryService.MarkSpawned(part: BasePart)
	part:SetAttribute("Spawned", true)
end

function RecoveryService.ResetAll()
	for part in spawned do
		GrabService.ForceRelease(part, "Reset")
		part:Destroy()
	end
	table.clear(spawned)
	for _, entry in entries do
		local part = entry.current
		if part and part.Parent and part:IsDescendantOf(workspace) then
			resetPhysics(part, entry.spawn)
		else
			if part then
				part:Destroy()
			end
			local fresh = entry.template:Clone()
			fresh.CFrame = entry.spawn
			entry.current = fresh
			fresh.Parent = if entry.parent.Parent then entry.parent else workspace
		end
	end
end

return RecoveryService
