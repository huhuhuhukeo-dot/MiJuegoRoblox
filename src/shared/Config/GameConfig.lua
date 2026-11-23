--[[
	GameConfig
	Single source of truth for every tunable number in the prototype.
	Shared by client and server: the server ALWAYS validates with these values,
	the client only uses them for prediction / feel.
]]

local GameConfig = {}

GameConfig.Debug = false
GameConfig.MaxPlayers = 4

-- STAGE 1 — Camera -----------------------------------------------------------
GameConfig.Camera = {
	FieldOfView = 75,
	SprintFieldOfView = 81,
	FovLerpSpeed = 8, -- 1/s, exponential smoothing
	ZoomDistance = 0.5, -- min == max -> locked first person
	-- Anti-clip: the camera is pulled back toward the body if a wall sits between
	-- the root part and the eye position.
	ClipProbeRadius = 0.22,
	ClipPadding = 0.12,
}

-- STAGE 2 — Movement ---------------------------------------------------------
GameConfig.Movement = {
	WalkSpeed = 12,
	SprintSpeed = 19,
	CrouchSpeed = 6,
	SpeedLerp = 9, -- 1/s, smoothing of WalkSpeed changes (walk <-> run)
	JumpHeight = 5.5,
	JumpCooldown = 0.45, -- s between jumps (prevents bunny hopping)
	CrouchHipDrop = 1.2, -- studs the body is lowered while crouched (R15)
	CrouchTransitionTime = 0.16, -- s
	StandRetryInterval = 0.15, -- s, client retries standing up while blocked
	StandCheckPadding = 0.15, -- extra studs checked above the head
	StandCheckWidth = 1.6, -- XZ size of the clearance box
	AntiSpeed = {
		Enabled = true,
		SampleInterval = 0.5, -- s
		Tolerance = 1.4, -- multiplier over the max legal speed
		FlatAllowance = 6, -- studs/s added on top (knock-backs, doors)
		MaxStrikes = 3, -- consecutive violations before correction
	},
}

-- STAGE 3 — Physical hand ----------------------------------------------------
GameConfig.Hand = {
	-- Reach is measured from the (camera-space) shoulder.
	MinReach = 1.6,
	MaxReach = 5.0,
	DefaultReach = 3.2,
	ReachStep = 0.35, -- per mouse wheel notch
	-- Camera-space offsets (X right, Y up, -Z forward).
	ShoulderOffset = Vector3.new(0.85, -0.85, 0.15),
	IdleOffset = Vector3.new(0.7, -1.05, -1.7),
	SurfaceOffset = 0.35, -- how far from a surface the extended hand stops
	-- Physics part
	Size = Vector3.new(0.5, 0.45, 0.6),
	Density = 0.3,
	Friction = 0.6,
	MaxForce = 500, -- enough to push light props and doors, too weak to fling them
	Responsiveness = 45,
	MaxVelocity = 70,
	MaxTorque = 3000,
	OrientationResponsiveness = 40,
	-- Client recovery when the hand gets stuck behind geometry
	StuckDistance = 3.5,
	StuckTime = 0.35,
	-- Server validation
	ServerReachTolerance = 3.0,
	ServerViolationTime = 1.0,
	ServerCheckInterval = 0.25,
	-- Visual arm (purely cosmetic)
	UpperArmLength = 2.45,
	ForearmLength = 2.55,
	ArmThickness = 0.42,
}

-- STAGE 4 — Grab / lift / drag ----------------------------------------------
GameConfig.Grab = {
	Range = 8, -- max distance head -> grab point
	ServerRangeTolerance = 1.5,
	MaxLiftMass = 30, -- heavier objects can only be dragged
	MaxDragMass = 260, -- heavier objects cannot be moved at all
	MaxLiftSize = 6, -- largest assembly dimension that can be lifted
	MaxDragSize = 12,
	Lift = {
		-- Acceleration headroom above gravity. Light objects respond fast,
		-- heavy ones feel sluggish (they "sag" because the force barely beats gravity).
		MaxAccel = 160,
		MinAccel = 45,
		MaxResponsiveness = 30,
		MinResponsiveness = 11,
		MaxVelocity = 40,
		MinVelocity = 13,
		TorquePerMass = 900,
		OrientationResponsiveness = 18,
	},
	Drag = {
		HorizontalAccel = 26, -- studs/s^2 on top of overcoming friction
		VerticalSupport = 0.3, -- fraction of the weight supported (never lifts)
		Responsiveness = 10,
		MaxVelocity = 9,
	},
	Articulated = { -- doors, drawers
		MaxForce = 6000,
		Responsiveness = 22,
		MaxVelocity = 14,
	},
	-- Client auto-release when the object is blocked far from the hand
	BreakDistance = 4.0,
	BreakTime = 0.25,
	-- Server enforcement
	ServerCheckInterval = 0.1,
	ServerMaxHoldDistance = 16, -- object -> root part
	ServerTeleportBackDistance = 30,
	ServerMaxSpeed = 90,
	-- Release behaviour
	ReleaseOwnershipDelay = 1.5, -- s the releasing player keeps simulating (smooth throw)
	ReleaseCollisionMaxWait = 2, -- s max wait before collisions with characters return
	-- Speed penalty while carrying
	LiftSpeedMultiplierAtMax = 0.75,
	DragSpeedMultiplier = 0.55,
}

-- STAGE 5 — Interactions -----------------------------------------------------
GameConfig.Interaction = {
	Range = 7, -- head -> closest point of the interactable
	ServerRangeTolerance = 1.5,
	DefaultCooldown = 0.3, -- s per instance
	Door = {
		OpenAngle = 90,
		ServoSpeed = 2.6, -- rad/s
		ServoTorque = 6000, -- strong enough to swing the leaf, gentle on players
		FrictionTorque = 300, -- idle resistance (the hand can still push it open)
		LimitAngle = 105,
		OpenThreshold = 6, -- degrees: below this the door counts as closed
	},
	Drawer = {
		OpenDistance = 1.6,
		ServoSpeed = 4,
		ServoForce = 40000,
		FrictionForce = 150,
		OpenThreshold = 0.15,
	},
}

-- STAGE 6 — Networking -------------------------------------------------------
-- Token buckets: Rate = tokens per second, Burst = bucket size.
GameConfig.RateLimits = {
	GrabRequest = { Rate = 5, Burst = 6 },
	ReleaseRequest = { Rate = 8, Burst = 10 },
	InteractRequest = { Rate = 5, Burst = 6 },
	MovementState = { Rate = 12, Burst = 20 },
}

GameConfig.Recovery = {
	KillY = -60, -- props below this height are returned to their spawn
	CheckInterval = 1,
}

GameConfig.World = {
	BuildTestArena = true, -- builds the test scene if Workspace has no "TestArena"
}

return GameConfig
