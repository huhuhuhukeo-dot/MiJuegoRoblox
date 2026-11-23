--[[
	GrabService (server, authoritative)
	Grab / lift / drag / release of physical props.

	Flow
	  1. Client raycasts and calls GrabRequest(part, localPoint).
	  2. Server validates: tag, state, alive, distance head->point, line of sight,
	     not held by anyone, mass/size limits, rate limit.
	  3. Server creates a GrabAttachment on the prop and constraints that pull it
	     toward the player's PhysicsHand attachment:
	        Lift        AlignPosition (magnitude limited) + AlignOrientation
	        Drag        AlignPosition with PER-AXIS limits: vertical force < weight
	        Articulated AlignPosition only (doors/drawers keep their joint)
	     Forces are finite, so props collide with walls instead of passing through.
	  4. Ownership of the prop goes to the holder for lag-free simulation. The
	     server watches distance and speed every ServerCheckInterval and takes the
	     object back (release, return ownership, rewind) if anything is off.
	  5. Release removes constraints, keeps the holder as owner briefly (smooth
	     throw), restores collisions once no character overlaps, then returns
	     ownership to the server.

	Exactly one holder per prop (heldBy map + HeldBy attribute); a player holds
	at most one prop. Death, respawn and disconnect release everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)
local Targeting = require(Shared.Interaction.Targeting)
local GrabMath = require(Shared.Physics.GrabMath)
local Validate = require(Shared.Net.Validate)
local Remotes = require(Shared.Net.Remotes)
local RateLimiter = require(Shared.Util.RateLimiter)
local Signal = require(Shared.Util.Signal)

local HandService = require(script.Parent.HandService)

local GrabService = {}
GrabService.GrabStarted = Signal.new() -- (player, part, mode)
GrabService.GrabEnded = Signal.new() -- (player, part, reason)

local GrabCfg = Config.Grab
local Attr = Contract.Attributes

type Hold = {
	player: Player,
	part: BasePart,
	mode: string,
	mass: number,
	attachment: Attachment,
	constraints: { Instance },
	savedGroups: { [BasePart]: string },
	lastValidCFrame: CFrame,
	strikes: number,
}

local holdsByPlayer: { [Player]: Hold } = {}
local holdsByPart: { [BasePart]: Hold } = {}
local releaseGeneration: { [BasePart]: number } = {}

local grabLimiter = RateLimiter.new(Config.RateLimits.GrabRequest.Rate, Config.RateLimits.GrabRequest.Burst)
local releaseLimiter = RateLimiter.new(Config.RateLimits.ReleaseRequest.Rate, Config.RateLimits.ReleaseRequest.Burst)

local function getCharacterParts(player: Player): (Model?, Humanoid?, BasePart?, BasePart?)
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil, nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or head == nil then
		return nil, nil, nil, nil
	end
	return character, humanoid, root :: BasePart, head :: BasePart
end

local function heldValue(character: Model): ObjectValue
	local v = character:FindFirstChild(Contract.Names.HeldObjectValue)
	if v and v:IsA("ObjectValue") then
		return v
	end
	local created = Instance.new("ObjectValue")
	created.Name = Contract.Names.HeldObjectValue
	created.Parent = character
	return created
end

local function setOwner(part: BasePart, owner: Player?)
	if part.Anchored or part.Parent == nil then
		return
	end
	pcall(function()
		part:SetNetworkOwner(owner)
	end)
end

local function hasLineOfSight(character: Model, from: Vector3, to: Vector3, target: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local dir = to - from
	local result = workspace:Raycast(from, dir, params)
	if result == nil then
		return true
	end
	local hit = result.Instance
	if hit == target or hit:IsDescendantOf(target) or hit.AssemblyRootPart == target.AssemblyRootPart then
		return true
	end
	-- something else is in the way, unless it is right at the grab point
	return (result.Position - to).Magnitude < 0.35
end

local function assemblyParts(part: BasePart): { BasePart }
	return part:GetConnectedParts(true)
end

local function setHeldCollision(hold: Hold)
	for _, p in assemblyParts(hold.part) do
		if p.Anchored then
			continue
		end
		hold.savedGroups[p] = p.CollisionGroup
		p.CollisionGroup = Contract.CollisionGroups.Held
	end
end

local function overlapsCharacter(parts: { BasePart }): boolean
	local characters = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(characters, plr.Character)
		end
	end
	if #characters == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = characters
	params.MaxParts = 1
	for _, p in parts do
		if p.Parent and #workspace:GetPartsInPart(p, params) > 0 then
			return true
		end
	end
	return false
end

-- Restores collisions once the prop no longer overlaps any character, then
-- gives simulation ownership back to the server.
local function scheduleRestore(part: BasePart, savedGroups: { [BasePart]: string })
	local generation = (releaseGeneration[part] or 0) + 1
	releaseGeneration[part] = generation
	task.spawn(function()
		local started = os.clock()
		local parts = {}
		for p in savedGroups do
			table.insert(parts, p)
		end
		while os.clock() - started < GrabCfg.ReleaseCollisionMaxWait do
			if releaseGeneration[part] ~= generation or holdsByPart[part] then
				return -- grabbed again, the new hold owns the collision state
			end
			if not overlapsCharacter(parts) then
				break
			end
			task.wait(0.1)
		end
		if releaseGeneration[part] ~= generation or holdsByPart[part] then
			return
		end
		for p, group in savedGroups do
			if p.Parent then
				p.CollisionGroup = group
			end
		end
		local remaining = GrabCfg.ReleaseOwnershipDelay - (os.clock() - started)
		if remaining > 0 then
			task.wait(remaining)
		end
		if releaseGeneration[part] == generation and holdsByPart[part] == nil and part.Parent then
			setOwner(part, nil) -- server owns idle props: clients cannot tamper with them
		end
	end)
end

local function buildConstraints(hold: Hold, handAttachment: Attachment, worldPoint: Vector3)
	local part = hold.part
	local gravity = workspace.Gravity

	local attachment = Instance.new("Attachment")
	attachment.Name = Contract.Names.GrabAttachment
	attachment.Parent = part
	-- keep the current relative orientation between hand and object
	attachment.WorldCFrame = CFrame.new(worldPoint) * handAttachment.WorldCFrame.Rotation
	hold.attachment = attachment

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "GrabAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.Attachment1 = handAttachment
	alignPosition.RigidityEnabled = false
	alignPosition.ReactionForceEnabled = false -- the object never yanks the player

	if hold.mode == "Lift" then
		local p = GrabMath.liftParams(hold.mass, gravity, GrabCfg)
		alignPosition.ApplyAtCenterOfMass = true
		alignPosition.MaxForce = p.MaxForce
		alignPosition.Responsiveness = p.Responsiveness
		alignPosition.MaxVelocity = p.MaxVelocity

		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "GrabAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOrientation.Attachment0 = attachment
		alignOrientation.Attachment1 = handAttachment
		alignOrientation.RigidityEnabled = false
		alignOrientation.ReactionTorqueEnabled = false
		alignOrientation.MaxTorque = p.MaxTorque
		alignOrientation.Responsiveness = p.OrientationResponsiveness
		alignOrientation.Parent = part
		table.insert(hold.constraints, alignOrientation)
	elseif hold.mode == "Drag" then
		local friction = part.CurrentPhysicalProperties.Friction
		local p = GrabMath.dragParams(hold.mass, gravity, friction, GrabCfg)
		alignPosition.ApplyAtCenterOfMass = true -- no tipping torque
		alignPosition.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		alignPosition.ForceRelativeTo = Enum.ActuatorRelativeTo.World
		alignPosition.MaxAxesForce = Vector3.new(p.Horizontal, p.Vertical, p.Horizontal)
		alignPosition.Responsiveness = p.Responsiveness
		alignPosition.MaxVelocity = p.MaxVelocity
	else -- Articulated
		alignPosition.ApplyAtCenterOfMass = false
		alignPosition.MaxForce = GrabCfg.Articulated.MaxForce
		alignPosition.Responsiveness = GrabCfg.Articulated.Responsiveness
		alignPosition.MaxVelocity = GrabCfg.Articulated.MaxVelocity
	end

	alignPosition.Parent = part
	table.insert(hold.constraints, alignPosition)
end

function GrabService.GetHold(player: Player): Hold?
	return holdsByPlayer[player]
end

function GrabService.GetHolder(part: BasePart): Player?
	local hold = holdsByPart[part]
	return if hold then hold.player else nil
end

-- Core validation + setup. Also used server-side by interactions (e.g. MoneyBag
-- "E" pick up). Returns ok and either the mode or a failure reason.
function GrabService.TryGrab(player: Player, part: any, localPoint: any): (boolean, string)
	if not Validate.worldInstance(part, "BasePart") then
		return false, "InvalidTarget"
	end
	if not Validate.vector3(localPoint, 64) then
		return false, "InvalidPoint"
	end
	local target = part :: BasePart
	if not CollectionService:HasTag(target, Contract.Tags.Grabbable) then
		return false, "NotGrabbable"
	end
	if target:GetAttribute(Attr.GrabEnabled) == false then
		return false, "Disabled"
	end
	if target.Anchored then
		return false, "Locked"
	end
	if holdsByPlayer[player] then
		return false, "AlreadyHolding"
	end
	if holdsByPart[target] then
		return false, "HeldByOther"
	end
	local character, humanoid, root, head = getCharacterParts(player)
	if character == nil or humanoid == nil or root == nil or head == nil then
		return false, "NotAlive"
	end
	local handAttachment = HandService.GetHandAttachment(player)
	if handAttachment == nil then
		return false, "NoHand"
	end

	-- clamp the requested point inside the part's box
	local half = target.Size * 0.5
	local lp = localPoint :: Vector3
	local clampedLocal = Vector3.new(
		math.clamp(lp.X, -half.X, half.X),
		math.clamp(lp.Y, -half.Y, half.Y),
		math.clamp(lp.Z, -half.Z, half.Z)
	)
	local worldPoint = target.CFrame:PointToWorldSpace(clampedLocal)
	if (worldPoint - head.Position).Magnitude > GrabCfg.Range + GrabCfg.ServerRangeTolerance then
		return false, "TooFar"
	end
	if not hasLineOfSight(character, head.Position, worldPoint, target) then
		return false, "Obstructed"
	end

	local mode: string?
	local reason: string?
	if target:GetAttribute(Attr.Articulated) == true then
		mode = "Articulated"
	else
		mode, reason = GrabMath.classify(target.AssemblyMass, Targeting.assemblyMaxDimension(target), GrabCfg)
	end
	if mode == nil then
		return false, reason or "CannotGrab"
	end

	local hold: Hold = {
		player = player,
		part = target,
		mode = mode,
		mass = target.AssemblyMass,
		attachment = nil :: any,
		constraints = {},
		savedGroups = {},
		lastValidCFrame = target.CFrame,
		strikes = 0,
	}
	releaseGeneration[target] = (releaseGeneration[target] or 0) + 1 -- cancel pending restores
	buildConstraints(hold, handAttachment, worldPoint)
	setHeldCollision(hold)
	setOwner(target, player)

	holdsByPlayer[player] = hold
	holdsByPart[target] = hold
	target:SetAttribute(Attr.HeldBy, player.UserId)
	character:SetAttribute(Attr.HoldMode, mode)
	character:SetAttribute(Attr.CarrySpeedMultiplier, GrabMath.speedMultiplier(mode, hold.mass, GrabCfg))
	heldValue(character).Value = target

	GrabService.GrabStarted:Fire(player, target, mode)
	return true, mode
end

function GrabService.Release(player: Player, reason: string?)
	local hold = holdsByPlayer[player]
	if hold == nil then
		return
	end
	holdsByPlayer[player] = nil
	holdsByPart[hold.part] = nil

	for _, c in hold.constraints do
		c:Destroy()
	end
	if hold.attachment then
		hold.attachment:Destroy()
	end

	local part = hold.part
	if part.Parent then
		part:SetAttribute(Attr.HeldBy, nil)
		scheduleRestore(part, hold.savedGroups)
	end
	local character = player.Character
	if character then
		character:SetAttribute(Attr.HoldMode, nil)
		character:SetAttribute(Attr.CarrySpeedMultiplier, 1)
		local v = character:FindFirstChild(Contract.Names.HeldObjectValue)
		if v and v:IsA("ObjectValue") then
			v.Value = nil
		end
	end
	GrabService.GrabEnded:Fire(player, part, reason or "Released")
end

-- Releases whoever holds `part` (used by delivery, locking doors, resets).
function GrabService.ForceRelease(part: BasePart, reason: string?)
	local hold = holdsByPart[part]
	if hold then
		GrabService.Release(hold.player, reason or "Forced")
	end
end

-- Periodic anti-exploit / consistency pass over every active hold.
local function validateHolds()
	for player, hold in holdsByPlayer do
		local part = hold.part
		if part.Parent == nil or not part:IsDescendantOf(workspace) then
			GrabService.Release(player, "Destroyed")
			continue
		end
		local character, _, root = getCharacterParts(player)
		if character == nil or root == nil then
			GrabService.Release(player, "NotAlive")
			continue
		end
		local distance = (part.Position - root.Position).Magnitude
		if distance > GrabCfg.ServerTeleportBackDistance then
			-- impossible position: rewind to the last trusted state
			GrabService.Release(player, "Rewind")
			setOwner(part, nil)
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.CFrame = hold.lastValidCFrame
			continue
		elseif distance > GrabCfg.ServerMaxHoldDistance then
			GrabService.Release(player, "TooFar")
			continue
		end
		local speed = part.AssemblyLinearVelocity.Magnitude
		if speed > GrabCfg.ServerMaxSpeed then
			hold.strikes += 1
			part.AssemblyLinearVelocity = part.AssemblyLinearVelocity.Unit * GrabCfg.ServerMaxSpeed * 0.5
			if hold.strikes >= 3 then
				GrabService.Release(player, "TooFast")
				setOwner(part, nil)
			end
			continue
		end
		hold.strikes = 0
		hold.lastValidCFrame = part.CFrame
	end
end

function GrabService.Init()
	local grabRemote = Remotes.Get("GrabRequest")
	local releaseRemote = Remotes.Get("ReleaseRequest")

	grabRemote.OnServerInvoke = function(player: Player, part: any, localPoint: any)
		if not grabLimiter:Check(player) then
			return false, "RateLimited"
		end
		local ok, result, detail = pcall(GrabService.TryGrab, player, part, localPoint)
		if not ok then
			warn("[GrabService] TryGrab error: " .. tostring(result))
			return false, "ServerError"
		end
		return result, detail
	end

	releaseRemote.OnServerEvent:Connect(function(player: Player)
		if not releaseLimiter:Check(player) then
			return
		end
		GrabService.Release(player, "Released")
	end)

	Players.PlayerRemoving:Connect(function(player)
		GrabService.Release(player, "Left")
		grabLimiter:Remove(player)
		releaseLimiter:Remove(player)
	end)

	HandService.SetViolationHandler(function(player)
		GrabService.Release(player, "HandViolation")
	end)

	task.spawn(function()
		while true do
			task.wait(GrabCfg.ServerCheckInterval)
			validateHolds()
		end
	end)
end

-- Called by CharacterService for death / respawn / removal.
function GrabService.OnCharacterLost(player: Player)
	GrabService.Release(player, "CharacterLost")
end

return GrabService
