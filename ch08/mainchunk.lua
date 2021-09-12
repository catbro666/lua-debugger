local ldb = require "luadebug"
local setbp = ldb.setbreakpoint
local rmbp = ldb.removebreakpoint

local id1 = setbp("testlib:")       -- main 3
local id2 = setbp("testlib:-5")     -- main 7
local id3 = setbp("testlib:-9")     -- main 9
local id4 = setbp("testlib:-13")    -- main 13

local lib = require "testlib"       -- break 4 times

local id5 = setbp("testlib:2")      -- foo 2
local id6 = setbp("testlib:3")      -- foo 3

lib.foo()   -- break 2 times

rmbp(id5)

lib.foo()   -- break 1 time

rmbp(id6)

lib.foo()   -- not break
