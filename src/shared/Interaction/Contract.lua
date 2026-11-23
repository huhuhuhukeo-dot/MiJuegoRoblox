--[[
	Contract
	Tags, attributes and instance names that define the data contract between
	level design (Studio), the server systems and the client.

	HOW TO MAKE SOMETHING INTERACTIVE (no new scripts needed):
	  * Grabbable physics prop: tag a BasePart (the assembly root) with "Grabbable".
	      optional attributes: GrabEnabled (bool), LootValue (number) + tag "Loot".
	  * Interactable: tag a Model or BasePart with "Interactable" and set the
	      attribute InteractionType to the name of a module in
	      ServerScriptService.Server.Interactions (Door, Drawer, Switch, Button,
	      Collectible, Container, MoneyBag).
	  * Delivery zone: tag a BasePart with "DeliveryZone" (optional PowerGroup).
	  * Powered light: tag a BasePart with "PoweredLight" + attribute PowerGroup.
]]

local Contract = {}

Contract.Tags = {
	Grabbable = "Grabbable",
	Interactable = "Interactable",
	Loot = "Loot",
	DeliveryZone = "DeliveryZone",
	PoweredLight = "PoweredLight",
}

Contract.Attributes = {
	-- props
	HeldBy = "HeldBy", -- number (UserId) while held, replicated
	GrabEnabled = "GrabEnabled", -- bool, false disables grabbing
	Articulated = "Articulated", -- bool, part moves on a hinge/prismatic (door, drawer)
	LootValue = "LootValue", -- number
	PropId = "PropId", -- string, used by the recovery/reset system
	-- interactables
	InteractionType = "InteractionType",
	Prompt = "InteractPrompt", -- string shown by the client, set by the server
	InteractEnabled = "InteractEnabled", -- bool
	PowerGroup = "PowerGroup",
	-- characters
	Crouching = "Crouching",
	Sprinting = "Sprinting",
	HoldMode = "HoldMode", -- "Lift" | "Drag" | "Articulated" | nil
	CarrySpeedMultiplier = "CarrySpeedMultiplier",
	HandReady = "HandReady",
	-- players
	PocketLoot = "PocketLoot",
}

Contract.Names = {
	PhysicsHand = "PhysicsHand",
	HandAttachment = "HandAttachment",
	HandAlignPosition = "HandAlignPosition",
	HandAlignOrientation = "HandAlignOrientation",
	HeldObjectValue = "HeldObject", -- ObjectValue inside the character
	GrabAttachment = "GrabAttachment",
	RemotesFolder = "Remotes",
	GameState = "GameState", -- Folder in ReplicatedStorage with shared attributes
	TestArena = "TestArena",
}

Contract.CollisionGroups = {
	Default = "Default",
	Characters = "Characters",
	Hand = "Hand",
	Held = "Held",
}

return Contract
