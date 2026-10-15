--[=[
	Lets you easily group related data structures so you can destroy all of them at once!
	@class Maid
]=]
local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local Deque = require("./deque")

local Maid = {}
Maid.__index = Maid

---@type Task
export type Task = (() -> ()) | thread | Instance | RBXScriptConnection | {Destroy: (any) -> ()} | {Disconnect: (any) -> ()}
export type Maid = typeof(setmetatable({_tasks = {} :: {Task}}, Maid))

--[=[
	Creates a new instance of the Maid class.
	@return Maid -- A new maid with no tasks.
]=]
function Maid.new(): Maid
	return setmetatable({_tasks = {}}, Maid)
end
Maid.New = Maid.new

--[=[
	Will call the destructor for the passed object or the given closure upon cleanup. You can also pass an array of objects you want to be cleaned.
	@param task Task | {Task} -- A closure, thread, Instance, connection, or object with a `Destroy` or `Disconnect` method, or an array of these.
]=]
function Maid:Task(task: Task | {Task})
	local candidate: any = task
	if type(candidate) == "table" and not candidate.Destroy and not candidate.Disconnect then
		for _, obj in candidate do
			table.insert(self._tasks, obj)
		end
	else
		table.insert(self._tasks, candidate)
	end
end

--[=[
	Will listen for the provided Instance's destruction, and run `Maid:Clean()` when it takes place.
	@param obj Instance -- The Instance to watch. Remember to properly scope your maids if you're going to use this!
]=]
function Maid:LinkCleanup(obj: Instance)
	if obj:IsA("Player") then
		self:Task(Players.PlayerRemoving:Connect(function(removed)
			if removed == obj then
				self:Clean()
			end
		end))
	else
		self:Task(obj.Destroying:Connect(function()
			self:Clean()
		end))
	end
end

local function cancelThread(thread: thread)
	xpcall(task.cancel, function(e)
		local name = debug.info(4, "n")
		warn(debug.traceback(`Maid could not cancel thread for "{name or "Unknown"}": {e}`))
	end, thread)
end

--[=[
	Cleans up all given tasks in the order they were added.
	If a task fails, the maid shows a warning and continues with the next task.
]=]
function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, obj in tasks do
		local kind = typeof(obj)
		local isTable = kind == "table"

		local ok, err = pcall(function()
			if kind == "Instance" or (isTable and obj.Destroy) then
				obj:Destroy()
			elseif kind == "RBXScriptConnection" or (isTable and obj.Disconnect) then
				obj:Disconnect()
			elseif kind == "thread" then
				cancelThread(obj)
			else
				obj()
			end
		end)
		if not ok then
			warn(debug.traceback(`Maid failed to clean task: {err}`))
		end
	end
end

--[=[
	Same as `Maid:Clean()`. With this method, a maid can be a task of another maid.
]=]
Maid.Destroy = Maid.Clean

--[=[
	Incrementally destroys any given instance tasks to prevent stuttering caused by the garbage collector.
	@param budget number -- The per frame budget allocated to instance destruction, in seconds.
]=]
function Maid:DeferredClean(budget: number)
	local tasks = self._tasks
	self._tasks = {}

	local queue = Deque.New()
	for _, obj in tasks do
		local kind = typeof(obj)
		local isTable = kind == "table"

		if kind == "RBXScriptConnection" or (isTable and not obj.Destroy and obj.Disconnect) then
			obj:Disconnect()
		elseif kind == "thread" then
			cancelThread(obj)
		else
			if kind == "Instance" then
				-- the Parent of a destroyed Instance is locked, so this can fail
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
				else
					obj()
				end
			end)
			if not ok then
				warn(debug.traceback(`Maid failed to clean task: {err}`))
			end

			if os.clock() - start > budget then
				Run.Heartbeat:Wait()
				start = os.clock()
			end
		end
	end)
end

return Maid
