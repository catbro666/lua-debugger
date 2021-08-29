local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local function foo()
    local a = 0
end

local id1 = setbp(foo)

local id2 = setbp("srcfuncmap.lua:5")

foo()   -- break once

rmbp(id1)

foo()   -- not break

local id3 = setbp("srcfuncmap.lua:7")
assert(id3 == 3)
local id4 = setbp(foo, 7)
assert(id3 == id4)

foo()   -- break once

rmbp(id3)

foo()   -- not break
