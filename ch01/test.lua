local mydebug = require "mydebug"
local setbp = mydebug.setbreakpoint
local rmbp = mydebug.removebreakpoint

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

local id1 = setbp(foo, 11)
local id2 = setbp(bar, 16)

foo(10)
bar(10)

rmbp(id1)

foo(20)
bar(20)

rmbp(id2)

foo(30)
bar(30)

