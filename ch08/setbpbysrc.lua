local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local function foo()
    local a = 0
end

local function bar()
    local a = 0
end

local id1 = setbp("foo")
local id2 = setbp("foo", 7)

local id3 = setbp("setbpbysrc.lua:9")
local id4 = setbp("setbpbysrc.lua:11")
local id5 = setbp("setbpbysrc.lua:100") -- invalid line
local id6 = setbp("setbpbysrc.lua:")
assert(not id6)
local id7 = setbp(":5")
assert(not id7)
local id8 = setbp("setbpbysrc.lua:aa")
assert(not id8)

foo()
bar()

rmbp(id1)
rmbp(id3)

foo()
bar()

rmbp(id2)
rmbp(id4)

foo()
bar()
