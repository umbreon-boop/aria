--[=[
	A library containing various project independent utilities.

	@class Aria
	@prop Deque     [Module](Deque.md)
	@prop Event     [Module](Event.md)
	@prop Interface [Module](Interface.md)
	@prop Maid      [Module](Maid.md)
	@prop Path      [Module](Path.md)
	@prop Serde     [Module](Serde.md)
	@prop Vec       [Module](Vec.md)
]=]
local Aria = {
	Deque = require("./deque"),
	Event = require("./event"),
	Interface = require("./interface"),
	Maid = require("./maid"),
	Path = require("./path"),
	Serde = require("./serde"),
	Vec = require("./vec")
}

return Aria
