local debug = require "debug"

local function foo()
    local a = 0
    
    a = a + 1

    a = a + 1
end

local function bar() end

local function sortlines(func)
    local info = debug.getinfo(func, "nSL")
    info.sortedlines = {}
    for k, v in pairs(info.activelines) do
        print(k, v)
        table.insert(info.sortedlines, k)
    end
    
    table.sort(info.sortedlines)
    
    for k, v in ipairs(info.sortedlines) do
        print(k, v)
    end
end

print("foo")
sortlines(foo)
print("bar")
sortlines(bar)
