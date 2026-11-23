--[[
	Validate
	Type guards for data coming from clients. Never trust remote arguments.
]]

local Validate = {}

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Validate.number(v: any): boolean
	return type(v) == "number" and finite(v)
end

function Validate.boolean(v: any): boolean
	return type(v) == "boolean"
end

function Validate.vector3(v: any, maxMagnitude: number?): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	if not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
		return false
	end
	if maxMagnitude and v.Magnitude > maxMagnitude then
		return false
	end
	return true
end

function Validate.instanceOf(v: any, className: string): boolean
	return typeof(v) == "Instance" and v:IsA(className)
end

-- Instance that currently lives in the Workspace (not destroyed / not in storage).
function Validate.worldInstance(v: any, className: string): boolean
	return Validate.instanceOf(v, className) and v:IsDescendantOf(workspace)
end

return Validate
