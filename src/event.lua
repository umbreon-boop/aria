--[=[
	@class Event
	A simple event system for connecting and firing callbacks.
	The module itself is a shared emitter. Use `Event.new()` to make an independent emitter.
]=]
local Event = { _event = {}, _waitThreads = {} }
Event.__index = Event

--[=[
	@type Connection {Connected: boolean, Disconnect: (self: Connection) -> ()}
	@within Event
	Represents a connection to an event that can be disconnected.
]=]
export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

--[=[
	Creates an independent emitter. Its events are not shared with the module or with other emitters.
	@return Event -- A new emitter with no connections.
]=]
function Event.new()
	return setmetatable({ _event = {}, _waitThreads = {} }, Event)
end
Event.New = Event.new

--[=[
	Fires all callbacks connected to the specified event.
	If a callback from `ConnectParallel` is connected, this function yields.
	@param name string -- The name of the event to fire
	@param ... any -- Arguments to pass to each callback
	@return {any} -- Array of errors from failed callbacks (empty if all succeeded)
]=]
function Event:Fire(name: string, ...: any): { any }
	local errors = {}
	local callbacks = self._event[name]
	local waitThreads = self._waitThreads[name]

	if callbacks then
		-- a copy, so that a callback can disconnect during the loop
		for _, callback in table.clone(callbacks) do
			local success, err = pcall(callback, ...)
			if not success then
				table.insert(errors, err)
			end
		end
	end

	if waitThreads then
		-- remove the list first, so that a thread which waits again goes into a new list
		self._waitThreads[name] = nil
		for _, thread in waitThreads do
			-- a thread can be cancelled while it waits, and a dead thread cannot be resumed
			if coroutine.status(thread) == "suspended" then
				task.spawn(thread, ...)
			end
		end
	end

	return errors
end

--[=[
	Connects a callback to the specified event.
	@param name string -- The name of the event to connect to
	@param callback (...any) -> () -- The function to call when the event fires
	@return Connection -- Connection object with Disconnect method
]=]
function Event:Connect(name: string, callback: (...any) -> ()): Connection
	local event = self
	event._event[name] = event._event[name] or {}
	table.insert(event._event[name], callback)

	local connection: Connection = {
		Connected = true,
		Disconnect = nil :: any,
	}

	connection.Disconnect = function(conn: Connection)
		if not conn.Connected then
			return
		end

		conn.Connected = false
		local callbacks = event._event[name]
		local index = callbacks and table.find(callbacks, callback)
		if index then
			table.remove(callbacks, index)
		end
	end

	return connection
end

--[=[
	Connects a callback to run in a parallel desynchronized thread when the event fires.
	This is useful for performance-critical callbacks that do not need to access the data model.
	The script must be a descendant of an Actor, otherwise the callback fails.

	@param name string -- The name of the event to connect to
	@param callback (...any) -> () -- The function to call when the event fires
	@return Connection -- Connection object with Disconnect method
]=]
function Event:ConnectParallel(name: string, callback: (...any) -> ()): Connection
	return self:Connect(name, function(...)
		task.desynchronize()
		local success, err = pcall(callback, ...)
		-- always go back to the serial phase, also when the callback fails
		task.synchronize()
		if not success then
			error(err, 0)
		end
	end)
end

--[=[
	Yields the current thread until the specified event fires, then returns the arguments.
	@param name string -- The name of the event to wait for
	@return ...any -- The arguments passed to Fire() when the event fires
	@yields
]=]
function Event:Wait(name: string): ...any
	self._waitThreads[name] = self._waitThreads[name] or {}

	table.insert(self._waitThreads[name], coroutine.running())
	return coroutine.yield()
end

return Event
