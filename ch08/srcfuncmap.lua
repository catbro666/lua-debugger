local ldb = require "luadebug"
local lib = require "testlib"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local id1 = setbp(lib.foo)

local id2 = setbp("testlib:1")  -- foo 2

lib.foo()   -- break once

rmbp(id1)

lib.foo()   -- not break

local id3 = setbp("testlib:3")  -- foo 3
assert(id3 == 3)
local id4 = setbp(lib.foo, 3)
assert(id3 == id4)

lib.foo()   -- break once

rmbp(id3)

lib.foo()   -- not break
