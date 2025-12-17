-- inspect module: parses and collects information about identifiers
-- Searches for specific identifier names and reports their type, location, and declaration

local lexer = require("lexer")
local parser = require("parser")
local typechecker = require("typechecker")

local Inspect = {}
Inspect.__index = Inspect

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

-- Check if path is a directory
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

-- Convert type node to string representation
local function type_to_string(type_node)
    if not type_node then
        return "unknown"
    end
    
    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        return type_to_string(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        if type_node.size then
            return type_to_string(type_node.element_type) .. "[" .. tostring(type_node.size) .. "]"
        else
            return type_to_string(type_node.element_type) .. "[]"
        end
    elseif type_node.kind == "generic" then
        local args = {}
        for _, arg in ipairs(type_node.type_args) do
            table.insert(args, type_to_string(arg))
        end
        return type_node.name .. "<" .. table.concat(args, ":") .. ">"
    elseif type_node.kind == "varargs" then
        return type_to_string(type_node.element_type) .. "..."
    end
    
    return "unknown"
end

-- Format function signature
local function format_function_signature(func)
    local parts = {}
    table.insert(parts, "fn")
    
    -- Add receiver type for methods
    if func.receiver_type then
        table.insert(parts, func.receiver_type .. ":" .. func.name .. "(")
    else
        table.insert(parts, func.name .. "(")
    end
    
    -- Add parameters
    local params = {}
    for _, param in ipairs(func.params) do
        local param_str = ""
        if param.mutable then
            param_str = "mut "
        end
        param_str = param_str .. type_to_string(param.type) .. " " .. param.name
        table.insert(params, param_str)
    end
    
    table.insert(parts, table.concat(params, ", ") .. ")")
    
    -- Add return type
    table.insert(parts, type_to_string(func.return_type))
    
    return table.concat(parts, " ")
end

-- Format struct field
local function format_struct_field(field)
    local parts = {}
    if field.public then
        table.insert(parts, "pub")
    end
    if field.mutable then
        table.insert(parts, "mut")
    end
    table.insert(parts, type_to_string(field.type))
    table.insert(parts, field.name)
    return table.concat(parts, " ")
end

-- Format variable declaration
local function format_var_decl(var_name, var_info)
    local parts = {}
    if var_info.mutable then
        table.insert(parts, "mut")
    end
    table.insert(parts, type_to_string(var_info.type))
    table.insert(parts, var_name)
    return table.concat(parts, " ")
end

-- Collect all identifiers from AST after typechecking
local function collect_identifiers(ast, tc, source_file)
    local identifiers = {}
    
    -- Helper to add identifier
    local function add_identifier(name, kind, line, declaration)
        if not identifiers[name] then
            identifiers[name] = {}
        end
        table.insert(identifiers[name], {
            kind = kind,
            line = line,
            file = source_file,
            declaration = declaration
        })
    end
    
    -- Collect from top-level items
    for _, item in ipairs(ast.items) do
        if item.kind == "struct" then
            local decl = "struct " .. item.name
            add_identifier(item.name, "struct", item.line or 0, decl)
            
            -- Also collect struct fields
            for _, field in ipairs(item.fields) do
                local field_decl = format_struct_field(field)
                add_identifier(field.name, "field", field.line or item.line or 0, field_decl)
            end
        elseif item.kind == "enum" then
            local decl = "enum " .. item.name
            add_identifier(item.name, "enum", item.line or 0, decl)
            
            -- Also collect enum values
            for _, value in ipairs(item.values) do
                local value_decl = item.name .. "::" .. value.name
                add_identifier(value.name, "enum_value", value.line or item.line or 0, value_decl)
            end
        elseif item.kind == "function" then
            local decl = format_function_signature(item)
            add_identifier(item.name, "function", item.line or 0, decl)
            
            -- Collect parameters
            for _, param in ipairs(item.params) do
                local param_decl = format_var_decl(param.name, { type = param.type, mutable = param.mutable })
                add_identifier(param.name, "parameter", item.line or 0, param_decl)
            end
        end
    end
    
    -- We could also walk the AST to find local variables, but that would require
    -- more complex scope tracking. For now, we focus on top-level declarations.
    
    return identifiers
end

-- Inspect a single file for a specific identifier
function Inspect.inspect_file(source_path, identifier_name, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end
    
    -- Extract just the filename (not the full path) for display
    local filename = source_path:match("([^/]+)$") or source_path
    options.source_file = filename
    options.source_path = source_path
    
    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        return false, string.format("Failed to read '%s': %s", source_path, err or "unknown error")
    end
    
    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        local clean_error = tokens:gsub("^%[string [^%]]+%]:%d+: ", "")
        return false, string.format("Lexer error in %s: %s", source_path, clean_error)
    end
    
    -- Parse
    local ok, ast = pcall(parser, tokens, source)
    if not ok then
        local clean_error = ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return false, string.format("Parser error in %s: %s", source_path, clean_error)
    end
    
    -- Type check
    local ok, typed_ast = pcall(typechecker, ast, options)
    if not ok then
        local clean_error = typed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return false, clean_error
    end
    
    -- Collect identifiers
    local identifiers = collect_identifiers(typed_ast, nil, filename)
    
    -- Find matches
    local matches = identifiers[identifier_name] or {}
    
    return true, matches
end

-- Main inspect function
function Inspect.inspect(identifier_name, paths, options)
    options = options or {}
    
    if not identifier_name or identifier_name == "" then
        return false, "Error: identifier name is required"
    end
    
    if not paths or #paths == 0 then
        return false, "Error: at least one file or directory path is required"
    end
    
    -- Expand paths to files
    local files = {}
    for _, path in ipairs(paths) do
        if is_directory(path) then
            local dir_files = get_cz_files_in_dir(path)
            for _, file in ipairs(dir_files) do
                table.insert(files, file)
            end
        else
            table.insert(files, path)
        end
    end
    
    if #files == 0 then
        return false, "Error: no .cz files found"
    end
    
    -- Inspect each file
    local all_matches = {}
    local errors = {}
    
    for _, file in ipairs(files) do
        local ok, matches = Inspect.inspect_file(file, identifier_name, options)
        if ok then
            for _, match in ipairs(matches) do
                table.insert(all_matches, match)
            end
        else
            -- Don't fail completely on parse errors, just collect them
            table.insert(errors, matches)
        end
    end
    
    -- Print results
    if #all_matches == 0 then
        if #errors > 0 then
            -- Print errors
            for _, err in ipairs(errors) do
                io.stderr:write(err .. "\n")
            end
            return false, string.format("No matches found for '%s' (some files had errors)", identifier_name)
        else
            io.stdout:write(string.format("No matches found for '%s'\n", identifier_name))
            return true, nil
        end
    end
    
    -- Print matches
    for _, match in ipairs(all_matches) do
        io.stdout:write(string.format("INSPECT at %s:%d %s\n", match.file, match.line, match.kind))
        io.stdout:write(string.format("    %s\n", match.declaration))
    end
    
    return true, nil
end

return Inspect
