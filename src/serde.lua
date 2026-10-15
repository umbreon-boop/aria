--[=[
	Serialization and deserialization of primitives, tables, and Roblox instances.
	Custom types should not rely on this for restoration but rather use a constructor to rebuild the instance based upon the deserialized data. They may also chose which fields to serialize by listing their names in a `self._serde` array.

	@class Serde
]=]
local Vec = require("./vec")

local Serde = {}
local Type = { NIL = 0, BOOL = 1, NUMBER = 2, STRING = 3, TABLE = 4, REF = 5, INSTANCE = 6, DATATYPE = 7 }

--@inline
local function writef32(vec, value)
	local byteOffset = vec.length // 8
	vec:_ensure(byteOffset + 4)
	buffer.writef32(vec.inner, byteOffset, value)
	vec:_use((byteOffset + 4) * 8)
end

--@inline
local function readf32(vec, pos)
	local byteOffset = pos // 8
	return buffer.readf32(vec.inner, byteOffset), pos + 32
end

--@inline
local function writef64(vec, value)
	local byteOffset = vec.length // 8
	vec:_ensure(byteOffset + 8)
	buffer.writef64(vec.inner, byteOffset, value)
	vec:_use((byteOffset + 8) * 8)
end

--@inline
local function readf64(vec, pos)
	local byteOffset = pos // 8
	return buffer.readf64(vec.inner, byteOffset), pos + 64
end

--@inline
local function packedCodec(n, extract, construct)
	return {
		encode = function(vec, val)
			local values = table.pack(extract(val))
			for i = 1, n do
				writef32(vec, values[i])
			end
		end,
		decode = function(vec, pos)
			local values = table.create(n)
			for i = 1, n do
				values[i], pos = readf32(vec, pos)
			end
			return construct(table.unpack(values, 1, n))
		end,
	}
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

-- values are written as unsigned 32-bit numbers, so negative values come back as large numbers
local function toSigned(value)
	return if value >= 0x80000000 then value - 0x100000000 else value
end

datatypes.EnumItem = {
	encode = function(vec, val)
		local text = tostring(val.EnumType)
		vec:Append(32, #text)
		vec:AppendString(text)
		vec:Append(32, val.Value)
	end,
	decode = function(vec, pos)
		local nameLength = vec:Read(pos, 32)
		pos += 32
		local name = vec:ReadString(pos // 8, nameLength)
		pos += nameLength * 8
		local value = toSigned(vec:Read(pos, 32))
		pos += 32
		for _, item in ipairs((Enum :: any)[name]:GetEnumItems()) do
			if item.Value == value then
				return item, pos
			end
		end
		return nil, pos
	end,
}

datatypes.BrickColor = {
	encode = function(vec, val)
		vec:Append(32, val.Number)
	end,
	decode = function(vec, pos)
		return BrickColor.new(vec:Read(pos, 32)), pos + 32
	end,
}

datatypes.Font = {
	encode = function(vec, val)
		vec:Append(32, #val.Family)
		vec:AppendString(val.Family)
		vec:Append(32, val.Weight.Value)
		vec:Append(32, val.Style.Value)
	end,
	decode = function(vec, pos)
		local familyLength = vec:Read(pos, 32)
		pos += 32
		local family = vec:ReadString(pos // 8, familyLength)
		pos += familyLength * 8
		local weightValue = toSigned(vec:Read(pos, 32))
		pos += 32
		local styleValue = toSigned(vec:Read(pos, 32))
		pos += 32

		local weight, style
		for _, item in ipairs((Enum :: any).FontWeight:GetEnumItems()) do
			if item.Value == weightValue then
				weight = item
				break
			end
		end
		for _, item in ipairs((Enum :: any).FontStyle:GetEnumItems()) do
			if item.Value == styleValue then
				style = item
				break
			end
		end
		return Font.new(family, weight, style), pos
	end,
}

datatypes.ColorSequence = {
	encode = function(vec, val)
		vec:Append(32, #val.Keypoints)
		for _, keypoint in ipairs(val.Keypoints) do
			writef32(vec, keypoint.Time)
			writef32(vec, keypoint.Value.R)
			writef32(vec, keypoint.Value.G)
			writef32(vec, keypoint.Value.B)
		end
	end,
	decode = function(vec, pos)
		local count = vec:Read(pos, 32)
		pos += 32
		local keypoints = {}
		for i = 1, count do
			local time, r, g, b
			time, pos = readf32(vec, pos)
			r, pos = readf32(vec, pos)
			g, pos = readf32(vec, pos)
			b, pos = readf32(vec, pos)
			keypoints[i] = ColorSequenceKeypoint.new(time, Color3.new(r, g, b))
		end
		return ColorSequence.new(keypoints), pos
	end,
}

datatypes.NumberSequence = {
	encode = function(vec, val)
		vec:Append(32, #val.Keypoints)
		for _, keypoint in ipairs(val.Keypoints) do
			writef32(vec, keypoint.Time)
			writef32(vec, keypoint.Value)
			writef32(vec, keypoint.Envelope)
		end
	end,
	decode = function(vec, pos)
		local count = vec:Read(pos, 32)
		pos += 32
		local keypoints = {}
		for i = 1, count do
			local time, value, envelope
			time, pos = readf32(vec, pos)
			value, pos = readf32(vec, pos)
			envelope, pos = readf32(vec, pos)
			keypoints[i] = NumberSequenceKeypoint.new(time, value, envelope)
		end
		return NumberSequence.new(keypoints), pos
	end,
}

datatypes.Content = {
	encode = function(vec, val)
		local text = val.SourceType == Enum.ContentSourceType.Uri and val.Uri or ""
		vec:Append(32, #text)
		vec:AppendString(text)
	end,
	decode = function(vec, pos)
		local length = vec:Read(pos, 32)
		pos += 32
		local uri = vec:ReadString(pos // 8, length)
		pos += length * 8
		return uri ~= "" and Content.fromUri(uri) or Content.none, pos
	end,
}

local serializers = {}
local deserializers = {}

local function serializeValue(vec, val, context)
	local valueType = typeof(val)
	local serializeFunction = serializers[valueType]
	if serializeFunction then
		serializeFunction(vec, val, context, serializeValue)
		return
	end

	local codec = datatypes[valueType]
	if not codec then
		error("Unsupported type: " .. valueType)
	end

	vec:Append(8, Type.DATATYPE)
	vec:Append(32, #valueType)
	vec:AppendString(valueType)

	local lengthPosition = vec.length
	vec:Append(32, 0)
	local payloadStart = vec.length
	codec.encode(vec, val)
	vec:Write(lengthPosition, 32, (vec.length - payloadStart) // 8)
end

local function deserializeValue(vec, pos, context)
	local typeByte = vec:Read(pos, 8)
	pos += 8

	if typeByte == Type.DATATYPE then
		local nameLength = vec:Read(pos, 32)
		pos += 32
		local name = vec:ReadString(pos // 8, nameLength)
		pos += nameLength * 8

		local payloadLength = vec:Read(pos, 32)
		pos += 32

		local codec = datatypes[name]
		if not codec then
			return nil, pos + payloadLength * 8
		end
		return codec.decode(vec, pos), pos + payloadLength * 8
	end

	local deserializeFunction = deserializers[typeByte]
	if not deserializeFunction then
		error("Unknown type marker: " .. typeByte)
	end

	return deserializeFunction(vec, pos, context, deserializeValue)
end

serializers["nil"] = function(vec)
	vec:Append(8, Type.NIL)
end

serializers["boolean"] = function(vec, val)
	vec:Append(8, Type.BOOL)
	vec:Append(8, val and 1 or 0)
end

serializers["number"] = function(vec, val)
	vec:Append(8, Type.NUMBER)
	writef64(vec, val)
end

serializers["string"] = function(vec, val)
	vec:Append(8, Type.STRING)
	vec:Append(32, #val)
	vec:AppendString(val)
end

serializers["Instance"] = function(vec, val, context)
	vec:Append(8, Type.INSTANCE)
	vec:Append(32, (context.instances and context.instances[val]) or 0)
end

serializers["table"] = function(vec, val, context, recursiveFunction)
	if context.ids[val] then
		vec:Append(8, Type.REF)
		vec:Append(32, context.ids[val])
		return
	end

	context.counter.n += 1
	local id = context.counter.n
	context.ids[val] = id

	vec:Append(8, Type.TABLE)
	vec:Append(32, id)

	local fields = val._serde
	if type(fields) == "table" then
		local count = 0
		for _, key in ipairs(fields) do
			if val[key] ~= nil then
				count += 1
			end
		end
		vec:Append(32, count)

		for _, key in ipairs(fields) do
			local value = val[key]
			if value ~= nil then
				recursiveFunction(vec, key, context)
				recursiveFunction(vec, value, context)
			end
		end
	else
		local count = 0
		for _ in pairs(val) do
			count += 1
		end
		vec:Append(32, count)

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
	local booleanByte = vec:Read(pos, 8)
	return booleanByte ~= 0, pos + 8
end

deserializers[Type.NUMBER] = function(vec, pos)
	return readf64(vec, pos)
end

deserializers[Type.STRING] = function(vec, pos)
	local length = vec:Read(pos, 32)
	pos += 32
	return vec:ReadString(pos // 8, length), pos + length * 8
end

deserializers[Type.INSTANCE] = function(vec, pos, context)
	local id = vec:Read(pos, 32)
	return context.instances and context.instances[id], pos + 32
end

deserializers[Type.REF] = function(vec, pos, context)
	local id = vec:Read(pos, 32)
	return context.ids[id], pos + 32
end

deserializers[Type.TABLE] = function(vec, pos, context, recursiveFunction)
	local id = vec:Read(pos, 32)
	pos += 32

	local outputTable = {}
	context.ids[id] = outputTable

	local count = vec:Read(pos, 32)
	pos += 32

	for _ = 1, count do
		local key, value
		key, pos = recursiveFunction(vec, pos, context)
		value, pos = recursiveFunction(vec, pos, context)
		outputTable[key] = value
	end

	return outputTable, pos
end

local dump = nil
local propertyCache = {}
local serviceClasses = {}
local classesByName = {}

local function fetch(url)
	-- executors add HttpGet to the DataModel, Studio and servers only have HttpService.
	-- Only the lookup is protected, so a failed request shows its own error.
	local ok, httpGet = pcall(function()
		return (game :: any).HttpGet
	end)
	if ok and httpGet then
		return httpGet(game, url)
	end
	return game:GetService("HttpService"):GetAsync(url)
end

local function getProperties(className)
	if not dump then
		local HttpService = game:GetService("HttpService")
		local version = fetch("https://setup.roblox.com/versionQTStudio")
		dump = HttpService:JSONDecode(fetch(string.format("https://setup.roblox.com/%s-API-Dump.json", version)))
		for _, class in ipairs(dump.Classes) do
			classesByName[class.Name] = class
			if class.Tags and table.find(class.Tags, "Service") then
				serviceClasses[class.Name] = true
			end
		end
	end

	if propertyCache[className] then
		return propertyCache[className]
	end

	local names = {}
	local seen = {}

	local current = classesByName[className]
	while current do
		for _, member in ipairs(current.Members) do
			if member.MemberType == "Property" and member.Name ~= "Parent" then
				local canSave = true
				if member.Tags then
					for _, tag in ipairs(member.Tags) do
						if tag == "Deprecated" or tag == "Hidden" or tag == "NotScriptable" or tag == "ReadOnly" then
							canSave = false
							break
						end
					end
				end
				if canSave and member.Serialization and member.Serialization.CanSave == false then
					canSave = false
				end
				if canSave and member.Security then
					if type(member.Security) == "string" then
						canSave = member.Security == "None"
					else
						canSave = member.Security.Write == "None"
					end
				end
				if canSave and not seen[member.Name] then
					seen[member.Name] = true
					names[#names + 1] = member.Name
				end
			end
		end
		current = current.Superclass and classesByName[current.Superclass] or nil
	end

	propertyCache[className] = names
	return names
end

local function resolveInstance(className)
	if not dump then
		getProperties(className)
	end
	if serviceClasses[className] then
		return game:GetService(className)
	end
	return Instance.new(className)
end

local function collectInstances(root, list, idOf)
	if idOf[root] then
		return
	end
	idOf[root] = #list + 1
	list[#list + 1] = root
	for _, child in ipairs(root:GetChildren()) do
		collectInstances(child, list, idOf)
	end
end

-- Ref identity across serializations (§8 of Debugger.md): a caller may pass
-- a persistent map to `Serialize`, and every instance discovered gets an id
-- in it — first time only — from a counter that never resets. The encoded
-- data keeps its own dense `#list + 1` ids (the readers key the property
-- section by position), so these global ids never touch the wire; they only
-- let a ref taken from one serialization name the same instance in another.
local nextRefId = 0

local function discoverInstances(val, list, idOf, seen)
	local valueType = typeof(val)
	if valueType == "Instance" then
		collectInstances(val, list, idOf)
	elseif valueType == "table" then
		if seen[val] then
			return
		end
		seen[val] = true
		for k, v in pairs(val) do
			discoverInstances(k, list, idOf, seen)
			discoverInstances(v, list, idOf, seen)
		end
	end
end

local function writeInstanceSection(vec, list, idOf, context, serializeFn)
	vec:Append(32, #list)
	for _, inst in ipairs(list) do
		vec:Append(32, idOf[inst])
		vec:Append(32, inst.Parent and idOf[inst.Parent] or 0)
		vec:Append(32, #inst.ClassName)
		vec:AppendString(inst.ClassName)
	end

	for _, inst in ipairs(list) do
		local names = getProperties(inst.ClassName)
		local lengthPosition = vec.length
		vec:Append(32, 0)
		local encodedCount = 0

		for _, name in ipairs(names) do
			local ok, val = pcall(function()
				return inst[name]
			end)
			if ok then
				local checkpoint = vec.length
				local counter = context.counter.n
				vec:Append(32, #name)
				vec:AppendString(name)
				if pcall(serializeFn, vec, val, context) then
					encodedCount += 1
				else
					-- remove the table ids of the failed write, otherwise later refs point to missing tables
					vec.length = checkpoint
					context.counter.n = counter
					for tbl, id in context.ids do
						if id > counter then
							context.ids[tbl] = nil
						end
					end
				end
			end
		end
		vec:Write(lengthPosition, 32, encodedCount)
	end
end

local function readInstanceSection(vec, pos, deserializeFn)
	local count = vec:Read(pos, 32)
	pos += 32

	local instances, parentOf = {}, {}
	for _ = 1, count do
		local id = vec:Read(pos, 32)
		pos += 32
		local parentId = vec:Read(pos, 32)
		pos += 32

		local nameLength = vec:Read(pos, 32)
		pos += 32
		local className = vec:ReadString(pos // 8, nameLength)
		pos += nameLength * 8

		local ok, inst = pcall(resolveInstance, className)
		instances[id] = ok and inst or nil
		parentOf[id] = parentId
	end

	for id, parentId in pairs(parentOf) do
		local inst = instances[id]
		if inst and parentId ~= 0 and instances[parentId] then
			inst.Parent = instances[parentId]
		end
	end

	local context = { ids = {}, instances = instances }
	for i = 1, count do
		local propertyCount = vec:Read(pos, 32)
		pos += 32
		local inst = instances[i]

		for _ = 1, propertyCount do
			local nameLength = vec:Read(pos, 32)
			pos += 32
			local name = vec:ReadString(pos // 8, nameLength)
			pos += nameLength * 8

			local val
			val, pos = deserializeFn(vec, pos, context)

			if inst and val ~= nil then
				pcall(function()
					inst[name] = val
				end)
			end
		end
	end

	return pos, context
end

--[=[
	Serializes basically everything you can get a reference to from within lua into a custom binary format. Can yield if the passed object contains an Instance as the API has not yet been fetched.
	The function writes only properties that a script can set again. It writes the parent of each Instance from the real tree.

	@param val any -- The value to serialize.
	@param refIds {[any]: number}? -- Optional persistent instance→id map. Every instance discovered is given an id here on first sight, unique across every Serialize call sharing the map — a ref taken from this map names one instance for the life of the map, no matter which two serializations are compared. The encoding itself is unchanged.
	@return string -- The encoded binary data.
]=]
function Serde.Serialize(val: any, refIds: { [any]: number }?): string
	local list, idOf = {}, {}
	discoverInstances(val, list, idOf, {})

	if refIds then
		for _, inst in ipairs(list) do
			if refIds[inst] == nil then
				nextRefId += 1
				refIds[inst] = nextRefId
			end
		end
	end

	local vec = Vec.New()
	local context = { ids = {}, counter = { n = 0 }, instances = idOf }
	writeInstanceSection(vec, list, idOf, context, serializeValue)
	serializeValue(vec, val, context)

	return vec:ToString()
end

--[=[
	Deserializes the custom binary format back into the serialized type. Can yield if the passed object contains an Instance as the API has not yet been fetched.
	Only give this function data that `Serialize` wrote. Bad or changed data can make it stop with an error, for example when a parent assignment is not possible.
	Services are not created again. The function gets them with `GetService` and changes the properties and children of the real service.

	@param data string -- The binary data to deserialize.
	@return any -- The deserialized value.
]=]
function Serde.Deserialize(data: string): any
	local vec = Vec.FromString(data)
	local pos, context = readInstanceSection(vec, 0, deserializeValue)
	return (deserializeValue(vec, pos, context))
end

return Serde
