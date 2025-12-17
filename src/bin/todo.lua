-- todo module: lists all #TODO markers in .cz files using the lexer

local lexer = require("lexer")

local Todo = {}
Todo.__index = Todo

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

-- Read file contents
local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

-- Search for #TODO markers in a file using the lexer
local function find_todos_in_file(filepath)
    local todos = {}
    
    -- Read the source file
    local source, err = read_file(filepath)
    if not source then
        return todos
    end
    
    -- Lex the source
    local ok, tokens = pcall(lexer, source)
    if not ok then
        -- If lexing fails, silently skip this file
        return todos
    end
    
    -- Search for TODO directive tokens
    for i, token in ipairs(tokens) do
        if token.type == "DIRECTIVE" and token.value == "TODO" then
            local message = nil
            -- Check if the next token is LPAREN, indicating a message
            if i + 1 <= #tokens and tokens[i + 1].type == "LPAREN" then
                -- Look for the string literal message
                if i + 2 <= #tokens and tokens[i + 2].type == "STRING" then
                    message = tokens[i + 2].value
                end
            end
            table.insert(todos, {
                line = token.line,
                message = message
            })
        end
    end
    
    return todos
end

function Todo.todo(path)
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
    
    local total_todos = 0
    
    -- Process each file
    for _, filepath in ipairs(files) do
        local todos = find_todos_in_file(filepath)
        
        if #todos > 0 then
            for _, todo in ipairs(todos) do
                io.stdout:write(string.format("%s:%d: TODO", filepath, todo.line))
                if todo.message then
                    io.stdout:write(string.format(": %s", todo.message))
                end
                io.stdout:write("\n")
                total_todos = total_todos + 1
            end
        end
    end
    
    if total_todos == 0 then
        io.stdout:write("No TODOs found\n")
    end
    
    return true
end

return Todo
