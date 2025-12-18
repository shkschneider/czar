-- Typechecker declaration collection
-- Handles collection of top-level declarations (structs, enums, functions)

local Errors = require("errors")

local Declarations = {}

-- Helper: Convert type to string for signature
local function type_to_signature_string(type_node)
    if not type_node then
        return "unknown"
    end
    
    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        return type_to_signature_string(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        return type_to_signature_string(type_node.element_type) .. "[" .. (type_node.size or "*") .. "]"
    elseif type_node.kind == "slice" then
        return type_to_signature_string(type_node.element_type) .. "[:]"
    elseif type_node.kind == "varargs" then
        return type_to_signature_string(type_node.element_type) .. "..."
    elseif type_node.kind == "string" then
        return "string"
    end
    
    return "unknown"
end

-- Helper: Create a signature string from function parameters
local function create_signature(params)
    local parts = {}
    for _, param in ipairs(params) do
        table.insert(parts, type_to_signature_string(param.type))
    end
    return table.concat(parts, ",")
end

-- Helper: Validate that overloads differ on exactly one type position
-- With "single type variance" requirement: all parameters that differ must change to/from the same base type
-- E.g., (u8,u8)->(f32,f32) is OK (both change u8<->f32)
-- But (u8,f32)->(u32,f64) is NOT OK (first changes u8<->u32, second changes f32<->f64)
-- Returns true if valid, false + error message if invalid
local function validate_overload_single_type_variance(existing_overloads, new_func, func_name)
    if #existing_overloads == 0 then
        return true, nil
    end
    
    -- Check against first existing overload
    local first_existing = existing_overloads[1]
    
    -- Must have same number of parameters
    if #first_existing.params ~= #new_func.params then
        return false, string.format(
            "Function overload '%s' must have same parameter count as previous definition (line %d)",
            func_name, first_existing.line or 0
        )
    end
    
    -- Find which parameter positions differ and what type changes occur
    local type_changes = {}  -- Maps old_type -> new_type for each change
    local all_same = true
    
    for i = 1, #first_existing.params do
        local old_type_str = type_to_signature_string(first_existing.params[i].type)
        local new_type_str = type_to_signature_string(new_func.params[i].type)
        if old_type_str ~= new_type_str then
            all_same = false
            -- Record this type change
            local change_sig = old_type_str .. "->" .. new_type_str
            table.insert(type_changes, change_sig)
        end
    end
    
    -- Check if signature is identical (duplicate)
    if all_same then
        return false, string.format(
            "Duplicate function definition '%s' with same signature (previously defined at line %d)",
            func_name, first_existing.line or 0
        )
    end
    
    -- Validate single type variance: all type changes must be the same
    -- This means if we have (u8,u8)->(f32,f32), both params change u8->f32
    if #type_changes > 1 then
        local first_change = type_changes[1]
        for i = 2, #type_changes do
            if type_changes[i] ~= first_change then
                return false, string.format(
                    "Function overload '%s' must vary on a single type only. Found multiple type changes: %s and %s",
                    func_name, first_change, type_changes[i]
                )
            end
        end
    end
    
    return true, nil
end

-- Helper: Replace generic type T with concrete type
local function replace_generic_type(type_node, concrete_type)
    if not type_node then
        return nil
    end
    
    if type_node.kind == "named_type" then
        if type_node.name == "T" then
            -- Replace T with concrete type
            return { kind = "named_type", name = concrete_type }
        else
            return type_node
        end
    elseif type_node.kind == "pointer" then
        return { kind = "pointer", to = replace_generic_type(type_node.to, concrete_type) }
    elseif type_node.kind == "array" then
        return { 
            kind = "array", 
            element_type = replace_generic_type(type_node.element_type, concrete_type),
            size = type_node.size
        }
    elseif type_node.kind == "slice" then
        return { 
            kind = "slice", 
            element_type = replace_generic_type(type_node.element_type, concrete_type)
        }
    elseif type_node.kind == "varargs" then
        return {
            kind = "varargs",
            element_type = replace_generic_type(type_node.element_type, concrete_type)
        }
    else
        return type_node
    end
end

-- Helper: Expand a generic function into concrete overloads
local function expand_generic_function(item, typechecker)
    if not item.generic_types or #item.generic_types == 0 then
        return {item}  -- Not generic, return as-is
    end
    
    local expanded = {}
    
    for _, concrete_type in ipairs(item.generic_types) do
        -- Deep copy the function item
        local expanded_func = {
            kind = "function",
            name = item.name,
            receiver_type = item.receiver_type,
            params = {},
            return_type = nil,
            body = item.body,  -- Body is shared (will be used in codegen)
            inline_directive = item.inline_directive,
            line = item.line,
            col = item.col,
            is_generic_instance = true,
            generic_concrete_type = concrete_type
        }
        
        -- Replace T with concrete type in parameters
        for _, param in ipairs(item.params) do
            local new_param = {
                name = param.name,
                type = replace_generic_type(param.type, concrete_type),
                mutable = param.mutable,
                default_value = param.default_value
            }
            table.insert(expanded_func.params, new_param)
        end
        
        -- Replace T with concrete type in return type
        expanded_func.return_type = replace_generic_type(item.return_type, concrete_type)
        
        table.insert(expanded, expanded_func)
    end
    
    return expanded
end

-- Collect all top-level declarations
function Declarations.collect_declarations(typechecker)
    local new_items = {}  -- Build new items list with expanded generics
    
    for _, item in ipairs(typechecker.ast.items) do
        if item.kind == "struct" then
            -- Check for duplicate struct definition
            if typechecker.structs[item.name] then
                local line = item.line or 0
                local prev_line = typechecker.structs[item.name].line or 0
                local msg = string.format(
                    "Duplicate struct definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_STRUCT, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                -- Check for duplicate field names within the struct
                local field_names = {}
                for _, field in ipairs(item.fields) do
                    if field_names[field.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate field '%s' in struct '%s'",
                            field.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        field_names[field.name] = true
                    end
                end
                typechecker.structs[item.name] = item
            end
            table.insert(new_items, item)  -- Keep struct in new items
        elseif item.kind == "enum" then
            -- Check for duplicate enum definition
            if typechecker.enums[item.name] then
                local line = item.line or 0
                local prev_line = typechecker.enums[item.name].line or 0
                local msg = string.format(
                    "Duplicate enum definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_ENUM, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                -- Check for duplicate value names within the enum
                local value_names = {}
                for _, value in ipairs(item.values) do
                    if value_names[value.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate value '%s' in enum '%s'",
                            value.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        value_names[value.name] = true
                    end
                end
                typechecker.enums[item.name] = item
            end
            table.insert(new_items, item)  -- Keep enum in new items
        elseif item.kind == "function" then
            -- Determine if this is a method or a global function
            local type_name = "__global__"
            -- Check for receiver_type field (used by parser for methods)
            if item.receiver_type then
                type_name = item.receiver_type
            elseif item.receiver then
                type_name = item.receiver.type.name
            end

            if not typechecker.functions[type_name] then
                typechecker.functions[type_name] = {}
            end

            -- Check for duplicate parameter names within the function
            -- Allow multiple '_' parameters (convention for unused/ignored parameters)
            local param_names = {}
            for _, param in ipairs(item.params) do
                if param.name ~= "_" and param_names[param.name] then
                    local line = item.line or 0
                    local msg = string.format(
                        "Duplicate parameter '%s' in function '%s'",
                        param.name, item.name
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.DUPLICATE_PARAMETER, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                else
                    param_names[param.name] = true
                end
            end

            -- Expand generic functions into concrete overloads
            local functions_to_add = expand_generic_function(item, typechecker)
            
            for _, func in ipairs(functions_to_add) do
                -- Support function overloading: store as array of overloads
                if not typechecker.functions[type_name][func.name] then
                    typechecker.functions[type_name][func.name] = {}
                end
                
                local existing_overloads = typechecker.functions[type_name][func.name]
                
                -- Validate overload (single type variance check)
                local valid, err_msg = validate_overload_single_type_variance(existing_overloads, func, func.name)
                if not valid then
                    local line = func.line or 0
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.DUPLICATE_FUNCTION, err_msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                else
                    -- Store the overload with its signature
                    func.signature = create_signature(func.params)
                    table.insert(typechecker.functions[type_name][func.name], func)
                    table.insert(new_items, func)  -- Add expanded function to new items
                end
            end
        elseif item.kind == "alias_macro" then
            -- Store type aliases
            if typechecker.type_aliases[item.alias_name] then
                local line = item.line or 0
                local msg = string.format("duplicate #alias for '%s'", item.alias_name)
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_ALIAS, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                typechecker.type_aliases[item.alias_name] = item.target_type_str
            end
            table.insert(new_items, item)  -- Keep macro in new items
        elseif item.kind == "allocator_macro" then
            -- Store other macros but don't type check them
            table.insert(new_items, item)  -- Keep macro in new items
        end
    end
    
    -- Replace AST items with expanded items
    typechecker.ast.items = new_items
end

return Declarations
