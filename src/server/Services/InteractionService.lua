--[[
	InteractionService (server, authoritative)
	One generic system for every interactive object. Behaviour lives in
	modules under Server/Interactions; each module implements this contract:

	  export type InteractionModule = {
	      Type: string,                          -- matches attribute InteractionType
	      Range: number?,                        -- overrides Config.Interaction.Range
	      Cooldown: number?,                     -- per instance, seconds
	      Setup: (inst, ctx) -> (),              -- once, when the instance appears
	      Cleanup: ((inst, ctx) -> ())?,         -- when it leaves the world
	      CanInteract: ((player, inst, ctx) -> (boolean, string?))?,
	      Interact: (player, inst, ctx) -> (),
	      OnGrabStarted: ((player, inst, part, ctx) -> ())?, -- a part of inst was grabbed
	      OnGrabEnded: ((player, inst, part, ctx) -> ())?,
	      OnReset: ((inst, ctx) -> ())?,         -- arena reset
	  }

	Adding a new interaction = adding one module file. No per-object scripts.
	The service validates rate, alive state, range, line of sight, enabled flag
	and cooldowns before any module code runs.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)
local Targeting = require(Shared.Interaction.Targeting)
local Remotes = require(Shared.Net.Remotes)
local RateLimiter = require(Shared.Util.RateLimiter)

local InteractionService = {}

local Attr = Contract.Attributes
local modules: { [string]: any } = {}
local active: { [Instance]: any } = {} -- instance -> module
local lastUse: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local limiter = RateLimiter.new(Config.RateLimits.InteractRequest.Rate, Config.RateLimits.InteractRequest.Burst)
local ctx: any

local function loadModules(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok and type(mod) == "table" and type(mod.Type) == "string" then
				modules[mod.Type] = mod
			elseif not ok then
				warn("[InteractionService] failed to load " .. child.Name .. ": " .. tostring(mod))
			end
			-- helper modules without Type (e.g. ArticulatedJoint) are skipped
		end
	end
end

local function safeCall(label: string, fn: any, ...: any): (boolean, any, any)
	if type(fn) ~= "function" then
		return true, nil, nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		warn(string.format("[InteractionService] %s error: %s", label, tostring(a)))
	end
	return ok, a, b
end

local function setupInstance(inst: Instance)
	if active[inst] or not inst:IsDescendantOf(workspace) then
		return
	end
	local kind = inst:GetAttribute(Attr.InteractionType)
	local mod = type(kind) == "string" and modules[kind]
	if not mod then
		warn("[InteractionService] unknown InteractionType on " .. inst:GetFullName() .. ": " .. tostring(kind))
		return
	end
	active[inst] = mod
	if inst:GetAttribute(Attr.InteractEnabled) == nil then
		inst:SetAttribute(Attr.InteractEnabled, true)
	end
	safeCall(kind .. ".Setup", mod.Setup, inst, ctx)
end

local function cleanupInstance(inst: Instance)
	local mod = active[inst]
	if mod then
		active[inst] = nil
		safeCall(mod.Type .. ".Cleanup", mod.Cleanup, inst, ctx)
	end
end

local function playerContext(player: Player): (Model?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if character == nil or humanoid == nil or humanoid.Health <= 0 or head == nil or not head:IsA("BasePart") then
		return nil, nil
	end
	return character, head
end

local function hasLineOfSight(character: Model, from: Vector3, to: Vector3, inst: Instance): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(from, to - from, params)
	if result == nil then
		return true
	end
	local hit = result.Instance
	return hit == inst or hit:IsDescendantOf(inst) or (result.Position - to).Magnitude < 0.4
end

-- Validates and executes an interaction. Exposed for tests / other services.
function InteractionService.TryInteract(player: Player, target: any): (boolean, string?)
	if typeof(target) ~= "Instance" or not target:IsDescendantOf(workspace) then
		return false, "InvalidTarget"
	end
	local mod = active[target]
	if mod == nil then
		return false, "NotInteractable"
	end
	if target:GetAttribute(Attr.InteractEnabled) == false then
		return false, "Disabled"
	end
	local character, head = playerContext(player)
	if character == nil or head == nil then
		return false, "NotAlive"
	end
	local point = Targeting.closestPoint(target, head.Position)
	if point == nil then
		return false, "NoGeometry"
	end
	local range = (mod.Range or Config.Interaction.Range) + Config.Interaction.ServerRangeTolerance
	if (point - head.Position).Magnitude > range then
		return false, "TooFar"
	end
	if not hasLineOfSight(character, head.Position, point, target) then
		return false, "Obstructed"
	end
	local now = os.clock()
	local cooldown = mod.Cooldown or Config.Interaction.DefaultCooldown
	if lastUse[target] and now - lastUse[target] < cooldown then
		return false, "Cooldown"
	end
	if mod.CanInteract then
		local ok, allowed, reason = safeCall(mod.Type .. ".CanInteract", mod.CanInteract, player, target, ctx)
		if not ok or not allowed then
			if reason then
				ctx.Notify(player, reason)
			end
			return false, reason or "Denied"
		end
	end
	lastUse[target] = now
	local ok = safeCall(mod.Type .. ".Interact", mod.Interact, player, target, ctx)
	return ok, nil
end

-- Finds the interactable owning a grabbed part and forwards grab events.
local function forwardGrab(hook: string, player: Player, part: BasePart)
	local inst = Targeting.findInteractable(part)
	local mod = inst and active[inst]
	if mod and mod[hook] then
		safeCall(mod.Type .. "." .. hook, mod[hook], player, inst, part, ctx)
	end
end

function InteractionService.Init(context)
	ctx = context
	local folder = script.Parent.Parent:FindFirstChild("Interactions")
	assert(folder, "Server/Interactions folder missing")
	loadModules(folder)

	for _, inst in CollectionService:GetTagged(Contract.Tags.Interactable) do
		setupInstance(inst)
	end
	CollectionService:GetInstanceAddedSignal(Contract.Tags.Interactable):Connect(setupInstance)
	CollectionService:GetInstanceRemovedSignal(Contract.Tags.Interactable):Connect(cleanupInstance)
	-- instances parked in storage / destroyed
	task.spawn(function()
		while true do
			task.wait(2)
			for inst in active do
				if not inst:IsDescendantOf(workspace) then
					cleanupInstance(inst)
				end
			end
			for _, inst in CollectionService:GetTagged(Contract.Tags.Interactable) do
				if not active[inst] and inst:IsDescendantOf(workspace) then
					setupInstance(inst) -- e.g. a collectible returned to the world
				end
			end
		end
	end)

	Remotes.Get("InteractRequest").OnServerEvent:Connect(function(player: Player, target: any)
		if not limiter:Check(player) then
			return
		end
		InteractionService.TryInteract(player, target)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Remove(player)
	end)

	ctx.Grab.GrabStarted:Connect(function(player, part)
		forwardGrab("OnGrabStarted", player, part)
	end)
	ctx.Grab.GrabEnded:Connect(function(player, part)
		forwardGrab("OnGrabEnded", player, part)
	end)
	ctx.World.ResetRequested:Connect(function()
		for inst, mod in active do
			safeCall(mod.Type .. ".OnReset", mod.OnReset, inst, ctx)
		end
	end)
end

return InteractionService
