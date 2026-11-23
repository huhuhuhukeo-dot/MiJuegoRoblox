--[[
	InteractionController (client) — STAGE 5
	"E" sends the interactable under the crosshair to the server. Prompts are
	read from the InteractPrompt attribute the server keeps up to date, so the
	client never has to know how each interaction works.
	If the player holds an interactable prop (money bag), E acts on it (drop).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Controls = require(Shared.Config.Controls)
local Contract = require(Shared.Interaction.Contract)
local Targeting = require(Shared.Interaction.Targeting)
local Remotes = require(Shared.Net.Remotes)

local PlayerContext = require(script.Parent.PlayerContext)
local InputBinder = require(script.Parent.InputBinder)
local TargetingController = require(script.Parent.TargetingController)
local GrabController = require(script.Parent.GrabController)

local InteractionController = {}

local interactRemote: RemoteEvent

-- Interactable currently under the crosshair and within range (or nil).
function InteractionController.GetFocus(): Instance?
	local target = TargetingController.Get()
	local inst = target.interactable
	if inst == nil or target.distance > Config.Interaction.Range then
		return nil
	end
	if inst:GetAttribute(Contract.Attributes.InteractEnabled) == false then
		return nil
	end
	return inst
end

local function interact()
	if PlayerContext.Get() == nil then
		return
	end
	local held = GrabController.GetHeld()
	local heldInteractable = held and Targeting.findInteractable(held)
	local focus = InteractionController.GetFocus()
	if heldInteractable and (focus == nil or focus == heldInteractable) then
		interactRemote:FireServer(heldInteractable)
	elseif focus then
		interactRemote:FireServer(focus)
	end
end

function InteractionController.Init()
	interactRemote = Remotes.Get("InteractRequest")
	InputBinder.Bind("FP_Interact", Controls.Interact, function(inputState)
		if inputState == Enum.UserInputState.Begin then
			interact()
		end
	end)
end

return InteractionController
