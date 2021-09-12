local str1 = "a.lua:10"
local s = string.find(str1, ":")
if s then
    local src = string.sub(str1, 1, s-1)
    local li = string.sub(str1, s+1)
    if src == "" then
        print("src: empty")
    else
        print("src: ", src)
    end
    if li == "" then
        print("line: nil")
    else
        print("line: ", li)
    end
    li = tonumber(li)
    if li then
        print("line: ", li)
    else
        print("not a valid line number")
    end
else
    print("no :")
end
