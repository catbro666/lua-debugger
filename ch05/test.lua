local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint
pv = ldb.printvarvalue
sv = ldb.setvarvalue
ptb = ldb.printtraceback

local function foo ()
    local a = 1
end

local function bar ()
    local b = 1
end

local id1 = setbp(foo, 9)
assert(id1 == 1)
local id1 = setbp(foo, 9)
assert(id1 == 1)
local id2 = setbp(foo, 10)

local id3 = setbp(bar, 13)
local id4 = setbp(bar, 14)

foo()
bar()

rmbp(id1)
rmbp(id2)
rmbp(id3)
rmbp(id4)
