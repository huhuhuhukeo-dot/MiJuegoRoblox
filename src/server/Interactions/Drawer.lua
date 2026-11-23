--[[
	Drawer interaction
	Model layout:
	  Drawer (Model)  tag Interactable, InteractionType = "Drawer"
	    Tray (BasePart, unanchored)  front of the drawer; other tray parts welded to it
	    Body (BasePart, anchored)    cabinet part holding Attachment0
	    PrismaticConstraint          slides along Attachment0's X axis
	  Optional attribute: OpenDistance (number)
	Works with E (servo) or by grabbing/pulling the tray with the hand.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local ArticulatedJoint = require(script.Parent.ArticulatedJoint)

local DrawerCfg = Config.Interaction.Drawer

local Drawer = {
	Type = "Drawer",
	Cooldown = 0.35,
}

local joints: { [Instance]: any } = {}

local function updatePrompt(model: Instance)
	local joint = joints[model]
	if joint then
		model:SetAttribute(Contract.Attributes.Prompt, if joint:IsOpen() then "Cerrar cajón" else "Abrir cajón")
	end
end

function Drawer.Setup(model: Instance, _ctx)
	local tray = model:FindFirstChild("Tray")
	local slider = model:FindFirstChildWhichIsA("PrismaticConstraint", true)
	if not (tray and tray:IsA("BasePart") and slider) then
		warn("[Drawer] " .. model:GetFullName() .. " needs a Tray part and a PrismaticConstraint")
		return
	end
	local distance = model:GetAttribute("OpenDistance")
	distance = if type(distance) == "number" then distance else DrawerCfg.OpenDistance
	slider.LimitsEnabled = true
	slider.LowerLimit = 0
	slider.UpperLimit = distance + 0.1

	tray:SetAttribute(Contract.Attributes.Articulated, true)
	if not CollectionService:HasTag(tray, Contract.Tags.Grabbable) then
		CollectionService:AddTag(tray, Contract.Tags.Grabbable)
	end
	joints[model] = ArticulatedJoint.new({
		instance = model,
		part = tray,
		constraint = slider,
		openTarget = distance,
		closedTarget = 0,
		openThreshold = DrawerCfg.OpenThreshold,
		servoSpeed = DrawerCfg.ServoSpeed,
		servoStrength = DrawerCfg.ServoForce,
		friction = DrawerCfg.FrictionForce,
	})
	model:GetAttributeChangedSignal("JointState"):Connect(function()
		updatePrompt(model)
	end)
	updatePrompt(model)
end

function Drawer.Cleanup(model: Instance)
	local joint = joints[model]
	if joint then
		joint:Destroy()
		joints[model] = nil
	end
end

function Drawer.CanInteract(_player: Player, model: Instance)
	local joint = joints[model]
	if joint == nil then
		return false, nil
	end
	if joint.grabbed then
		return false, "Alguien está sujetando el cajón"
	end
	return true, nil
end

function Drawer.Interact(_player: Player, model: Instance)
	joints[model]:Toggle()
end

function Drawer.OnGrabStarted(_player: Player, model: Instance)
	local joint = joints[model]
	if joint then
		joint:OnGrabStarted()
	end
end

function Drawer.OnGrabEnded(_player: Player, model: Instance)
	local joint = joints[model]
	if joint then
		joint:OnGrabEnded()
	end
end

function Drawer.OnReset(model: Instance)
	local joint = joints[model]
	if joint and joint:IsOpen() then
		joint:Toggle()
	end
end

return Drawer
