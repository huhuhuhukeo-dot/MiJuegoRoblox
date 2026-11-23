--[[
	CrouchPose
	Applies the crouch pose to a character for a blend value alpha (0 = standing,
	1 = crouched). Used by BOTH sides:
	  * the server applies the final pose (replicates to every client),
	  * the owning client applies it every frame during the transition for an
	    instant, smooth response (prediction). Both end in identical values.

	R15: lowers Humanoid.HipHeight and bends hips/knees/ankles (Motor6D.C0) so
	the feet stay on the floor and the real collision height is reduced.
	R6 (fallback): only lowers the camera through Humanoid.CameraOffset.
]]

local GrabMath = require(script.Parent.Parent.Physics.GrabMath)
local Config = require(script.Parent.Parent.Config.GameConfig)

local CrouchPose = {}

type Joint = { motor: Motor6D, original: CFrame, angle: number }
type PoseData = {
	humanoid: Humanoid,
	isR15: boolean,
	standHipHeight: number,
	drop: number,
	joints: { Joint },
	alpha: number,
}

local cache: { [Model]: PoseData } = setmetatable({}, { __mode = "k" }) :: any

local function jointLength(part: Instance?, a: string, b: string): number?
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	local attA = part:FindFirstChild(a)
	local attB = part:FindFirstChild(b)
	if attA and attB and attA:IsA("Attachment") and attB:IsA("Attachment") then
		return (attA.Position - attB.Position).Magnitude
	end
	return part.Size.Y
end

-- Captures the standing pose. Must be called while the character stands.
function CrouchPose.capture(character: Model): PoseData?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	local data: PoseData = {
		humanoid = humanoid,
		isR15 = humanoid.RigType == Enum.HumanoidRigType.R15,
		standHipHeight = humanoid.HipHeight,
		drop = Config.Movement.CrouchHipDrop,
		joints = {},
		alpha = 0,
	}
	if data.isR15 then
		local achieved = math.huge
		for _, side in { "Left", "Right" } do
			local upper = character:FindFirstChild(side .. "UpperLeg")
			local lower = character:FindFirstChild(side .. "LowerLeg")
			local foot = character:FindFirstChild(side .. "Foot")
			local hip = upper and upper:FindFirstChild(side .. "Hip")
			local knee = lower and lower:FindFirstChild(side .. "Knee")
			local ankle = foot and foot:FindFirstChild(side .. "Ankle")
			if not (hip and knee and ankle and hip:IsA("Motor6D") and knee:IsA("Motor6D") and ankle:IsA("Motor6D")) then
				-- Non standard rig: fall back to camera-only crouch
				data.isR15 = false
				data.joints = {}
				break
			end
			local thigh = jointLength(upper, side .. "HipRigAttachment", side .. "KneeRigAttachment") or 1.2
			local shin = jointLength(lower, side .. "KneeRigAttachment", side .. "AnkleRigAttachment") or 1.2
			local hipA, kneeA, ankleA, got = GrabMath.crouchLegAngles(Config.Movement.CrouchHipDrop, thigh, shin)
			achieved = math.min(achieved, got)
			table.insert(data.joints, { motor = hip, original = hip.C0, angle = hipA })
			table.insert(data.joints, { motor = knee, original = knee.C0, angle = kneeA })
			table.insert(data.joints, { motor = ankle, original = ankle.C0, angle = ankleA })
		end
		if data.isR15 and achieved < math.huge then
			data.drop = achieved
		end
	end
	cache[character] = data
	return data
end

function CrouchPose.get(character: Model): PoseData?
	return cache[character] or CrouchPose.capture(character)
end

-- Height (studs) the body/camera is lowered when fully crouched.
function CrouchPose.getDrop(character: Model): number
	local data = CrouchPose.get(character)
	return if data then data.drop else Config.Movement.CrouchHipDrop
end

function CrouchPose.apply(character: Model, alpha: number)
	local data = CrouchPose.get(character)
	if data == nil then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	data.alpha = alpha
	if data.isR15 then
		data.humanoid.HipHeight = data.standHipHeight - data.drop * alpha
		for _, joint in data.joints do
			if joint.motor.Parent then
				joint.motor.C0 = joint.original * CFrame.Angles(joint.angle * alpha, 0, 0)
			end
		end
	else
		data.humanoid.CameraOffset = Vector3.new(0, -data.drop * alpha, 0)
	end
end

function CrouchPose.getAlpha(character: Model): number
	local data = cache[character]
	return if data then data.alpha else 0
end

-- Axis-aligned box (CFrame, size) that must be empty for the character to
-- stand up from its current crouch. Uses the root part as reference.
function CrouchPose.standClearanceBox(character: Model): (CFrame?, Vector3?)
	local data = CrouchPose.get(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if data == nil or root == nil or head == nil or not root:IsA("BasePart") or not head:IsA("BasePart") then
		return nil, nil
	end
	local raise = data.drop * data.alpha
	if raise <= 0.01 then
		return nil, nil
	end
	local headTop = head.Position.Y + head.Size.Y * 0.5
	local bottom = headTop + 0.05
	local top = headTop + raise + Config.Movement.StandCheckPadding
	local width = Config.Movement.StandCheckWidth
	local center = Vector3.new(root.Position.X, (bottom + top) * 0.5, root.Position.Z)
	return CFrame.new(center), Vector3.new(width, top - bottom, width)
end

-- True when nothing solid (for characters) blocks standing up.
function CrouchPose.canStand(character: Model): boolean
	local cf, size = CrouchPose.standClearanceBox(character)
	if cf == nil or size == nil then
		return true
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.CollisionGroup = "Characters" -- respects the collision matrix (ignores held props, hands)
	params.RespectCanCollide = true
	params.MaxParts = 1
	return #workspace:GetPartBoundsInBox(cf, size, params) == 0
end

return CrouchPose
