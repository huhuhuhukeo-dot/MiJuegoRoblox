--[[
	ArmRenderer (client, visual only)
	Renders ONE arm per player from replicated physics data:
	  * local player: viewmodel arm parented to the camera; shoulder in camera
	    space, hand = the locally simulated PhysicsHand
	  * other players: arm from their real right shoulder to their replicated
	    PhysicsHand; their native right arm is hidden locally so each player
	    shows exactly one coherent hand
	The renderer never writes to physics or networking.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local ArmRig = require(script.Parent.ArmRig)
local Controllers = script.Parent.Parent.Controllers
local PlayerContext = require(Controllers.PlayerContext)
local CameraController = require(Controllers.CameraController)
local HandController = require(Controllers.HandController)
local GrabController = require(Controllers.GrabController)

local ArmRenderer = {}

local HandCfg = Config.Hand
local REMOTE_CULL_DISTANCE = 160
local NATIVE_RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" }

local localPlayer = Players.LocalPlayer
local localRig: any = nil
local localGrip = 0
local remoteFolder: Folder
local remotes: { [Player]: { rig: any, character: Model, grip: number } } = {}

local function colorsOf(character: Model): (Color3, Color3)
	local skin = Color3.fromRGB(234, 184, 146)
	local sleeve = Color3.fromRGB(60, 70, 90)
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		skin = bodyColors.RightArmColor3
	end
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt == nil then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			sleeve = torso.Color
		end
	end
	return skin, sleeve
end

function ArmRenderer.GetIgnoreList(): { Instance }
	return { remoteFolder }
end

local function approach(current: number, target: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-14 * dt))
end

local function updateLocal(dt: number)
	local character = PlayerContext.Get()
	local hand = HandController.GetHand()
	if character == nil or hand == nil then
		if localRig then
			localRig:SetVisible(false)
		end
		return
	end
	local camera = workspace.CurrentCamera
	if localRig == nil or localRig.model.Parent ~= camera then
		if localRig then
			localRig:Destroy()
		end
		local skin, sleeve = colorsOf(character)
		localRig = ArmRig.new(skin, sleeve, camera, 0.9)
	end
	localRig:SetVisible(true)
	local camCF = camera.CFrame
	local shoulder = camCF:PointToWorldSpace(HandCfg.ShoulderOffset)
	local held = GrabController.GetHeld()
	local gripTarget = if held then 1 elseif HandController.IsExtended() then 0.25 else 0.45
	localGrip = approach(localGrip, gripTarget, dt)
	local pole = camCF.RightVector * 0.6 - camCF.UpVector
	localRig:Update(shoulder, CFrame.new(hand.Position) * camCF.Rotation, pole, localGrip)
end

local function releaseRemote(player: Player)
	local entry = remotes[player]
	if entry then
		entry.rig:Destroy()
		for _, name in NATIVE_RIGHT_ARM do
			local p = entry.character:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.LocalTransparencyModifier = 0
			end
		end
		remotes[player] = nil
	end
end

local function updateRemotes(dt: number)
	local camPos = workspace.CurrentCamera.CFrame.Position
	for _, player in Players:GetPlayers() do
		if player == localPlayer then
			continue
		end
		local character = player.Character
		local hand = character and character:FindFirstChild(Contract.Names.PhysicsHand)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local entry = remotes[player]
		if character == nil or hand == nil or not hand:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
			if entry then
				releaseRemote(player)
			end
			continue
		end
		if entry and entry.character ~= character then
			releaseRemote(player)
			entry = nil
		end
		if entry == nil then
			local skin, sleeve = colorsOf(character)
			entry = { rig = ArmRig.new(skin, sleeve, remoteFolder, 0.8), character = character, grip = 0 }
			remotes[player] = entry
		end
		local visible = (hand.Position - camPos).Magnitude < REMOTE_CULL_DISTANCE
		entry.rig:SetVisible(visible)
		if not visible then
			continue
		end
		-- shoulder from the real rig
		local shoulder: Vector3
		local upper = character:FindFirstChild("RightUpperArm")
		local att = upper and upper:FindFirstChild("RightShoulderRigAttachment")
		local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
		if att and att:IsA("Attachment") then
			shoulder = att.WorldPosition
		elseif torso then
			shoulder = torso.CFrame:PointToWorldSpace(Vector3.new(1, 0.5, 0))
		else
			continue
		end
		for _, name in NATIVE_RIGHT_ARM do
			local p = character:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				p.LocalTransparencyModifier = 1
			end
		end
		local holding = character:GetAttribute(Contract.Attributes.HoldMode) ~= nil
		entry.grip = approach(entry.grip, if holding then 1 else 0.4, dt)
		local right = if torso then torso.CFrame.RightVector else Vector3.xAxis
		entry.rig:Update(shoulder, (hand :: BasePart).CFrame, right * 0.4 - Vector3.yAxis, entry.grip)
	end
end

function ArmRenderer.Init()
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "RemoteArms (local)"
	remoteFolder.Parent = workspace
	Players.PlayerRemoving:Connect(releaseRemote)
	RunService:BindToRenderStep("FP_Arms", CameraController.RenderPriority + 4, function(dt)
		updateLocal(dt)
		updateRemotes(dt)
	end)
end

return ArmRenderer
