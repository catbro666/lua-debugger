local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint
pv = ldb.printvarvalue
sv = ldb.setvarvalue
ptb = ldb.printtraceback

g = 1

local u = 2
local function foo (n)
    local a = 3
    u = u
    g = g
end

local id1 = setbp(foo, 14)

foo(10)

rmbp(id1)

