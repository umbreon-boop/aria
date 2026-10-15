Aria
====

A library containing various project independent utilities.

Importing
---------

We recommend that you import it using `umbra add aria https://github.com/umbreon-boop/aria`, after which you can use it with:
```lua
local Aria = require("@aria/maid")
```

but you can also fetch it directly from the web:
```lua
local Aria = loadstring(isfile("yourProject/aria.lua") and readfile("yourProject/aria.lua") or (function()
    local s = game:HttpGet("https://github.com/umbreon-boop/aria/releases/latest/download/artifact.lua")
    makefolder("yourProject") writefile("yourProject/aria.lua", s) return s
end)())().Maid
```
