--[[
	Button interaction (momentary)
	Model: Button (Model) tag Interactable, InteractionType = "Button"
	  Cap (BasePart, anchored)  moves in when pressed
	  attributes:
	    Action  "ResetArena" | "ToggleLock" | "TogglePower"
	    Target  for ToggleLock: the Id attribute of a Door model
	            for TogglePower: a power group name
	New actions are added to the ACTIONS table below.
]]

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Interaction.Contract)

local Button = {
	Type = "Button",
	Cooldown = 1.0,
}

local function findById(id: any): Instance?
	if type(id) ~= "string" then
		return nil
	end
	for _, inst in CollectionService:GetTagged(Contract.Tags.Interactable) do
		if inst:GetAttribute("Id") == id and inst:IsDescendantOf(workspace) then
			return inst
		end
	end
	return nil
end

local ACTIONS = {
	ResetArena = {
		prompt = function()
			return "Reiniciar escenario"
		end,
		run = function(player: Player, _model: Instance, ctx)
			ctx.World.ResetAll()
			ctx.NotifyAll("ArenaReset", player.DisplayName)
		end,
	},
	ToggleLock = {
		prompt = function(model: Instance)
			local door = findById(model:GetAttribute("Target"))
			if door and door:GetAttribute("Locked") == true then
				return "Desbloquear puerta"
			end
			return "Bloquear puerta"
		end,
		run = function(player: Player, model: Instance, ctx)
			local door = findById(model:GetAttribute("Target"))
			if door == nil then
				ctx.Notify(player, "Este botón no está conectado a ninguna puerta")
				return
			end
			door:SetAttribute("Locked", door:GetAttribute("Locked") ~= true)
		end,
	},
	TogglePower = {
		prompt = function()
			return "Pulsar"
		end,
		run = function(_player: Player, model: Instance, ctx)
			local group = model:GetAttribute("Target")
			if type(group) == "string" then
				ctx.World.SetPower(group, not ctx.World.IsPowered(group))
			end
		end,
	},
}

local function refreshPrompt(model: Instance)
	local action = ACTIONS[model:GetAttribute("Action")]
	model:SetAttribute(Contract.Attributes.Prompt, if action then action.prompt(model) else "Botón")
end

function Button.Setup(model: Instance, _ctx)
	refreshPrompt(model)
	local door = findById(model:GetAttribute("Target"))
	if door then
		door:GetAttributeChangedSignal("Locked"):Connect(function()
			refreshPrompt(model)
		end)
	end
end

function Button.CanInteract(_player: Player, model: Instance)
	if ACTIONS[model:GetAttribute("Action")] == nil then
		return false, "Este botón no tiene ninguna acción"
	end
	return true, nil
end

function Button.Interact(player: Player, model: Instance, ctx)
	local cap = model:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		local base = cap.CFrame
		local pressed = base * CFrame.new(0, 0, cap.Size.Z * 0.6)
		local tween = TweenService:Create(cap, TweenInfo.new(0.08), { CFrame = pressed })
		tween.Completed:Once(function()
			TweenService:Create(cap, TweenInfo.new(0.15), { CFrame = base }):Play()
		end)
		tween:Play()
	end
	ACTIONS[model:GetAttribute("Action")].run(player, model, ctx)
	refreshPrompt(model)
end

return Button
