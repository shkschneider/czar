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

    return table.concat(parts, " "):gsub("fn%s+([%w_]+)%s*%(%s*", "fn %1(")
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

-- Get detailed type description
local function describe_type(type_node)
    if not type_node then
        return "unknown"
    end

    if type_node.kind == "pointer" then
        return "pointer to " .. describe_type(type_node.to)
    elseif type_node.kind == "array" then
        if type_node.size then
            return "array[" .. tostring(type_node.size) .. "] of " .. describe_type(type_node.element_type)
        else
            return "slice of " .. describe_type(type_node.element_type)
        end
    elseif type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "generic" then
        local args = {}
        for _, arg in ipairs(type_node.type_args) do
            table.insert(args, describe_type(arg))
        end
        return type_node.name .. "<" .. table.concat(args, ", ") .. ">"
    end

    return type_to_string(type_node)
end

-- Format struct with all fields
local function format_struct_full(struct_item)
    local lines = {}
    table.insert(lines, "struct " .. struct_item.name .. " {")
    for _, field in ipairs(struct_item.fields) do
        table.insert(lines, "    " .. format_struct_field(field))
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

-- Format enum with all values
local function format_enum_full(enum_item)
    local lines = {}
    table.insert(lines, "enum " .. enum_item.name .. " {")
    for _, value in ipairs(enum_item.values) do
        table.insert(lines, "    " .. value.name)
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

-- Collect all identifiers from AST after typechecking
local function collect_identifiers(ast, tc, source_file, module_name)
    local identifiers = {}

    -- Helper to add identifier with extended information
    local function add_identifier(name, kind, line, declaration, context)
        if not identifiers[name] then
            identifiers[name] = {}
        end
        table.insert(identifiers[name], {
            kind = kind,
            line = line,
            file = source_file,
            declaration = declaration,
            context = context or {},
            module = module_name
        })
    end

    -- Collect from top-level items
    for _, item in ipairs(ast.items) do
        if item.kind == "struct" then
            -- Full struct definition
            local decl = format_struct_full(item)
            local context = {
                field_count = #item.fields,
                fields = {}
            }
            for _, field in ipairs(item.fields) do
                table.insert(context.fields, field.name)
            end
            add_identifier(item.name, "struct", item.line or 0, decl, context)

            -- Also collect struct fields with struct context
            for _, field in ipairs(item.fields) do
                local field_decl = format_struct_field(field)
                local field_context = {
                    struct_name = item.name,
                    struct_line = item.line or 0
                }
                add_identifier(field.name, "struct_field", field.line or item.line or 0, field_decl, field_context)
            end
        elseif item.kind == "enum" then
            -- Full enum definition
            local decl = format_enum_full(item)
            local context = {
                value_count = #item.values,
                values = {}
            }
            for _, value in ipairs(item.values) do
                table.insert(context.values, value.name)
            end
            add_identifier(item.name, "enum", item.line or 0, decl, context)

            -- Also collect enum values with enum context
            for _, value in ipairs(item.values) do
                local value_decl = item.name .. "::" .. value.name
                local value_context = {
                    enum_name = item.name,
                    enum_line = item.line or 0
                }
                add_identifier(value.name, "enum_value", value.line or item.line or 0, value_decl, value_context)
            end
        elseif item.kind == "function" then
            local decl = format_function_signature(item)
            local context = {
                param_count = #item.params,
                return_type = type_to_string(item.return_type),
                return_type_desc = describe_type(item.return_type),
                is_method = item.receiver_type ~= nil,
                receiver_type = item.receiver_type
            }
            add_identifier(item.name, "function", item.line or 0, decl, context)

            -- Collect parameters with function context
            for param_idx, param in ipairs(item.params) do
                local param_decl = format_var_decl(param.name, { type = param.type, mutable = param.mutable })
                local is_vararg = param.type.kind == "varargs"
                local param_context = {
                    function_name = item.name,
                    function_line = item.line or 0,
                    param_index = param_idx,
                    param_of = format_function_signature(item),
                    type_desc = describe_type(param.type),
                    is_mutable = param.mutable or false,
                    is_vararg = is_vararg
                }
                add_identifier(param.name, "function_parameter", item.line or 0, param_decl, param_context)
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

    -- Extract module name if available
    local module_name = nil
    if typed_ast.module and typed_ast.module.path then
        module_name = table.concat(typed_ast.module.path, ".")
    end

    -- Collect identifiers
    local identifiers = collect_identifiers(typed_ast, nil, source_path, module_name)

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

    -- Default to current working directory if no paths provided
    if not paths or #paths == 0 then
        paths = {"."}
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
            return false, "No matches found"  -- Return false to trigger exit code 1
        end
    end

    -- Print matches
    for _, match in ipairs(all_matches) do
        -- Convert kind to lowercase-with-dashes
        local kind_formatted = match.kind:gsub("_", "-")
        io.stdout:write(string.format("INSPECT at %s:%d %s\n", match.file, match.line, kind_formatted))

        -- Print verbose context information
        if match.context then
            local ctx = match.context

            if match.kind == "function_parameter" and ctx.function_name then
                -- Nth parameter of function X
                local ordinal = ctx.param_index
                local suffix = "th"
                if ordinal == 1 then suffix = "st"
                elseif ordinal == 2 then suffix = "nd"
                elseif ordinal == 3 then suffix = "rd"
                end
                io.stdout:write(string.format("\t%d%s parameter of function %s\n", ordinal, suffix, ctx.function_name))

                -- Check if vararg
                if ctx.is_vararg then
                    io.stdout:write("\tvararg\n")
                end

                -- Mutability
                if ctx.is_mutable then
                    io.stdout:write("\tmutable\n")
                else
                    io.stdout:write("\timmutable\n")
                end

                -- Type description
                if ctx.type_desc then
                    if ctx.type_desc:match("^pointer to") then
                        io.stdout:write(string.format("\t%s\n", ctx.type_desc))
                    elseif ctx.type_desc:match("^array%[") or ctx.type_desc:match("^slice of") then
                        io.stdout:write(string.format("\t%s\n", ctx.type_desc))
                    end
                end

            elseif match.kind == "struct_field" and ctx.struct_name then
                io.stdout:write(string.format("\tfield of struct %s\n", ctx.struct_name))

            elseif match.kind == "enum_value" and ctx.enum_name then
                io.stdout:write(string.format("\tvalue of enum %s\n", ctx.enum_name))

            elseif match.kind == "function" then
                io.stdout:write(string.format("\tfunction returning %s\n", ctx.return_type_desc or ctx.return_type))
            end
        end

        -- Print declaration with "> " prefix on each line
        if match.declaration then
            for line in match.declaration:gmatch("[^\n]+") do
                io.stdout:write(string.format("\t> %s\n", line))
            end
        end
    end

    return true, nil
end

return Inspect
