--[[
	Switch interaction
	Model: Switch (Model) tag Interactable, InteractionType = "Switch"
	  Lever (BasePart, anchored)  rotated to show the state
	  attributes: PowerGroup (string), On (bool, initial state)
	State is global (WorldStateService power group) so every switch of the
	same group and every client stays in sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Interaction.Contract)

local Switch = {
	Type = "Switch",
	Cooldown = 0.5,
}

local LEVER_ANGLE = math.rad(35)
local levers: { [Instance]: { part: BasePart, base: CFrame } } = {}

local function render(model: Instance, on: boolean)
	local lever = levers[model]
	if lever and lever.part.Parent then
		lever.part.CFrame = lever.base * CFrame.Angles(if on then -LEVER_ANGLE else LEVER_ANGLE, 0, 0)
		lever.part.Color = if on then Color3.fromRGB(70, 200, 90) else Color3.fromRGB(200, 60, 60)
	end
	model:SetAttribute("On", on)
	model:SetAttribute(Contract.Attributes.Prompt, if on then "Apagar energía" else "Encender energía")
end

local function groupOf(model: Instance): string
	local g = model:GetAttribute(Contract.Attributes.PowerGroup)
	return if type(g) == "string" then g else "Default"
end

function Switch.Setup(model: Instance, ctx)
	local lever = model:FindFirstChild("Lever")
	if lever and lever:IsA("BasePart") then
		levers[model] = { part = lever, base = lever.CFrame }
	end
	local group = groupOf(model)
	if model:GetAttribute("On") == true then
		ctx.World.SetPower(group, true)
	end
	render(model, ctx.World.IsPowered(group))
	ctx.World.PowerChanged:Connect(function(changed: string, on: boolean)
		if changed == group and model.Parent then
			render(model, on)
		end
	end)
end

function Switch.Cleanup(model: Instance)
	levers[model] = nil
end

function Switch.Interact(_player: Player, model: Instance, ctx)
	local group = groupOf(model)
	ctx.World.SetPower(group, not ctx.World.IsPowered(group))
end

return Switch
