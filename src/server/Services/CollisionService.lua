--[[
	CollisionService
	Registers the collision groups and the collision matrix.

	                Default  Characters  Hand   Held
	  Default         yes       yes       yes    yes
	  Characters      yes       yes       NO     NO   (no standing on a carried box, no self-push)
	  Hand            yes       NO        NO     NO   (the hand pushes props/doors, never players)
	  Held            yes       NO        NO     yes  (carried props still hit walls & other props)
]]

local PhysicsService = game:GetService("PhysicsService")

local Contract = require(game:GetService("ReplicatedStorage").Shared.Interaction.Contract)

local CollisionService = {}

local G = Contract.CollisionGroups

function CollisionService.Init()
	for _, name in { G.Characters, G.Hand, G.Held } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(G.Characters, G.Hand, false)
	PhysicsService:CollisionGroupSetCollidable(G.Characters, G.Held, false)
	PhysicsService:CollisionGroupSetCollidable(G.Hand, G.Hand, false)
	PhysicsService:CollisionGroupSetCollidable(G.Hand, G.Held, false)
	PhysicsService:CollisionGroupSetCollidable(G.Held, G.Held, true)
	PhysicsService:CollisionGroupSetCollidable(G.Characters, G.Characters, true)
end

-- Assigns a group to every BasePart of a character, including later accessories.
function CollisionService.TagCharacter(character: Model, handName: string)
	local function apply(inst: Instance)
		if inst:IsA("BasePart") then
			inst.CollisionGroup = if inst.Name == handName then G.Hand else G.Characters
		end
	end
	for _, d in character:GetDescendants() do
		apply(d)
	end
	return character.DescendantAdded:Connect(apply)
end

return CollisionService
