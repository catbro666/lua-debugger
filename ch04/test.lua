local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint
pv = ldb.printvarvalue
sv = ldb.setvarvalue
ptb = ldb.printtraceback

local function f3()
end

local function f2()
    f3()
end

local function f1()
    f2()
end

-- add break in f3
local id1 = setbp(f3, 9)
-- didn't add break in f2

-- add breaks in f1 before and after calling f2
local id2 = setbp(f1, 16)
local id3 = setbp(f1, 17)

f1()

rmbp(id1)
rmbp(id2)
rmbp(id3)
