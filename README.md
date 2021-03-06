# Name

luadebug - A simple Lua debugger supporting breakpoints

luadebug - 一个简单的Lua调试器，支持断点调试

# Table of Contents

- [Name](#Name)
- [Branchs](#Branchs)
- [Desciption](#Desciption)
- [Methods](#Methods)
    - [setbreakpoint](#setbreakpoint)
    - [removebreakpoint](#removebreakpoint)
    - [printvarvalue](#printvarvalue)
    - [setvarvalue](#setvarvalue)
    - [printtraceback](#printtraceback)


# Branchs

- ch01: minimal implementation of breakpoints 断点的最小实现
- ch02: general variable print function 通用变量打印函数
- ch03: general variable set function & traceback of call stack print function 通用变量修改函数及调用栈回溯打印函数
- ch04: optimize: hook event processing 优化: 钩子事件处理
- ch05: optimize: data structures of breakpoint info 优化: 断点信息数据结构
- ch06: breakpoints' line number check & autocorrection 断点的行号检查及自动修正
- ch07: support setting breakpoints by function name 支持通过函数名称添加断点
- ch08: support setting breakpoints by package name 支持通过包名称添加断点
- ch09: support setting and removing breakpoints dynamically 支持动态增删断点

# Desciption

This Lua module provides debugging funtions to debug Lua programs in the style of `gdb`.

That is, you can add breakpoints to debug your application.

To start debugging, just add the following line into the beginning of your source code

```lua
require("luadebug").init()
```

then it will enter an interactive mode , and you can set/remove breakpoint as you wish.

The current supported debugging functions are as follows. You can alos use the short name within the parenthesis.

Note that all these debugging functions are set in the `_G`.

If any naming conflict occurs, you can substitute the names like:

```lua
require("luadebug").init({"bb", "dd", "pp", "ss", "tt", "ii", "hh"})
```

# Methods

## setbreakpoint (b)

**syntax:** id = setbreakpoint(location, line)

Sets a breakpoint within a function or a package. `location` can be one of the follows:

### a string consists of a function name, a `@` and an optional line number

Example:

```lua
local function foo()            -- line 1
    local a = 1                 -- line 2
end                             -- line 3
```


```
lua_debug> setbreakpoint("foo@")           -- set bp at first active line (line 2) of function "foo"
lua_debug> setbreakpoint("foo@3")          -- set bp at line 3 within function "foo" (line number should be a valid active line number)
```

Note that the number specified should be a valid active line of the corresponding function.

### a string consists of a package name, a `:` and an optional line number

If a negative line number is specified, the breakpoint will be set within mainchunk.

If a positive line number is specified, the breakpoint will be set within subfuntion of mainchunk.

If no line number is specified, the breakpoint will be set at the first activeline of mainchunk.

Example:

- `testpackage.lua`

```lua
local n = 0                     -- line 1
local function foo()            -- line 2
    local a = 1                 -- line 3
end                             -- line 4
```

- `test.lua`

```lua
lua_debug> setbreakpoint("testpackage:")   -- set bp at first activeline (line 1) of mainchunk
lua_debug> setbreakpoint("testpackage:-2") -- set bp at line 4 (function declaration) within mainchunk
lua_debug> setbreakpoint("testpackage:2")  -- set bp at line 3 within function foo
lua_debug> setbreakpoint("testpackage:4")  -- set bp at line 4 within function foo
```

If the line number is out of the range of function definition, returns `nil`; otherwise, the line number

will be automatically corrected to the nearest activeline (greater than or equal to the line number in parameter).

If line number is not specified, then it will be the smallest activeline by default.

Returns the breakpoint id when success , otherwise returns `nil`.

If the same breakpoint is already set, returns the previous id.

The breakpoint `id` can be later used to remove the breakpoint.

[Back to TOC](#table-of-contents)


## removebreakpoint (d)

**syntax:** removebreakpoint(id)

Removes the breakpoint set before. If `id` is not a valid breakpoint id, it does nothing.

[Back to TOC](#table-of-contents)


## printvarvalue (p)

**syntax:** printvarvalue(name, level)

Prints the value of a variable called `name`. The variable can be either a local variable, an upvalue,

or a variable in `_ENV` table. And `level` specifies the stack level of the active function

from which the variable is searched; `1` (the default) means the function where the breakpoint is set.

If the variable is found, then it prints the where the variable is found (local | upvalue | global),

and the value of variable. If not found, it then prompts the variable is not found.

[Back to TOC](#table-of-contents)


## setvarvalue (s)

**syntax:** setvarvalue(name, value, level)

Sets the value of a variable called `name` to `value`. The variable can be either a local variable, an upvalue,

or a variable in `_ENV` table. And `level` specifies the stack level of the active function

from which the variable is searched; `1` (the default) means the function where the breakpoint is set.

If the variable is found, then modifies the value to `value` and prints the where the variable is found (local | upvalue | global).

If not found, it then prompts the variable is not found.

[Back to TOC](#table-of-contents)


## printtraceback (bt)

**syntax:** printvarvalue(level)

Prints a traceback of call stack. The parameter `level` (1 by default) tells at which level to start the traceback.

[Back to TOC](#table-of-contents)


## printbreakinfo (i)
**syntax:** printbreakinfo()

Prints the information of all the breakpoints exsiting.

[Back to TOC](#table-of-contents)


## help (h)

**syntax:** help(verbose)

Shows the help infos. If `verbose` is true, shows verbose help info

[Back to TOC](#table-of-contents)
