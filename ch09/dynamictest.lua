require("luadebug").init()
local lib = require "testlib"

local g = 1
local function faa ()
    g = 2
end

faa()
lib.foo()
lib.bar()
faa()
