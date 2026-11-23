--[[
	Signal
	Minimal pure-Luau signal (no BindableEvent, no instance allocation).
	Handlers run synchronously in connection order; errors are isolated.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: any) -> (), Connected: boolean }

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local connection = { Connected = true }
	local handlers = self._handlers
	connection.Disconnect = function(c)
		if not c.Connected then
			return
		end
		c.Connected = false
		for i, entry in handlers do
			if entry == connection then
				table.remove(handlers, i)
				break
			end
		end
	end
	connection._fn = fn
	table.insert(handlers, connection)
	return connection
end

function Signal:Fire(...: any)
	-- copy so handlers may disconnect while iterating
	local snapshot = table.clone(self._handlers)
	for _, connection in snapshot do
		if connection.Connected then
			local ok, err = pcall(connection._fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
