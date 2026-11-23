--[[
	MoneyBag interaction
	A money bag is a physical prop: tags Grabbable + Interactable + Loot,
	InteractionType = "MoneyBag", attribute LootValue.
	  * Left click: grab it with the hand like any prop (GrabService)
	  * E: server-side pick up into the hand (same validated GrabService path);
	       E again while holding it drops it.
	It is delivered by dropping/carrying it into an active delivery zone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Interaction.Contract)

local MoneyBag = {
	Type = "MoneyBag",
	Cooldown = 0.3,
}

local REASONS = {
	AlreadyHolding = "Ya tienes algo en la mano",
	TooHeavy = "Demasiado pesado",
	Obstructed = "No llegas a la bolsa",
	TooFar = "Demasiado lejos",
}

function MoneyBag.Setup(bag: Instance)
	local value = bag:GetAttribute(Contract.Attributes.LootValue)
	value = if type(value) == "number" then value else 0
	bag:SetAttribute(Contract.Attributes.Prompt, string.format("Agarrar bolsa ($%d)", value))
end

function MoneyBag.CanInteract(player: Player, bag: Instance, ctx)
	if not bag:IsA("BasePart") then
		return false, nil
	end
	local holder = ctx.Grab.GetHolder(bag)
	if holder and holder ~= player then
		return false, "Otro jugador tiene la bolsa"
	end
	return true, nil
end

function MoneyBag.Interact(player: Player, bag: Instance, ctx)
	local part = bag :: BasePart
	if ctx.Grab.GetHolder(part) == player then
		ctx.Grab.Release(player, "Released")
		return
	end
	local ok, reason = ctx.Grab.TryGrab(player, part, Vector3.zero)
	if not ok then
		ctx.Notify(player, REASONS[reason] or "No puedes agarrar la bolsa")
	end
end

return MoneyBag
