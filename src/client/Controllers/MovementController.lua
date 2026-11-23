--[[
	MovementController (client) — STAGE 2
	WASD + mouse orientation come from Roblox's default controls (character
	faces the camera yaw in first person). This controller adds:
	  * Shift sprint with a smooth walk<->run transition and FOV kick
	  * Ctrl/C crouch: predicted locally (instant), confirmed by the server;
	    smooth pose blend; refuses to stand up under obstacles
	  * Controlled jump: fixed JumpHeight, cooldown, disabled while crouched
	  * Carry penalty: speed multiplier set by the server while holding props

	Extension points for later (stamina, footstep sounds):
	  MovementController.StateChanged:Connect(function(state) ... end)
	  MovementController.SetSprintGate(function(): boolean ... end)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Controls = require(Shared.Config.Controls)
local Contract = require(Shared.Interaction.Contract)
local CrouchPose = require(Shared.Movement.CrouchPose)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerContext = require(script.Parent.PlayerContext)
local InputBinder = require(script.Parent.InputBinder)
local CameraController = require(script.Parent.CameraController)

local MovementController = {}
MovementController.StateChanged = Signal.new() -- ({ Crouching, Sprinting, Moving })

local MoveCfg = Config.Movement
local Attr = Contract.Attributes

local state = {
	crouchInput = false,
	crouchToggled = false,
	sprintInput = false,
	crouched = false,
	sprinting = false,
	moving = false,
	alpha = 0,
	lastStandTry = 0,
	standBlockedUntil = 0,
	lastJump = -math.huge,
	jumpEnabled = true,
	sentCrouch = false,
	sentSprint = false,
}

local sprintGate: () -> boolean = function()
	return true
end

function MovementController.SetSprintGate(fn: () -> boolean)
	sprintGate = fn
end

function MovementController.IsCrouching(): boolean
	return state.crouched
end

function MovementController.IsSprinting(): boolean
	return state.sprinting
end

local movementRemote

local function resetForCharacter(character: Model, humanoid: Humanoid)
	state.crouched = false
	state.crouchToggled = false
	state.sprinting = false
	state.alpha = 0
	state.sentCrouch = false
	state.sentSprint = false
	state.jumpEnabled = true
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = MoveCfg.JumpHeight
	humanoid.WalkSpeed = MoveCfg.WalkSpeed
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		character:WaitForChild("RightFoot", 5) -- make sure the leg joints replicated
		character:WaitForChild("LeftFoot", 5)
	end
	CrouchPose.capture(character)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			state.lastJump = os.clock()
		end
	end)
end

local function step(dt: number)
	local character, humanoid = PlayerContext.Get()
	if character == nil or humanoid == nil then
		return
	end
	local now = os.clock()

	-- Crouch intent -> predicted state
	local wantCrouch = if Controls.CrouchIsToggle then state.crouchToggled else state.crouchInput
	if wantCrouch and not state.crouched then
		state.crouched = true
	elseif not wantCrouch and state.crouched then
		if now >= state.standBlockedUntil and now - state.lastStandTry >= MoveCfg.StandRetryInterval then
			state.lastStandTry = now
			if CrouchPose.canStand(character) then
				state.crouched = false
			end
		end
	end

	-- Smooth pose blend (identical final values to the server's pose)
	local target = if state.crouched then 1 else 0
	if state.alpha ~= target then
		local rate = dt / math.max(MoveCfg.CrouchTransitionTime, 1e-3)
		state.alpha = if target > state.alpha then math.min(target, state.alpha + rate) else math.max(target, state.alpha - rate)
		CrouchPose.apply(character, state.alpha)
	end

	-- Jump control
	local canJump = not state.crouched and now - state.lastJump >= MoveCfg.JumpCooldown
	if canJump ~= state.jumpEnabled then
		state.jumpEnabled = canJump
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, canJump)
	end

	-- Speed
	state.moving = humanoid.MoveDirection.Magnitude > 0.1
	local holdMode = character:GetAttribute(Attr.HoldMode)
	state.sprinting = state.sprintInput and state.moving and not state.crouched and holdMode ~= "Drag" and sprintGate()
	local base = if state.crouched then MoveCfg.CrouchSpeed elseif state.sprinting then MoveCfg.SprintSpeed else MoveCfg.WalkSpeed
	local mult = character:GetAttribute(Attr.CarrySpeedMultiplier)
	local targetSpeed = base * (if type(mult) == "number" then mult else 1)
	local k = 1 - math.exp(-MoveCfg.SpeedLerp * dt)
	humanoid.WalkSpeed += (targetSpeed - humanoid.WalkSpeed) * k

	CameraController.SetFovTarget(if state.sprinting then Config.Camera.SprintFieldOfView else Config.Camera.FieldOfView)

	-- Replicate state changes only
	if state.crouched ~= state.sentCrouch or state.sprinting ~= state.sentSprint then
		state.sentCrouch = state.crouched
		state.sentSprint = state.sprinting
		movementRemote:FireServer(state.crouched, state.sprinting)
		MovementController.StateChanged:Fire({
			Crouching = state.crouched,
			Sprinting = state.sprinting,
			Moving = state.moving,
		})
	end
end

function MovementController.Init()
	movementRemote = Remotes.Get("MovementState")

	InputBinder.Bind("FP_Sprint", Controls.Sprint, function(inputState)
		state.sprintInput = inputState == Enum.UserInputState.Begin
	end)
	InputBinder.Bind("FP_Crouch", Controls.Crouch, function(inputState)
		if inputState == Enum.UserInputState.Begin then
			state.crouchInput = true
			state.crouchToggled = not state.crouchToggled
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			state.crouchInput = false
		end
	end)

	-- Server correction: it refused to let us stand up (obstacle on its side)
	Remotes.Get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "MovementCorrection" and type(data) == "table" and data.Crouching == true then
			state.crouched = true
			state.sentCrouch = true
			state.standBlockedUntil = os.clock() + 0.5
		end
	end)

	PlayerContext.OnCharacter(function(character, humanoid)
		task.spawn(resetForCharacter, character, humanoid)
	end)
	RunService.PreSimulation:Connect(step)
end

return MovementController
