--[[
	GrabController (client) — STAGE 4
	Input + prediction side of grabbing. The SERVER decides everything:
	the client only asks (GrabRequest) and mirrors the server's answer, which
	arrives as the character's "HeldObject" ObjectValue. That makes the client
	state self-healing: forced releases (death, delivery, anti-exploit, locked
	door, another system) are picked up automatically.

	Left click (hold): grab what the crosshair points at; release to drop.
	(Controls.GrabIsToggle = true switches to click-to-grab / click-to-drop.)
	The prop keeps its physical velocity when dropped (no velocity reset).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Controls = require(Shared.Config.Controls)
local Contract = require(Shared.Interaction.Contract)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerContext = require(script.Parent.PlayerContext)
local InputBinder = require(script.Parent.InputBinder)
local TargetingController = require(script.Parent.TargetingController)
local HandController = require(script.Parent.HandController)

local GrabController = {}
GrabController.Feedback = Signal.new() -- (reasonCode: string) for the HUD

local GrabCfg = Config.Grab

local grabRemote: RemoteFunction
local releaseRemote: RemoteEvent

local buttonDown = false
local pending = false
local grabbedWithButton = false
local breakTime = 0

function GrabController.GetHeld(): BasePart?
	local character = PlayerContext.Get()
	local v = character and character:FindFirstChild(Contract.Names.HeldObjectValue)
	if v and v:IsA("ObjectValue") and v.Value and v.Value:IsA("BasePart") and v.Value.Parent then
		return v.Value :: BasePart
	end
	return nil
end

function GrabController.IsPending(): boolean
	return pending
end

function GrabController.Release()
	grabbedWithButton = false
	if GrabController.GetHeld() then
		releaseRemote:FireServer()
	end
end

local function tryGrab()
	if pending or GrabController.GetHeld() then
		return
	end
	local target = TargetingController.Get()
	local part = target.grabbable
	if part == nil or target.position == nil then
		return
	end
	if target.distance > GrabCfg.Range then
		GrabController.Feedback:Fire("TooFar")
		return
	end
	local heldBy = part:GetAttribute(Contract.Attributes.HeldBy)
	if heldBy ~= nil then
		GrabController.Feedback:Fire("HeldByOther")
		return
	end
	pending = true
	local localPoint = part.CFrame:PointToObjectSpace(target.position)
	local distance = target.distance
	task.spawn(function()
		local ok, success, detail = pcall(function()
			return grabRemote:InvokeServer(part, localPoint)
		end)
		pending = false
		if ok and success == true then
			grabbedWithButton = true
			HandController.SetReach(distance) -- no jump: start where it was grabbed
			if not Controls.GrabIsToggle and not buttonDown then
				GrabController.Release() -- button released while waiting for the server
			end
		else
			GrabController.Feedback:Fire(if ok then tostring(detail) else "ServerError")
		end
	end)
end

local function onGrabInput(inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		buttonDown = true
		if GrabController.GetHeld() then
			-- toggle mode, or the object was picked up with E (MoneyBag)
			if Controls.GrabIsToggle or not grabbedWithButton then
				GrabController.Release()
			end
			return
		end
		tryGrab()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		buttonDown = false
		if not Controls.GrabIsToggle and grabbedWithButton then
			GrabController.Release()
		end
	end
end

local function step(dt: number)
	local held = GrabController.GetHeld()
	HandController.SetHeld(held)
	if held == nil then
		grabbedWithButton = false
		breakTime = 0
		return
	end
	-- Auto release if the prop is stuck far from the hand (e.g. behind a wall)
	local hand = HandController.GetHand()
	local att = held:FindFirstChild(Contract.Names.GrabAttachment)
	if hand and att and att:IsA("Attachment") then
		if (att.WorldPosition - hand.Position).Magnitude > GrabCfg.BreakDistance then
			breakTime += dt
			if breakTime >= GrabCfg.BreakTime then
				breakTime = 0
				GrabController.Release()
				GrabController.Feedback:Fire("Slipped")
			end
		else
			breakTime = 0
		end
	end
end

function GrabController.Init()
	grabRemote = Remotes.Get("GrabRequest")
	releaseRemote = Remotes.Get("ReleaseRequest")
	InputBinder.Bind("FP_Grab", Controls.Grab, onGrabInput)
	PlayerContext.CharacterRemoved:Connect(function()
		buttonDown = false
		grabbedWithButton = false
		pending = false
	end)
	RunService.Heartbeat:Connect(step)
end

return GrabController
