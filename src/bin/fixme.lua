-- fixme module: lists all #FIXME markers in .cz files

local Fixme = {}
Fixme.__index = Fixme

-- Helper function to check if path is a directory
local function is_directory(path)
    local handle = io.popen("test -d " .. path:gsub("'", "'\\''") .. " && echo yes || echo no")
    local result = handle:read("*a"):match("^%s*(.-)%s*$")
    handle:close()
    return result == "yes"
end

-- Get all .cz files from a directory recursively
local function get_cz_files_in_dir(dir)
    local files = {}
    local handle = io.popen("find " .. dir:gsub("'", "'\\''") .. " -type f -name '*.cz' 2>/dev/null")
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

-- Search for #FIXME markers in a file
local function find_fixmes_in_file(filepath)
    local fixmes = {}
    local file = io.open(filepath, "r")
    if not file then
        return fixmes
    end
    
    local line_num = 0
    for line in file:lines() do
        line_num = line_num + 1
        -- Match #FIXME with optional message in parentheses
        -- Pattern matches: #FIXME or #FIXME("message") or #FIXME ( "message" )
        -- But not inside comments (lines starting with //)
        local trimmed = line:match("^%s*(.-)%s*$")
        if not trimmed:match("^//") then
            local fixme_match = line:match("#FIXME")
            if fixme_match then
                local message = line:match('#FIXME%s*%(%s*"([^"]*)"')
                if message then
                    table.insert(fixmes, {
                        line = line_num,
                        message = message,
                        full_line = trimmed
                    })
                else
                    -- No message provided
                    table.insert(fixmes, {
                        line = line_num,
                        message = nil,
                        full_line = trimmed
                    })
                end
            end
        end
    end
    
    file:close()
    return fixmes
end

function Fixme.fixme(path)
    -- Default to current directory if no path provided
    path = path or "."
    
    local files = {}
    
    -- Determine if path is a directory or file
    if is_directory(path) then
        files = get_cz_files_in_dir(path)
    else
        -- Single file
        if path:match("%.cz$") then
            table.insert(files, path)
        else
            return false, string.format("Error: file must have .cz extension, got: %s", path)
        end
    end
    
    if #files == 0 then
        io.stdout:write("No .cz files found\n")
        return true
    end
    
    local total_fixmes = 0
    
    -- Process each file
    for _, filepath in ipairs(files) do
        local fixmes = find_fixmes_in_file(filepath)
        
        if #fixmes > 0 then
            for _, fixme in ipairs(fixmes) do
                io.stdout:write(string.format("%s:%d: FIXME", filepath, fixme.line))
                if fixme.message then
                    io.stdout:write(string.format(": %s", fixme.message))
                end
                io.stdout:write("\n")
                total_fixmes = total_fixmes + 1
            end
        end
    end
    
    if total_fixmes == 0 then
        io.stdout:write("No FIXMEs found\n")
    end
    
    return true
end

return Fixme
