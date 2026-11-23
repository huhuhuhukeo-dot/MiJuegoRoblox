--[[
	HUDController (client)
	Functional prototype HUD; every element reflects real game state:
	  * crosshair: white = nothing, green = grabbable, amber = interactable
	  * context prompt: what E / left click will do on the current target,
	    including the predicted lift/drag classification of the prop
	  * hold indicator, movement state, team loot, pocket loot, power state
	  * notifications from the server (Notify remote) and grab feedback
	  * help panel (H) generated from Shared.Config.Controls
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.GameConfig)
local Controls = require(Shared.Config.Controls)
local Contract = require(Shared.Interaction.Contract)
local Targeting = require(Shared.Interaction.Targeting)
local GrabMath = require(Shared.Physics.GrabMath)
local Remotes = require(Shared.Net.Remotes)

local PlayerContext = require(script.Parent.PlayerContext)
local InputBinder = require(script.Parent.InputBinder)
local TargetingController = require(script.Parent.TargetingController)
local GrabController = require(script.Parent.GrabController)
local InteractionController = require(script.Parent.InteractionController)
local MovementController = require(script.Parent.MovementController)

local HUDController = {}

local player = Players.LocalPlayer
local Names = Controls.DisplayNames

local REASONS = {
	TooFar = "Demasiado lejos",
	TooHeavy = "Demasiado pesado para moverlo",
	TooBig = "Demasiado grande",
	HeldByOther = "Otro jugador lo está sujetando",
	Obstructed = "Algo bloquea el camino",
	Locked = "Está bloqueado",
	AlreadyHolding = "Ya tienes algo en la mano",
	RateLimited = "Más despacio",
	NotAlive = "No puedes hacerlo ahora",
	NoHand = "La mano aún no está lista",
	Disabled = "No se puede agarrar",
	NotGrabbable = "No se puede agarrar",
	Slipped = "Se te ha escapado",
	ServerError = "Error del servidor",
	InvalidTarget = "Objetivo no válido",
}

local COLORS = {
	idle = Color3.fromRGB(255, 255, 255),
	grab = Color3.fromRGB(90, 230, 120),
	interact = Color3.fromRGB(255, 195, 70),
	blocked = Color3.fromRGB(230, 80, 80),
}

local gui: ScreenGui
local crosshair: Frame
local promptLabel: TextLabel
local holdLabel: TextLabel
local stateLabel: TextLabel
local lootLabel: TextLabel
local toastFrame: Frame
local helpFrame: Frame

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(245, 245, 245)
	l.TextStrokeTransparency = 0.5
	l.TextSize = 18
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function toast(text: string, color: Color3?)
	local l = label(toastFrame, {
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		TextColor3 = color or Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		Font = Enum.Font.GothamBold,
	})
	task.delay(3, function()
		l:Destroy()
	end)
	local children = toastFrame:GetChildren()
	local labels = 0
	for _, c in children do
		if c:IsA("TextLabel") then
			labels += 1
		end
	end
	if labels > 4 then
		for _, c in children do
			if c:IsA("TextLabel") and c ~= l then
				c:Destroy()
				break
			end
		end
	end
end

function HUDController.Toast(text: string, color: Color3?)
	toast(text, color)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PrototypeHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.BorderSizePixel = 0
	crosshair.BackgroundColor3 = COLORS.idle
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = crosshair
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = crosshair
	crosshair.Parent = gui

	promptLabel = label(gui, {
		Name = "Prompt",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(520, 24),
		Text = "",
	})
	holdLabel = label(gui, {
		Name = "Hold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(620, 24),
		Text = "",
		TextSize = 17,
	})
	stateLabel = label(gui, {
		Name = "MoveState",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(300, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		TextSize = 16,
	})
	lootLabel = label(gui, {
		Name = "Loot",
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.fromOffset(360, 70),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		TextSize = 17,
	})

	toastFrame = Instance.new("Frame")
	toastFrame.Name = "Toasts"
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.Position = UDim2.new(0.5, 0, 0, 60)
	toastFrame.Size = UDim2.fromOffset(600, 140)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastFrame
	toastFrame.Parent = gui

	helpFrame = Instance.new("Frame")
	helpFrame.Name = "Help"
	helpFrame.AnchorPoint = Vector2.new(1, 0)
	helpFrame.Position = UDim2.new(1, -16, 0, 56)
	helpFrame.Size = UDim2.fromOffset(330, 270)
	helpFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	helpFrame.BackgroundTransparency = 0.35
	helpFrame.Visible = true
	local helpCorner = Instance.new("UICorner")
	helpCorner.CornerRadius = UDim.new(0, 8)
	helpCorner.Parent = helpFrame
	local lines = {
		"CONTROLES  (" .. Names.ToggleHelp .. " ocultar)",
		"WASD  moverse   ·   Ratón  mirar",
		Names.Sprint .. "  correr",
		Names.Crouch .. "  agacharse",
		Names.Jump .. "  saltar",
		Names.ExtendHand .. "  extender la mano",
		Names.Grab .. "  agarrar / soltar (mantener)",
		Names.Reach .. "  alcance de la mano",
		Names.Interact .. "  interactuar",
		"",
		"Objetivo: abre la puerta, coge la bolsa,",
		"enciende el interruptor y llévala a la zona.",
	}
	label(helpFrame, {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 1, -16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 15,
		Text = table.concat(lines, "\n"),
		TextWrapped = true,
	})
	helpFrame.Parent = gui
end

local function describeGrab(part: BasePart): (string, Color3)
	local heldBy = part:GetAttribute(Contract.Attributes.HeldBy)
	if heldBy ~= nil and heldBy ~= player.UserId then
		return "Otro jugador lo está sujetando", COLORS.blocked
	end
	if part:GetAttribute(Contract.Attributes.Articulated) == true then
		return string.format("[%s] Sujetar y mover", Names.Grab), COLORS.grab
	end
	if part.Anchored then
		return "Bloqueado", COLORS.blocked
	end
	local mass = part.AssemblyMass
	local mode = GrabMath.classify(mass, Targeting.assemblyMaxDimension(part), Config.Grab)
	if mode == "Lift" then
		return string.format("[%s] Levantar %s (masa %.0f)", Names.Grab, part.Name, mass), COLORS.grab
	elseif mode == "Drag" then
		return string.format("[%s] Arrastrar %s (pesado, masa %.0f)", Names.Grab, part.Name, mass), COLORS.grab
	end
	return string.format("%s: demasiado pesado (masa %.0f)", part.Name, mass), COLORS.blocked
end

local function update()
	local character = PlayerContext.Get()
	local stateFolder = ReplicatedStorage:FindFirstChild(Contract.Names.GameState)
	local teamLoot = stateFolder and stateFolder:GetAttribute("TeamLoot") or 0
	local powered = stateFolder and stateFolder:GetAttribute("Power_Delivery") == true
	local pocket = player:GetAttribute(Contract.Attributes.PocketLoot) or 0
	lootLabel.Text = string.format(
		"Botín del equipo: $%d\nBolsillo: $%d\nEnergía zona de entrega: %s",
		teamLoot,
		pocket,
		if powered then "ENCENDIDA" else "apagada"
	)
	if character == nil then
		promptLabel.Text = ""
		holdLabel.Text = ""
		stateLabel.Text = ""
		crosshair.BackgroundColor3 = COLORS.idle
		return
	end

	local held = GrabController.GetHeld()
	if held then
		local mode = character:GetAttribute(Contract.Attributes.HoldMode)
		local verb = if mode == "Drag" then "Arrastrando" elseif mode == "Articulated" then "Moviendo" else "Sosteniendo"
		holdLabel.Text = string.format("%s: %s   ·   suelta %s   ·   %s alcance", verb, held.Name, Names.Grab, Names.Reach)
	elseif GrabController.IsPending() then
		holdLabel.Text = "..."
	else
		holdLabel.Text = ""
	end

	local parts = {}
	if MovementController.IsCrouching() then
		table.insert(parts, "Agachado")
	elseif MovementController.IsSprinting() then
		table.insert(parts, "Corriendo")
	end
	stateLabel.Text = table.concat(parts, " · ")

	local target = TargetingController.Get()
	local text, color = "", COLORS.idle
	local focus = InteractionController.GetFocus()
	if focus then
		local prompt = focus:GetAttribute(Contract.Attributes.Prompt)
		text = string.format("[%s] %s", Names.Interact, if type(prompt) == "string" then prompt else "Interactuar")
		color = COLORS.interact
	end
	if held == nil and target.grabbable and target.distance <= Config.Grab.Range then
		local grabText, grabColor = describeGrab(target.grabbable)
		text = if text ~= "" then text .. "   ·   " .. grabText else grabText
		if focus == nil then
			color = grabColor
		end
	end
	promptLabel.Text = text
	crosshair.BackgroundColor3 = color
end

function HUDController.Init()
	build()
	InputBinder.Bind("FP_ToggleHelp", Controls.ToggleHelp, function(inputState)
		if inputState == Enum.UserInputState.Begin then
			helpFrame.Visible = not helpFrame.Visible
		end
	end)
	GrabController.Feedback:Connect(function(reason: string)
		toast(REASONS[reason] or reason, COLORS.blocked)
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "Message" and type(data) == "string" then
			toast(data)
		elseif kind == "LootDelivered" and type(data) == "table" then
			local by = if type(data.by) == "string" then " (" .. data.by .. ")" else ""
			toast(string.format("¡Entregado +$%d%s!", tonumber(data.amount) or 0, by), COLORS.grab)
		elseif kind == "ArenaReset" then
			toast("Escenario reiniciado por " .. tostring(data), COLORS.interact)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return HUDController
