--!strict
-- A tiny signal with the same :Connect / :Once / :Wait shape as a Roblox event.
-- Unlike a BindableEvent it passes tables BY REFERENCE (a BindableEvent deep-copies them, so a Plot table that
-- came through one would no longer == the Plot you hold). Each handler runs in its own thread via task.spawn,
-- so a handler that errors or yields never breaks the code that fired the signal.
--
-- Used for the server module signals in the build plan §B5 (PlayerData.Loaded, Plots.PlotAssigned, ...)
-- and the client ctx bus. Usage is identical to an RBXScriptSignal:
--   local conn = Plots.PlotAssigned:Connect(function(player, plot) ... end)
--   conn:Disconnect()

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

type Handler = {
	Fn: (...any) -> (),
	Connection: Connection,
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { Handler } = {}

	local function remove(handler: Handler)
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end

	local signal = {} :: Signal

	function signal.Connect(_self: Signal, fn: (...any) -> ()): Connection
		local handler: Handler
		local connection = {
			Connected = true,
		} :: Connection
		function connection.Disconnect(conn: Connection)
			if conn.Connected then
				conn.Connected = false
				remove(handler)
			end
		end
		handler = { Fn = fn, Connection = connection }
		table.insert(handlers, handler)
		return connection
	end

	function signal.Once(self: Signal, fn: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end

	function signal.Wait(self: Signal): ...any
		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal.Fire(_self: Signal, ...: any)
		-- Clone first: a handler may connect or disconnect while we loop.
		for _, handler in table.clone(handlers) do
			if handler.Connection.Connected then
				task.spawn(handler.Fn, ...)
			end
		end
	end

	function signal.DisconnectAll(_self: Signal)
		for _, handler in table.clone(handlers) do
			handler.Connection:Disconnect()
		end
	end

	return signal
end

return Signal
