--[[
	PlayerContext (client)
	Single place that tracks the local character and tells controllers when a
	new one is ready (after respawn) or gone. Avoids every controller writing
	its own CharacterAdded / WaitForChild logic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local PlayerContext = {}
PlayerContext.CharacterReady = Signal.new() -- (character, humanoid, root, head)
PlayerContext.CharacterRemoved = Signal.new() -- (character)

local player = Players.LocalPlayer
local current: { character: Model, humanoid: Humanoid, root: BasePart, head: BasePart }? = nil

function PlayerContext.Get(): (Model?, Humanoid?, BasePart?, BasePart?)
	local c = current
	if c and c.character.Parent and c.humanoid.Health > 0 then
		return c.character, c.humanoid, c.root, c.head
	end
	return nil, nil, nil, nil
end

-- Character even if dead (for cleanup).
function PlayerContext.GetCharacter(): Model?
	return if current then current.character else nil
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 15)
	local root = character:WaitForChild("HumanoidRootPart", 15)
	local head = character:WaitForChild("Head", 15)
	if not (humanoid and root and head) or player.Character ~= character then
		return
	end
	current = { character = character, humanoid = humanoid :: Humanoid, root = root :: BasePart, head = head :: BasePart }
	PlayerContext.CharacterReady:Fire(character, humanoid, root, head)
end

function PlayerContext.Init()
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function(character)
		if current and current.character == character then
			current = nil
		end
		PlayerContext.CharacterRemoved:Fire(character)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Lets controllers that initialise late still receive the current character.
function PlayerContext.OnCharacter(fn: (Model, Humanoid, BasePart, BasePart) -> ())
	PlayerContext.CharacterReady:Connect(fn)
	local character, humanoid, root, head = PlayerContext.Get()
	if character and humanoid and root and head then
		task.spawn(fn, character, humanoid, root, head)
	end
end

return PlayerContext
