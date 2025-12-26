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
    elseif type_node.kind == "nullable" then
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
    elseif type_node.kind == "nullable" then
        return { kind = "nullable", to = replace_generic_type(type_node.to, concrete_type) }
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
    local Warnings = require("warnings")
    local new_items = {}  -- Build new items list with expanded generics

    -- Helper function to check if a name is TitleCase (starts with uppercase)
    local function is_titlecase(name)
        return name:match("^%u")
    end

    -- Helper function to check if a name has underscores
    local function has_underscore(name)
        return name:match("_")
    end

    -- Helper function to check if interface name follows iInterfaceName format
    local function is_valid_interface_name(name)
        -- Should start with lowercase 'i' followed by an uppercase letter
        return name:match("^i%u")
    end

    -- Helper function to check if a name is snake_case (lowercase with underscores)
    local function is_snake_case(name)
        -- Should be all lowercase, can have underscores, no uppercase letters
        return not name:match("%u")
    end

    for _, item in ipairs(typechecker.ast.items) do
        if item.kind == "struct" then
            -- Check naming convention: structs MUST be TitleCase (now enforced as error)
            if not is_titlecase(item.name) then
                local msg = string.format(
                    "Struct '%s' must be TitleCase (e.g., '%s').",
                    item.name,
                    item.name:sub(1,1):upper() .. item.name:sub(2)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, item.line,
                    Errors.ErrorType.INVALID_STRUCT_NAME, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end

            -- Check naming convention: structs should not have underscores (use PascalCase)
            if has_underscore(item.name) then
                local suggested_name = item.name:gsub("_(%l)", function(c) return c:upper() end):gsub("_", "")
                local msg = string.format(
                    "Struct '%s' must not contain underscores. Use PascalCase instead (e.g., '%s').",
                    item.name,
                    suggested_name
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, item.line,
                    Errors.ErrorType.INVALID_STRUCT_NAME, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end

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
        elseif item.kind == "iface" then
            -- Check naming convention: interfaces should follow iInterfaceName format
            if not is_valid_interface_name(item.name) then
                local suggested_name = "i" .. item.name:sub(1,1):upper() .. item.name:sub(2)
                local msg = string.format(
                    "Interface '%s' should follow format 'iInterfaceName' with lowercase 'i' prefix (e.g., '%s')",
                    item.name,
                    suggested_name
                )
                Warnings.emit(
                    typechecker.source_file,
                    item.line,
                    Warnings.WarningType.INTERFACE_WRONG_FORMAT,
                    msg,
                    typechecker.source_path,
                    nil
                )
            end

            -- Check naming convention: interfaces should not have underscores (use iPascalCase)
            if has_underscore(item.name) then
                -- Remove underscores and convert to PascalCase, keeping the 'i' prefix if present
                local name_without_i = item.name:match("^i(.+)") or item.name
                local suggested_name = "i" .. name_without_i:gsub("_(%l)", function(c) return c:upper() end):gsub("_", "")
                local msg = string.format(
                    "Interface '%s' should not contain underscores. Use iPascalCase instead (e.g., '%s')",
                    item.name,
                    suggested_name
                )
                Warnings.emit(
                    typechecker.source_file,
                    item.line,
                    Warnings.WarningType.INTERFACE_HAS_UNDERSCORE,
                    msg,
                    typechecker.source_path,
                    nil
                )
            end

            -- Check for duplicate interface definition
            if typechecker.ifaces[item.name] then
                local line = item.line or 0
                local prev_line = typechecker.ifaces[item.name].line or 0
                local msg = string.format(
                    "Duplicate interface definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_STRUCT, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                -- Check for duplicate method names within the interface
                local method_names = {}
                for _, method in ipairs(item.methods) do
                    if method_names[method.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate method '%s' in interface '%s'",
                            method.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        method_names[method.name] = true
                    end
                end

                -- Check for duplicate field names within the interface
                local field_names = {}
                for _, field in ipairs(item.fields or {}) do
                    if field_names[field.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate field '%s' in interface '%s'",
                            field.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        field_names[field.name] = true
                    end
                end

                -- Check for name conflicts between fields and methods
                for _, field in ipairs(item.fields or {}) do
                    if method_names[field.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Interface '%s' has both field and method named '%s'",
                            item.name, field.name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    end
                end

                -- Warn if interface is empty (useless interface)
                local has_fields = item.fields and #item.fields > 0
                local has_methods = item.methods and #item.methods > 0
                if not has_fields and not has_methods then
                    local Warnings = require("warnings")
                    Warnings.emit(
                        typechecker.source_file,
                        item.line or 0,
                        Warnings.WarningType.USELESS_INTERFACE,
                        string.format("Interface '%s' is empty and serves no purpose", item.name),
                        typechecker.source_path,
                        nil
                    )
                end

                typechecker.ifaces[item.name] = item
            end
            table.insert(new_items, item)  -- Keep interface in new items
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
        elseif item.kind == "allocator_macro" then
            -- Store other macros but don't type check them
            table.insert(new_items, item)  -- Keep macro in new items
        end
    end

    -- Replace AST items with expanded items
    typechecker.ast.items = new_items

    -- Validate interface implementations
    Declarations.validate_interface_implementations(typechecker)
end

-- Helper: Get parameter count for method signature comparison, optionally skipping 'self'
local function get_method_param_count(params, skip_self)
    local start_idx = 1
    if skip_self and #params > 0 and params[1].name == "self" then
        start_idx = 2
    end
    return #params - start_idx + 1, start_idx
end

-- Validate that structs properly implement their declared interfaces
function Declarations.validate_interface_implementations(typechecker)
    for struct_name, struct_def in pairs(typechecker.structs) do
        if struct_def.implements then
            local iface_name = struct_def.implements
            local iface_def = typechecker.ifaces[iface_name]

            if not iface_def then
                local msg = string.format(
                    "Struct '%s' implements undefined interface '%s'",
                    struct_name, iface_name
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, struct_def.line or 0,
                    Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                -- Check that all interface fields are present in the struct
                for _, iface_field in ipairs(iface_def.fields or {}) do
                    local field_name = iface_field.name
                    local found = false

                    for _, struct_field in ipairs(struct_def.fields) do
                        if struct_field.name == field_name then
                            -- Check that field types match
                            local struct_field_type_str = type_to_signature_string(struct_field.type)
                            local iface_field_type_str = type_to_signature_string(iface_field.type)

                            if struct_field_type_str == iface_field_type_str then
                                found = true
                                break
                            else
                                local msg = string.format(
                                    "Struct '%s' field '%s' type '%s' does not match interface '%s' expected type '%s'",
                                    struct_name, field_name, struct_field_type_str, iface_name, iface_field_type_str
                                )
                                local formatted_error = Errors.format("ERROR", typechecker.source_file, struct_def.line or 0,
                                    Errors.ErrorType.MISMATCHED_SIGNATURE, msg, typechecker.source_path)
                                typechecker:add_error(formatted_error)
                                found = true
                                break
                            end
                        end
                    end

                    if not found then
                        local msg = string.format(
                            "Struct '%s' does not have field '%s' required by interface '%s'",
                            struct_name, field_name, iface_name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, struct_def.line or 0,
                            Errors.ErrorType.MISSING_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    end
                end

                -- Check that all interface methods are implemented by the struct
                local struct_methods = typechecker.functions[struct_name] or {}

                for _, iface_method in ipairs(iface_def.methods) do
                    local method_name = iface_method.name
                    local impl_overloads = struct_methods[method_name]

                    if not impl_overloads or #impl_overloads == 0 then
                        local msg = string.format(
                            "Struct '%s' does not implement method '%s' required by interface '%s'",
                            struct_name, method_name, iface_name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, struct_def.line or 0,
                            Errors.ErrorType.MISSING_METHOD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        -- Check that at least one overload matches the interface signature
                        local found_match = false
                        for _, impl_func in ipairs(impl_overloads) do
                            -- Compare signatures (skip 'self' parameter for instance methods)
                            local impl_params = impl_func.params
                            local iface_params = iface_method.params

                            -- Get parameter count, skipping 'self' if present
                            local impl_param_count, impl_start_idx = get_method_param_count(impl_params, true)

                            -- Check parameter count
                            if impl_param_count == #iface_params then
                                -- Check each parameter type
                                local params_match = true
                                for i = 1, #iface_params do
                                    local impl_param = impl_params[impl_start_idx + i - 1]
                                    local iface_param = iface_params[i]
                                    local impl_type_str = type_to_signature_string(impl_param.type)
                                    local iface_type_str = type_to_signature_string(iface_param.type)
                                    if impl_type_str ~= iface_type_str then
                                        params_match = false
                                        break
                                    end
                                end

                                -- Check return type
                                local impl_ret_str = type_to_signature_string(impl_func.return_type)
                                local iface_ret_str = type_to_signature_string(iface_method.return_type)

                                if params_match and impl_ret_str == iface_ret_str then
                                    found_match = true
                                    break
                                end
                            end
                        end

                        if not found_match then
                            -- Build expected signature string
                            local param_strs = {}
                            for _, param in ipairs(iface_method.params) do
                                table.insert(param_strs, type_to_signature_string(param.type) .. " " .. param.name)
                            end
                            local expected_sig = string.format("%s(%s) %s",
                                method_name,
                                table.concat(param_strs, ", "),
                                type_to_signature_string(iface_method.return_type))

                            local msg = string.format(
                                "Struct '%s' method '%s' does not match interface '%s' signature: expected '%s'",
                                struct_name, method_name, iface_name, expected_sig
                            )
                            local formatted_error = Errors.format("ERROR", typechecker.source_file, struct_def.line or 0,
                                Errors.ErrorType.MISMATCHED_SIGNATURE, msg, typechecker.source_path)
                            typechecker:add_error(formatted_error)
                        end
                    end
                end
            end
        end
    end
end

return Declarations
