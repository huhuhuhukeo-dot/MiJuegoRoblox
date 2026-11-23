--[[
	HandService (server)
	Creates ONE physical hand per character and keeps it honest.

	The hand is a real unanchored part (its own assembly) driven by an
	AlignPosition + AlignOrientation in OneAttachment mode. Network ownership is
	given to the owning player, so the client writes the constraint targets
	locally and the resulting physics replicates to everybody. Nothing is
	teleported every frame: the hand moves only through constraint forces.

	Server responsibilities:
	  * build the hand (size, mass, collision group, constraints, ownership)
	  * validate continuously that it stays within reach of the head
	  * recover it (and release held objects) when it is out of bounds
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)

local HandService = {}

local HandCfg = Config.Hand
local Names = Contract.Names

type HandRecord = {
	player: Player,
	character: Model,
	hand: BasePart,
	violationTime: number,
}

local records: { [Player]: HandRecord } = {}
local onViolation: ((player: Player, reason: string) -> ())? = nil

local function maxLegalDistance(): number
	return HandCfg.MaxReach + HandCfg.ShoulderOffset.Magnitude + HandCfg.ServerReachTolerance
end

local function restPosition(character: Model): CFrame?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.CFrame * CFrame.new(HandCfg.IdleOffset)
	end
	return nil
end

-- Called by CharacterService once the character is in the Workspace.
function HandService.SetupCharacter(player: Player, character: Model): BasePart?
	local rest = restPosition(character)
	if rest == nil then
		return nil
	end

	local old = character:FindFirstChild(Names.PhysicsHand)
	if old then
		old:Destroy()
	end

	local hand = Instance.new("Part")
	hand.Name = Names.PhysicsHand
	hand.Size = HandCfg.Size
	hand.Shape = Enum.PartType.Block
	hand.Transparency = 1 -- the visible arm is rendered client-side (see client/Visual)
	hand.CanCollide = true
	hand.CanTouch = false
	hand.CastShadow = false
	hand.Massless = false -- separate assembly: Massless would be ignored anyway
	hand.CustomPhysicalProperties = PhysicalProperties.new(HandCfg.Density, HandCfg.Friction, 0, 1, 1)
	hand.CollisionGroup = Contract.CollisionGroups.Hand
	hand.CFrame = rest

	local attachment = Instance.new("Attachment")
	attachment.Name = Names.HandAttachment
	attachment.Parent = hand

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = Names.HandAlignPosition
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.MaxForce = HandCfg.MaxForce
	alignPosition.MaxVelocity = HandCfg.MaxVelocity
	alignPosition.Responsiveness = HandCfg.Responsiveness
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.RigidityEnabled = false
	alignPosition.Position = rest.Position
	alignPosition.Parent = hand

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = Names.HandAlignOrientation
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = HandCfg.MaxTorque
	alignOrientation.Responsiveness = HandCfg.OrientationResponsiveness
	alignOrientation.RigidityEnabled = false
	alignOrientation.CFrame = rest.Rotation
	alignOrientation.Parent = hand

	hand.Parent = character

	local ok, err = pcall(function()
		hand:SetNetworkOwner(player)
	end)
	if not ok then
		warn("[HandService] SetNetworkOwner failed: " .. tostring(err))
	end

	records[player] = { player = player, character = character, hand = hand, violationTime = 0 }
	character:SetAttribute(Contract.Attributes.HandReady, true)
	return hand
end

function HandService.GetHand(player: Player): BasePart?
	local r = records[player]
	if r and r.hand.Parent then
		return r.hand
	end
	return nil
end

function HandService.GetHandAttachment(player: Player): Attachment?
	local hand = HandService.GetHand(player)
	local att = hand and hand:FindFirstChild(Names.HandAttachment)
	if att and att:IsA("Attachment") then
		return att
	end
	return nil
end

-- Server-side recovery: put the hand back next to the head. Ownership is taken
-- back during the move so the client cannot immediately override it.
function HandService.ResetHand(player: Player)
	local r = records[player]
	if r == nil or r.hand.Parent == nil then
		return
	end
	local rest = restPosition(r.character)
	if rest == nil then
		return
	end
	pcall(function()
		r.hand:SetNetworkOwner(nil)
	end)
	r.hand.AssemblyLinearVelocity = Vector3.zero
	r.hand.AssemblyAngularVelocity = Vector3.zero
	r.hand.CFrame = rest
	task.defer(function()
		if r.hand.Parent and player.Parent then
			pcall(function()
				r.hand:SetNetworkOwner(player)
			end)
		end
	end)
end

function HandService.SetViolationHandler(fn: (player: Player, reason: string) -> ())
	onViolation = fn
end

local function validate(dt: number)
	local limit = maxLegalDistance()
	for player, r in records do
		if r.hand.Parent == nil or r.character.Parent == nil then
			records[player] = nil
			continue
		end
		local head = r.character:FindFirstChild("Head")
		if head == nil or not head:IsA("BasePart") then
			continue
		end
		local distance = (r.hand.Position - head.Position).Magnitude
		if distance > limit then
			r.violationTime += dt
			if r.violationTime >= HandCfg.ServerViolationTime then
				r.violationTime = 0
				if onViolation then
					onViolation(player, "HandOutOfReach")
				end
				HandService.ResetHand(player)
			end
		else
			r.violationTime = 0
		end
		-- ownership watchdog (auto-assignment must never give it to someone else)
		local ok, owner = pcall(function()
			return r.hand:GetNetworkOwner()
		end)
		if ok and owner ~= player then
			pcall(function()
				r.hand:SetNetworkOwner(player)
			end)
		end
	end
end

function HandService.Init()
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
	task.spawn(function()
		local interval = HandCfg.ServerCheckInterval
		while true do
			local dt = task.wait(interval)
			validate(dt)
		end
	end)
end

return HandService
