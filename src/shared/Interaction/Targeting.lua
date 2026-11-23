--[[
	Targeting
	Pure lookup helpers shared by client (prompts, prediction) and server
	(validation). They never mutate anything.
]]

local CollectionService = game:GetService("CollectionService")

local Contract = require(script.Parent.Contract)

local Targeting = {}

local MAX_ANCESTOR_STEPS = 6

-- Returns the tagged BasePart that represents the grabbable assembly that
-- `part` belongs to (the part itself, a BasePart ancestor, the assembly root,
-- or the PrimaryPart of a tagged model).
function Targeting.findGrabbable(part: Instance?): BasePart?
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	local current: Instance? = part
	local steps = 0
	while current and steps < MAX_ANCESTOR_STEPS do
		if CollectionService:HasTag(current, Contract.Tags.Grabbable) then
			if current:IsA("BasePart") then
				return current
			elseif current:IsA("Model") and current.PrimaryPart then
				return current.PrimaryPart
			end
			return nil
		end
		if current == workspace then
			break
		end
		current = current.Parent
		steps += 1
	end
	local root = (part :: BasePart).AssemblyRootPart
	if root and CollectionService:HasTag(root, Contract.Tags.Grabbable) then
		return root
	end
	return nil
end

-- Returns the instance (Model or BasePart) tagged "Interactable" that owns `inst`.
function Targeting.findInteractable(inst: Instance?): Instance?
	local current = inst
	local steps = 0
	while current and current ~= workspace and steps < MAX_ANCESTOR_STEPS do
		if CollectionService:HasTag(current, Contract.Tags.Interactable) then
			return current
		end
		current = current.Parent
		steps += 1
	end
	return nil
end

-- Closest point of a part's oriented box to `point`.
function Targeting.closestPointOnPart(part: BasePart, point: Vector3): Vector3
	local cf = part.CFrame
	local half = part.Size * 0.5
	local rel = cf:PointToObjectSpace(point)
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return cf:PointToWorldSpace(clamped)
end

-- Closest point of an interactable (Model or BasePart) to `point`.
-- Returns the point and the part that contains it.
function Targeting.closestPoint(inst: Instance, point: Vector3): (Vector3?, BasePart?)
	local bestPoint, bestPart, bestDist = nil, nil, math.huge
	local function consider(p: BasePart)
		local c = Targeting.closestPointOnPart(p, point)
		local d = (c - point).Magnitude
		if d < bestDist then
			bestPoint, bestPart, bestDist = c, p, d
		end
	end
	if inst:IsA("BasePart") then
		consider(inst)
	end
	local count = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			consider(d)
			count += 1
			if count > 64 then
				break -- interactables are small; guard against huge models
			end
		end
	end
	return bestPoint, bestPart
end

-- Approximate largest dimension of the assembly `root` belongs to.
function Targeting.assemblyMaxDimension(root: BasePart): number
	local parts = root:GetConnectedParts(true)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in parts do
		local r = p.Size.Magnitude * 0.5
		local pos = p.Position
		minV = minV:Min(pos - Vector3.new(r, r, r))
		maxV = maxV:Max(pos + Vector3.new(r, r, r))
	end
	if #parts == 1 then
		local s = root.Size
		return math.max(s.X, s.Y, s.Z)
	end
	local ext = maxV - minV
	-- the sphere bound over-estimates; scale back to a reasonable box estimate
	return math.max(ext.X, ext.Y, ext.Z) * 0.8
end

return Targeting
