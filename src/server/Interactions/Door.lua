--[[
	Door interaction
	Expected model layout (built by TestArenaBuilder, or by hand in Studio):
	  Door (Model)  tag Interactable, InteractionType = "Door"
	    Panel (BasePart, unanchored)      the moving leaf
	    Frame (BasePart, anchored)        holds the hinge attachment
	    HingeConstraint (anywhere inside) Attachment0 on Frame, Attachment1 on Panel
	  Optional attributes on the model: Locked (bool), OpenAngle (number)

	Ways to use it:
	  * E: opens away from the player / closes (servo)
	  * Grab the panel (left click): pull/push it physically with the hand
	  * Push it with the extended hand (right click): physical collision
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local ArticulatedJoint = require(script.Parent.ArticulatedJoint)

local DoorCfg = Config.Interaction.Door

local Door = {
	Type = "Door",
	Cooldown = 0.4,
}

local joints: { [Instance]: any } = {}

local function updatePrompt(model: Instance)
	local joint = joints[model]
	if joint == nil then
		return
	end
	local state = joint:GetState()
	local text = if state == "Locked" then "Puerta bloqueada" elseif state == "Open" then "Cerrar puerta" else "Abrir puerta"
	model:SetAttribute(Contract.Attributes.Prompt, text)
end

-- Picks the opening direction that moves the leaf AWAY from the player.
local function openDirectionFor(joint, player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hinge = joint.constraint :: HingeConstraint
	local a0 = hinge.Attachment0
	if root == nil or a0 == nil then
		return 1
	end
	local pivot = a0.WorldPosition
	local axis = a0.WorldAxis
	local offset = joint.part.Position - pivot
	local angle = math.rad(DoorCfg.OpenAngle)
	local plus = pivot + CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(offset)
	local minus = pivot + CFrame.fromAxisAngle(axis, -angle):VectorToWorldSpace(offset)
	local p = (root :: BasePart).Position
	return if (plus - p).Magnitude >= (minus - p).Magnitude then 1 else -1
end

function Door.Setup(model: Instance, ctx)
	local panel = model:FindFirstChild("Panel")
	local hinge = model:FindFirstChildWhichIsA("HingeConstraint", true)
	if not (panel and panel:IsA("BasePart") and hinge) then
		warn("[Door] " .. model:GetFullName() .. " needs a Panel part and a HingeConstraint")
		return
	end
	local openAngle = model:GetAttribute("OpenAngle")
	openAngle = if type(openAngle) == "number" then openAngle else DoorCfg.OpenAngle

	hinge.LimitsEnabled = true
	hinge.LowerAngle = -DoorCfg.LimitAngle
	hinge.UpperAngle = DoorCfg.LimitAngle

	panel:SetAttribute(Contract.Attributes.Articulated, true)
	if not CollectionService:HasTag(panel, Contract.Tags.Grabbable) then
		CollectionService:AddTag(panel, Contract.Tags.Grabbable)
	end

	local joint = ArticulatedJoint.new({
		instance = model,
		part = panel,
		constraint = hinge,
		openTarget = openAngle,
		closedTarget = 0,
		openThreshold = DoorCfg.OpenThreshold,
		servoSpeed = DoorCfg.ServoSpeed,
		servoStrength = DoorCfg.ServoTorque,
		friction = DoorCfg.FrictionTorque,
	})
	joints[model] = joint
	joint.baseOpenAngle = openAngle

	if model:GetAttribute("StartLocked") == nil then
		model:SetAttribute("StartLocked", model:GetAttribute("Locked") == true)
	end
	if model:GetAttribute("Locked") == true then
		joint:SetLocked(true)
	end
	model:GetAttributeChangedSignal("Locked"):Connect(function()
		local want = model:GetAttribute("Locked") == true
		if want then
			ctx.Grab.ForceRelease(panel, "DoorLocked")
		end
		joint:SetLocked(want)
		updatePrompt(model)
	end)
	model:GetAttributeChangedSignal("JointState"):Connect(function()
		updatePrompt(model)
	end)
	updatePrompt(model)
end

function Door.Cleanup(model: Instance)
	local joint = joints[model]
	if joint then
		joint:Destroy()
		joints[model] = nil
	end
end

function Door.CanInteract(_player: Player, model: Instance)
	local joint = joints[model]
	if joint == nil then
		return false, nil
	end
	if joint:IsLocked() then
		return false, "La puerta está bloqueada"
	end
	if joint.grabbed then
		return false, "Alguien está sujetando la puerta"
	end
	return true, nil
end

function Door.Interact(player: Player, model: Instance)
	local joint = joints[model]
	if not joint:IsOpen() then
		joint:SetOpenTarget(joint.baseOpenAngle * openDirectionFor(joint, player))
	end
	joint:Toggle()
end

function Door.OnGrabStarted(_player: Player, model: Instance)
	local joint = joints[model]
	if joint then
		joint:OnGrabStarted()
	end
end

function Door.OnGrabEnded(_player: Player, model: Instance)
	local joint = joints[model]
	if joint then
		joint:OnGrabEnded()
	end
end

function Door.OnReset(model: Instance)
	local joint = joints[model]
	if joint == nil then
		return
	end
	local startLocked = model:GetAttribute("StartLocked") == true
	if model:GetAttribute("Locked") ~= startLocked then
		model:SetAttribute("Locked", startLocked) -- triggers the change handler
	elseif not startLocked and joint:IsOpen() then
		joint:Toggle() -- close
	end
end

return Door
