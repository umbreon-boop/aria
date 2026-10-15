--[=[
	Basic implementation of a first-in, first-out double ended queue.
	@class Deque
]=]
local Deque = {}
Deque.__index = Deque

export type Deque = typeof(setmetatable({} :: {
	items: {[number]: any},
	head: number,
	tail: number,
}, Deque))

--[=[
	Adds a value to the back of the queue.

	@param self Deque -- The queue to add to.
	@param value any -- The value to enqueue. Must not be `nil`, since `pop` uses `nil` to signal an empty queue.
]=]
function Deque.Push(self: Deque, value: any)
	self.tail += 1
	self.items[self.tail] = value
end

--[=[
	Adds a value to the front of the queue.

	@param self Deque -- The queue to add to.
	@param value any -- The value to enqueue. Must not be `nil`, since `pop` uses `nil` to signal an empty queue.
]=]
function Deque.PushFront(self: Deque, value: any)
	self.head -= 1
	self.items[self.head] = value
end

--[=[
	Removes and returns the value at the front of the queue.

	@param self Deque -- The queue to remove from.
	@return any? -- The oldest value in the queue, or `nil` if the queue is empty.
]=]
function Deque.Pop(self: Deque): any?
	if self.head > self.tail then
		return nil
	end

	local value = self.items[self.head]
	self.items[self.head] = nil
	self.head += 1

	return value
end

--[=[
	Removes and returns the value at the end of the queue.

	@param self Deque -- The queue to remove from.
	@return any? -- The newest value in the queue, or `nil` if the queue is empty.
]=]
function Deque.PopBack(self: Deque): any?
	if self.head > self.tail then
		return nil
	end

	local value = self.items[self.tail]
	self.items[self.tail] = nil
	self.tail -= 1

	return value
end

--[=[
	Returns the number of values currently in the queue.

	@param self Deque -- The queue to measure.
	@return number -- The count of values waiting to be popped.
]=]
function Deque.Len(self: Deque): number
	return self.tail - self.head + 1
end

--[=[
	Creates an empty queue.
	@return Deque -- A new queue containing no values.
]=]
function Deque.New(): Deque
	return setmetatable({items = {}, head = 1, tail = 0}, Deque)
end

return Deque
