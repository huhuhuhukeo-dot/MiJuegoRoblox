--[[
	HandController (client) — STAGE 3
	Drives the player's single PHYSICAL hand (built by the server, owned by
	this client). Each frame it computes a target and writes it into the
	hand's AlignPosition/AlignOrientation; the physics engine moves the hand
	with finite force, so it collides with the world, pushes light props and
	doors, and replicates to everyone. The hand is never teleported except
	for stuck-recovery.

	Controls (see Shared.Config.Controls):
	  Right click / F (hold)  extend the hand toward the crosshair
	  Mouse wheel / Z-X       reach distance while extended or holding
	  The mouse keeps rotating the camera at all times.

	Target rules:
	  relaxed  -> fixed camera-space rest pose (lower right of the view)
	  extended -> point on the crosshair ray at `reach`, stopped short of
	              surfaces (SurfaceOffset) so the hand rests against them
	  always   -> clamped to MaxReach from the camera-space shoulder
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Controls = require(Shared.Config.Controls)
local Contract = require(Shared.Interaction.Contract)
local Signal = require(Shared.Util.Signal)

local PlayerContext = require(script.Parent.PlayerContext)
local InputBinder = require(script.Parent.InputBinder)
local CameraController = require(script.Parent.CameraController)

local HandController = {}
HandController.ExtendedChanged = Signal.new() -- (extended: boolean)

local HandCfg = Config.Hand

local hand: BasePart? = nil
local alignPosition: AlignPosition? = nil
local alignOrientation: AlignOrientation? = nil

local extendInput = false
local holding: BasePart? = nil
local holdRadius = 0
local reach = HandCfg.DefaultReach
local stuckTime = 0
local lastExtended = false
local currentTarget = Vector3.zero

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
local extraIgnore: { Instance } = {}

function HandController.SetIgnoreList(list: { Instance })
	extraIgnore = list
end

function HandController.GetHand(): BasePart?
	if hand and hand.Parent then
		return hand
	end
	return nil
end

function HandController.IsExtended(): boolean
	return extendInput or holding ~= nil
end

function HandController.GetReach(): number
	return reach
end

function HandController.SetReach(value: number)
	reach = math.clamp(value, HandCfg.MinReach, HandCfg.MaxReach)
end

-- Called by GrabController with the currently held prop (or nil).
function HandController.SetHeld(part: BasePart?)
	if part == holding then
		return
	end
	holding = part
	if part then
		local s = part.Size
		holdRadius = math.min(math.max(s.X, s.Y, s.Z) * 0.5, 2)
	else
		holdRadius = 0
	end
end

function HandController.GetTarget(): Vector3
	return currentTarget
end

local function yawRotation(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z) * -math.sign(look.Y)
		if flat.Magnitude < 1e-3 then
			return CFrame.identity
		end
	end
	return CFrame.lookAt(Vector3.zero, flat.Unit)
end

local function computeTarget(camCF: CFrame, character: Model): Vector3
	local shoulder = camCF:PointToWorldSpace(HandCfg.ShoulderOffset)
	local target: Vector3
	if HandController.IsExtended() then
		local ignore = { character, workspace.CurrentCamera }
		for _, inst in extraIgnore do
			table.insert(ignore, inst)
		end
		if holding then
			table.insert(ignore, holding)
		end
		params.FilterDescendantsInstances = ignore
		params.CollisionGroup = if holding then Contract.CollisionGroups.Held else Contract.CollisionGroups.Hand
		local origin = camCF.Position
		local dir = camCF.LookVector
		local distance = reach
		local result = workspace:Raycast(origin, dir * (reach + holdRadius + HandCfg.SurfaceOffset), params)
		if result then
			distance = math.min(distance, result.Distance - HandCfg.SurfaceOffset - holdRadius)
		end
		distance = math.max(distance, if holding then HandCfg.MinReach else 0.8)
		target = origin + dir * distance
	else
		target = camCF:PointToWorldSpace(HandCfg.IdleOffset)
	end
	local offset = target - shoulder
	if offset.Magnitude > HandCfg.MaxReach then
		target = shoulder + offset.Unit * HandCfg.MaxReach
	end
	return target
end

local function step(dt: number)
	local character = PlayerContext.Get()
	local h, ap, ao = hand, alignPosition, alignOrientation
	if character == nil or h == nil or ap == nil or ao == nil or h.Parent == nil then
		return
	end
	local camCF = workspace.CurrentCamera.CFrame
	local target = computeTarget(camCF, character)
	local rotation = yawRotation(camCF)
	currentTarget = target
	ap.Position = target
	ao.CFrame = rotation

	-- Stuck recovery: e.g. the hand got wedged behind a door frame
	if holding == nil and (h.Position - target).Magnitude > HandCfg.StuckDistance then
		stuckTime += dt
		if stuckTime >= HandCfg.StuckTime then
			stuckTime = 0
			h.AssemblyLinearVelocity = Vector3.zero
			h.AssemblyAngularVelocity = Vector3.zero
			h.CFrame = CFrame.new(target) * rotation
		end
	else
		stuckTime = 0
	end

	local extended = HandController.IsExtended()
	if extended ~= lastExtended then
		lastExtended = extended
		HandController.ExtendedChanged:Fire(extended)
	end
end

local function attach(character: Model)
	hand, alignPosition, alignOrientation = nil, nil, nil
	holding = nil
	holdRadius = 0
	reach = HandCfg.DefaultReach
	local part = character:WaitForChild(Contract.Names.PhysicsHand, 15)
	if part == nil or not part:IsA("BasePart") then
		warn("[HandController] PhysicsHand did not replicate")
		return
	end
	local ap = part:WaitForChild(Contract.Names.HandAlignPosition, 5)
	local ao = part:WaitForChild(Contract.Names.HandAlignOrientation, 5)
	if ap and ao and ap:IsA("AlignPosition") and ao:IsA("AlignOrientation") then
		hand, alignPosition, alignOrientation = part, ap, ao
	end
end

local function adjustReach(delta: number)
	if HandController.IsExtended() then
		HandController.SetReach(reach + delta)
	end
end

function HandController.Init()
	InputBinder.Bind("FP_ExtendHand", Controls.ExtendHand, function(inputState)
		extendInput = inputState == Enum.UserInputState.Begin
	end)
	InputBinder.Bind("FP_ReachWheel", { Enum.UserInputType.MouseWheel }, function(_, input)
		adjustReach(math.sign(input.Position.Z) * HandCfg.ReachStep)
	end)
	InputBinder.Bind("FP_ReachIncrease", Controls.ReachIncrease, function(inputState)
		if inputState == Enum.UserInputState.Begin then
			adjustReach(HandCfg.ReachStep)
		end
	end)
	InputBinder.Bind("FP_ReachDecrease", Controls.ReachDecrease, function(inputState)
		if inputState == Enum.UserInputState.Begin then
			adjustReach(-HandCfg.ReachStep)
		end
	end)
	PlayerContext.OnCharacter(function(character)
		task.spawn(attach, character)
	end)
	RunService:BindToRenderStep("FP_Hand", CameraController.RenderPriority + 3, step)
end

return HandController
