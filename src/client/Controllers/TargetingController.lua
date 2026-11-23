--[[
	TargetingController (client)
	One raycast per frame from the camera centre. Every other controller (HUD,
	grab, interaction) reads the same result, so prompts and actions always
	agree with each other. Purely client-side; the server re-validates.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Targeting = require(Shared.Interaction.Targeting)

local PlayerContext = require(script.Parent.PlayerContext)
local CameraController = require(script.Parent.CameraController)

local TargetingController = {}

export type Target = {
	hit: BasePart?,
	position: Vector3?,
	normal: Vector3?,
	distance: number,
	grabbable: BasePart?,
	interactable: Instance?,
}

local MAX_DISTANCE = math.max(Config.Grab.Range, Config.Interaction.Range) + 1
local EMPTY: Target = { distance = math.huge }

local current: Target = EMPTY
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = false -- props being carried (no-collide groups) stay targetable

local extraIgnore: { Instance } = {}

function TargetingController.SetIgnoreList(list: { Instance })
	extraIgnore = list
end

function TargetingController.Get(): Target
	return current
end

local function step()
	local character = PlayerContext.Get()
	if character == nil then
		current = EMPTY
		return
	end
	local camera = workspace.CurrentCamera
	local ignore = { character, camera }
	for _, inst in extraIgnore do
		table.insert(ignore, inst)
	end
	params.FilterDescendantsInstances = ignore
	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, camera.CFrame.LookVector * MAX_DISTANCE, params)
	if result == nil or not result.Instance:IsA("BasePart") then
		current = EMPTY
		return
	end
	local hit = result.Instance :: BasePart
	current = {
		hit = hit,
		position = result.Position,
		normal = result.Normal,
		distance = result.Distance,
		grabbable = Targeting.findGrabbable(hit),
		interactable = Targeting.findInteractable(hit),
	}
end

function TargetingController.Init()
	RunService:BindToRenderStep("FP_Targeting", CameraController.RenderPriority + 2, step)
end

return TargetingController
