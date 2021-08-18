#!/usr/bin/env lua

local debug = require "debug"

-- record breakpoint associated status
local status = {}
status.bpnum = 0        -- current breakpoint number
status.bpid = 0         -- current breakpoint id
status.bptable = {}     -- breakpoint infos table indexed by id
status.stackinfos = {}  -- table for saving stack infos
status.stackdepth = 0   -- the depth of stack
status.funcinfos = {}   -- table for caching func infos
status.funcbpt = {}     -- breakpoint infos table indexed by func

-- hook
local function hook (event, line)
    local s = status
    if event == "call" or event == "tail call" then
        local func = debug.getinfo(2, "f").func
        if event == "call" then     -- for tail call, just overwrite
            s.stackdepth = s.stackdepth + 1
        end
        -- found breakpoint in current function
        if s.funcbpt[func] then
            s.stackinfos[s.stackdepth] = {func = func, hasbreak = true}
            debug.sethook(hook, "crl")	-- add "line" event
        else        -- no breakpoints found
            s.stackinfos[s.stackdepth] = {func = func, hasbreak = false}
            debug.sethook(hook, "cr")   -- remove "line" event temporarily
        end
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
        local curfunc = s.stackinfos[s.stackdepth].func
        local funcbp = s.funcbpt[curfunc]
        assert(funcbp)
        if funcbp[line] then
            if not s.funcinfos[curfunc] then
                s.funcinfos[curfunc] = debug.getinfo(2, "nS")
            end
            local info = s.funcinfos[curfunc]
            local prompt = string.format("%s (%s)%s %s:%d\n",
                info.what, info.namewhat, info.name, info.short_src, line)
            io.write(prompt)
            debug.debug()
        end
    end
end


-- set breakpoint
local function setbreakpoint(func, line)
    local s = status
    if type(func) ~= "function" or type(line) ~= "number" then
        return nil
    end
    -- already set this breakpoint
    if s.funcbpt[func] and s.funcbpt[func][line] then
        return s.funcbpt[func][line]
    end
    s.bpid = s.bpid + 1
    s.bpnum = s.bpnum + 1
    s.bptable[s.bpid] = {func = func, line = line}
    if s.funcbpt[func] then             -- already has breaks
        s.funcbpt[func].num = s.funcbpt[func].num + 1
        s.funcbpt[func][line] = s.bpid
    else                                -- first breakpoint of this func
        s.funcbpt[func] = {}
        s.funcbpt[func].num = 1
        s.funcbpt[func][line] = s.bpid
    end
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
    local func = s.bptable[id].func
    local line = s.bptable[id].line
    s.funcbpt[func].num = s.funcbpt[func].num - 1
    s.funcbpt[func][line] = nil
    if s.funcbpt[func].num == 0 then
        s.funcbpt[func] = nil
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
