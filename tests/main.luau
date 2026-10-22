local roblox = require("@lune/roblox")
task = require("@lune/task")

local function property(name: string, valueType: string, options: { [string]: any }?)
	options = options or {}
	return {
		MemberType = "Property",
		Name = name,
		ValueType = { Name = valueType },
		Serialization = {
			CanSave = options.canSave ~= false,
			CanLoad = options.canLoad ~= false,
		},
		Security = options.security or { Read = "None", Write = "None" },
		Tags = options.tags or {},
	}
end

local function class(name: string, superclass: string?, tags: { string }?, members: { any }?)
	return {
		Name = name,
		Superclass = superclass,
		Tags = tags or {},
		Members = members or {},
	}
end

local dump = {
	Classes = {
		class("Instance", nil, nil, {
			property("Name", "string"),
			property("Archivable", "bool"),
		}),
		class("BasePart", "Instance", nil, {
			property("Anchored", "bool"),
			property("CanCollide", "bool"),
			property("Color", "Color3"),
			property("CFrame", "CFrame"),
			property("Material", "Enum"),
			property("Size", "Vector3", { canSave = false }),
			property("Transparency", "number"),
		}),
		class("Part", "BasePart"),
		class("Model", "Instance", nil, {
			property("PrimaryPart", "Instance"),
		}),
		class("Folder", "Instance"),
		class("ObjectValue", "Instance", nil, {
			property("Value", "Instance"),
		}),
		class("StringValue", "Instance", nil, {
			property("Value", "string"),
		}),
		class("NumberValue", "Instance", nil, {
			property("Value", "number"),
		}),
		class("BoolValue", "Instance", nil, {
			property("Value", "bool"),
		}),
		class("TextLabel", "Instance", nil, {
			property("Text", "string"),
			property("TextColor3", "Color3"),
			property("BackgroundColor3", "Color3"),
			property("FontFace", "Font"),
			property("TextSize", "number"),
		}),
		class("Camera", "Instance", nil, {
			property("CFrame", "CFrame"),
		}),
		class("Attachment", "Instance", nil, {
			property("CFrame", "CFrame"),
		}),
		class("Workspace", "Instance", { "Service" }, {
			property("CurrentCamera", "Instance"),
		}),
		class("Players", "Instance", { "Service" }),
		class("RunService", "Instance", { "Service" }),
		class("HttpService", "Instance", { "Service" }),
		class("EncodingService", "Instance", { "Service" }),
		class("Terrain", "BasePart", { "NotCreatable" }),
		class("Player", "Instance", { "NotCreatable" }),
	},
}

local encoding = {}
function encoding:CompressBuffer(input: buffer): buffer
	local output = buffer.create(buffer.len(input))
	buffer.copy(output, 0, input, 0, buffer.len(input))
	return output
end
function encoding:GetDecompressedBufferSize(input: buffer): number
	return buffer.len(input)
end
function encoding:DecompressBuffer(input: buffer): buffer
	local output = buffer.create(buffer.len(input))
	buffer.copy(output, 0, input, 0, buffer.len(input))
	return output
end

local workspace = roblox.Instance.new("Workspace")
local players = roblox.Instance.new("Players")
local runService = roblox.Instance.new("RunService")
local services: { [string]: any } = {
	Workspace = workspace,
	Players = players,
	RunService = runService,
	EncodingService = encoding,
	HttpService = {
		JSONDecode = function(_, value: string)
			assert(value == "dump", "unexpected JSON payload")
			return dump
		end,
	},
}

game = {
	HttpGet = function(_, url: string)
		if string.find(url, "versionQTStudio", 1, true) then
			return "test-version"
		end
		if string.find(url, "API-Dump", 1, true) then
			return "dump"
		end
		error("unexpected URL: " .. url)
	end,
	GetService = function(_, name: string)
		local service = services[name]
		if not service then
			error("unknown service: " .. name)
		end
		return service
	end,
	FindFirstChild = function(_, name: string)
		return services[name]
	end,
}

Instance = roblox.Instance
Vector3 = roblox.Vector3
Vector2 = roblox.Vector2
CFrame = roblox.CFrame
Color3 = roblox.Color3
UDim = roblox.UDim
UDim2 = roblox.UDim2
Rect = roblox.Rect
BrickColor = roblox.BrickColor
Font = roblox.Font
Content = roblox.Content
ColorSequence = roblox.ColorSequence
ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
NumberSequence = roblox.NumberSequence
NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
NumberRange = roblox.NumberRange
Ray = roblox.Ray
Region3 = roblox.Region3
Region3int16 = roblox.Region3int16
Vector3int16 = roblox.Vector3int16
Vector2int16 = roblox.Vector2int16
PhysicalProperties = roblox.PhysicalProperties
Faces = roblox.Faces
Axes = roblox.Axes
Enum = roblox.Enum

local Serde = require("../src/serde")
local Vec = require("../src/vec")
local Deque = require("../src/deque")
local Event = require("../src/event")
local Interface = require("../src/interface")
local Maid = require("../src/maid")

local function round(value: any): any
	return Serde.Deserialize(Serde.Serialize(value))
end

local function equal(actual: any, expected: any, message: string?)
	assert(actual == expected, message or `expected {expected}, got {actual}`)
end

local function close(actual: number, expected: number, message: string?)
	assert(math.abs(actual - expected) < 1e-6, message or `expected {expected}, got {actual}`)
end

equal(round(nil), nil)
equal(round(true), true)
equal(round(false), false)
equal(round(0), 0)
equal(round(1.5), 1.5)
equal(round(math.huge), math.huge)
equal(round(-math.huge), -math.huge)
equal(round("hello"), "hello")
equal(round(""), "")
equal(round("a\0b"), "a\0b")

local nested = { a = 1, b = "x", c = { true, false, 3 } }
local nestedCopy = round(nested)
equal(nestedCopy.a, 1)
equal(nestedCopy.b, "x")
equal(nestedCopy.c[1], true)
equal(nestedCopy.c[3], 3)

local cycle = {}
cycle.self = cycle
local cycleCopy = round(cycle)
assert(cycleCopy.self == cycleCopy, "table cycle was not restored")

local whitelisted = { keep = 1, drop = 2, _serde = { "keep" } }
local whitelistedCopy = round(whitelisted)
equal(whitelistedCopy.keep, 1)
equal(whitelistedCopy.drop, nil)
equal(whitelistedCopy._serde, nil)

local typed = { [1] = "one", [true] = "yes", [2.5] = "half" }
local typedCopy = round(typed)
equal(typedCopy[1], "one")
equal(typedCopy[true], "yes")
equal(typedCopy[2.5], "half")

local vector = round(Vector3.new(1, 2, 3))
close(vector.X, 1)
close(vector.Y, 2)
close(vector.Z, 3)

local vector2 = round(Vector2.new(1, 2))
close(vector2.X, 1)
close(vector2.Y, 2)

local cframe = CFrame.new(1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1)
local cframeCopy = round(cframe)
local components = { cframe:GetComponents() }
local copyComponents = { cframeCopy:GetComponents() }
for index = 1, 12 do
	close(copyComponents[index], components[index], `CFrame component {index}`)
end

local color = round(Color3.new(0.25, 0.5, 0.75))
close(color.R, 0.25)
close(color.G, 0.5)
close(color.B, 0.75)

local udim = round(UDim.new(1, 2))
close(udim.Scale, 1)
close(udim.Offset, 2)

local udim2 = round(UDim2.new(1, 2, 3, 4))
close(udim2.X.Scale, 1)
close(udim2.X.Offset, 2)
close(udim2.Y.Scale, 3)
close(udim2.Y.Offset, 4)

local rect = round(Rect.new(1, 2, 3, 4))
close(rect.Min.X, 1)
close(rect.Min.Y, 2)
close(rect.Max.X, 3)
close(rect.Max.Y, 4)

local enumItem = round(Enum.Material.Plastic)
equal(enumItem, Enum.Material.Plastic)

local brickColor = round(BrickColor.new(21))
equal(brickColor.Number, 21)

local content = round(Content.fromUri("rbxasset://test"))
equal(content.SourceType, Enum.ContentSourceType.Uri)
equal(content.Uri, "rbxasset://test")
equal(round(Content.none).SourceType, Enum.ContentSourceType.None)

local font = Font.new("rbxasset://fonts/families/Arial.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
local fontCopy = round(font)
equal(fontCopy.Family, font.Family)
equal(fontCopy.Weight, Enum.FontWeight.Bold)
equal(fontCopy.Style, Enum.FontStyle.Italic)

local colorSequence = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.new(0, 0, 1)),
})
local colorSequenceCopy = round(colorSequence)
equal(#colorSequenceCopy.Keypoints, 2)
close(colorSequenceCopy.Keypoints[1].Time, 0)
close(colorSequenceCopy.Keypoints[2].Value.B, 1)

local numberSequence = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1, 0),
	NumberSequenceKeypoint.new(1, 2, 0.5),
})
local numberSequenceCopy = round(numberSequence)
equal(#numberSequenceCopy.Keypoints, 2)
close(numberSequenceCopy.Keypoints[1].Value, 1)
close(numberSequenceCopy.Keypoints[2].Envelope, 0.5)

local numberRange = round(NumberRange.new(1, 2))
close(numberRange.Min, 1)
close(numberRange.Max, 2)

local ray = round(Ray.new(Vector3.new(1, 2, 3), Vector3.new(0, 1, 0)))
close(ray.Origin.X, 1)
close(ray.Origin.Z, 3)
close(ray.Direction.Y, 1)

local region = round(Region3.new(Vector3.new(1, 2, 3), Vector3.new(4, 5, 6)))
close(region.CFrame.Position.X, 2.5)
close(region.Size.Z, 3)

local region16 = round(Region3int16.new(Vector3int16.new(1, 2, 3), Vector3int16.new(4, 5, 6)))
equal(region16.Min.X, 1)
equal(region16.Max.Z, 6)

local vector3int16 = round(Vector3int16.new(1, -2, 3))
equal(vector3int16.X, 1)
equal(vector3int16.Y, -2)
equal(vector3int16.Z, 3)

local vector2int16 = round(Vector2int16.new(-1, 2))
equal(vector2int16.X, -1)
equal(vector2int16.Y, 2)

local physical = round(PhysicalProperties.new(1, 0.5, 0.25, 2, 3))
close(physical.Density, 1)
close(physical.FrictionWeight, 2)
close(physical.ElasticityWeight, 3)

local bufferValue = buffer.create(3)
buffer.writeu8(bufferValue, 0, 1)
buffer.writeu8(bufferValue, 1, 2)
buffer.writeu8(bufferValue, 2, 3)
local bufferCopy = round(bufferValue)
equal(buffer.len(bufferCopy), 3)
equal(buffer.readu8(bufferCopy, 0), 1)
equal(buffer.readu8(bufferCopy, 1), 2)
equal(buffer.readu8(bufferCopy, 2), 3)

local faces = round(Faces.new(Enum.NormalId.Top, Enum.NormalId.Left))
equal(faces.Top, true)
equal(faces.Left, true)
equal(faces.Bottom, false)
equal(faces.Right, false)

local axes = round(Axes.new(Enum.Axis.X, Enum.Axis.Z))
equal(axes.X, true)
equal(axes.Z, true)
equal(axes.Y, false)
equal(axes.Right, axes.X)
equal(axes.Front, axes.Z)
equal(axes.Top, axes.Y)

local part = Instance.new("Part")
part.Name = "AriaPart"
part.Anchored = true
part.Size = Vector3.new(1, 2, 3)
part.CFrame = CFrame.new(1, 2, 3)
part.Color = Color3.new(0.25, 0.5, 0.75)
part.Material = Enum.Material.Plastic
part.Transparency = 0.25
part:SetAttribute("Health", 100)
part:SetAttribute("Tint", Color3.new(1, 0, 0))
part.Parent = workspace

local partCopy = round(part)
equal(partCopy.ClassName, "Part")
equal(partCopy.Name, "AriaPart")
equal(partCopy.Anchored, true)
equal(partCopy.Parent, workspace)
close(partCopy.Size.Y, 2)
close(partCopy.CFrame.Position.Z, 3)
close(partCopy.Color.G, 0.5)
equal(partCopy.Material, Enum.Material.Plastic)
close(partCopy.Transparency, 0.25)
equal(partCopy:GetAttribute("Health"), 100)
equal(partCopy:GetAttribute("Tint"), Color3.new(1, 0, 0))
partCopy:Destroy()

local model = Instance.new("Model")
model.Name = "AriaModel"
model.Parent = workspace
local child = Instance.new("Part")
child.Name = "Child"
child.Parent = model
model.PrimaryPart = child
local reference = Instance.new("ObjectValue")
reference.Name = "Reference"
reference.Value = child
reference.Parent = model

local modelCopy = round(model)
equal(modelCopy.Parent, workspace)
local childCopy = modelCopy:FindFirstChild("Child")
local referenceCopy = modelCopy:FindFirstChild("Reference")
assert(childCopy and referenceCopy, "model children were not restored")
equal(referenceCopy.Value, childCopy)
equal(modelCopy.PrimaryPart, childCopy)
modelCopy:Destroy()

local label = Instance.new("TextLabel")
label.Name = "AriaLabel"
label.Text = "hello"
label.TextColor3 = Color3.new(0.1, 0.2, 0.3)
label.TextSize = 18
label.FontFace = Font.new("rbxasset://fonts/families/Arial.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
label.Parent = workspace
local labelCopy = round(label)
equal(labelCopy.Parent, workspace)
equal(labelCopy.Text, "hello")
close(labelCopy.TextColor3.G, 0.2)
equal(labelCopy.TextSize, 18)
equal(labelCopy.FontFace.Weight, Enum.FontWeight.Bold)
equal(labelCopy.FontFace.Style, Enum.FontStyle.Italic)
labelCopy:Destroy()

local serviceCopy = round({ workspace = workspace })
equal(serviceCopy.workspace, workspace)

local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
local terrainCopy = round({ terrain = terrain })
equal(terrainCopy.terrain, terrain)
terrain:Destroy()

local instanceKeyed = { [child] = "child" }
local instanceKeyedCopy = round(instanceKeyed)
local key = next(instanceKeyedCopy)
equal(key.ClassName, "Part")
equal(instanceKeyedCopy[key], "child")

local refIds = {}
Serde.Serialize({ child }, refIds)
assert(refIds[child] ~= nil)
local firstRef = refIds[child]
Serde.Serialize({ child }, refIds)
equal(refIds[child], firstRef)

child:Destroy()
model:Destroy()
part:Destroy()

assert(not pcall(Serde.Deserialize, "not aria"))
local serialized = Serde.Serialize({ 1, 2, 3 })
assert(not pcall(Serde.Deserialize, string.sub(serialized, 1, #serialized - 1)))
assert(not pcall(Serde.Deserialize, serialized .. "\0"))
assert(not pcall(Serde.Serialize, function() end))
assert(not pcall(Serde.Serialize, { bad = function() end }))

local vectorValue = Vec.New()
vectorValue:Append(4, 0b1010)
vectorValue:Append(8, 0x5A)
local compressed = vectorValue:Compress()
local decompressed = Vec.Decompress(compressed)
equal(decompressed.length, vectorValue.length)
equal(decompressed:ToString(), vectorValue:ToString())
local decompressedBuffer = Vec.Decompress(compressed.inner)
equal(decompressedBuffer:ToString(), vectorValue:ToString())
local decompressedMethod = compressed:Decompress()
equal(decompressedMethod.length, vectorValue.length)
assert(not pcall(Vec.Decompress, compressed, 1))

local deque = Deque.New()
assert(not pcall(Deque.Push, deque, nil))
assert(not pcall(Deque.PushFront, deque, nil))
Deque.Push(deque, 1)
Deque.PushFront(deque, 0)
equal(Deque.Len(deque), 2)
equal(Deque.Pop(deque), 0)
equal(Deque.PopBack(deque), 1)

local sourceBuffer = buffer.create(2)
buffer.writeu8(sourceBuffer, 0, 1)
buffer.writeu8(sourceBuffer, 1, 2)
local fromBuffer = Vec.FromBuffer(sourceBuffer)
buffer.writeu8(sourceBuffer, 0, 9)
equal(fromBuffer:Read(0, 8), 1)

local emitter = Event.New()
local calls = 0
local function callback()
	calls += 1
end
local first = emitter:Connect("run", callback)
local second = emitter:Connect("run", callback)
second:Disconnect()
emitter:Fire("run")
equal(calls, 1)
first:Disconnect()
emitter:Fire("run")
equal(calls, 1)
assert(Event.new, "Event.new alias is missing")

local storage = { value = 1 }
local interface = Interface.New({ value = function() end }, storage)
storage.value = 2
equal(interface.value, 1)

local cleaned = false
local maid = Maid.New()
maid:Task({
	Disconnect = function()
		error("expected failure")
	end,
})
maid:Task(function()
	cleaned = true
end)
maid:DeferredClean(10)
task.wait(0.1)
equal(cleaned, true)
assert(Maid.new, "Maid.new alias is missing")
assert(Maid.LinkCleanup, "Maid.LinkCleanup alias is missing")

local removedCalls = 0
local removable = function()
	removedCalls += 1
end
local removeMaid = Maid.New()
equal(removeMaid:Task(removable), removable)
equal(removeMaid:Remove(removable), true)
equal(removedCalls, 1)
equal(removeMaid:Remove(removable), false)

local releasedCalls = 0
local releasable = function()
	releasedCalls += 1
end
local releaseMaid = Maid.New()
releaseMaid:Task(releasable)
equal(releaseMaid:Release(releasable), true)
equal(releasedCalls, 0)
equal(releaseMaid:Release(releasable), false)

local duplicateCalls = 0
local duplicate = function()
	duplicateCalls += 1
end
local duplicateMaid = Maid.New()
duplicateMaid:Task(duplicate)
duplicateMaid:Task(duplicate)
duplicateMaid:Clean()
equal(duplicateCalls, 1)
duplicateMaid:Clean()
equal(duplicateCalls, 1)

print("all tests passed")
