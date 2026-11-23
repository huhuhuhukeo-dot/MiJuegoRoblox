--[[
	Collectible interaction
	Any BasePart or Model tagged Interactable with InteractionType = "Collectible"
	and attribute LootValue. "E" puts it in the player's pocket (LootService).
	Pocket loot is delivered by entering an active delivery zone; it returns to
	the world if the carrier dies or leaves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Interaction.Contract)

local Collectible = {
	Type = "Collectible",
	Cooldown = 0.2,
}

function Collectible.Setup(inst: Instance)
	local value = inst:GetAttribute(Contract.Attributes.LootValue)
	value = if type(value) == "number" then value else 0
	inst:SetAttribute(Contract.Attributes.Prompt, string.format("Recoger ($%d)", value))
end

function Collectible.Interact(player: Player, inst: Instance, ctx)
	if inst:IsA("BasePart") then
		ctx.Grab.ForceRelease(inst, "Collected")
	end
	local value = ctx.Loot.Collect(player, inst)
	ctx.Notify(player, string.format("+$%d en el bolsillo", value))
end

return Collectible
