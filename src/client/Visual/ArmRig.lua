--[[
	ArmRig (client, visual only)
	A cosmetic arm: upper arm + forearm + palm + fingers + thumb, posed every
	frame with two-bone IK between a shoulder point and the PHYSICS hand.
	Parts are anchored, non-colliding and non-queryable: the visual never
	affects physics or raycasts. `grip` (0..1) curls the fingers; this is the
	hook for future hand animations (poses can drive grip/finger CFrames).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrabMath = require(ReplicatedStorage.Shared.Physics.GrabMath)
local Config = require(ReplicatedStorage.Shared.Config.GameConfig)

local ArmRig = {}
ArmRig.__index = ArmRig

local HandCfg = Config.Hand

local function visualPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function ArmRig.new(skin: Color3, sleeve: Color3, parent: Instance, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "VisualArm"
	local t = HandCfg.ArmThickness * s
	local self = setmetatable({
		model = model,
		scale = s,
		l1 = HandCfg.UpperArmLength * s,
		l2 = HandCfg.ForearmLength * s,
		upper = visualPart("UpperArm", Vector3.new(t, t, HandCfg.UpperArmLength * s), sleeve, model),
		fore = visualPart("Forearm", Vector3.new(t * 0.9, t * 0.9, HandCfg.ForearmLength * s), skin, model),
		palm = visualPart("Palm", Vector3.new(0.42, 0.18, 0.5) * s, skin, model),
		fingers = visualPart("Fingers", Vector3.new(0.4, 0.14, 0.34) * s, skin, model),
		thumb = visualPart("Thumb", Vector3.new(0.12, 0.12, 0.3) * s, skin, model),
		foreLength = HandCfg.ForearmLength * s,
		parts = {},
		cframes = {},
	}, ArmRig)
	self.parts = { self.upper, self.fore, self.palm, self.fingers, self.thumb }
	model.Parent = parent
	return self
end

function ArmRig:SetVisible(visible: boolean)
	local tr = if visible then 0 else 1
	for _, p in self.parts do
		if p.Transparency ~= tr then
			p.Transparency = tr
		end
	end
end

-- shoulder: world point; hand: world CFrame of the palm (-Z = fingers);
-- pole: preferred elbow direction; grip: 0 open .. 1 closed.
function ArmRig:Update(shoulder: Vector3, hand: CFrame, pole: Vector3, grip: number)
	local s = self.scale
	local wrist = hand:PointToWorldSpace(Vector3.new(0, 0, 0.25 * s))
	local toWrist = wrist - shoulder
	local distance = toWrist.Magnitude
	if distance < 1e-3 then
		return
	end
	local dir = toWrist / distance
	local angle = GrabMath.solveTwoBone(distance, self.l1, self.l2)
	local bend = pole - dir * pole:Dot(dir)
	if bend.Magnitude < 1e-3 then
		bend = dir:Cross(Vector3.xAxis)
		if bend.Magnitude < 1e-3 then
			bend = dir:Cross(Vector3.zAxis)
		end
	end
	bend = bend.Unit
	local elbow = shoulder + dir * (math.cos(angle) * self.l1) + bend * (math.sin(angle) * self.l1)

	-- forearm stretches only if the hand is beyond the arm's length
	local foreLength = (wrist - elbow).Magnitude
	if math.abs(foreLength - self.foreLength) > 0.02 then
		self.foreLength = foreLength
		local t = self.fore.Size.X
		self.fore.Size = Vector3.new(t, t, math.max(foreLength, 0.1))
	end

	local c = self.cframes
	c[1] = CFrame.lookAt((shoulder + elbow) * 0.5, elbow, bend)
	c[2] = CFrame.lookAt((elbow + wrist) * 0.5, wrist, bend)
	c[3] = hand
	c[4] = hand * CFrame.new(0, 0, -0.25 * s) * CFrame.Angles(-grip * 1.35, 0, 0) * CFrame.new(0, 0, -0.17 * s)
	c[5] = hand * CFrame.new(-0.24 * s, -0.02 * s, -0.08 * s) * CFrame.Angles(0, grip * 0.9, 0) * CFrame.new(0, 0, -0.12 * s)
	workspace:BulkMoveTo(self.parts, c, Enum.BulkMoveMode.FireCFrameChanged)
end

function ArmRig:Destroy()
	self.model:Destroy()
end

return ArmRig
