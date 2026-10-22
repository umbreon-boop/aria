--[=[
	A basic wrapper for easily creating reactive APIs. Useful for creating Instance like objects.
	Methods come before stored values. Do not use the names `New`, `Define`, `From` or `Clone` for properties, because the method hides the value.
	@class Interface
]=]
local Interface = {}
Interface.__index = function(self, key: any)
	return Interface[key] or self._storage[key]
end
Interface.__newindex = function(self, key: any, value: any)
	local calls = self._callbacks[key]
	if calls == nil then
		error("There is no registered property for " .. tostring(key) .. " in the indexed object.", 2)
	end

	if self._storage[key] ~= value then
		self._storage[key] = value
		for _, call in ipairs(calls) do
			call(value)
		end
	end
end

type Callback = (value: any) -> ()
export type Interface = typeof(setmetatable(
		{} :: {
			_storage: { [string]: any },
			_callbacks: { [string]: { Callback } },
		},
		Interface
	))

local setmetatable = setmetatable
local ipairs = ipairs
local function clone(t, seen)
	seen = seen or {}
	if seen[t] then
		return seen[t]
	end

	local result = setmetatable({}, getmetatable(t))
	seen[t] = result
	for k, v in pairs(t) do
		-- rawset, because the metatable can have a __newindex, for example an Interface
		rawset(result, k, if type(v) == "table" then clone(v, seen) else v)
	end
	return result
end

--[=[
	Creates a new instance of the Interface.

	@param callbacks { [string]: Callback | { Callback } }? -- Optional table of initial callbacks. A value can be one function or an array of functions.
	@param storage { [string]: any }? -- Optional initial state table
	@return Interface -- The newly created reactive interface instance
]=]
function Interface.New(callbacks: { [string]: Callback | { Callback } }?, storage: { [string]: any }?): Interface
	local self = setmetatable({}, Interface)

	local lists = {}
	for name, calls in callbacks or {} do
		-- a copy, so that a later Define does not change the table of the caller
		lists[name] = if type(calls) == "function" then { calls } else table.clone(calls)
	end

	rawset(self, "_callbacks", lists)
	rawset(self, "_storage", if storage then clone(storage) else {})

	return self
end

--[=[
	Registers a new reactive property on the interface.

	@param name string -- The name of the property to register
	@param callback Callback? -- An optional function to execute when the property changes
]=]
function Interface:Define(name: string, callback: Callback?)
	self._callbacks[name] = self._callbacks[name] or {}
	if callback then
		table.insert(self._callbacks[name], callback)
	end
end

--[=[
	Sets values from a table into storage and fires their registered callbacks. Register the properties with `Define` before you call this.
	Each value works like a direct assignment. If a property is not registered, the function stops with an error and changes no values.
	If the argument is an Interface, the function returns the argument without changes.
	@param properties { [string]: any } -- A table of property names and values to apply
	@return Interface -- This Interface, or the argument if it is an Interface
	@error "There is no registered property for {key} in the indexed object." -- Throws when a property is not registered
]=]
function Interface:From(properties: { [string]: any })
	if properties._storage and properties._callbacks then
		return properties
	end

	-- check all keys first, so that an error does not leave a partial update
	for key in pairs(properties) do
		if self._callbacks[key] == nil then
			error("There is no registered property for " .. tostring(key) .. " in the indexed object.", 2)
		end
	end

	for key, value in pairs(properties) do
		Interface.__newindex(self, key, value)
	end

	return self
end

--[=[
	Creates a deep copy of the current Interface. You can change the copy and the original independently.
	The copy keeps the metatable of the original, so subclasses stay subclasses. Callbacks are copied by reference.
	@return Interface -- A new, independent Interface instance
]=]
function Interface:Clone(): Interface
	local seen = {}
	local new = setmetatable({}, getmetatable(self))
	seen[self] = new
	for property, value in pairs(self) do
		rawset(new, property, if type(value) == "table" then clone(value, seen) else value)
	end

	return new
end

return Interface
