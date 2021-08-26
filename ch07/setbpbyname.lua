local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local function foo()
    local a = 0
end

local function bar()
    local a = 0
end

local function pee()
    local a = 0
end

local id1 = setbp(foo)
local id2 = setbp(foo, 7)

local id3 = setbp("bar")
local id4 = setbp("bar", 11)
local id5 = setbp("bar", 100)

local id6 = setbp(pee)
local id7 = setbp("pee", 15)

foo()
bar()
pee()

rmbp(id1)
rmbp(id3)
rmbp(id6)

foo()
bar()
pee()

rmbp(id2)
rmbp(id4)
rmbp(id7)

foo()
bar()
pee()
