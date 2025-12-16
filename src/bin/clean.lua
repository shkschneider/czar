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

    return #errors == 0, { removed = files_removed, errors = errors }
end

return Clean
