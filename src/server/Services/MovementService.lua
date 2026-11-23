--[[
	MovementService (server)
	Authoritative movement STATE (crouching, sprinting) and a light anti-speed
	check. Walk speed itself is smoothed on the owning client (the client owns
	its character's physics in Roblox, so speed must be validated by
	measuring displacement, which is what this service does).

	Crouch: the server re-checks head clearance before allowing the player to
	stand up and applies the final pose (replicated to everyone). If the client
	predicted wrongly it receives a "MovementCorrection" notification.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)
local CrouchPose = require(Shared.Movement.CrouchPose)
local Remotes = require(Shared.Net.Remotes)
local Validate = require(Shared.Net.Validate)
local RateLimiter = require(Shared.Util.RateLimiter)

local MovementService = {}

local MoveCfg = Config.Movement
local Attr = Contract.Attributes

type SpeedSample = { position: Vector3, strikes: number, lastValid: CFrame }
local samples: { [Player]: SpeedSample } = {}

local limiter = RateLimiter.new(Config.RateLimits.MovementState.Rate, Config.RateLimits.MovementState.Burst)
local notify: RemoteEvent

local function getCharacter(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return character, humanoid
end

function MovementService.SetupCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = MoveCfg.JumpHeight
	humanoid.WalkSpeed = MoveCfg.WalkSpeed
	character:SetAttribute(Attr.Crouching, false)
	character:SetAttribute(Attr.Sprinting, false)
	character:SetAttribute(Attr.CarrySpeedMultiplier, 1)
	CrouchPose.capture(character)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("[MovementService] R6 rig detected: crouch only lowers the camera. Use R15 (Game Settings > Avatar).")
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		samples[player] = { position = root.Position, strikes = 0, lastValid = root.CFrame }
	end
end

local function setCrouch(player: Player, character: Model, wantCrouch: boolean)
	local isCrouching = character:GetAttribute(Attr.Crouching) == true
	if wantCrouch == isCrouching then
		return
	end
	if not wantCrouch and not CrouchPose.canStand(character) then
		notify:FireClient(player, "MovementCorrection", { Crouching = true })
		return
	end
	character:SetAttribute(Attr.Crouching, wantCrouch)
	CrouchPose.apply(character, if wantCrouch then 1 else 0)
	if wantCrouch then
		character:SetAttribute(Attr.Sprinting, false)
	end
end

local function onMovementState(player: Player, crouching: any, sprinting: any)
	if not limiter:Check(player) then
		return
	end
	if not (Validate.boolean(crouching) and Validate.boolean(sprinting)) then
		return
	end
	local character = getCharacter(player)
	if character == nil then
		return
	end
	setCrouch(player, character, crouching)
	local canSprint = sprinting
		and character:GetAttribute(Attr.Crouching) ~= true
		and character:GetAttribute(Attr.HoldMode) ~= "Drag"
	character:SetAttribute(Attr.Sprinting, canSprint)
end

-- Highest horizontal speed the player could legally have right now.
local function legalSpeed(character: Model): number
	local mult = character:GetAttribute(Attr.CarrySpeedMultiplier)
	mult = if type(mult) == "number" then math.max(mult, 0.1) else 1
	return MoveCfg.SprintSpeed * math.max(mult, 1) -- lenient: never below sprint
end

local function checkSpeeds(dt: number)
	local anti = MoveCfg.AntiSpeed
	for player, sample in samples do
		local character, humanoid = getCharacter(player)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character == nil or humanoid == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local delta = root.Position - sample.position
		local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 1e-3)
		local limit = legalSpeed(character) * anti.Tolerance + anti.FlatAllowance
		local seated = humanoid.SeatPart ~= nil
		if horizontal > limit and not seated then
			sample.strikes += 1
			if sample.strikes >= anti.MaxStrikes then
				sample.strikes = 0
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = sample.lastValid
				warn(string.format("[MovementService] speed correction for %s (%.1f > %.1f)", player.Name, horizontal, limit))
			end
		else
			sample.strikes = 0
			sample.lastValid = root.CFrame
		end
		sample.position = root.Position
	end
end

function MovementService.Init()
	notify = Remotes.Get("Notify")
	Remotes.Get("MovementState").OnServerEvent:Connect(onMovementState)
	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
		limiter:Remove(player)
	end)
	if MoveCfg.AntiSpeed.Enabled then
		task.spawn(function()
			while true do
				local dt = task.wait(MoveCfg.AntiSpeed.SampleInterval)
				checkSpeeds(dt)
			end
		end)
	end
end

-- Lets server systems (e.g. teleports) reset the anti-speed baseline.
function MovementService.ResetBaseline(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local sample = samples[player]
	if sample and root and root:IsA("BasePart") then
		sample.position = root.Position
		sample.lastValid = root.CFrame
		sample.strikes = 0
	end
end

return MovementService
