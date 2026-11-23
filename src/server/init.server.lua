--[[
	Server bootstrap
	Initialises every server system in dependency order. Each service is a
	ModuleScript with an Init function; no other server Scripts are needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)

local Services = script:WaitForChild("Services")
local CollisionService = require(Services.CollisionService)
local WorldStateService = require(Services.WorldStateService)
local HandService = require(Services.HandService)
local GrabService = require(Services.GrabService)
local MovementService = require(Services.MovementService)
local LootService = require(Services.LootService)
local RecoveryService = require(Services.RecoveryService)
local InteractionService = require(Services.InteractionService)
local DeliveryService = require(Services.DeliveryService)
local CharacterService = require(Services.CharacterService)
local TestArenaBuilder = require(script:WaitForChild("World"):WaitForChild("TestArenaBuilder"))


-- 1. Networking & physics rules
Remotes.Init()
CollisionService.Init()
WorldStateService.Init()

-- 2. Content (test scene) before the systems that scan tags
if Config.World.BuildTestArena and workspace:FindFirstChild("TestArena") == nil then
	TestArenaBuilder.Build(workspace, ServerStorage)
end

-- 3. Gameplay systems
local notifyRemote = Remotes.Get("Notify")
local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, "Message", message)
end
local function notifyAll(kind: string, data: any)
	notifyRemote:FireAllClients(kind, data)
end

HandService.Init()
GrabService.Init()
MovementService.Init()
LootService.Init()
RecoveryService.Init()
InteractionService.Init({
	Config = Config,
	Grab = GrabService,
	Hand = HandService,
	Loot = LootService,
	Recovery = RecoveryService,
	World = WorldStateService,
	Notify = notify,
	NotifyAll = notifyAll,
})
DeliveryService.Init(notifyAll)

-- 4. Players last, so every system is ready for the first character
CharacterService.Init()

print("[Server] prototype systems ready")
