#!/usr/bin/env lua

local debug = require "debug"

-- record breakpoint status
local status = {}
status.bpnum = 0        -- current breakpoint number
status.bpid = 0         -- current breakpoint id
status.bptable = {}     -- table for saving breakpoint infos
status.stackinfos = {}  -- table for saving stack infos
status.stackdepth = 0   -- the depth of stack
status.funcinfos = {}   -- table for caching func infos

-- hook
local function hook (event, line)
    local s = status
    if event == "call" or event == "tail call" then
        local func = debug.getinfo(2, "f").func
        for _, v in pairs(s.bptable) do
            -- found breakpoint in current function
            if v.func == func then
                if event == "call" then
                    s.stackdepth = s.stackdepth + 1
                end
                s.stackinfos[s.stackdepth] =
                    {func = func, hasbreak = true}
                debug.sethook(hook, "crl")	-- add "line" event
                return
            end
        end
        -- no breakpoints found
        if event == "call" then
            s.stackdepth = s.stackdepth + 1
        end
        s.stackinfos[s.stackdepth] = {func = func, hasbreak = false}
        debug.sethook(hook, "cr")   -- remove "line" event temporarily
    elseif event == "return" or event == "tail return" then
        s.stackinfos[s.stackdepth] = nil
        s.stackdepth = s.stackdepth - 1
        -- if the previous function has breakpoints
        if s.stackdepth > 0 and s.stackinfos[s.stackdepth].hasbreak then
            debug.sethook(hook, "crl")  -- restore "line" event
        else
            debug.sethook(hook, "cr")   -- remove "line" event
        end
    elseif event == "line" then
        for _, v in pairs(s.bptable) do
            if v.func == s.stackinfos[s.stackdepth].func
                and v.line == line then
                if not s.funcinfos[v.func] then
                    s.funcinfos[v.func] = debug.getinfo(2, "nS")
                end
                local info = s.funcinfos[v.func]
                local prompt = string.format("%s (%s)%s %s:%d\n",
                    info.what, info.namewhat, info.name, info.short_src, line)
                io.write(prompt)
                debug.debug()
            end
        end
    end
end


-- set breakpoint
local function setbreakpoint(func, line)
    local s = status
    if type(func) ~= "function" or type(line) ~= "number" then
        return nil
    end
    s.bpid = s.bpid + 1
    s.bpnum = s.bpnum + 1
    s.bptable[s.bpid] = {func = func, line = line}
    if s.bpnum == 1 then                -- first breakpoint
        debug.sethook(hook, "c")        -- set hook for "call" event
    end
    return s.bpid                       --> return breakpoint id
end


-- remove breakpoint
local function removebreakpoint(id)
    local s = status
    if s.bptable[id] == nil then
        return
    end
    s.bptable[id] = nil
    s.bpnum = s.bpnum - 1
    if s.bpnum == 0 then
        debug.sethook()                 -- remove hook
    end
end


-- get variable value from local, upvalue or _ENV
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
local function printvarvalue (name, level)
    -- 1 by default
    -- plus 4 to include printvarvalue, debug mainchunk, debug.debug, hook
    level = (level or 1) + 4
    local where, value = _getvarvalue(name, level)
    if value then
        print(where, value)
    else
        print(name, "not found")
    end
end


-- set variable value to local, upvalue or _ENV
local function _setvarvalue (name, value, level)
    local index

    -- + 1 to correct the level to include _setvarvalue itself,
    level = (level or 1) + 1
    -- try local vars
    for i = 1, math.huge do
        local n, v = debug.getlocal(level, i)
        if not n then break end
        if n == name then
            index = i
            -- we didn't break here in order to get the local var with max index
        end
    end
    if index then
        debug.setlocal(level, index, value)
        return "local"
    end

    -- try upvalues
    local func = debug.getinfo(level, "f").func
    for i = 1, math.huge do
        local n, v = debug.getupvalue(func, i)
        if not n then break end
        if n == name then
            debug.setupvalue(func, i, value)
            return "upvalue"
        end
    end

    -- try to get from _ENV
    local _, env = _getvarvalue("_ENV", level, true)
    if env and env[name] then
        env[name] = value
        return "global"
    else
        return nil
    end
end


-- wrap _setvarvalue, to print value
local function setvarvalue (name, value, level)
    -- 1 by default
    -- plus 4 to include setvarvalue, debug mainchunk, debug.debug, hook
    level = (level or 1) + 4
    local where = _setvarvalue(name, value, level)
    if where then
        print(where, name)
    else
        print(name, "not found")
    end
end


-- print a traceback of call stack
local function printtraceback(level)
    -- 1 by default
    -- plus 4 to include printtraceback, debug mainchunk, debug.debug, hook
    level = (level or 1) + 4
    print(debug.traceback(nil, level))
end


return {
    setbreakpoint = setbreakpoint,
    removebreakpoint = removebreakpoint,
    printvarvalue = printvarvalue,
    printtraceback = printtraceback,
    setvarvalue = setvarvalue,
}
