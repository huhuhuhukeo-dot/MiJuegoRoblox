--[[
	Client bootstrap
	Initialises every client controller in dependency order. Controllers are
	ModuleScripts; this is the only LocalScript.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes") -- created by the server at boot

local Controllers = script:WaitForChild("Controllers")
local Visual = script:WaitForChild("Visual")

local PlayerContext = require(Controllers.PlayerContext)
local CameraController = require(Controllers.CameraController)
local MovementController = require(Controllers.MovementController)
local TargetingController = require(Controllers.TargetingController)
local HandController = require(Controllers.HandController)
local GrabController = require(Controllers.GrabController)
local InteractionController = require(Controllers.InteractionController)
local HUDController = require(Controllers.HUDController)
local ArmRenderer = require(Visual.ArmRenderer)

PlayerContext.Init()
CameraController.Init() -- Stage 1
MovementController.Init() -- Stage 2
TargetingController.Init()
HandController.Init() -- Stage 3
GrabController.Init() -- Stage 4
InteractionController.Init() -- Stage 5
ArmRenderer.Init() -- Stage 3/6 visuals (local + remote hands)
HUDController.Init()

-- Local-only visuals must never block gameplay rays
local ignore = ArmRenderer.GetIgnoreList()
TargetingController.SetIgnoreList(ignore)
HandController.SetIgnoreList(ignore)
CameraController.SetIgnoreList(ignore)
