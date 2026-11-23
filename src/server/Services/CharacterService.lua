--[[
	CharacterService (server)
	Player / character lifecycle orchestration:
	  * locks first person on the Player (server value, replicated)
	  * per character: collision groups, physical hand, movement state
	  * death / respawn / leave: releases held objects and loot safely
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Contract = require(Shared.Interaction.Contract)
local Maid = require(Shared.Util.Maid)

local CollisionService = require(script.Parent.CollisionService)
local HandService = require(script.Parent.HandService)
local GrabService = require(script.Parent.GrabService)
local MovementService = require(script.Parent.MovementService)
local LootService = require(script.Parent.LootService)

local CharacterService = {}

local characterMaids: { [Player]: any } = {}

local function lockFirstPerson(player: Player)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = Config.Camera.ZoomDistance
	player.CameraMaxZoomDistance = Config.Camera.ZoomDistance
	player.DevEnableMouseLock = false
end

local function onCharacterAdded(player: Player, character: Model)
	local previous = characterMaids[player]
	if previous then
		previous:Clean()
	end
	local maid = Maid.new()
	characterMaids[player] = maid

	-- The character may not be parented yet when CharacterAdded fires.
	if character.Parent == nil then
		character.AncestryChanged:Wait()
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local head = character:WaitForChild("Head", 10)
	if not (humanoid and root and head) or character.Parent == nil then
		warn("[CharacterService] incomplete character for " .. player.Name)
		return
	end
	if player.Character ~= character then
		return -- respawned while we were waiting
	end

	lockFirstPerson(player)
	maid:Give(CollisionService.TagCharacter(character, Contract.Names.PhysicsHand))
	MovementService.SetupCharacter(player, character)
	HandService.SetupCharacter(player, character)

	maid:Give((humanoid :: Humanoid).Died:Connect(function()
		GrabService.OnCharacterLost(player)
		LootService.DropPocket(player, "Died")
	end))
end

local function onPlayerAdded(player: Player)
	lockFirstPerson(player)
	player:SetAttribute(Contract.Attributes.PocketLoot, 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		GrabService.OnCharacterLost(player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function CharacterService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		GrabService.OnCharacterLost(player)
		LootService.DropPocket(player, "Left")
		local maid = characterMaids[player]
		if maid then
			maid:Clean()
			characterMaids[player] = nil
		end
	end)
end

return CharacterService
