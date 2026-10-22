--[=[
	Serialization and deserialization of primitives, tables, and Roblox instances.
	Custom types should not rely on this for restoration but rather use a constructor to rebuild the instance based upon the deserialized data. They may also chose which fields to serialize by listing their names in a `self._serde` array.

	@class Serde
]=]
local Vec = require("./vec")

local Serde = {}
local Type = { NIL = 0, BOOL = 1, NUMBER = 2, STRING = 3, TABLE = 4, REF = 5, INSTANCE = 6, DATATYPE = 7, BUFFER = 8 }
local MAGIC = "ARIA"
local VERSION = 2
local MAX_ITEMS = 1_000_000
local MAX_STRING = 64 * 1024 * 1024
local MAX_DEPTH = 256

--@inline
local function writef64(vec, value)
	local byteOffset = vec.length // 8
	vec:_ensure(byteOffset + 8)
	buffer.writef64(vec.inner, byteOffset, value)
	vec:_use((byteOffset + 8) * 8)
end

local function readf64(vec, pos)
	if pos + 64 > vec.length then
		error("Truncated serialized data", 2)
	end
	local byteOffset = pos // 8
	return buffer.readf64(vec.inner, byteOffset), pos + 64
end

--@inline
local function writeu8(vec, value)
	vec:Append(8, value)
end

local function readu8(vec, pos)
	if pos + 8 > vec.length then
		error("Truncated serialized data", 2)
	end
	return vec:Read(pos, 8), pos + 8
end

local function readBool(vec, pos)
	local value
	value, pos = readu8(vec, pos)
	if value > 1 then
		error("Invalid boolean value", 2)
	end
	return value == 1, pos
end

--@inline
local function writeu32(vec, value)
	vec:Append(32, value % 0x100000000)
end

local function readu32(vec, pos)
	if pos + 32 > vec.length then
		error("Truncated serialized data", 2)
	end
	return vec:Read(pos, 32), pos + 32
end

--@inline
local function writeu16(vec, value)
	vec:Append(16, value % 0x10000)
end

local function readu16(vec, pos)
	if pos + 16 > vec.length then
		error("Truncated serialized data", 2)
	end
	return vec:Read(pos, 16), pos + 16
end

--@inline
local function writeString(vec, value)
	if #value > MAX_STRING then
		error("String is too large to serialize")
	end
	writeu32(vec, #value)
	vec:AppendString(value)
end

local function readString(vec, pos, maxLength)
	local length
	length, pos = readu32(vec, pos)
	if length > (maxLength or MAX_STRING) then
		error("Serialized string is too large", 2)
	end
	if pos + length * 8 > vec.length then
		error("Truncated serialized string", 2)
	end
	if length == 0 then
		return "", pos
	end
	return vec:ReadString(pos // 8, length), pos + length * 8
end

local function writePath(vec, path)
	writeu32(vec, #path)
	for _, name in ipairs(path) do
		writeString(vec, name)
	end
end

local function readPath(vec, pos)
	local count
	count, pos = readu32(vec, pos)
	if count > MAX_ITEMS or count > (vec.length - pos) // 32 then
		error("Invalid path length", 2)
	end

	local path = table.create(count)
	for index = 1, count do
		path[index], pos = readString(vec, pos)
	end
	return path, pos
end

local function writeHeader(vec)
	vec:AppendString(MAGIC)
	writeu8(vec, VERSION)
end

local function readHeader(vec)
	if vec.length < (#MAGIC + 1) * 8 then
		error("Serialized data is too short", 2)
	end
	if vec:ReadString(0, #MAGIC) ~= MAGIC then
		error("Invalid serialized data", 2)
	end
	local version = vec:Read(#MAGIC * 8, 8)
	if version ~= VERSION then
		error(`Unsupported serialized format version: {version}`, 2)
	end
	return (#MAGIC + 1) * 8
end

local function toSigned(value)
	return if value >= 0x80000000 then value - 0x100000000 else value
end

local function toSigned16(value)
	return if value >= 0x8000 then value - 0x10000 else value
end

--@inline
local function packedCodec(n, extract, construct)
	return {
		encode = function(vec, val)
			local values = table.pack(extract(val))
			for index = 1, n do
				writef64(vec, values[index])
			end
		end,
		decode = function(vec, pos)
			local values = table.create(n)
			for index = 1, n do
				values[index], pos = readf64(vec, pos)
			end
			return construct(table.unpack(values, 1, n)), pos
		end,
	}
end

local function getEnum(name)
	local ok, enum = pcall(function()
		return (Enum :: any)[name]
	end)
	if not ok or not enum then
		error(`Unknown enum: {name}`)
	end
	return enum
end

local function getEnumItem(enum, value)
	for _, item in ipairs(enum:GetEnumItems()) do
		if item.Value == value then
			return item
		end
	end
	error(`Unknown enum item: {enum}.{value}`)
end

local function enumName(value)
	local name = tostring(value.EnumType)
	return if string.sub(name, 1, 5) == "Enum." then string.sub(name, 6) else name
end

local datatypes = {}
datatypes.Vector3 = packedCodec(3, function(v)
	return v.X, v.Y, v.Z
end, Vector3.new)
datatypes.Vector2 = packedCodec(2, function(v)
	return v.X, v.Y
end, Vector2.new)
datatypes.CFrame = packedCodec(12, function(v)
	return v:GetComponents()
end, CFrame.new)
datatypes.Color3 = packedCodec(3, function(v)
	return v.R, v.G, v.B
end, Color3.new)
datatypes.UDim = packedCodec(2, function(v)
	return v.Scale, v.Offset
end, UDim.new)
datatypes.UDim2 = packedCodec(4, function(v)
	return v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset
end, UDim2.new)
datatypes.Rect = packedCodec(4, function(v)
	return v.Min.X, v.Min.Y, v.Max.X, v.Max.Y
end, Rect.new)

datatypes.EnumItem = {
	encode = function(vec, val)
		writeString(vec, enumName(val))
		writeu32(vec, val.Value)
	end,
	decode = function(vec, pos)
		local name
		name, pos = readString(vec, pos)
		local value
		value, pos = readu32(vec, pos)
		return getEnumItem(getEnum(name), toSigned(value)), pos
	end,
}

datatypes.BrickColor = {
	encode = function(vec, val)
		writeu32(vec, val.Number)
	end,
	decode = function(vec, pos)
		local number
		number, pos = readu32(vec, pos)
		return BrickColor.new(number), pos
	end,
}

datatypes.Content = {
	encode = function(vec, val, context, recursiveFunction)
		local source = val.SourceType
		if source == Enum.ContentSourceType.None then
			writeu8(vec, 0)
		elseif source == Enum.ContentSourceType.Uri then
			writeu8(vec, 1)
			writeString(vec, val.Uri)
		elseif source == Enum.ContentSourceType.Object then
			writeu8(vec, 2)
			recursiveFunction(vec, val.Object, context)
		elseif source == Enum.ContentSourceType.Opaque then
			error("Content.Opaque cannot be serialized")
		else
			error("Unknown Content source type")
		end
	end,
	decode = function(vec, pos, context, recursiveFunction)
		local tag
		tag, pos = readu8(vec, pos)
		if tag == 0 then
			return Content.none, pos
		elseif tag == 1 then
			local uri
			uri, pos = readString(vec, pos)
			return Content.fromUri(uri), pos
		elseif tag == 2 then
			local object
			object, pos = recursiveFunction(vec, pos, context)
			if object == nil then
				error("Content object is missing")
			end
			return Content.fromObject(object), pos
		end
		error(`Unknown Content source tag: {tag}`)
	end,
}

local function createFont(family, weight, style)
	weight = weight or Enum.FontWeight.Regular
	style = style or Enum.FontStyle.Normal

	local ok, font = pcall(Font.new, family, weight, style)
	if ok then
		return font
	end
	if typeof(family) == "Content" and family.SourceType == Enum.ContentSourceType.Uri then
		local fallback, result = pcall(Font.new, family.Uri, weight, style)
		if fallback then
			return result
		end
	end
	error("Could not create Font")
end

datatypes.Font = {
	encode = function(vec, val, context, recursiveFunction)
		local family = val.Family
		if typeof(family) == "string" then
			family = Content.fromUri(family)
		end
		if typeof(family) ~= "Content" then
			error("Font family is not Content")
		end
		datatypes.Content.encode(vec, family, context, recursiveFunction)
		writeu32(vec, val.Weight.Value)
		writeu32(vec, val.Style.Value)
	end,
	decode = function(vec, pos, context, recursiveFunction)
		local family
		family, pos = datatypes.Content.decode(vec, pos, context, recursiveFunction)
		local weightValue
		weightValue, pos = readu32(vec, pos)
		local styleValue
		styleValue, pos = readu32(vec, pos)
		local weight = getEnumItem(Enum.FontWeight, toSigned(weightValue))
		local style = getEnumItem(Enum.FontStyle, toSigned(styleValue))
		return createFont(family, weight, style), pos
	end,
}

datatypes.ColorSequence = {
	encode = function(vec, val)
		if #val.Keypoints > MAX_ITEMS then
			error("Too many ColorSequence keypoints")
		end
		writeu32(vec, #val.Keypoints)
		for _, keypoint in ipairs(val.Keypoints) do
			writef64(vec, keypoint.Time)
			writef64(vec, keypoint.Value.R)
			writef64(vec, keypoint.Value.G)
			writef64(vec, keypoint.Value.B)
		end
	end,
	decode = function(vec, pos)
		local count
		count, pos = readu32(vec, pos)
		if count > MAX_ITEMS or count > (vec.length - pos) // (32 * 8) then
			error("Invalid ColorSequence keypoint count")
		end
		local keypoints = table.create(count)
		for index = 1, count do
			local time, r, g, b
			time, pos = readf64(vec, pos)
			r, pos = readf64(vec, pos)
			g, pos = readf64(vec, pos)
			b, pos = readf64(vec, pos)
			keypoints[index] = ColorSequenceKeypoint.new(time, Color3.new(r, g, b))
		end
		return ColorSequence.new(keypoints), pos
	end,
}

datatypes.NumberSequence = {
	encode = function(vec, val)
		if #val.Keypoints > MAX_ITEMS then
			error("Too many NumberSequence keypoints")
		end
		writeu32(vec, #val.Keypoints)
		for _, keypoint in ipairs(val.Keypoints) do
			writef64(vec, keypoint.Time)
			writef64(vec, keypoint.Value)
			writef64(vec, keypoint.Envelope)
		end
	end,
	decode = function(vec, pos)
		local count
		count, pos = readu32(vec, pos)
		if count > MAX_ITEMS or count > (vec.length - pos) // (24 * 8) then
			error("Invalid NumberSequence keypoint count")
		end
		local keypoints = table.create(count)
		for index = 1, count do
			local time, value, envelope
			time, pos = readf64(vec, pos)
			value, pos = readf64(vec, pos)
			envelope, pos = readf64(vec, pos)
			keypoints[index] = NumberSequenceKeypoint.new(time, value, envelope)
		end
		return NumberSequence.new(keypoints), pos
	end,
}

datatypes.NumberRange = {
	encode = function(vec, val)
		writef64(vec, val.Min)
		writef64(vec, val.Max)
	end,
	decode = function(vec, pos)
		local min, max
		min, pos = readf64(vec, pos)
		max, pos = readf64(vec, pos)
		return NumberRange.new(min, max), pos
	end,
}

datatypes.Ray = {
	encode = function(vec, val)
		writef64(vec, val.Origin.X)
		writef64(vec, val.Origin.Y)
		writef64(vec, val.Origin.Z)
		writef64(vec, val.Direction.X)
		writef64(vec, val.Direction.Y)
		writef64(vec, val.Direction.Z)
	end,
	decode = function(vec, pos)
		local ox, oy, oz, dx, dy, dz
		ox, pos = readf64(vec, pos)
		oy, pos = readf64(vec, pos)
		oz, pos = readf64(vec, pos)
		dx, pos = readf64(vec, pos)
		dy, pos = readf64(vec, pos)
		dz, pos = readf64(vec, pos)
		return Ray.new(Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz)), pos
	end,
}

datatypes.Region3 = {
	encode = function(vec, val)
		local position, size = val.CFrame.Position, val.Size
		writef64(vec, position.X)
		writef64(vec, position.Y)
		writef64(vec, position.Z)
		writef64(vec, size.X)
		writef64(vec, size.Y)
		writef64(vec, size.Z)
	end,
	decode = function(vec, pos)
		local px, py, pz, sx, sy, sz
		px, pos = readf64(vec, pos)
		py, pos = readf64(vec, pos)
		pz, pos = readf64(vec, pos)
		sx, pos = readf64(vec, pos)
		sy, pos = readf64(vec, pos)
		sz, pos = readf64(vec, pos)
		local half = Vector3.new(sx / 2, sy / 2, sz / 2)
		local center = Vector3.new(px, py, pz)
		return Region3.new(center - half, center + half), pos
	end,
}

datatypes.Vector3int16 = {
	encode = function(vec, val)
		writeu16(vec, val.X)
		writeu16(vec, val.Y)
		writeu16(vec, val.Z)
	end,
	decode = function(vec, pos)
		local x, y, z
		x, pos = readu16(vec, pos)
		y, pos = readu16(vec, pos)
		z, pos = readu16(vec, pos)
		return Vector3int16.new(toSigned16(x), toSigned16(y), toSigned16(z)), pos
	end,
}

datatypes.Vector2int16 = {
	encode = function(vec, val)
		writeu16(vec, val.X)
		writeu16(vec, val.Y)
	end,
	decode = function(vec, pos)
		local x, y
		x, pos = readu16(vec, pos)
		y, pos = readu16(vec, pos)
		return Vector2int16.new(toSigned16(x), toSigned16(y)), pos
	end,
}

datatypes.Region3int16 = {
	encode = function(vec, val)
		for _, vector in ipairs({val.Min, val.Max}) do
			writeu16(vec, vector.X)
			writeu16(vec, vector.Y)
			writeu16(vec, vector.Z)
		end
	end,
	decode = function(vec, pos)
		local function readVector()
			local x, y, z
			x, pos = readu16(vec, pos)
			y, pos = readu16(vec, pos)
			z, pos = readu16(vec, pos)
			return Vector3int16.new(toSigned16(x), toSigned16(y), toSigned16(z))
		end
		local min = readVector()
		local max = readVector()
		return Region3int16.new(min, max), pos
	end,
}

datatypes.TweenInfo = {
	encode = function(vec, val)
		writef64(vec, val.Time)
		datatypes.EnumItem.encode(vec, val.EasingStyle)
		datatypes.EnumItem.encode(vec, val.EasingDirection)
		writef64(vec, val.RepeatCount)
		writeu8(vec, val.Reverses and 1 or 0)
		writef64(vec, val.DelayTime)
	end,
	decode = function(vec, pos)
		local time
		time, pos = readf64(vec, pos)
		local style
		style, pos = datatypes.EnumItem.decode(vec, pos)
		local direction
		direction, pos = datatypes.EnumItem.decode(vec, pos)
		local repeatCount
		repeatCount, pos = readf64(vec, pos)
		local reverses
		reverses, pos = readBool(vec, pos)
		local delayTime
		delayTime, pos = readf64(vec, pos)
		return TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime), pos
	end,
}

datatypes.DateTime = {
	encode = function(vec, val)
		local millis = val.UnixTimestampMillis or val.UnixTimestamp * 1000
		writef64(vec, millis)
	end,
	decode = function(vec, pos)
		local millis
		millis, pos = readf64(vec, pos)
		local ok, value = pcall(DateTime.fromUnixTimestampMillis, millis)
		if not ok then
			value = DateTime.fromUnixTimestamp(millis / 1000)
		end
		return value, pos
	end,
}

datatypes.PhysicalProperties = {
	encode = function(vec, val)
		writef64(vec, val.Density)
		writef64(vec, val.Friction)
		writef64(vec, val.Elasticity)
		writef64(vec, val.FrictionWeight)
		writef64(vec, val.ElasticityWeight)
	end,
	decode = function(vec, pos)
		local density, friction, elasticity, frictionWeight, elasticityWeight
		density, pos = readf64(vec, pos)
		friction, pos = readf64(vec, pos)
		elasticity, pos = readf64(vec, pos)
		frictionWeight, pos = readf64(vec, pos)
		elasticityWeight, pos = readf64(vec, pos)
		return PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight), pos
	end,
}

datatypes.PathWaypoint = {
	encode = function(vec, val)
		writef64(vec, val.Position.X)
		writef64(vec, val.Position.Y)
		writef64(vec, val.Position.Z)
		datatypes.EnumItem.encode(vec, val.Action)
		writeString(vec, val.Label)
	end,
	decode = function(vec, pos)
		local x, y, z
		x, pos = readf64(vec, pos)
		y, pos = readf64(vec, pos)
		z, pos = readf64(vec, pos)
		local action
		action, pos = datatypes.EnumItem.decode(vec, pos)
		local label
		label, pos = readString(vec, pos)
		return PathWaypoint.new(Vector3.new(x, y, z), action, label), pos
	end,
}

datatypes.Faces = {
	encode = function(vec, val)
		for _, name in ipairs({ "Top", "Bottom", "Left", "Right", "Front", "Back" }) do
			writeu8(vec, val[name] and 1 or 0)
		end
	end,
	decode = function(vec, pos)
		local names = { "Top", "Bottom", "Left", "Right", "Front", "Back" }
		local args = {}
		for _, name in ipairs(names) do
			local enabled
			enabled, pos = readBool(vec, pos)
			if enabled then
				table.insert(args, (Enum.NormalId :: any)[name])
			end
		end
		return Faces.new(table.unpack(args)), pos
	end,
}

datatypes.Axes = {
	encode = function(vec, val)
		for _, name in ipairs({ "X", "Y", "Z" }) do
			writeu8(vec, val[name] and 1 or 0)
		end
	end,
	decode = function(vec, pos)
		local args = {}
		for _, name in ipairs({ "X", "Y", "Z" }) do
			local enabled
			enabled, pos = readBool(vec, pos)
			if enabled then
				table.insert(args, (Enum.Axis :: any)[name])
			end
		end
		return Axes.new(table.unpack(args)), pos
	end,
}

local serializers = {}
local deserializers = {}

local function serializeValue(vec, val, context)
	context.depth += 1
	if context.depth > MAX_DEPTH then
		context.depth -= 1
		error("Maximum serialization depth exceeded")
	end

	local valueType = typeof(val)
	local serializeFunction = serializers[valueType]
	if serializeFunction then
		serializeFunction(vec, val, context, serializeValue)
		context.depth -= 1
		return
	end

	local codec = datatypes[valueType]
	if not codec then
		context.depth -= 1
		error("Unsupported type: " .. valueType)
	end

	writeu8(vec, Type.DATATYPE)
	writeString(vec, valueType)

	local lengthPosition = vec.length
	writeu32(vec, 0)
	local payloadStart = vec.length
	codec.encode(vec, val, context, serializeValue)
	vec:Write(lengthPosition, 32, (vec.length - payloadStart) // 8)
	context.depth -= 1
end

local function deserializeValue(vec, pos, context)
	local typeByte
	typeByte, pos = readu8(vec, pos)
	context.depth += 1
	if context.depth > MAX_DEPTH then
		context.depth -= 1
		error("Maximum deserialization depth exceeded")
	end

	if typeByte == Type.DATATYPE then
		local name
		name, pos = readString(vec, pos)
		local payloadLength
		payloadLength, pos = readu32(vec, pos)
		local payloadEnd = pos + payloadLength * 8
		if payloadEnd > vec.length then
			context.depth -= 1
			error("Truncated datatype payload", 2)
		end

		local codec = datatypes[name]
		if not codec then
			context.depth -= 1
			error(`Unknown datatype: {name}`, 2)
		end
		local value, after = codec.decode(vec, pos, context, deserializeValue)
		if after ~= payloadEnd then
			context.depth -= 1
			error(`Datatype payload length mismatch: {name}`, 2)
		end
		context.depth -= 1
		return value, payloadEnd
	end

	local deserializeFunction = deserializers[typeByte]
	if not deserializeFunction then
		context.depth -= 1
		error("Unknown type marker: " .. typeByte)
	end

	local value, after = deserializeFunction(vec, pos, context, deserializeValue)
	context.depth -= 1
	return value, after
end

serializers["nil"] = function(vec)
	writeu8(vec, Type.NIL)
end

serializers["boolean"] = function(vec, val)
	writeu8(vec, Type.BOOL)
	writeu8(vec, val and 1 or 0)
end

serializers["number"] = function(vec, val)
	writeu8(vec, Type.NUMBER)
	writef64(vec, val)
end

serializers["string"] = function(vec, val)
	writeu8(vec, Type.STRING)
	writeString(vec, val)
end

serializers["buffer"] = function(vec, val)
	local length = buffer.len(val)
	if length > MAX_STRING then
		error("Buffer is too large to serialize")
	end
	writeu8(vec, Type.BUFFER)
	writeu32(vec, length)
	vec:AppendString(buffer.readstring(val, 0, length))
end

serializers["Instance"] = function(vec, val, context)
	local id = context.instances[val]
	if not id then
		error("Instance is not part of the serialized graph: " .. tostring(val))
	end
	writeu8(vec, Type.INSTANCE)
	writeu32(vec, id)
end

serializers["table"] = function(vec, val, context, recursiveFunction)
	if context.ids[val] then
		writeu8(vec, Type.REF)
		writeu32(vec, context.ids[val])
		return
	end

	if context.counter.n >= MAX_ITEMS then
		error("Too many tables")
	end
	context.counter.n += 1
	local id = context.counter.n
	context.ids[val] = id

	writeu8(vec, Type.TABLE)
	writeu32(vec, id)

	local fields = val._serde
	if type(fields) == "table" then
		local seen = {}
		local names = {}
		for _, key in ipairs(fields) do
			if key ~= "_serde" and not seen[key] and val[key] ~= nil then
				seen[key] = true
				names[#names + 1] = key
			end
		end
		if #names > MAX_ITEMS then
			error("Table has too many entries")
		end
		writeu32(vec, #names)
		for _, key in ipairs(names) do
			recursiveFunction(vec, key, context)
			recursiveFunction(vec, val[key], context)
		end
	else
		local count = 0
		for _ in pairs(val) do
			count += 1
		end
		if count > MAX_ITEMS then
			error("Table has too many entries")
		end
		writeu32(vec, count)
		for key, value in pairs(val) do
			recursiveFunction(vec, key, context)
			recursiveFunction(vec, value, context)
		end
	end
end

deserializers[Type.NIL] = function(_, pos)
	return nil, pos
end

deserializers[Type.BOOL] = function(vec, pos)
	return readBool(vec, pos)
end

deserializers[Type.NUMBER] = function(vec, pos)
	return readf64(vec, pos)
end

deserializers[Type.STRING] = function(vec, pos)
	return readString(vec, pos)
end

deserializers[Type.BUFFER] = function(vec, pos)
	local length
	length, pos = readu32(vec, pos)
	if length > MAX_STRING or pos + length * 8 > vec.length then
		error("Invalid buffer length", 2)
	end
	local value = if length == 0 then "" else vec:ReadString(pos // 8, length)
	return buffer.fromstring(value), pos + length * 8
end

deserializers[Type.INSTANCE] = function(vec, pos, context)
	local id
	id, pos = readu32(vec, pos)
	if id == 0 or id > context.instanceCount then
		error("Invalid instance reference", 2)
	end
	return context.instances[id], pos
end

deserializers[Type.REF] = function(vec, pos, context)
	local id
	id, pos = readu32(vec, pos)
	local value = context.ids[id]
	if value == nil then
		error("Invalid table reference", 2)
	end
	return value, pos
end

deserializers[Type.TABLE] = function(vec, pos, context, recursiveFunction)
	local id
	id, pos = readu32(vec, pos)
	if id == 0 or id > MAX_ITEMS then
		error("Invalid table id", 2)
	end
	if context.ids[id] ~= nil then
		error("Duplicate table id", 2)
	end

	local count
	count, pos = readu32(vec, pos)
	if count > MAX_ITEMS or count > (vec.length - pos) // 16 then
		error("Invalid table entry count", 2)
	end

	local output = {}
	context.ids[id] = output
	for _ = 1, count do
		local key, value
		key, pos = recursiveFunction(vec, pos, context)
		if key == nil then
			error("Table key cannot be nil", 2)
		end
		value, pos = recursiveFunction(vec, pos, context)
		output[key] = value
	end
	return output, pos
end

local dump = nil
local propertyCache = {}
local propertySetCache = {}
local serviceClasses = {}
local notCreatableClasses = {}
local classesByName = {}

local function fetch(url)
	local ok, httpGet = pcall(function()
		return (game :: any).HttpGet
	end)
	if ok and httpGet then
		local success, result = pcall(httpGet, game, url)
		if success and type(result) == "string" and result ~= "" then
			return result
		end
	end
	return game:GetService("HttpService"):GetAsync(url)
end

local function getProperties(className)
	if not dump then
		local HttpService = game:GetService("HttpService")
		local version = fetch("https://setup.rbxcdn.com/versionQTStudio")
		version = string.match(version, "^%s*(.-)%s*$")
		dump = HttpService:JSONDecode(fetch(string.format("https://setup.rbxcdn.com/%s-API-Dump.json", version)))
		for _, class in ipairs(dump.Classes) do
			classesByName[class.Name] = class
			local tags = class.Tags or {}
			if table.find(tags, "Service") then
				serviceClasses[class.Name] = true
			end
			if table.find(tags, "NotCreatable") then
				notCreatableClasses[class.Name] = true
			end
		end
	end

	if propertyCache[className] then
		return propertyCache[className]
	end

	local names = {}
	local seen = {}
	local classesSeen = {}
	local current = classesByName[className]
	while current and not classesSeen[current] do
		classesSeen[current] = true
		for _, member in ipairs(current.Members or {}) do
			if member.MemberType == "Property" and member.Name ~= "Parent" and not seen[member.Name] then
				local serializable = true
				for _, tag in ipairs(member.Tags or {}) do
					if tag == "Deprecated" or tag == "Hidden" or tag == "NotScriptable" or tag == "ReadOnly" then
						serializable = false
						break
					end
				end

				local serialization = member.Serialization
				if serialization and serialization.CanLoad == false then
					serializable = false
				end

				local security = member.Security
				if security then
					if type(security) == "string" then
						serializable = serializable and security == "None"
					else
						serializable = serializable and security.Read == "None" and security.Write == "None"
					end
				end

				if serializable then
					seen[member.Name] = true
					names[#names + 1] = member.Name
				end
			end
		end
		current = current.Superclass and classesByName[current.Superclass] or nil
	end

	local set = {}
	for _, name in ipairs(names) do
		set[name] = true
	end
	propertyCache[className] = names
	propertySetCache[className] = set
	return names
end

local function getInstancePath(instance)
	local path = {}
	local current = instance
	while current and current ~= game do
		path[#path + 1] = current.Name
		current = current.Parent
	end
	for index = 1, #path // 2 do
		path[index], path[#path - index + 1] = path[#path - index + 1], path[index]
	end
	return path
end

local function resolvePath(path)
	if #path == 0 then
		return nil
	end

	local current = game
	for index, name in ipairs(path) do
		local nextInstance
		if index == 1 then
			local ok, service = pcall(function()
				return game:GetService(name)
			end)
			if ok then
				nextInstance = service
			end
		end
		if not nextInstance then
			local ok, child = pcall(function()
				return current:FindFirstChild(name)
			end)
			if ok then
				nextInstance = child
			end
		end
		if not nextInstance then
			return nil
		end
		current = nextInstance
	end
	return current
end

local function hasClass(instance, className)
	local ok, actual = pcall(function()
		return instance.ClassName
	end)
	return ok and actual == className
end

local function resolveInstance(className, ownPath)
	getProperties(className)

	if serviceClasses[className] then
		local ok, service = pcall(function()
			return game:GetService(className)
		end)
		return if ok then service else nil
	end

	if notCreatableClasses[className] and #ownPath > 0 then
		local existing = resolvePath(ownPath)
		if existing and hasClass(existing, className) then
			return existing
		end
	end

	local ok, instance = pcall(Instance.new, className)
	if ok and instance then
		return instance
	end

	if #ownPath > 0 then
		local existing = resolvePath(ownPath)
		if existing and hasClass(existing, className) then
			return existing
		end
	end
	return nil
end

local function isServiceClass(className)
	if not dump then
		getProperties(className)
	end
	return serviceClasses[className] == true
end

local discoverValue
local function expandInstance(instance, state, depth)
	local names = getProperties(instance.ClassName)
	for _, name in ipairs(names) do
		local ok, value = pcall(function()
			return instance[name]
		end)
		if ok then
			discoverValue(value, state, false, depth + 1)
		end
	end

	local attributesOk, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if attributesOk and type(attributes) == "table" then
		for _, value in pairs(attributes) do
			discoverValue(value, state, false, depth + 1)
		end
	end

	for _, child in ipairs(instance:GetChildren()) do
		discoverValue(child, state, false, depth + 1)
	end
end

local function addInstance(instance, state, allowService, depth)
	if state.idOf[instance] then
		if allowService and state.shallow[instance] then
			state.shallow[instance] = nil
			expandInstance(instance, state, depth)
		end
		return
	end
	if #state.list >= MAX_ITEMS then
		error("Too many instances")
	end
	state.idOf[instance] = #state.list + 1
	state.list[#state.list + 1] = instance

	if isServiceClass(instance.ClassName) and not allowService then
		state.shallow[instance] = true
		return
	end
	expandInstance(instance, state, depth)
end

discoverValue = function(value, state, allowService, depth)
	if depth > MAX_DEPTH then
		error("Maximum discovery depth exceeded")
	end

	local valueType = typeof(value)
	if valueType == "Instance" then
		addInstance(value, state, allowService, depth)
	elseif valueType == "table" then
		local seen = state.seen[value]
		if seen == true or (seen == false and not allowService) then
			return
		end
		if seen == nil then
			state.tableCount += 1
			if state.tableCount > MAX_ITEMS then
				error("Too many tables")
			end
		end
		state.seen[value] = allowService

		local fields = value._serde
		if type(fields) == "table" then
			local selected = {}
			for _, key in ipairs(fields) do
				if key ~= "_serde" and not selected[key] and value[key] ~= nil then
					selected[key] = true
					discoverValue(key, state, allowService, depth + 1)
					discoverValue(value[key], state, allowService, depth + 1)
				end
			end
		else
			for key, entry in pairs(value) do
				discoverValue(key, state, allowService, depth + 1)
				discoverValue(entry, state, allowService, depth + 1)
			end
		end
	elseif valueType == "Content" then
		if value.SourceType == Enum.ContentSourceType.Object then
			discoverValue(value.Object, state, allowService, depth + 1)
		end
	elseif valueType == "Font" then
		discoverValue(value.Family, state, allowService, depth + 1)
	end
end

local function writeAttributes(vec, instance, context, serializeFunction)
	local ok, attributes = pcall(function()
		return instance:GetAttributes()
	end)
	if not ok or type(attributes) ~= "table" then
		writeu32(vec, 0)
		return
	end

	local names = {}
	for name, value in pairs(attributes) do
		if type(name) == "string" and value ~= nil then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	if #names > MAX_ITEMS then
		error("Instance has too many attributes")
	end

	local lengthPosition = vec.length
	writeu32(vec, 0)
	local encodedCount = 0
	for _, name in ipairs(names) do
		local checkpoint = vec.length
		local counter = context.counter.n
		local depth = context.depth
		writeString(vec, name)
		if pcall(serializeFunction, vec, attributes[name], context) then
			encodedCount += 1
		else
			vec.length = checkpoint
			context.counter.n = counter
			context.depth = depth
			for tableValue, id in context.ids do
				if id > counter then
					context.ids[tableValue] = nil
				end
			end
		end
	end
	vec:Write(lengthPosition, 32, encodedCount)
end

local function writeInstanceSection(vec, state, context, serializeFunction)
	writeu32(vec, #state.list)

	for _, instance in ipairs(state.list) do
		writeu32(vec, state.idOf[instance])

		local parent = instance.Parent
		local parentId = parent and state.idOf[parent] or 0
		writeu32(vec, parentId)
		if parentId == 0 then
			writePath(vec, if parent then getInstancePath(parent) else {})
		end

		writeString(vec, instance.ClassName)

		local ownPath = if serviceClasses[instance.ClassName] then {} else getInstancePath(instance)
		writeu8(vec, if #ownPath > 0 then 1 else 0)
		if #ownPath > 0 then
			writePath(vec, ownPath)
		end
	end

	for _, instance in ipairs(state.list) do
		if state.shallow[instance] then
			writeu32(vec, 0)
			writeu32(vec, 0)
			continue
		end

		local names = getProperties(instance.ClassName)
		local lengthPosition = vec.length
		writeu32(vec, 0)
		local encodedCount = 0

		for _, name in ipairs(names) do
			local ok, value = pcall(function()
				return instance[name]
			end)
			if ok then
				local checkpoint = vec.length
				local counter = context.counter.n
				local depth = context.depth
				writeString(vec, name)
				if pcall(serializeFunction, vec, value, context) then
					encodedCount += 1
				else
					vec.length = checkpoint
					context.counter.n = counter
					context.depth = depth
					for tableValue, id in context.ids do
						if id > counter then
							context.ids[tableValue] = nil
						end
					end
				end
			end
		end
		vec:Write(lengthPosition, 32, encodedCount)
		writeAttributes(vec, instance, context, serializeFunction)
	end
end

local function readInstanceSection(vec, pos)
	local count
	count, pos = readu32(vec, pos)
	if count > MAX_ITEMS or count > (vec.length - pos) // (13 * 8) then
		error("Invalid instance count", 2)
	end

	local instances = {}
	local classNames = {}
	local parentOf = {}
	for id = 1, count do
		local encodedId
		encodedId, pos = readu32(vec, pos)
		if encodedId ~= id then
			error("Invalid instance id", 2)
		end

		local parentId
		parentId, pos = readu32(vec, pos)
		if parentId > count then
			error("Invalid instance parent", 2)
		end
		local parentPath = nil
		if parentId == 0 then
			parentPath, pos = readPath(vec, pos)
		end

		local className
		className, pos = readString(vec, pos)
		if className == "" then
			error("Invalid class name", 2)
		end

		local hasOwnPath
		hasOwnPath, pos = readu8(vec, pos)
		if hasOwnPath > 1 then
			error("Invalid instance path flag", 2)
		end
		local ownPath = {}
		if hasOwnPath == 1 then
			ownPath, pos = readPath(vec, pos)
		end

		local instance = resolveInstance(className, ownPath)
		if not instance then
			warn(`Serde could not resolve instance of class "{className}"`)
		end
		instances[id] = instance
		classNames[id] = className
		parentOf[id] = {id = parentId, path = parentPath or {}}
	end

	local parentState = {}
	for id = 1, count do
		local current = id
		while current ~= 0 and parentState[current] == nil do
			parentState[current] = 1
			current = parentOf[current].id
		end
		if current ~= 0 and parentState[current] == 1 then
			error("Cycle in instance parents", 2)
		end
		current = id
		while current ~= 0 and parentState[current] == 1 do
			parentState[current] = 2
			current = parentOf[current].id
		end
	end

	for id = 1, count do
		local instance = instances[id]
		local parent = parentOf[id]
		if instance then
			local target = nil
			if parent.id ~= 0 then
				target = instances[parent.id]
			elseif #parent.path > 0 then
				target = resolvePath(parent.path)
			end
			if target then
				pcall(function()
					instance.Parent = target
				end)
			elseif parent.id ~= 0 or #parent.path > 0 then
				warn(`Serde could not resolve parent of "{instance}"`)
			end
		end
	end

	local context = { ids = {}, instances = instances, instanceCount = count, depth = 0 }
	for id = 1, count do
		local propertyCount
		propertyCount, pos = readu32(vec, pos)
		if propertyCount > MAX_ITEMS or propertyCount > (vec.length - pos) // (5 * 8) then
			error("Invalid property count", 2)
		end

		local instance = instances[id]
		local allowed = propertySetCache[classNames[id]]
		if not allowed then
			getProperties(classNames[id])
			allowed = propertySetCache[classNames[id]] or {}
		end
		for _ = 1, propertyCount do
			local name
			name, pos = readString(vec, pos)
			if pos + 8 > vec.length then
				error("Truncated serialized property", 2)
			end
			local typeByte = vec:Read(pos, 8)
			local value
			value, pos = deserializeValue(vec, pos, context)

			if instance and allowed[name] and (typeByte == Type.NIL or value ~= nil) then
				pcall(function()
					instance[name] = value
				end)
			end
		end

		local attributeCount
		attributeCount, pos = readu32(vec, pos)
		if attributeCount > MAX_ITEMS or attributeCount > (vec.length - pos) // (5 * 8) then
			error("Invalid attribute count", 2)
		end
		for _ = 1, attributeCount do
			local name
			name, pos = readString(vec, pos)
			if pos + 8 > vec.length then
				error("Truncated serialized attribute", 2)
			end
			local typeByte = vec:Read(pos, 8)
			local value
			value, pos = deserializeValue(vec, pos, context)
			if instance and (typeByte == Type.NIL or value ~= nil) then
				pcall(function()
					instance:SetAttribute(name, value)
				end)
			end
		end
	end

	return pos, context
end

--[=[
	Serializes basically everything you can get a reference to from within lua into a custom binary format. Can yield if the passed object contains an Instance as the API has not yet been fetched.
	The function writes only properties that a script can set again, along with attributes. It writes the parent of each Instance from the real tree.

	@param val any -- The value to serialize.
	@param refIds {[any]: number}? -- Optional persistent instance→id map. Every instance discovered is given an id here on first sight, unique across every Serialize call sharing the map.
	@return string -- The encoded binary data.
]=]
function Serde.Serialize(val: any, refIds: { [any]: number }?): string
	local state = { list = {}, idOf = {}, shallow = {}, seen = {}, tableCount = 0 }
	discoverValue(val, state, true, 0)
	if #state.list > MAX_ITEMS then
		error("Too many instances")
	end

	if refIds then
		local nextRefId = 0
		for _, id in pairs(refIds) do
			if type(id) == "number" and id > nextRefId then
				nextRefId = id
			end
		end
		for _, instance in ipairs(state.list) do
			if refIds[instance] == nil then
				if nextRefId >= 0xFFFFFFFF then
					error("Reference id overflow")
				end
				nextRefId += 1
				refIds[instance] = nextRefId
			end
		end
	end

	local vec = Vec.New()
	writeHeader(vec)
	local context = { ids = {}, counter = { n = 0 }, instances = state.idOf, depth = 0 }
	writeInstanceSection(vec, state, context, serializeValue)
	serializeValue(vec, val, context)

	return vec:ToString()
end

--[=[
	Deserializes the custom binary format back into the serialized type. Can yield if the passed object contains an Instance as the API has not yet been fetched.
	Only give this function data that `Serialize` wrote. Bad or changed data stops with an error instead of being silently skipped.

	@param data string -- The binary data to deserialize.
	@return any -- The deserialized value.
]=]
function Serde.Deserialize(data: string): any
	local vec = Vec.FromString(data)
	local pos = readHeader(vec)
	local sectionEnd, context = readInstanceSection(vec, pos)
	local value, finalPos = deserializeValue(vec, sectionEnd, context)
	if finalPos ~= vec.length then
		error("Trailing serialized data", 2)
	end
	return value
end

return Serde
