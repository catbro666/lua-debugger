#!/usr/bin/env lua

local debug = require "debug"

local version = "0.0.1"
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

local debug_mode = false
local hascustomnames = false


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
    else
        if info.what == "main" then
            return nil
        end
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


local updatehookevent


-- hook
local function hook (event, line)
    local s = status
    if event == "call" or event == "tail call" then
        -- level 2: hook, target func
        local sinfo = debug.getinfo(2, "nf")
        local finfo = updatehookevent(sinfo)
        if event == "call" then     -- for tail call, just overwrite
            s.stackdepth = s.stackdepth + 1
        end
        if debug_mode then
            local prompt = string.format("call %s (%s)%s %s depth %d\n",
                finfo.what, sinfo.namewhat, sinfo.name, finfo.short_src,
                s.stackdepth)
            io.write(prompt)
        end
        s.stackinfos[s.stackdepth] =
            {stackinfo = sinfo, funcinfo = finfo}
    elseif event == "return" or event == "tail return" then
--        local sinfo = debug.getinfo(2, "nf")
--        local finfo = updatehookevent(sinfo)
        if s.stackdepth > 0 then
            if debug_mode then
                local sinfo = s.stackinfos[s.stackdepth].stackinfo
                local finfo = s.stackinfos[s.stackdepth].funcinfo
                local prompt = string.format("return %s (%s)%s %s depth %d\n",
                    finfo.what, sinfo.namewhat, sinfo.name, finfo.short_src,
                    s.stackdepth)
                io.write(prompt)
            end
            s.stackinfos[s.stackdepth] = nil
            s.stackdepth = s.stackdepth - 1
        end
        if s.bpnum == 0 then
            if debug_mode then
                print("remove hook")
            end
            debug.sethook()
            s.stackinfos = {}
            s.stackdepth = 0
        end
        if s.stackdepth > 0 then
            updatehookevent(s.stackinfos[s.stackdepth].stackinfo)
        end
    elseif event == "line" then
        if debug_mode then
            print("line", line, " depth", s.stackdepth)
        end
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


-- check if there are breakpoints in the function 'func'
-- if so, add line event; otherwise, remove line event
function updatehookevent(stackinfo)
    local s = status
    local func = stackinfo.func
    local name = stackinfo.name
    local funcinfo = getfuncinfo(func)
    local hasbreak = false
    -- check unsolved srcbp
    solvesrcbp(funcinfo, func)

    if funcinfo.what ~= "C" then
        if funcinfo.what == "main" then
            funcinfo.refname = "main"
        else
            funcinfo.refname = name
        end
        setsrcfunc(funcinfo, func)
    end

    if s.funcbpt[func] then
--         local id = s.funcbpt[func]
--         if s.bptable[id] and not s.bptable[id].src then
--             s.bptable[id].src = funcinfo.short_src
--         end
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

    -- found breakpoint in current function
    if hasbreak then
        if debug_mode then
            print("add line event")
        end
        debug.sethook(hook, "crl")	-- add "line" event
    else        -- no breakpoints found
        if debug_mode then
            print("remove line event")
        end
        debug.sethook(hook, "cr")   -- remove "line" event
    end

    return funcinfo
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
    s.bptable[s.bpid] = {func = func, line = line, src = info.short_src}

    if not funcbp then                  -- first breakpoint of this func
        s.funcbpt[func] = {}
        funcbp = s.funcbpt[func]
        funcbp.num = 0
    end
    funcbp.num = funcbp.num + 1
    funcbp[line] = s.bpid

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

    return s.bpid                       --> return breakpoint id
end


-- set breakpoint
local function setbreakpoint(where, line)
    local id
    if (type(where) ~= "function" and type(where) ~= "string")
        or ( line and type(line) ~= "number") then
        io.write("invalid parameter\n")
        return nil
    end

    if type(where) == "function" then
        local info = getfuncinfo(where)
        if not info then
            io.write("invalid function\n")
            return nil
        end
        if info.what == "main" then
            info.refname = "main"
            if not line or line == 0 then
                line = -1
            elseif line > 0 then
                line = -line
            end
        end
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
            local path, err
            if packname == "." then     -- current package
                -- level 5: setbreakpoint, debug mainchunk, debug.debug,
                --          hook or init, target func
                local func = debug.getinfo(5, "f").func
                path = getfuncinfo(func).short_src
            else
                path, err = package.searchpath(packname, package.path)
                if not path then
                    io.write(err)
                    return nil
                end
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
                if funcname == "." then     -- current function
                    -- level 5: setbreakpoint, debug mainchunk, debug.debug,
                    --          hook or init, target func
                    local func = debug.getinfo(5, "f").func
                    local info = getfuncinfo(func)
                    if not info then
                        io.write("invalid function\n")
                        return nil
                    end
                    if info.what == "main" then
                        info.refname = "main"
                        if not line or line == 0 then
                            line = -1
                        elseif line > 0 then
                            line = -line
                        end
                    end
                    return setfuncbp(func, line)
                else
                    return setnamebp(funcname, line)
                end
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


-- print breakpoint info
local function printbreakinfo()
    local s = status
    for i=1,s.bpid do
        local bp = s.bptable[i]
        local prompt
        if bp then
            if bp.name then
                prompt = string.format("id: %d, name: %s, line: %d\n",
                    i, bp.name, bp.line)
            else
                local refname
                if bp.func then
                    refname = getfuncinfo(bp.func).refname
                end
                prompt = string.format("id: %d, src: %s, line: %d, refname: %s\n",
                    i, bp.src, bp.line, refname)
            end
            io.write(prompt)
        end
    end
end


local longnames = {
    "setbreakpoint",
    "removebreakpoint",
    "printvarvalue",
    "setvarvalue",
    "printtraceback",
    "printbreakinfo",
    "help",
}

local shortnames = {
    "b",
    "d",
    "p",
    "s",
    "bt",
    "i",
    "h",
}

local customnames

local function help(verbose)
    if hascustomnames then
        io.write(customnames[1] .. ":       set breakpoint\n")
        io.write(customnames[2] .. ":       remove breakpoint\n")
        io.write(customnames[3] .. ":       print var value\n")
        io.write(customnames[4] .. ":       set var value\n")
        io.write(customnames[5] .. ":       print traceback\n")
        io.write(customnames[6] .. ":       print breakpoint info\n")
        io.write(customnames[7] .. ":       help info\n")
        if verbose then
            io.write("\nExamples: \n")
            io.write("  " .. customnames[1] .. "(\"foo@\")          set bp at the first active line of function \"foo\"\n")
            io.write("  " .. customnames[1] .. "(\"foo@4\")         set bp at line 4 of function \"foo\"\n")
            io.write("  " .. customnames[1] .. "(\".@4\")           set bp at line 4 of current function\n")
            io.write("  " .. customnames[1] .. "(\".@\")            set bp at the first active line of current function\n")
            io.write("  " .. customnames[1] .. "(\"mylib:2\")       set bp at line 3 of package \"mylib\"\n")
            io.write("  " .. customnames[1] .. "(\"mylib:4\")       set bp at line 4 of package \"mylib\"\n")
            io.write("  " .. customnames[1] .. "(\"mylib:-2\")      set bp at line 4 within mainchunk\n")
            io.write("  " .. customnames[1] .. "(\"mylib:\")        set bp at first activeline of mainchunk\n")
            io.write("  " .. customnames[1] .. "(\".:4\")           set bp at line 4 of current package\n")
            io.write("  " .. customnames[2] .. "(1)               remove the breakpoint with id 1\n")
            io.write("  " .. customnames[3] .. "(\"a\")             print var \"a\", searching from stack level 1\n")
            io.write("  " .. customnames[3] .. "(\"a\", 2)          print var \"a\", searching from stack level 2\n")
            io.write("  " .. customnames[4] .. "(\"a\", 8)          set the value of var \"a\" to 8, searching from stack level 1\n")
            io.write("  " .. customnames[4] .. "(\"a\", 8, 2)       set the value of var \"a\" to 8, searching from stack level 2\n")
            io.write("  " .. customnames[5] .. "()                print a traceback of call stack, from stack level 1\n")
            io.write("  " .. customnames[5] .. "(2)               print a traceback of call stack, from stack level 2\n")
            io.write("  " .. customnames[6] .. "()                print the information of all the breakpoints\n")
            io.write("  " .. customnames[7] .. "(1)               show verbose help info\n")
        end
    else
        io.write("setbreakpoint/b:          set breakpoint\n")
        io.write("removebreakpoint/d:       remove breakpoint\n")
        io.write("printvarvalue/p:          print var value\n")
        io.write("setvarvalue/s:            set var value\n")
        io.write("printtraceback/bt:        print traceback\n")
        io.write("printbreakinfo/i:         print breakpoint info\n")
        io.write("help/h:                   help info\n")
        if verbose then
            io.write("\nExamples: \n")
            io.write("  setbreakpoint(\"foo@\")         set bp at the first active line of function \"foo\"\n")
            io.write("  setbreakpoint(\"foo@4\")        set bp at line 4 of function \"foo\"\n")
            io.write("  setbreakpoint(\".@4\")          set bp at line 4 of current function\n")
            io.write("  setbreakpoint(\".@\")           set bp at the first active line of current function\n")
            io.write("  setbreakpoint(\"mylib:2\")      set bp at line 3 of package \"mylib\"\n")
            io.write("  setbreakpoint(\"mylib:4\")      set bp at line 4 of package \"mylib\"\n")
            io.write("  setbreakpoint(\"mylib:-2\")     set bp at line 4 within mainchunk\n")
            io.write("  setbreakpoint(\"mylib:\")       set bp at first activeline of mainchunk\n")
            io.write("  setbreakpoint(\".:4\")          set bp at line 4 of current package\n")
            io.write("  removebreakpoint(1)           remove the breakpoint with id 1\n")
            io.write("  printvarvalue(\"a\")            print var \"a\", searching from stack level 1\n")
            io.write("  printvarvalue(\"a\", 2)         print var \"a\", searching from stack level 2\n")
            io.write("  setvarvalue(\"a\", 8)           set the value of var \"a\" to 8, searching from stack level 1\n")
            io.write("  setvarvalue(\"a\", 8, 2)        set the value of var \"a\" to 8, searching from stack level 2\n")
            io.write("  printtraceback()              print a traceback of call stack, from stack level 1\n")
            io.write("  printtraceback(2)             print a traceback of call stack, from stack level 2\n")
            io.write("  printbreakinfo()              print the information of all the breakpoints\n")
            io.write("  help(1)                       show verbose help info\n")
        end
    end
end


local function hasdupname(names)
    for _, v in ipairs(names) do
        if _G[v] then
            print("table `_G` already has element called \"" .. v .. "\" please specify custom names as the following example:")
            print("require(\"luadebug\").init({\"bb\", \"dd\", \"pp\", \"ss\", \"tt\", \"ii\", \"hh\"})\n")
            return true
        end
    end
    return false
end


local function init(name_table, is_debug)
    local s = status
    if not _G.luadebug_inited then
        if name_table and type(name_table) == "table" then
            if hasdupname(name_table) then
                return
            end
            _G[name_table[1]] = setbreakpoint
            _G[name_table[2]] = removebreakpoint
            _G[name_table[3]] = printvarvalue
            _G[name_table[4]] = setvarvalue
            _G[name_table[5]] = printtraceback
            _G[name_table[6]] = printbreakinfo
            _G[name_table[7]] = help
            hascustomnames = true
            customnames = name_table
        else
            if hasdupname(longnames) then
                return
            end
            if hasdupname(shortnames) then
                return
            end
            _G.setbreakpoint = setbreakpoint
            _G.removebreakpoint = removebreakpoint
            _G.printvarvalue = printvarvalue
            _G.setvarvalue = setvarvalue
            _G.printtraceback = printtraceback
            _G.printbreakinfo = printbreakinfo
            _G.help = help
            -- short names
            _G.b = setbreakpoint
            _G.d = removebreakpoint
            _G.p = printvarvalue
            _G.bt = printtraceback
            _G.s = setvarvalue
            _G.i = printbreakinfo
            _G.h = help
        end
        if is_debug then
            debug_mode = true
        end
        _G.luadebug_inited = true
    end

    io.write(string.format("luadebug %s start ...\n", version))
    if hascustomnames then
        io.write("input '" .. customnames[7] .. "()' for help info or '"
            .. customnames[7] .. "(1)' for verbose info\n")
    else
        io.write("input 'help()' for help info or 'help(1)' for verbose info\n")
    end

    local sinfo = debug.getinfo(2, "nfl")
    local func = sinfo.func
    local name = sinfo.name
    local finfo = getfuncinfo(func)
    local prompt = string.format("%s (%s)%s %s:%d\n",
        finfo.what, sinfo.namewhat, name, finfo.short_src, sinfo.currentline)
    io.write(prompt)
    debug.debug()

    if s.bpnum > 0 then
        if s.stackdepth == 0 then       -- set hook
            local max_depth = 2
            while ( true ) do
                if not debug.getinfo(max_depth, "f") then
                    max_depth = max_depth - 1
                    break
                end
                max_depth = max_depth + 1
            end
            -- init stackinfos
            for i=max_depth, 1, -1 do
                s.stackdepth = s.stackdepth + 1
                local sinfo = debug.getinfo(i, "nf")
                local func = sinfo.func
                local finfo = getfuncinfo(func)
                s.stackinfos[s.stackdepth] =
                    {stackinfo = sinfo, funcinfo = finfo}
            end
            -- add sethook
            s.stackdepth = s.stackdepth + 1
            s.stackinfos[s.stackdepth] =
                {stackinfo = {name = "sethook", func = debug.sethook},
                 funcinfo = getfuncinfo(debug.sethook)}
            debug.sethook(hook, "cr")
            if debug_mode then
                print("set hook")
            end
        end
    end
end


return {
    init = init,
}
