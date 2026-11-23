--[[
	GrabMath
	Pure numeric helpers (no Roblox instances) so they can be unit-tested
	outside Roblox (see tests/). Used by the server to configure constraints
	and by the client to predict / display.
]]

local GrabMath = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
GrabMath.lerp = lerp

-- Decides how an object can be manipulated.
-- Returns "Lift" | "Drag" | nil, plus a reason when nil.
function GrabMath.classify(mass: number, maxDimension: number, cfg): (string?, string?)
	if mass ~= mass or mass <= 0 then
		return nil, "InvalidMass"
	end
	if mass <= cfg.MaxLiftMass and maxDimension <= cfg.MaxLiftSize then
		return "Lift", nil
	end
	if mass > cfg.MaxDragMass then
		return nil, "TooHeavy"
	end
	if maxDimension > cfg.MaxDragSize then
		return nil, "TooBig"
	end
	return "Drag", nil
end

-- 0 for weightless objects, 1 at the lift limit.
function GrabMath.weightRatio(mass: number, cfg): number
	return math.clamp(mass / cfg.MaxLiftMass, 0, 1)
end

-- Parameters for an AlignPosition/AlignOrientation pair lifting `mass`.
function GrabMath.liftParams(mass: number, gravity: number, cfg)
	local lift = cfg.Lift
	local r = GrabMath.weightRatio(mass, cfg)
	local accel = lerp(lift.MaxAccel, lift.MinAccel, r)
	return {
		MaxForce = mass * (gravity + accel),
		Responsiveness = lerp(lift.MaxResponsiveness, lift.MinResponsiveness, r),
		MaxVelocity = lerp(lift.MaxVelocity, lift.MinVelocity, r),
		MaxTorque = math.max(200, mass * lift.TorquePerMass),
		OrientationResponsiveness = lift.OrientationResponsiveness,
	}
end

-- Per-axis forces for dragging a heavy object along the floor.
-- Vertical force always stays BELOW the weight, so it can never be lifted.
function GrabMath.dragParams(mass: number, gravity: number, friction: number, cfg)
	local drag = cfg.Drag
	local weight = mass * gravity
	local support = math.clamp(drag.VerticalSupport, 0, 0.9)
	local normalForce = weight * (1 - support)
	return {
		Horizontal = normalForce * friction + mass * drag.HorizontalAccel,
		Vertical = weight * support,
		Responsiveness = drag.Responsiveness,
		MaxVelocity = drag.MaxVelocity,
	}
end

-- Walk speed multiplier applied while carrying.
function GrabMath.speedMultiplier(mode: string?, mass: number, cfg): number
	if mode == "Lift" then
		return lerp(1, cfg.LiftSpeedMultiplierAtMax, GrabMath.weightRatio(mass, cfg))
	elseif mode == "Drag" then
		return cfg.DragSpeedMultiplier
	end
	return 1
end

-- Two-bone IK. Given the shoulder->target distance and bone lengths returns the
-- angle (radians) between the shoulder->target line and the first bone, and the
-- (clamped) distance actually reachable.
function GrabMath.solveTwoBone(distance: number, l1: number, l2: number): (number, number)
	local maxD = l1 + l2 - 1e-3
	local minD = math.abs(l1 - l2) + 1e-3
	local d = math.clamp(distance, minD, maxD)
	local cosA = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
	return math.acos(math.clamp(cosA, -1, 1)), d
end

-- Leg angles (radians) for a squat that lowers the hip joint by `drop` studs.
-- thigh tilts forward by `hip`, the shin tilts backward by `phi = hip * 0.6`.
-- Returns hipAngle, kneeAngle (relative), ankleAngle (relative) and the drop
-- actually achieved (may be smaller if the legs are too short).
function GrabMath.crouchLegAngles(drop: number, thigh: number, shin: number)
	local SHIN_RATIO = 0.6
	local MAX_HIP = 1.45
	local function dropFor(theta: number): number
		return thigh * (1 - math.cos(theta)) + shin * (1 - math.cos(theta * SHIN_RATIO))
	end
	if drop <= 0 then
		return 0, 0, 0, 0
	end
	local lo, hi = 0, MAX_HIP
	if dropFor(hi) < drop then
		lo = hi
	else
		for _ = 1, 30 do
			local mid = (lo + hi) * 0.5
			if dropFor(mid) < drop then
				lo = mid
			else
				hi = mid
			end
		end
	end
	local theta = lo
	local phi = theta * SHIN_RATIO
	return theta, -(theta + phi), phi, dropFor(theta)
end

return GrabMath
