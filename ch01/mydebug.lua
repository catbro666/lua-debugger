#!/usr/bin/env lua

local debug = require "debug"

-- record breakpoint status
local status = {}
status.bpnum = 0        -- current breakpoint number
status.bpid = 0         -- current breakpoint id
status.bptable = {}     -- table to save breakpoint infos


-- hook
local function linehook (event, line)
    local info = debug.getinfo(2, "nfS")
    for _, v in pairs(status.bptable) do
        if v.func == info.func and v.line == line then
            local prompt = string.format("(%s)%s %s:%d\n", 
                info.namewhat, info.name, info.short_src, line)
            io.write(prompt)
            debug.debug()
        end
    end
end

-- set breakpoint
local function setbreakpoint(func, line)
    if type(func) ~= "function" or type(line) ~= "number" then
        return 0
    end
    status.bpid = status.bpid + 1
    status.bpnum = status.bpnum + 1
    status.bptable[status.bpid] = {func = func, line = line}
    if status.bpnum == 1 then           -- first breakpoint
        debug.sethook(linehook, "l")	-- set hook
    end
    return status.bpid                  --> return breakpoint id
end


-- remove breakpoint
local function removebreakpoint(id)
    if status.bptable[id] == nil then
        return
    end
    status.bptable[id] = nil
    status.bpnum = status.bpnum - 1
    if status.bpnum == 0 then
        debug.sethook()                 -- remove hook
    end
end


return {
    setbreakpoint = setbreakpoint,
    removebreakpoint = removebreakpoint,
}
