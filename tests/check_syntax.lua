-- Compiles source without running modules or changing settings.
for _,path in ipairs(arg) do
    local chunk,err=loadfile(path)
    assert(chunk,err)
end
print("PASS Lua syntax: "..#arg.." files")
