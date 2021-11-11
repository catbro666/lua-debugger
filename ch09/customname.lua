d = 1
require("luadebug").init({"bb", "dd", "pp", "ss", "tt", "ii", "hh"})
local lib = require "testlib"

g = 1
local function faa ()
    local a = 1
end

faa()
lib.foo()
lib.bar()
faa()
