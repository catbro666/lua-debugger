local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local function foo()
end

setbp(foo, 6)

local bar = foo

foo()

bar()
