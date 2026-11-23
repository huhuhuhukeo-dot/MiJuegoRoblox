--[[
	Container interaction (crate / safe)
	Model: Container (Model) tag Interactable, InteractionType = "Container"
	  Body (BasePart, anchored)
	  Lid  (BasePart, anchored)  hinged on its back (+Z) top edge
	  attributes: Contents (string, name of a template in ServerStorage.Templates)
	"E" opens/closes the lid. The contents are spawned once per arena reset.
]]

local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Interaction.Contract)

local Container = {
	Type = "Container",
	Cooldown = 0.6,
}

local OPEN_ANGLE = math.rad(105)
local data: { [Instance]: { lid: BasePart, closed: CFrame, open: CFrame, spawnedOnce: boolean } } = {}

local function updatePrompt(model: Instance)
	model:SetAttribute(Contract.Attributes.Prompt, if model:GetAttribute("Opened") == true then "Cerrar" else "Abrir")
end

function Container.Setup(model: Instance)
	local lid = model:FindFirstChild("Lid")
	if not (lid and lid:IsA("BasePart")) then
		warn("[Container] " .. model:GetFullName() .. " needs a Lid part")
		return
	end
	local closed = lid.CFrame
	local pivot = closed * CFrame.new(0, lid.Size.Y * 0.5, lid.Size.Z * 0.5)
	local open = pivot * CFrame.Angles(OPEN_ANGLE, 0, 0) * pivot:Inverse() * closed
	data[model] = { lid = lid, closed = closed, open = open, spawnedOnce = false }
	model:SetAttribute("Opened", false)
	updatePrompt(model)
end

function Container.Cleanup(model: Instance)
	data[model] = nil
end

local function spawnContents(model: Instance, ctx)
	local name = model:GetAttribute("Contents")
	local templates = ServerStorage:FindFirstChild("Templates")
	local template = type(name) == "string" and templates and templates:FindFirstChild(name)
	if not template then
		return
	end
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local clone = template:Clone()
	local at = body.CFrame * CFrame.new(0, body.Size.Y * 0.5 + 1.2, 0)
	if clone:IsA("BasePart") then
		ctx.Recovery.MarkSpawned(clone)
		clone.CFrame = at
	elseif clone:IsA("Model") then
		clone:PivotTo(at)
	end
	clone.Parent = model.Parent
end

function Container.Interact(_player: Player, model: Instance, ctx)
	local d = data[model]
	if d == nil then
		return
	end
	local opening = model:GetAttribute("Opened") ~= true
	model:SetAttribute("Opened", opening)
	TweenService:Create(d.lid, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		CFrame = if opening then d.open else d.closed,
	}):Play()
	if opening and not d.spawnedOnce then
		d.spawnedOnce = true
		task.delay(0.3, spawnContents, model, ctx)
	end
	updatePrompt(model)
end

function Container.OnReset(model: Instance)
	local d = data[model]
	if d then
		d.spawnedOnce = false
		d.lid.CFrame = d.closed
		model:SetAttribute("Opened", false)
		updatePrompt(model)
	end
end

return Container
