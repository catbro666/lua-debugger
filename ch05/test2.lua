local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local function foo ()
    local a = 1
    for i = 1, 10000000 do
        a = a + 1
    end
end

local function bar ()
end

local id1 = setbp(bar, 13)

foo()
