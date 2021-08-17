local ldb = require "luadebug"
local setbp = ldb.setbreakpoint

local function foo()
    local a = 0

    a = a + 1

    a = a + 1
end

local id1 = setbp(foo)
assert(id1 == 1)
local id2 = setbp(foo, 4)
assert(id2 == id1)
local id3 = setbp(foo, 5)
assert(id3 == id1)
local id4 = setbp(foo, 6)
assert(id4 == 2)
local id5 = setbp(foo, 7)
assert(id5 == id4)
local id6 = setbp(foo, 8)
assert(id6 == 3)
local id7 = setbp(foo, 100)
assert(not id7)

foo()
