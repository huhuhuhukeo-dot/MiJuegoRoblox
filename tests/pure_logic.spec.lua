--[[
	Pure logic tests (no Roblox APIs). They run in Roblox Studio's command bar
	or in any standalone Luau runtime.

	Standalone: the runner must provide `requirePath(path)` that loads a file
	relative to the repository root and returns its value (see docs/TESTING.md).
	Studio:     replace requirePath with require(game.ReplicatedStorage.Shared...).
]]

-- selene: allow(undefined_variable)
local load = requirePath or function(path: string)
	error("requirePath not available: " .. path)
end

local GrabMath = load("src/shared/Physics/GrabMath.lua")
local RateLimiter = load("src/shared/Util/RateLimiter.lua")
local Signal = load("src/shared/Util/Signal.lua")

if warn == nil then
	warn = function(...)
		print("[warn]", ...)
	end
end

local passed, failed = 0, 0
local function check(name: string, condition: boolean)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-4)
end

local cfg = {
	MaxLiftMass = 30,
	MaxDragMass = 260,
	MaxLiftSize = 6,
	MaxDragSize = 12,
	LiftSpeedMultiplierAtMax = 0.75,
	DragSpeedMultiplier = 0.55,
	Lift = {
		MaxAccel = 160, MinAccel = 45,
		MaxResponsiveness = 30, MinResponsiveness = 11,
		MaxVelocity = 40, MinVelocity = 13,
		TorquePerMass = 900, OrientationResponsiveness = 18,
	},
	Drag = { HorizontalAccel = 26, VerticalSupport = 0.3, Responsiveness = 10, MaxVelocity = 9 },
}
local G = 196.2

-- classify -------------------------------------------------------------------
check("light box lifts", GrabMath.classify(4, 2, cfg) == "Lift")
check("lift limit inclusive", GrabMath.classify(30, 6, cfg) == "Lift")
check("heavy box drags", GrabMath.classify(160, 4, cfg) == "Drag")
check("big light object drags", GrabMath.classify(10, 8, cfg) == "Drag")
do
	local mode, reason = GrabMath.classify(300, 4, cfg)
	check("too heavy rejected", mode == nil and reason == "TooHeavy")
	mode, reason = GrabMath.classify(50, 20, cfg)
	check("too big rejected", mode == nil and reason == "TooBig")
	mode, reason = GrabMath.classify(0 / 0, 1, cfg)
	check("NaN mass rejected", mode == nil and reason == "InvalidMass")
	mode = GrabMath.classify(-1, 1, cfg)
	check("negative mass rejected", mode == nil)
end

-- lift params: force always beats gravity, heavier = slower --------------------
do
	local light = GrabMath.liftParams(4, G, cfg)
	local heavy = GrabMath.liftParams(30, G, cfg)
	check("light lift beats gravity", light.MaxForce > 4 * G)
	check("heavy lift beats gravity", heavy.MaxForce > 30 * G)
	check("heavy is less responsive", heavy.Responsiveness < light.Responsiveness)
	check("heavy moves slower", heavy.MaxVelocity < light.MaxVelocity)
	check("max mass uses min accel", near(heavy.MaxForce, 30 * (G + 45)))
end

-- drag params: can never lift ------------------------------------------------
do
	for _, mass in { 31, 100, 160, 260 } do
		local p = GrabMath.dragParams(mass, G, 0.35, cfg)
		check("drag vertical < weight (" .. mass .. ")", p.Vertical < mass * G)
		check("drag overcomes friction (" .. mass .. ")", p.Horizontal > mass * G * (1 - 0.3) * 0.35)
	end
end

-- speed multiplier --------------------------------------------------------------
check("no penalty empty handed", GrabMath.speedMultiplier(nil, 0, cfg) == 1)
check("lift penalty at max", near(GrabMath.speedMultiplier("Lift", 30, cfg), 0.75))
check("lift penalty light", GrabMath.speedMultiplier("Lift", 3, cfg) > 0.95)
check("drag penalty", near(GrabMath.speedMultiplier("Drag", 100, cfg), 0.55))

-- two bone IK -----------------------------------------------------------------
do
	local a, d = GrabMath.solveTwoBone(10, 2.4, 2.6)
	check("IK clamps unreachable distance", d < 5 and near(a, 0, 0.05))
	a = GrabMath.solveTwoBone(3, 2.4, 2.6)
	check("IK bends when close", a > 0.5 and a < math.pi / 2)
	-- reconstruct: the elbow must be l1 from shoulder and l2 from target
	local l1, l2, dist = 2.4, 2.6, 3.5
	local ang = GrabMath.solveTwoBone(dist, l1, l2)
	local ex, ey = math.cos(ang) * l1, math.sin(ang) * l1
	local toTarget = math.sqrt((dist - ex) ^ 2 + ey ^ 2)
	check("IK elbow geometry", near(toTarget, l2, 1e-3))
end

-- crouch leg angles -------------------------------------------------------------
do
	local hip, knee, ankle, got = GrabMath.crouchLegAngles(1.2, 1.15, 1.15)
	check("crouch drop achieved", near(got, 1.2, 1e-3))
	check("feet stay flat", near(hip + knee + ankle, 0, 1e-6))
	check("hip bends forward", hip > 0)
	local _, _, _, short = GrabMath.crouchLegAngles(5, 1, 1)
	check("short legs clamp drop", short < 5 and short > 0)
	local h0 = GrabMath.crouchLegAngles(0, 1, 1)
	check("zero drop = no bend", h0 == 0)
end

-- rate limiter ----------------------------------------------------------------
do
	local rl = RateLimiter.new(2, 3)
	local key = {}
	check("burst 1", rl:Check(key, 0))
	check("burst 2", rl:Check(key, 0))
	check("burst 3", rl:Check(key, 0))
	check("burst exhausted", not rl:Check(key, 0))
	check("refills over time", rl:Check(key, 0.5))
	check("but not too fast", not rl:Check(key, 0.6))
	check("other keys independent", rl:Check({}, 0.6))
	check("caps at burst", (function()
		local k = {}
		rl:Check(k, 0)
		local ok = 0
		for _ = 1, 10 do
			if rl:Check(k, 1000) then
				ok += 1
			end
		end
		return ok == 3
	end)())
end

-- signal -----------------------------------------------------------------------
do
	local s = Signal.new()
	local total = 0
	local c1 = s:Connect(function(n)
		total += n
	end)
	s:Connect(function()
		error("isolated failure")
	end)
	s:Connect(function(n)
		total += n * 10
	end)
	s:Fire(1)
	check("signal fires all handlers, isolating errors", total == 11)
	c1:Disconnect()
	s:Fire(1)
	check("disconnect works", total == 21)
	s:DisconnectAll()
	s:Fire(1)
	check("disconnect all", total == 21)
end

print(string.format("pure logic tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
