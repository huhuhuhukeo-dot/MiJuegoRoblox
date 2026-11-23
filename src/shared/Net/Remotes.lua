--[[
	Remotes
	Declares every remote used by the game in ONE place. The server creates
	them at boot (Remotes.Init); clients obtain them with Remotes.Get, which
	waits until they replicate.

	Direction & payloads (all arguments are validated on the server):
	  GrabRequest     RemoteFunction  C->S (part: BasePart, localPoint: Vector3) -> (ok, modeOrReason)
	  ReleaseRequest  RemoteEvent     C->S ()
	  InteractRequest RemoteEvent     C->S (target: Instance)
	  MovementState   RemoteEvent     C->S (crouching: boolean, sprinting: boolean)
	  Notify          RemoteEvent     S->C (kind: string, data: any)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contract = require(script.Parent.Parent.Interaction.Contract)

local Remotes = {}

local DEFINITIONS = {
	GrabRequest = "RemoteFunction",
	ReleaseRequest = "RemoteEvent",
	InteractRequest = "RemoteEvent",
	MovementState = "RemoteEvent",
	Notify = "RemoteEvent",
}

local cache: { [string]: Instance } = {}

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init is server-only")
	local folder = ReplicatedStorage:FindFirstChild(Contract.Names.RemotesFolder)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = Contract.Names.RemotesFolder
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		local remote = folder:FindFirstChild(name)
		if remote == nil then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		cache[name] = remote
	end
end

function Remotes.Get(name: string): any
	local cached = cache[name]
	if cached then
		return cached
	end
	assert(DEFINITIONS[name], "Unknown remote: " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild(Contract.Names.RemotesFolder, 30)
	assert(folder, "Remotes folder did not replicate")
	local remote = folder:WaitForChild(name, 30)
	assert(remote, "Remote did not replicate: " .. name)
	cache[name] = remote
	return remote
end

return Remotes
