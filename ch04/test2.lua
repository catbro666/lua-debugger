local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint
pv = ldb.printvarvalue
sv = ldb.setvarvalue
ptb = ldb.printtraceback

local function foo(n)
    if n == 0 then
        return 0
    end
    return foo(n-1)
end

local function bar()
end

-- add a break in bar
local id1 = setbp(bar, 16)

foo(100000000000)

rmbp(id1)
