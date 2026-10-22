--[=[
	A library containing various project independent utilities.

	@class Aria
	@prop Cache     [Module](Cache.md)
	@prop Deque     [Module](Deque.md)
	@prop Event     [Module](Event.md)
	@prop Interface [Module](Interface.md)
	@prop Maid      [Module](Maid.md)
	@prop Serde     [Module](Serde.md)
	@prop Vec       [Module](Vec.md)
]=]
local Aria = {
	Cache = require("./cache"),
	Deque = require("./deque"),
	Event = require("./event"),
	Interface = require("./interface"),
	Maid = require("./maid"),
	Serde = require("./serde"),
	Vec = require("./vec")
}

return Aria
