--[[
	TestArenaBuilder
	Builds the prototype's test scene from code so the repository is the single
	source of truth (no binary place file needed). Runs only when the Workspace
	has no "TestArena" (so a hand-made arena in Studio takes priority).

	Layout (floor top at y = 0.05, +Z points toward the spawns)
	  z ~ +45   Spawns (4) + reset button
	  z 20..36  Props area: light box, heavy box, money bag, small can, table
	            Crouch tunnel (ceiling at 4.4 studs)
	  x ~ +30   Delivery zone (powered by the switch)
	  z -10..-30 Room behind Door 1: table + money bag, switch, drawer with a gem
	  z -30..-40 Vault behind Door 2 (locked, button-controlled): crate with a bag

	Every interactive object only uses tags/attributes (see Shared.Interaction.Contract).
]]

local CollectionService = game:GetService("CollectionService")

local Contract = require(game:GetService("ReplicatedStorage").Shared.Interaction.Contract)

local TestArenaBuilder = {}

local Tags = Contract.Tags
local Attr = Contract.Attributes
local FLOOR = 0.05

type Props = { [string]: any }

local function make(className: string, props: Props, parent: Instance?): any
	local inst = Instance.new(className)
	local tags = props.Tags
	local attributes = props.Attributes
	for key, value in props do
		if key ~= "Tags" and key ~= "Attributes" then
			(inst :: any)[key] = value
		end
	end
	if inst:IsA("BasePart") then
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
	end
	if attributes then
		for k, v in attributes do
			inst:SetAttribute(k, v)
		end
	end
	if tags then
		for _, t in tags do
			CollectionService:AddTag(inst, t)
		end
	end
	inst.Parent = parent
	return inst
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	return make("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = true,
	}, parent)
end

local function weld(a: BasePart, b: BasePart)
	make("WeldConstraint", { Part0 = a, Part1 = b }, a)
end

-- `facing` is the direction the readable side points to (toward the reader).
local function sign(parent: Instance, position: Vector3, facing: Vector3, text: string, width: number?)
	local cf = CFrame.lookAt(position, position + facing)
	local board = block(parent, "Sign", Vector3.new(width or 6, 1.4, 0.2), cf, Color3.fromRGB(30, 30, 35))
	board.CanCollide = false
	board.CanQuery = false
	local gui = make("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, board)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(240, 240, 240),
	}, gui)
	return board
end

local function table_(parent: Instance, name: string, center: Vector3, width: number, depth: number, height: number)
	local model = make("Model", { Name = name }, parent)
	local wood = Color3.fromRGB(120, 85, 55)
	local top = block(model, "Top", Vector3.new(width, 0.5, depth), CFrame.new(center.X, FLOOR + height - 0.25, center.Z), wood, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local legPos = Vector3.new(center.X + sx * (width / 2 - 0.4), FLOOR + (height - 0.5) / 2, center.Z + sz * (depth / 2 - 0.4))
			block(model, "Leg", Vector3.new(0.4, height - 0.5, 0.4), CFrame.new(legPos), wood, Enum.Material.Wood)
		end
	end
	model.PrimaryPart = top
	return model, FLOOR + height
end

local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, density: number, friction: number?)
	return make("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(density, friction or 0.5, 0.05, 1, 1),
		Tags = { Tags.Grabbable },
	}, parent)
end

function TestArenaBuilder.MakeMoneyBag(cf: CFrame, value: number): Part
	local bag = make("Part", {
		Name = "BolsaDinero",
		Size = Vector3.new(1.6, 1.3, 1.6),
		CFrame = cf,
		Color = Color3.fromRGB(70, 110, 60),
		Material = Enum.Material.Fabric,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.8, 0, 1, 1),
		Tags = { Tags.Grabbable, Tags.Interactable, Tags.Loot },
		Attributes = { [Attr.InteractionType] = "MoneyBag", [Attr.LootValue] = value },
	}, nil)
	local knot = make("Part", {
		Name = "Knot",
		Size = Vector3.new(0.6, 0.4, 0.6),
		CFrame = cf * CFrame.new(0, 0.85, 0),
		Color = Color3.fromRGB(60, 95, 50),
		Material = Enum.Material.Fabric,
		Anchored = false,
		Massless = true,
	}, bag)
	weld(bag, knot)
	local gui = make("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 50 }, bag)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "$",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(230, 220, 120),
	}, gui)
	return bag
end

-- Door leaf hinged at x = hingeX, in a wall at constant z; the leaf extends to +X.
local function door(parent: Instance, name: string, id: string, hingeX: number, z: number, locked: boolean)
	local model = make("Model", {
		Name = name,
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Door", Id = id, Locked = locked },
	}, parent)
	local height = 7.3
	local width = 4.1
	local y = FLOOR + 0.1 + height / 2
	local frame = block(model, "Frame", Vector3.new(0.4, 7.5, 1.1), CFrame.new(hingeX - 0.2, FLOOR + 3.75, z), Color3.fromRGB(70, 60, 50), Enum.Material.Wood)
	local panel = make("Part", {
		Name = "Panel",
		Size = Vector3.new(width, height, 0.3),
		CFrame = CFrame.new(hingeX + 0.3 + width / 2, y, z),
		Color = if locked then Color3.fromRGB(90, 95, 110) else Color3.fromRGB(150, 105, 65),
		Material = if locked then Enum.Material.DiamondPlate else Enum.Material.Wood,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.4, 0, 1, 1),
	}, model)
	local handle = make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.25, 0.25, 0.9),
		CFrame = CFrame.new(hingeX + 0.3 + width - 0.4, FLOOR + 3.4, z),
		Color = Color3.fromRGB(200, 180, 90),
		Material = Enum.Material.Metal,
		Anchored = false,
		Massless = true,
	}, panel)
	weld(panel, handle)
	local hingeCF = CFrame.new(hingeX + 0.25, y, z) * CFrame.Angles(0, 0, math.pi / 2) -- axis (X) = world up
	local a0 = make("Attachment", { Name = "HingeA0" }, frame)
	a0.WorldCFrame = hingeCF
	local a1 = make("Attachment", { Name = "HingeA1" }, panel)
	a1.WorldCFrame = hingeCF
	make("HingeConstraint", { Name = "Hinge", Attachment0 = a0, Attachment1 = a1 }, model)
	make("NoCollisionConstraint", { Part0 = panel, Part1 = frame }, panel)
	return model
end

-- Wall along X (constant z) from x0 to x1 with optional doorway [dx0, dx1].
local function wallX(parent: Instance, z: number, x0: number, x1: number, doorway: { number }?)
	local color = Color3.fromRGB(165, 160, 150)
	local h = 10
	local function seg(a: number, b: number, y0: number, y1: number)
		if b - a > 0.01 then
			block(parent, "Wall", Vector3.new(b - a, y1 - y0, 1), CFrame.new((a + b) / 2, FLOOR + (y0 + y1) / 2, z), color, Enum.Material.Brick)
		end
	end
	if doorway then
		seg(x0, doorway[1], 0, h)
		seg(doorway[2], x1, 0, h)
		seg(doorway[1], doorway[2], 7.5, h) -- lintel
	else
		seg(x0, x1, 0, h)
	end
end

local function wallZ(parent: Instance, x: number, z0: number, z1: number)
	block(parent, "Wall", Vector3.new(1, 10, math.abs(z1 - z0)), CFrame.new(x, FLOOR + 5, (z0 + z1) / 2), Color3.fromRGB(165, 160, 150), Enum.Material.Brick)
end

local function button(parent: Instance, name: string, cf: CFrame, action: string, target: string?)
	local model = make("Model", {
		Name = name,
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Button", Action = action, Target = target },
	}, parent)
	block(model, "Base", Vector3.new(1.8, 1.8, 0.3), cf * CFrame.new(0, 0, 0.25), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	block(model, "Cap", Vector3.new(1.1, 1.1, 0.35), cf, Color3.fromRGB(220, 50, 50), Enum.Material.Neon)
	return model
end

function TestArenaBuilder.Build(root: Instance, serverStorage: Instance)
	local arena = make("Folder", { Name = Contract.Names.TestArena }, nil)

	-- Floor & spawns ---------------------------------------------------------
	block(arena, "Floor", Vector3.new(170, 1, 170), CFrame.new(0, FLOOR - 0.5, 0), Color3.fromRGB(95, 100, 95), Enum.Material.Concrete)
	for i, x in { -6, -2, 2, 6 } do
		make("SpawnLocation", {
			Name = "Spawn" .. i,
			Size = Vector3.new(3, 0.2, 3),
			CFrame = CFrame.new(x, FLOOR + 0.1, 46),
			Anchored = true,
			Neutral = true,
			Duration = 0,
			Transparency = 0.4,
			Color = Color3.fromRGB(80, 140, 220),
			CanCollide = false,
		}, arena)
	end
	sign(arena, Vector3.new(0, 7, 38), Vector3.zAxis, "PROTOTIPO V1 — pulsa H para ver los controles", 14)

	-- Reset button on a pedestal (cap faces up, pressing moves it down) -----
	block(arena, "Pedestal", Vector3.new(1.6, 2.6, 1.6), CFrame.new(10, FLOOR + 1.3, 42), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	button(arena, "BotonReinicio", CFrame.new(10, FLOOR + 2.78, 42) * CFrame.Angles(math.rad(90), 0, 0), "ResetArena", nil)
	sign(arena, Vector3.new(10, 4.6, 42.9), Vector3.zAxis, "Reiniciar escenario", 4)

	-- Props area -----------------------------------------------------------
	sign(arena, Vector3.new(-16, 6, 37), Vector3.zAxis, "Zona de objetos: agarrar, levantar, arrastrar", 12)
	local _, tableTop = table_(arena, "MesaPruebas", Vector3.new(-18, 0, 22), 8, 4, 3)
	prop(arena, "CajaLiviana", Vector3.new(2, 2, 2), CFrame.new(-12, FLOOR + 1, 30), Color3.fromRGB(190, 150, 90), Enum.Material.WoodPlanks, 0.5)
	prop(arena, "CajaPesada", Vector3.new(4, 4, 4), CFrame.new(-25, FLOOR + 2, 31), Color3.fromRGB(90, 95, 105), Enum.Material.DiamondPlate, 2.5, 0.35)
	prop(arena, "CajaPequena", Vector3.new(1.2, 1.2, 1.2), CFrame.new(-20, tableTop + 0.6, 22), Color3.fromRGB(200, 120, 60), Enum.Material.WoodPlanks, 0.5)
	local can = prop(arena, "Lata", Vector3.new(0.9, 0.6, 0.6), CFrame.new(-16, tableTop + 0.3, 22), Color3.fromRGB(200, 40, 40), Enum.Material.Metal, 0.6)
	can.Shape = Enum.PartType.Cylinder
	local bag = TestArenaBuilder.MakeMoneyBag(CFrame.new(-6, FLOOR + 0.65, 28), 500)
	bag.Parent = arena

	-- Crouch tunnel (clearance 4.4 studs: stand ~5.1, crouched ~3.9) ---------
	sign(arena, Vector3.new(14, 7, 37), Vector3.zAxis, "Túnel: agáchate (Ctrl / C)", 8)
	block(arena, "TunnelWall", Vector3.new(1, 6, 16), CFrame.new(10.5, FLOOR + 3, 28), Color3.fromRGB(120, 110, 100), Enum.Material.Brick)
	block(arena, "TunnelWall", Vector3.new(1, 6, 16), CFrame.new(17.5, FLOOR + 3, 28), Color3.fromRGB(120, 110, 100), Enum.Material.Brick)
	block(arena, "TunnelCeiling", Vector3.new(8, 1, 16), CFrame.new(14, FLOOR + 4.4 + 0.5, 28), Color3.fromRGB(110, 100, 90), Enum.Material.Brick)

	-- Delivery zone (needs power: switch inside the room) -----------------
	make("Part", {
		Name = "ZonaEntrega",
		Size = Vector3.new(8, 5, 8),
		CFrame = CFrame.new(30, FLOOR + 2.5, 0),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 0.75,
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(200, 60, 60),
		Tags = { Tags.DeliveryZone },
		Attributes = { [Attr.PowerGroup] = "Delivery" },
	}, arena)
	local lamp = block(arena, "LamparaEntrega", Vector3.new(1.2, 0.6, 1.2), CFrame.new(30, FLOOR + 8, 0), Color3.fromRGB(255, 240, 200))
	CollectionService:AddTag(lamp, Tags.PoweredLight)
	lamp:SetAttribute(Attr.PowerGroup, "Delivery")
	make("PointLight", { Range = 18, Brightness = 2, Enabled = false }, lamp)
	block(arena, "PosteLampara", Vector3.new(0.4, 7.6, 0.4), CFrame.new(30, FLOOR + 3.8, -4.4), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
	sign(arena, Vector3.new(30, 6.5, 4.5), Vector3.zAxis, "ZONA DE ENTREGA (requiere energía)", 9)

	-- Room ------------------------------------------------------------------
	wallX(arena, -10, -20.5, 20.5, { -2.25, 2.25 })
	wallX(arena, -40, -20.5, 20.5, nil)
	wallZ(arena, -20, -10, -40)
	wallZ(arena, 20, -10, -40)
	wallX(arena, -30, -19.5, 19.5, { 7.75, 12.25 }) -- vault partition
	door(arena, "Puerta", "MainDoor", -2.25, -10, false)
	door(arena, "PuertaBoveda", "VaultDoor", 7.75, -30, true)
	sign(arena, Vector3.new(0, 8.8, -9.35), Vector3.zAxis, "Habitación", 5)

	local _, roomTable = table_(arena, "MesaHabitacion", Vector3.new(8, 0, -20), 6, 3, 3)
	local roomBag = TestArenaBuilder.MakeMoneyBag(CFrame.new(8, roomTable + 0.65, -20), 1000)
	roomBag.Parent = arena

	-- Switch on the right wall: lever sticks out of the wall (-X) and flips up/down
	local switch = make("Model", {
		Name = "Interruptor",
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Switch", [Attr.PowerGroup] = "Delivery", On = false },
	}, arena)
	block(switch, "Plate", Vector3.new(0.2, 1.8, 1.2), CFrame.new(19.4, FLOOR + 4, -14), Color3.fromRGB(230, 230, 220))
	local leverCF = CFrame.fromMatrix(Vector3.new(19.0, FLOOR + 4, -14), Vector3.zAxis, -Vector3.xAxis)
	block(switch, "Lever", Vector3.new(0.25, 0.9, 0.25), leverCF, Color3.fromRGB(200, 60, 60), Enum.Material.Metal)
	sign(arena, Vector3.new(19.35, FLOOR + 6, -14), -Vector3.xAxis, "Energía de la zona de entrega", 4)

	-- Button that locks/unlocks the vault door (cap faces the room, +Z)
	button(arena, "BotonBoveda", CFrame.new(4, FLOOR + 4, -29.33) * CFrame.Angles(0, math.pi, 0), "ToggleLock", "VaultDoor")
	sign(arena, Vector3.new(4, FLOOR + 5.6, -29.35), Vector3.zAxis, "Bóveda: bloquear/desbloquear", 5)

	-- Drawer cabinet against the left wall; the tray slides along +X ---------
	local cz = -18
	local cabinet = make("Model", {
		Name = "Cajonera",
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Drawer" },
	}, arena)
	local dark = Color3.fromRGB(90, 65, 45)
	local light = Color3.fromRGB(140, 100, 70)
	local cx = -18.3
	block(cabinet, "Bottom", Vector3.new(2.4, 0.2, 3), CFrame.new(cx, FLOOR + 0.1, cz), dark, Enum.Material.Wood)
	block(cabinet, "Top", Vector3.new(2.4, 0.2, 3), CFrame.new(cx, FLOOR + 3.0, cz), dark, Enum.Material.Wood)
	block(cabinet, "Back", Vector3.new(0.2, 3, 3), CFrame.new(-19.4, FLOOR + 1.55, cz), dark, Enum.Material.Wood)
	block(cabinet, "SideL", Vector3.new(2.4, 3, 0.2), CFrame.new(cx, FLOOR + 1.55, cz - 1.4), dark, Enum.Material.Wood)
	block(cabinet, "SideR", Vector3.new(2.4, 3, 0.2), CFrame.new(cx, FLOOR + 1.55, cz + 1.4), dark, Enum.Material.Wood)
	local shelf = block(cabinet, "Body", Vector3.new(2.4, 0.2, 2.6), CFrame.new(cx, FLOOR + 1.5, cz), dark, Enum.Material.Wood)
	block(cabinet, "FrontLow", Vector3.new(0.2, 1.35, 2.6), CFrame.new(-17.2, FLOOR + 0.8, cz), dark, Enum.Material.Wood)
	local tray = make("Part", {
		Name = "Tray",
		Size = Vector3.new(0.2, 1.1, 2.5),
		CFrame = CFrame.new(-17.15, FLOOR + 2.2, cz),
		Color = light,
		Material = Enum.Material.Wood,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.15, 0, 1, 1),
	}, cabinet)
	local function trayPart(name: string, size: Vector3, pos: Vector3)
		local p = make("Part", {
			Name = name,
			Size = size,
			CFrame = CFrame.new(pos),
			Color = light,
			Material = Enum.Material.Wood,
			Anchored = false,
			CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.15, 0, 1, 1),
		}, tray)
		weld(tray, p)
		return p
	end
	trayPart("TrayBottom", Vector3.new(2.0, 0.1, 2.4), Vector3.new(-18.2, FLOOR + 1.68, cz))
	trayPart("TrayBack", Vector3.new(0.1, 0.5, 2.4), Vector3.new(-19.15, FLOOR + 1.95, cz))
	trayPart("TraySideL", Vector3.new(2.0, 0.5, 0.1), Vector3.new(-18.2, FLOOR + 1.95, cz - 1.15))
	trayPart("TraySideR", Vector3.new(2.0, 0.5, 0.1), Vector3.new(-18.2, FLOOR + 1.95, cz + 1.15))
	local knob = trayPart("Knob", Vector3.new(0.3, 0.2, 0.8), Vector3.new(-16.95, FLOOR + 2.2, cz))
	knob.Color = Color3.fromRGB(200, 180, 90)
	local slideCF = CFrame.new(-17.5, FLOOR + 1.7, cz) -- X axis = world +X
	local s0 = make("Attachment", { Name = "SlideA0" }, shelf)
	s0.WorldCFrame = slideCF
	local s1 = make("Attachment", { Name = "SlideA1" }, tray)
	s1.WorldCFrame = slideCF
	make("PrismaticConstraint", { Name = "Slide", Attachment0 = s0, Attachment1 = s1 }, cabinet)

	make("Part", {
		Name = "Gema",
		Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = CFrame.new(-18.2, FLOOR + 2.0, cz) * CFrame.Angles(0, math.rad(45), 0),
		Color = Color3.fromRGB(80, 220, 255),
		Material = Enum.Material.Neon,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(0.8, 0.6, 0, 1, 1),
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Collectible", [Attr.LootValue] = 250 },
	}, arena)

	-- Vault: crate whose contents (a money bag) appear when opened ----------
	local crate = make("Model", {
		Name = "Caja fuerte",
		Tags = { Tags.Interactable },
		Attributes = { [Attr.InteractionType] = "Container", Contents = "MoneyBag" },
	}, arena)
	-- rotated 180 deg so the lid hinge (+Z local) is on the far side from the vault door
	local flip = CFrame.Angles(0, math.pi, 0)
	block(crate, "Body", Vector3.new(3, 2, 2.2), CFrame.new(12, FLOOR + 1, -36) * flip, Color3.fromRGB(60, 70, 60), Enum.Material.Metal)
	block(crate, "Lid", Vector3.new(3, 0.3, 2.2), CFrame.new(12, FLOOR + 2.15, -36) * flip, Color3.fromRGB(80, 95, 80), Enum.Material.Metal)

	-- Templates for runtime spawns --------------------------------------
	local templates = serverStorage:FindFirstChild("Templates") or make("Folder", { Name = "Templates" }, serverStorage)
	local template = TestArenaBuilder.MakeMoneyBag(CFrame.new(), 1500)
	template.Name = "MoneyBag"
	template.Parent = templates

	arena.Parent = root
	return arena
end

return TestArenaBuilder
