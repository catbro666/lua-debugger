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
status.namebpt = {}     -- breakpoint infos table indexed by name
status.srcbpt = {}      -- breakpoint infos table indexed by src name
status.srcfuncmap = {}  -- key: src, val: table(key: func, val: funcinfo)


-- check if this breakpoint in a known function
local function lookforfunc (src, line)
    assert(line)
    local srcfunc = status.srcfuncmap[src]
    if srcfunc then
        for func, info in pairs(srcfunc) do
            if info.what == "main" then
                if line < 0 then
                    return func
                end
            elseif line >= info.linedefined
                and line <= info.lastlinedefined then
                return func
            end
        end
    end
    return nil
end


local function setsrcfunc (info, func)
    local s = status
    local srcfunc = s.srcfuncmap[info.short_src]
    if not srcfunc then
        srcfunc = {}
        s.srcfuncmap[info.short_src] = srcfunc
    end
    if not srcfunc[func] then
        srcfunc[func] = info
    end
end


local function getfuncinfo (func)
    local s = status
    local info = s.funcinfos[func]
    if not info then
        info = debug.getinfo(func, "SL")
        if (info.activelines) then
            info.sortedlines = {}
            for k, _ in pairs(info.activelines) do
               table.insert(info.sortedlines, k)
            end
            table.sort(info.sortedlines)
            -- treat mainchunk specially so that `verifyfuncline` can work normally
            if info.what == "main" then
                info.linedefined = 1
                info.lastlinedefined = info.sortedlines[#info.sortedlines]
            end
        end
        s.funcinfos[func] = info
    end
    return info
end


local function verifyfuncline (info, line)
    if not line then
        return info.sortedlines[1]
    end
    if line < 0 then
        if info.what ~= "main" then
            return nil
        end
        line = -line
    end
    if line < info.linedefined or line > info.lastlinedefined then
        return nil
    end
    for _, v in ipairs(info.sortedlines) do
        if v >= line then
            return v
        end
    end
    assert(false)   -- impossible to reach here
end


local function modsrcbp(src, func, oline, nline)
    local s = status
    local srcbp = s.srcbpt[src]
    local id = srcbp[oline]

    -- remove srcbpt
    srcbp.num = srcbp.num - 1
    srcbp[oline] = nil
    if srcbp.num == 0 then
        srcbp = nil
    end

    -- set funcbpt
    local funcbp = s.funcbpt[func]
    -- check if the same breakpoint is already set
    if funcbp and funcbp[nline] then
        s.bptable[id] = nil             -- remove the breakpoint
        s.bpnum = s.bpnum - 1
        assert(s.bpnum > 0)
        return funcbp[nline]
    end

    if not funcbp then                  -- first breakpoint of this func
        s.funcbpt[func] = {}
        funcbp = s.funcbpt[func]
        funcbp.num = 0
    end
    funcbp.num = funcbp.num + 1
    funcbp[nline] = id

    -- update bptable
    s.bptable[id].func = func
    s.bptable[id].line = nline

    return id
end


local function solvesrcbp (info, func)
    local s = status
    local srcbp = s.srcbpt[info.short_src]
    if srcbp then
        for k, v in pairs(srcbp) do
            if k ~= "num" then
                line = verifyfuncline(info, k)
                if line then
                    modsrcbp(info.short_src, func, k, line)
                end
            end
        end
    end
end


-- hook
local function hook (event, line)
    local s = status
    if event == "call" or event == "tail call" then
        local stackinfo = debug.getinfo(2, "nf")
        local func = stackinfo.func
        local name = stackinfo.name
        local funcinfo = getfuncinfo(func)
        local hasbreak = false
        -- check unsolved srcbp
        solvesrcbp(funcinfo, func)

        if funcinfo.what ~= "C" then
            setsrcfunc(funcinfo, func)
        end

        if s.funcbpt[func] then
            local id = s.funcbpt[func]
            if s.bptable[id] and not s.bptable[id].src then
                s.bptable[id].src = funcinfo.short_src
            end
            hasbreak = true
        end
        if not hasbreak and s.namebpt[name] then
            local min = funcinfo.linedefined
            local max = funcinfo.lastlinedefined
            for k, _ in pairs(s.namebpt[name]) do
                if type(k) == "number" and ((k >= min and k <= max) or k == 0) then
                    hasbreak = true
                    break
                end
            end
        end
        if event == "call" then     -- for tail call, just overwrite
            s.stackdepth = s.stackdepth + 1
        end
        s.stackinfos[s.stackdepth] =
            {stackinfo = stackinfo, funcinfo = funcinfo, hasbreak = hasbreak}
        -- found breakpoint in current function
        if hasbreak then
            debug.sethook(hook, "crl")	-- add "line" event
        else        -- no breakpoints found
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
        local sinfo = s.stackinfos[s.stackdepth].stackinfo
        local finfo = s.stackinfos[s.stackdepth].funcinfo
        local func = sinfo.func
        local name = sinfo.name
        local funcbp = s.funcbpt[func]
        local namebp = s.namebpt[name]
        if (funcbp and funcbp[line]) or (namebp and namebp[line])
            or (namebp and namebp[0] and line == finfo.sortedlines[1]) then
            local prompt = string.format("%s (%s)%s %s:%d\n",
                finfo.what, sinfo.namewhat, name, finfo.short_src, line)
            io.write(prompt)
            debug.debug()
        end
    end
end


local function setfuncbp(func, line)
    local s = status
    -- get func info
    local info = getfuncinfo(func)
    if not info then
        io.write("unable to get func info\n")
        return nil
    end

    -- verify the line
    line = verifyfuncline(info, line)
    if not line then
        io.write("invalid line\n")
        return nil
    end

    local funcbp = s.funcbpt[func]
    -- check if the same breakpoint is already set
    if funcbp and funcbp[line] then
        return funcbp[line]
    end

    s.bpid = s.bpid + 1
    s.bpnum = s.bpnum + 1
    s.bptable[s.bpid] = {func = func, line = line}

    if not funcbp then                  -- first breakpoint of this func
        s.funcbpt[func] = {}
        funcbp = s.funcbpt[func]
        funcbp.num = 0
    end
    funcbp.num = funcbp.num + 1
    funcbp[line] = s.bpid

    if s.bpnum == 1 then                -- first global breakpoint
        debug.sethook(hook, "c")        -- set hook for "call" event
    end
    return s.bpid                       --> return breakpoint id
end


local function setnamebp(name, line)
    local s = status
    local namebp = s.namebpt[name]
    if not line then                    -- if not specified
        line = 0                        -- use '0' to denote 1st activeline
    end
    -- check if the same breakpoint is already set
    if namebp and namebp[line] then
        return namebp[line]
    end

    s.bpid = s.bpid + 1
    s.bpnum = s.bpnum + 1
    s.bptable[s.bpid] = {name = name, line = line}

    if not namebp then                  -- first breakpoint of this name
        s.namebpt[name] = {}
        namebp = s.namebpt[name]
        namebp.num = 0
    end
    namebp.num = namebp.num + 1
    namebp[line] = s.bpid

    if s.bpnum == 1 then                -- first global breakpoint
        debug.sethook(hook, "c")        -- set hook for "call" event
    end
    return s.bpid                       --> return breakpoint id
end


local function setsrcbp(src, line)
    local s = status

    -- check if this breakpoint is located in a known function
    local func = lookforfunc(src, line)
    if func then
        return setfuncbp(func, line)
    end

    local srcbp = s.srcbpt[src]
    -- check if this breakpoint is already set
    if srcbp and srcbp[line] then
        return srcbp[line]
    end

    s.bpid = s.bpid + 1
    s.bpnum = s.bpnum + 1
    s.bptable[s.bpid] = {src = src, line = line}

    if not srcbp then                  -- first breakpoint of this src
        s.srcbpt[src] = {}
        srcbp = s.srcbpt[src]
        srcbp.num = 0
    end
    srcbp.num = srcbp.num + 1
    srcbp[line] = s.bpid

    if s.bpnum == 1 then                -- first global breakpoint
        debug.sethook(hook, "c")        -- set hook for "call" event
    end
    return s.bpid                       --> return breakpoint id
end


-- set breakpoint
local function setbreakpoint(where, line)
    if (type(where) ~= "function" and type(where) ~= "string")
        or ( line and type(line) ~= "number") then
        io.write("invalid parameter\n")
        return nil
    end

    if type(where) == "function" then
        return setfuncbp(where, line)
    else            -- "string"
        local i = string.find(where, ":")
        if i then   -- package name
            local packname = string.sub(where, 1, i-1)
            local line = string.sub(where, i+1)
            if packname == "" then
                io.write("no package name specified!\n")
                return nil
            end
            if line ~= "" then
                line = tonumber(line)
                if not line then
                    io.write("no valid line number specified!\n")
                    return nil
                end
            else
                line = -1
            end
            local path, err = package.searchpath(packname, package.path)
            if not path then
                io.write(err)
                return nil
            end
            return setsrcbp(path, line)
        else
            local i = string.find(where, "@")
            if i then   -- function name
                local funcname = string.sub(where, 1, i-1)
                local line = string.sub(where, i+1)
                if funcname == "" then
                    io.write("no function name specified!\n")
                    return nil
                end
                if line ~= "" then
                    line = tonumber(line)
                    if not line then
                        io.write("no valid line number specified!\n")
                        return nil
                    end
                else
                    line = nil
                end
                return setnamebp(funcname, line)
            end
        end
    end
end


-- remove breakpoint
local function removebreakpoint(id)
    local s = status
    if s.bptable[id] == nil then
        return
    end
    local func = s.bptable[id].func
    local name = s.bptable[id].name
    local src = s.bptable[id].src
    local line = s.bptable[id].line
    local dstbp = nil
    if func then
        dstbp = s.funcbpt[func]
    elseif src then
        dstbp = s.srcbpt[src]
    else
        dstbp = s.namebpt[name]
    end
    if dstbp and dstbp[line] then
        dstbp.num = dstbp.num - 1
        dstbp[line] = nil
        if dstbp.num == 0 then
            dstbp = nil
        end
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
