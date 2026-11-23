--[[
	InputBinder (client)
	Binds actions from Shared.Config.Controls through ContextActionService at
	high priority so default Roblox scripts (camera zoom, etc.) do not also
	react. Handlers receive the UserInputState and the InputObject.
]]

local ContextActionService = game:GetService("ContextActionService")

local InputBinder = {}

local PRIORITY = Enum.ContextActionPriority.High.Value

function InputBinder.Bind(name: string, inputs: { any }, handler: (Enum.UserInputState, InputObject) -> ())
	ContextActionService:BindActionAtPriority(name, function(_, state, input)
		handler(state, input)
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, table.unpack(inputs))
end

function InputBinder.Unbind(name: string)
	ContextActionService:UnbindAction(name)
end

return InputBinder
