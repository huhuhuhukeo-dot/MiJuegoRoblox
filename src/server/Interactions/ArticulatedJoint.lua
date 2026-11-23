--[[
	ArticulatedJoint (helper, not an interaction type)
	Shared behaviour for anything that moves on a physical joint:
	  * HingeConstraint     -> doors
	  * PrismaticConstraint -> drawers

	Modes of the joint actuator:
	  Friction  Motor with zero target speed and small max torque/force:
	            the part rests in place but the physical hand can push it.
	  Servo     strong servo toward the open/closed target ("E" toggle).
	  Free      no actuator while a player drags the part with the hand.
	  Locked    moving part anchored (only allowed when closed).

	State attribute "JointState" ("Closed" | "Open" | "Locked") is written on
	the owning instance and replicates to every client.
]]

local RunService = game:GetService("RunService")

local ArticulatedJoint = {}
ArticulatedJoint.__index = ArticulatedJoint

export type Options = {
	instance: Instance,
	part: BasePart,
	constraint: HingeConstraint | PrismaticConstraint,
	openTarget: number,
	closedTarget: number,
	openThreshold: number,
	servoSpeed: number,
	servoStrength: number,
	friction: number,
}

local all: { [any]: boolean } = {}
local heartbeatConnection: RBXScriptConnection? = nil

function ArticulatedJoint.new(opts: Options)
	local self = setmetatable({
		instance = opts.instance,
		part = opts.part,
		constraint = opts.constraint,
		isHinge = opts.constraint:IsA("HingeConstraint"),
		openTarget = opts.openTarget,
		closedTarget = opts.closedTarget,
		openThreshold = opts.openThreshold,
		servoSpeed = opts.servoSpeed,
		servoStrength = opts.servoStrength,
		friction = opts.friction,
		mode = "Friction",
		servoTarget = nil :: number?,
		locked = false,
		lockWhenClosed = false,
		grabbed = false,
		closedCFrame = opts.part.CFrame,
	}, ArticulatedJoint)
	self:_setFriction()
	pcall(function()
		opts.part:SetNetworkOwner(nil) -- idle doors/drawers are simulated by the server
	end)
	all[self] = true
	if heartbeatConnection == nil then
		heartbeatConnection = RunService.Heartbeat:Connect(function()
			for joint in all do
				joint:_update()
			end
		end)
	end
	self:_writeState()
	return self
end

function ArticulatedJoint:Destroy()
	all[self] = nil
end

function ArticulatedJoint:GetValue(): number
	local c = self.constraint
	if self.isHinge then
		return (c :: HingeConstraint).CurrentAngle
	end
	return (c :: PrismaticConstraint).CurrentPosition
end

function ArticulatedJoint:IsOpen(): boolean
	return math.abs(self:GetValue() - self.closedTarget) > self.openThreshold
end

function ArticulatedJoint:GetState(): string
	if self.locked then
		return "Locked"
	end
	return if self:IsOpen() then "Open" else "Closed"
end

function ArticulatedJoint:_writeState()
	local state = self:GetState()
	if self.instance:GetAttribute("JointState") ~= state then
		self.instance:SetAttribute("JointState", state)
	end
end

function ArticulatedJoint:_setFriction()
	local c = self.constraint
	c.ActuatorType = Enum.ActuatorType.Motor
	if self.isHinge then
		local h = c :: HingeConstraint
		h.AngularVelocity = 0
		h.MotorMaxTorque = self.friction
		h.MotorMaxAcceleration = math.huge
	else
		local p = c :: PrismaticConstraint
		p.Velocity = 0
		p.MotorMaxForce = self.friction
		p.MotorMaxAcceleration = math.huge
	end
	self.mode = "Friction"
	self.servoTarget = nil
end

function ArticulatedJoint:_setServo(target: number)
	local c = self.constraint
	c.ActuatorType = Enum.ActuatorType.Servo
	if self.isHinge then
		local h = c :: HingeConstraint
		h.TargetAngle = target
		h.AngularSpeed = self.servoSpeed
		h.ServoMaxTorque = self.servoStrength
	else
		local p = c :: PrismaticConstraint
		p.TargetPosition = target
		p.Speed = self.servoSpeed
		p.ServoMaxForce = self.servoStrength
	end
	self.mode = "Servo"
	self.servoTarget = target
end

function ArticulatedJoint:_update()
	if self.part.Parent == nil then
		self:Destroy()
		return
	end
	if self.mode == "Servo" and self.servoTarget then
		local tolerance = if self.isHinge then 1.5 else 0.03
		if math.abs(self:GetValue() - self.servoTarget) <= tolerance then
			self:_setFriction()
			if self.lockWhenClosed and not self:IsOpen() then
				self.lockWhenClosed = false
				self:_anchorClosed()
			end
		end
	end
	self:_writeState()
end

function ArticulatedJoint:_anchorClosed()
	self.part.AssemblyLinearVelocity = Vector3.zero
	self.part.AssemblyAngularVelocity = Vector3.zero
	self.part.CFrame = self.closedCFrame
	self.part.Anchored = true
	self.locked = true
	self:_writeState()
end

-- "E" interaction: open if closed, close if open.
function ArticulatedJoint:Toggle()
	if self.locked or self.grabbed then
		return
	end
	local target = if self:IsOpen() then self.closedTarget else self.openTarget
	-- open away from the player is handled by the module choosing openTarget
	self:_setServo(target)
end

function ArticulatedJoint:SetOpenTarget(value: number)
	self.openTarget = value
end

function ArticulatedJoint:SetLocked(locked: boolean)
	if locked == self.locked and not (locked and self.lockWhenClosed) then
		return
	end
	if locked then
		if self:IsOpen() then
			self.lockWhenClosed = true -- close first, lock on arrival
			self:_setServo(self.closedTarget)
		else
			self:_anchorClosed()
		end
	else
		self.lockWhenClosed = false
		self.locked = false
		self.part.Anchored = false
		self:_setFriction()
		pcall(function()
			self.part:SetNetworkOwner(nil)
		end)
		self:_writeState()
	end
end

function ArticulatedJoint:IsLocked(): boolean
	return self.locked
end

function ArticulatedJoint:OnGrabStarted()
	self.grabbed = true
	self.lockWhenClosed = false
	self.constraint.ActuatorType = Enum.ActuatorType.None
	self.mode = "Free"
end

function ArticulatedJoint:OnGrabEnded()
	self.grabbed = false
	self:_setFriction()
end

return ArticulatedJoint
