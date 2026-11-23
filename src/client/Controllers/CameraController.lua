--[[
	CameraController (client) — STAGE 1
	First person built ON TOP of Roblox's default camera module (stable,
	smooth mouse look, handles mouse lock), with these guarantees:
	  * LockFirstPerson + zoom locked: no accidental third person, ever.
	  * Re-binds subject/type on every respawn (no broken camera after death).
	  * Own body and accessories are always hidden locally (LocalTransparencyModifier),
	    so they never block the view; the one-hand viewmodel is separate.
	  * Anti-clip: a spherecast from the body to the eye pulls the camera back
	    if it would end up inside geometry (e.g. crouch transitions, slopes).
	  * Smooth FOV changes (sprint) through SetFovTarget.
	  * Height follows the character: crouching lowers the body, so the camera
	    lowers with it with no separate offset to desynchronise.

	Render order (BindToRenderStep):
	  Camera (default) -> FP_CameraGuard (+1) -> FP_Targeting (+2)
	  -> FP_Hand (+3) -> FP_Arms (+4)
	Later stages (hand animation) read the final camera CFrame in their step.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local PlayerContext = require(script.Parent.PlayerContext)

local CameraController = {}

local CamCfg = Config.Camera
local player = Players.LocalPlayer

local fovTarget = CamCfg.FieldOfView
local hiddenParts: { Instance } = {}
local clipParams = RaycastParams.new()
clipParams.FilterType = Enum.RaycastFilterType.Exclude
clipParams.RespectCanCollide = true

CameraController.RenderPriority = Enum.RenderPriority.Camera.Value

local function enforcePlayerSettings()
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	if player.CameraMaxZoomDistance ~= CamCfg.ZoomDistance then
		player.CameraMaxZoomDistance = CamCfg.ZoomDistance
	end
	if player.CameraMinZoomDistance ~= CamCfg.ZoomDistance then
		player.CameraMinZoomDistance = CamCfg.ZoomDistance
	end
end

local function trackHidden(character: Model)
	table.clear(hiddenParts)
	local function add(d: Instance)
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= Contract.Names.PhysicsHand then
			table.insert(hiddenParts, d)
		end
	end
	for _, d in character:GetDescendants() do
		add(d)
	end
	return character.DescendantAdded:Connect(add)
end

local function bindCamera(humanoid: Humanoid)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
	camera.FieldOfView = CamCfg.FieldOfView
end

function CameraController.SetFovTarget(fov: number)
	fovTarget = fov
end

-- Extra instances the anti-clip probe must ignore (viewmodel, held object...).
local extraIgnore: { Instance } = {}
function CameraController.SetIgnoreList(list: { Instance })
	extraIgnore = list
end

local function step(dt: number)
	enforcePlayerSettings()
	local camera = workspace.CurrentCamera
	local character, humanoid, root = PlayerContext.Get()
	if character == nil or humanoid == nil or root == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= humanoid then
		bindCamera(humanoid)
	end

	-- FOV smoothing (frame-rate independent)
	local alpha = 1 - math.exp(-CamCfg.FovLerpSpeed * dt)
	camera.FieldOfView += (fovTarget - camera.FieldOfView) * alpha

	-- Keep own body/accessories invisible to the local player
	for i = #hiddenParts, 1, -1 do
		local p = hiddenParts[i]
		if p.Parent == nil then
			table.remove(hiddenParts, i)
		else
			(p :: any).LocalTransparencyModifier = 1
		end
	end

	-- Anti-clip: probe from inside the body to the eye position
	local eye = camera.CFrame.Position
	local origin = root.Position
	local offset = eye - origin
	if offset.Magnitude > 0.05 then
		local ignore = { character, camera }
		for _, inst in extraIgnore do
			table.insert(ignore, inst)
		end
		clipParams.FilterDescendantsInstances = ignore
		clipParams.CollisionGroup = Contract.CollisionGroups.Characters
		local hit = workspace:Spherecast(origin, CamCfg.ClipProbeRadius, offset, clipParams)
		if hit then
			local safe = math.max(0, hit.Distance - CamCfg.ClipPadding)
			camera.CFrame = CFrame.new(origin + offset.Unit * safe) * camera.CFrame.Rotation
		end
	end
end

function CameraController.Init()
	enforcePlayerSettings()
	local hiddenConnection: RBXScriptConnection? = nil
	PlayerContext.OnCharacter(function(character, humanoid)
		if hiddenConnection then
			hiddenConnection:Disconnect()
		end
		hiddenConnection = trackHidden(character)
		bindCamera(humanoid)
	end)
	RunService:BindToRenderStep("FP_CameraGuard", CameraController.RenderPriority + 1, step)
end

return CameraController
