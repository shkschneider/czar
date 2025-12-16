-- clean module: removes binaries and generated files (.c and .s)

local Clean = {}
Clean.__index = Clean

function Clean.clean(path)
    -- If no path provided, clean current directory
    path = path or "."
    
    local files_removed = {}
    local errors = {}
    
    -- Helper function to try removing a file
    local function try_remove(filepath)
        local ok, err = os.remove(filepath)
        if ok then
            table.insert(files_removed, filepath)
        elseif err then
            -- Only add to errors if the file exists but couldn't be removed
            -- (os.remove returns nil if file doesn't exist, which is fine)
            local f = io.open(filepath, "r")
            if f then
                f:close()
                table.insert(errors, string.format("Failed to remove %s: %s", filepath, err))
            end
        end
    end
    
    -- Remove a.out if it exists
    try_remove("a.out")
    
    -- If path is a directory, find all .c and .s files
    if path:match("/$") or path == "." then
        local handle = io.popen("find " .. path .. " -type f \\( -name '*.c' -o -name '*.s' \\) 2>/dev/null")
        if handle then
            for file in handle:lines() do
                try_remove(file)
            end
            handle:close()
        end
    elseif path:match("%.cz$") then
        -- If path is a .cz file, remove corresponding .c and .s files
        local c_path = path:gsub("%.cz$", ".c")
        local s_path = path:gsub("%.cz$", ".s")
        try_remove(c_path)
        try_remove(s_path)
    elseif path:match("%.c$") then
        -- If path is a .c file, remove it and corresponding .s file
        try_remove(path)
        local s_path = path:gsub("%.c$", ".s")
        try_remove(s_path)
    elseif path:match("%.s$") then
        -- If path is a .s file, remove it
        try_remove(path)
    end
    
    return #errors == 0, { removed = files_removed, errors = errors }
end

return Clean
