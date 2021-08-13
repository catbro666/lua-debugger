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
        return nil
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


-- get variable from local, upvalue or _ENV
-- modified from "Programming in Lua Fourth edition"
local function _getvarvalue (name, level, isenv)
    local value
    local found = false

    -- + 1 to correct the level to include _getvarvalue itself,
    level = (level or 1) + 1
    -- try local vars
    for i = 1, math.huge do
        local n, v = debug.getlocal(level, i)
        if not n then break end
        if n == name then
            value = v
            found = true
            -- we didn't break here in order to get the local var with max index
        end
    end
    if found then return "local", value end

    -- try upvalues
    local func = debug.getinfo(level, "f").func
    for i = 1, math.huge do
        local n, v = debug.getupvalue(func, i)
        if not n then break end
        if n == name then return "upvalue", v end
    end

    if isenv then return "noenv" end	-- avoid dead loop

    -- try to get from _ENV
    local _, env = _getvarvalue("_ENV", level, true)
    if env then
        return "global", env[name]
    else
        return "noenv"
    end
end

-- wrap _getvarvalue, to print value
local function getvarvalue (name, level)
    -- default by 1
    -- plus 4 to include getvarvalue, debug mainchunk, debug.debug, hook
    level = (level or 1) + 4
    local where, value = _getvarvalue(name, level)
    if value then
        print(where, value)
    else
        print(name, "not found")
    end
end

return {
    setbreakpoint = setbreakpoint,
    removebreakpoint = removebreakpoint,
    getvarvalue = getvarvalue,
}
