local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint
pv = ldb.printvarvalue

g = 1

local u = 2
local function foo (n)
    local a = 3
    a = a + 1
    u = u + 1
    g = g + 1
end

local function bar (n)
    n = n + 1
end

local id1 = setbp(foo, 12)
local id2 = setbp(bar, 17)

foo(10)
bar(10)

rmbp(id2)

foo(20)
bar(20)

rmbp(id1)

foo(30)
bar(30)

