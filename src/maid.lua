--[=[
	Lets you easily group related data structures so you can destroy all of them at once!
	@class Maid
]=]
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Deque = require("./deque")

local cancelThread = task.cancel

local Maid = {}
Maid.__index = Maid

---@type Task
export type Task = (() -> ()) | thread | Instance | RBXScriptConnection | {Destroy: (any) -> ()} | {Disconnect: (any) -> ()}
type Slot = Task | false
export type Maid = typeof(setmetatable({
	_tasks = {} :: {Slot}?,
	_index = {} :: {[Task]: number}?,
	_holes = 0,
}, Maid))

--@inline
local function isAlive(self: Maid)
	if not self._tasks or not self._index then
		error("Maid is destroyed", 3)
	end
end

--@inline
local function live(self: Maid): {Slot}
	if not self._tasks or not self._index then
		error("Maid is destroyed", 3)
	end
	return self._tasks
end

--@inline
local function add(tasks: {Slot}, index: {[Task]: number}, obj: any)
	if obj ~= nil and not index[obj] then
		table.insert(tasks, obj)
		index[obj] = #tasks
	end
end

--@inline
local function position(self: Maid, task: Task): number?
	if self._index then
		return self._index[task]
	end
end

--@inline
local function remove(self: Maid, task: Task, position: number)
	local tasks, index = self._tasks, self._index
	if tasks and index then
		tasks[position] = false
		index[task] = nil
		self._holes += 1

		-- compact once more than half of the slots are empty
		if self._holes > 32 and self._holes * 2 > #tasks then
			local compact = {}
			table.clear(index)
			for _, obj in tasks do
				if obj then
					table.insert(compact, obj)
					index[obj] = #compact
				end
			end
			self._tasks = compact
			self._holes = 0
		end
	end
end

--[=[
	Will call the destructor for the passed object or the given closure upon cleanup. You can also pass an array of objects you want to be cleaned.
	A task that is already tracked is ignored, so it is cleaned once.
	@param value Task | {Task} -- A closure, thread, Instance, connection, or object with a `Destroy` or `Disconnect` method, or an array of these.
	@return Task | {Task} -- The parameter is returned back
	@error "Maid is destroyed" -- Thrown when the maid was destroyed with `Destroy`
]=]
function Maid:Task<T>(value: Task | {Task}): T
	local tasks = live(self)
	local index = self._index :: {[Task]: number}
	local candidate: any = value
	if type(candidate) == "table" and not candidate.Destroy and not candidate.Disconnect then
		for _, obj in candidate do
			add(tasks, index, obj)
		end
	else
		add(tasks, index, candidate)
	end
	return candidate
end

local function link(self: Maid, obj: Instance, destroy: boolean)
	isAlive(self)
	if obj:IsA("Player") then
		self:Task(Players.PlayerRemoving:Connect(function(removed)
			if removed == obj then
				if destroy then
					self:Destroy()
				else
					self:Clean()
				end
			end
		end))
	else
		self:Task(obj.Destroying:Connect(function()
			if destroy then
				self:Destroy()
			else
				self:Clean()
			end
		end))
	end
end

--[=[
	Will destroy the Maid upon the given Instance's destruction.
	@param obj Instance -- The Instance to watch. Remember to properly scope your maids if you're going to use this!
	@error "Maid is destroyed" -- Thrown when the maid was destroyed with `Destroy`
]=]
function Maid:Link(obj: Instance)
	link(self, obj, true)
end

--[=[
	Will clean the Maid upon the given Instance's destruction. This is the old `Link` behavior.
	@param obj Instance -- The Instance to watch.
	@error "Maid is destroyed" -- Thrown when the maid was destroyed with `Destroy`
]=]
function Maid:LinkCleanup(obj: Instance)
	link(self, obj, false)
end

--@inline
local function cleanTask(obj: any)
	local kind = typeof(obj)
	local isTable = kind == "table"

	local ok, err = pcall(function()
		if kind == "Instance" or (isTable and obj.Destroy) then
			obj:Destroy()
		elseif kind == "RBXScriptConnection" or (isTable and obj.Disconnect) then
			obj:Disconnect()
		elseif kind == "thread" then
			local cancelled, cancelError = pcall(cancelThread, obj)
			if not cancelled then
				warn(debug.traceback("Maid could not cancel thread: " .. tostring(cancelError)))
			end
		elseif kind == "function" then
			obj()
		else
			warn("Could not destroy object " .. tostring(obj))
		end
	end)
	if not ok then
		warn(debug.traceback("Maid failed to clean task: " .. tostring(err)))
	end
end

--@inline
local function clean(tasks: {Slot})
	for _, obj in tasks do
		if obj then
			cleanTask(obj)
		end
	end
end

--[=[
	Cleans a single task right away and stops tracking it.
	Does nothing when the task is not tracked or the maid is destroyed.
	@param task Task -- The task to clean, as it was passed to `Task`.
	@return boolean -- Whether the task was tracked.
]=]
function Maid:Remove(task: Task): boolean
	local position = position(self, task)
	if not position then
		return false
	end
	remove(self, task, position)
	cleanTask(task)
	return true
end

--[=[
	Stops tracking a task without cleaning it, for example to hand it to another maid.
	Does nothing when the task is not tracked or the maid is destroyed.
	@param task Task -- The task to release, as it was passed to `Task`.
	@return boolean -- Whether the task was tracked.
]=]
function Maid:Release(task: Task): boolean
	local position = position(self, task)
	if not position then
		return false
	end
	remove(self, task, position)
	return true
end

--[=[
	Destroys the Maid instance whilst cleaning up all given tasks.
	Afterwards `Task`, `Link` and `DeferredClean` throw. Calling it again does nothing.
]=]
function Maid:Destroy()
	local tasks = self._tasks
	if not tasks then
		return
	end
	self._tasks = nil
	self._index = nil
	clean(tasks)
end

--[=[
	Cleans up all given tasks in the order they were added.
	If a task fails, the maid shows a warning and continues with the next task.
	Does nothing when the maid is destroyed.
]=]
function Maid:Clean()
	local tasks = self._tasks
	if not tasks then
		return
	end
	self._tasks = {}
	self._index = {}
	self._holes = 0
	clean(tasks)
end

--[=[
	Incrementally destroys any given instance tasks to prevent stuttering caused by the garbage collector.
	@param budget number -- The per frame budget allocated to instance destruction, in seconds.
	@error "Maid is destroyed" -- Thrown when the maid was destroyed with `Destroy`
]=]
function Maid:DeferredClean(budget: number)
	if type(budget) ~= "number" or budget < 0 then
		error("budget must be a non-negative number", 2)
	end

	local tasks = live(self)
	self._tasks = {}
	self._index = {}
	self._holes = 0

	local queue = Deque.New()
	for _, obj in tasks do
		if not obj then
			continue
		end

		local kind = typeof(obj)
		local isTable = kind == "table"

		if kind == "RBXScriptConnection" or (isTable and not obj.Destroy and obj.Disconnect) or kind == "thread" then
			cleanTask(obj)
		else
			if kind == "Instance" then
				-- the Parent of a destroyed Instance is locked
				pcall(function()
					obj.Parent = nil
				end)
			end
			queue:Push(obj)
		end
	end

	if queue:Len() == 0 then
		return
	end

	task.spawn(function()
		local start = os.clock()
		while queue:Len() > 0 do
			local obj = queue:Pop()

			local ok, err = pcall(function()
				if typeof(obj) == "Instance" then
					for _, child in obj:GetChildren() do
						-- one locked child must not stop the other children
						pcall(function()
							child.Parent = nil
						end)
						queue:PushFront(child)
					end
					obj:Destroy()
				elseif type(obj) == "table" and obj.Destroy then
					obj:Destroy()
				elseif type(obj) == "function" then
					obj()
				else
					warn("Could not destroy object " .. tostring(obj))
				end
			end)
			if not ok then
				warn(debug.traceback("Maid failed to clean task: " .. tostring(err)))
			end

			if os.clock() - start > budget then
				Run.Heartbeat:Wait()
				start = os.clock()
			end
		end
	end)
end

--[=[
	Creates a new instance of the Maid class.
	@return Maid -- A new maid with no tasks.
]=]
function Maid.New(): Maid
	return setmetatable({_tasks = {}, _index = {}, _holes = 0}, Maid)
end

Maid.new = Maid.New

return Maid
