-- fixme module: lists all #FIXME markers in .cz files using the lexer and parser

local lexer = require("lexer")
local parser = require("parser")

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

-- Search for #FIXME markers in a file using the lexer and parser
local function find_fixmes_in_file(filepath)
    local fixmes = {}
    
    -- Read the source file
    local source, err = read_file(filepath)
    if not source then
        return fixmes
    end
    
    -- Lex the source
    local ok, tokens = pcall(lexer, source)
    if not ok then
        -- If lexing fails, silently skip this file
        return fixmes
    end
    
    -- Parse to get AST for function context
    local ok_parse, ast = pcall(parser, tokens, source)
    if not ok_parse then
        -- If parsing fails, still try to extract FIXMEs without function context
        for i, token in ipairs(tokens) do
            if token.type == "DIRECTIVE" and token.value == "FIXME" then
                local message = nil
                if i + 1 <= #tokens and tokens[i + 1].type == "LPAREN" then
                    if i + 2 <= #tokens and tokens[i + 2].type == "STRING" then
                        message = tokens[i + 2].value
                    end
                end
                table.insert(fixmes, {
                    line = token.line,
                    col = token.col,
                    message = message,
                    func_name = nil
                })
            end
        end
        return fixmes
    end
    
    -- Walk the AST to find FIXMEs and their function context
    local function walk_ast(node, current_function)
        if not node or type(node) ~= "table" then
            return
        end
        
        -- Check if this is a function definition
        local func_name = current_function
        if node.kind == "function" and node.name then
            func_name = node.name
        end
        
        -- Check if this is a FIXME statement
        if node.kind == "fixme_stmt" then
            local message = nil
            if node.message and node.message.kind == "string" then
                message = node.message.value
            end
            table.insert(fixmes, {
                line = node.line,
                col = node.col,
                message = message,
                func_name = func_name
            })
        end
        
        -- Recursively walk children
        for key, value in pairs(node) do
            if key ~= "kind" and key ~= "line" and key ~= "col" then
                if type(value) == "table" then
                    if value.kind then
                        -- Single node
                        walk_ast(value, func_name)
                    else
                        -- Array of nodes
                        for _, child in ipairs(value) do
                            if type(child) == "table" then
                                walk_ast(child, func_name)
                            end
                        end
                    end
                end
            end
        end
    end
    
    walk_ast(ast, nil)
    
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
                -- Format: "FIXME in function_name() at filename:line message"
                local output = "FIXME "
                if fixme.func_name then
                    output = output .. string.format("in %s() ", fixme.func_name)
                end
                output = output .. string.format("at %s:%d", filepath, fixme.line)
                if fixme.message then
                    output = output .. string.format(" %s", fixme.message)
                else
                    output = output .. " FIXME"
                end
                io.stdout:write(output .. "\n")
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
