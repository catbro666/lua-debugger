local ldb = require "luadebug"
local lib = require "testlib"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local id1 = setbp("foo@")           -- foo 2
local id2 = setbp("foo@3")          -- foo 3

local id3 = setbp("testlib:5")      -- bar 6
local id4 = setbp("testlib:7")      -- bar 7
local id5 = setbp("testlib:100")    -- invalid line
local id6 = setbp(":5")
assert(not id6)
local id7 = setbp("testlib:aa")
assert(not id7)

lib.foo(1)              -- break twice
lib.bar(1)              -- break twice

rmbp(id1)
rmbp(id3)

lib.foo(2)              -- break once
lib.bar(2)              -- break once

rmbp(id2)
rmbp(id4)

lib.foo(3)              -- not break
lib.bar(3)              -- not break
