--[=[
	Simple wrapper type over `buffer` that automatically extends its capacity

	@class Vec
	@prop capacity number -- The memory currently allocated to the vector in **bytes**
	@prop length number -- The topmost written location in bits
]=]
local Vec = {}
Vec.__index = Vec

export type Vec = typeof(setmetatable({} :: {
	inner: buffer,
	capacity: number,
	length: number,
}, Vec))

--@inline
function Vec:_ensure(required)
	local capacity = buffer.len(self.inner)
	if (required - capacity) > 0 then
		capacity = if required > capacity * 2 then required else capacity * 2

		local new = buffer.create(capacity)
		self.capacity = capacity

		buffer.copy(new, 0, self.inner, 0)
		self.inner = new
	end
end

--@inline
function Vec:_use(slots)
	self.length = if slots > self.length then slots else self.length
end

--[=[
	Reads a range of bits into an unsigned integer from the buffer based on a specific `count` integer from 0 to 32, inclusive.

	@param offset number -- The offset from which to start reading
	@param count number -- How many bits to read
	@return number -- The value that will be read from the buffer
]=]
function Vec:Read(offset: number, count: number): number
	return buffer.readbits(self.inner, offset, count)
end

--[=[
	Writes data to the buffer based on a specific `count` integer from 0 to 32, inclusive. `value` is treated as an unsigned 32-bit number and only `count` least significant bits are written.

	@param offset number -- The offset from which to start writing
	@param count number -- How many bits to write
	@param value number -- The value that will be written to the buffer
]=]
function Vec:Write(offset: number, count: number, value: number)
	local required = offset + count
	self:_ensure(math.ceil(required / 8))

	self:_use(required)
	buffer.writebits(self.inner, offset, count, value)
end

--[=[
	Writes data to the end of the buffer.

	@param count number -- How many bits to write
	@param value number -- The value that will be written to the buffer
]=]
function Vec:Append(count: number, value: number)
	self:Write(self.length, count, value)
end

--[=[
	Reads a string from the buffer.

	@param offset number -- The offset from which to start reading
	@param count number -- How many **bytes** to read
	@return string -- The value that will be read from the buffer
]=]
function Vec:ReadString(offset: number, count: number): string
	return buffer.readstring(self.inner, offset, count)
end

--[=[
	Writes a string to the buffer.

	@param offset number -- The byte offset from which to start writing
	@param value string -- The value that will be written to the buffer
	@param count number? -- How many **bytes** to write
]=]
function Vec:WriteString(offset: number, value: string, count: number?)
	local required = if count then offset + count else offset + #value
	self:_ensure(required)

	self:_use(required * 8)
	buffer.writestring(self.inner, offset, value, count)
end

--[=[
	Writes a string to the end of the buffer. The string starts at the next full byte.

	@param value string -- The value that will be written to the buffer
	@param count number? -- How many **bytes** to write, defaults to the whole string
]=]
function Vec:AppendString(value: string, count: number?)
	self:WriteString(math.ceil(self.length / 8), value, count)
end

--[=[
	Converts the vector into a string.
	@return string The resulting string
]=]
function Vec:ToString(): string
	return buffer.readstring(self.inner, 0, math.ceil(self.length / 8))
end

--[=[
	Creates a new vector from a string.

	@param str string The string to initialize the vector with
	@return Vec The now initialized vector
]=]
function Vec.FromString(str: string): Vec
	local new = buffer.fromstring(str)
	local len = buffer.len(new)
	return setmetatable({
		inner = new,
		capacity = len,
		length = len * 8
	}, Vec)
end

--[=[
	Creates a new instance of this class.

	@param capacity number? -- How many bytes will be initially allocated to the vector
	@return Vec The newly allocated vector
]=]
function Vec.New(capacity: number?): Vec
	capacity = capacity or 8
	return setmetatable({
		inner = buffer.create(capacity),
		capacity = capacity,
		length = 0
	}, Vec)
end

return Vec
