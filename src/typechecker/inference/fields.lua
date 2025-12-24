-- Field and struct type inference
-- Handles field access, array indexing, struct literals, and new expressions

local Resolver = require("typechecker.resolver")
local Errors = require("errors")

local Fields = {}

-- Forward declarations - will be set from init.lua
Fields.infer_type = nil
Fields.get_base_type_name = nil
Fields.type_to_string = nil
Fields.types_compatible = nil

-- Helper: Assign field names for positional arguments based on struct definition order
local function assign_positional_field_names(expr, struct_def, struct_name, typechecker)
    if not expr.is_positional then
        return true
    end
    
    for i, field_init in ipairs(expr.fields) do
        if i <= #struct_def.fields then
            field_init.name = struct_def.fields[i].name
        else
            -- Too many positional arguments
            local line = expr.line or 0
            local msg = string.format(
                "Too many positional arguments for struct '%s': expected %d, got %d",
                struct_name,
                #struct_def.fields,
                #expr.fields
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return false
        end
    end
    return true
end

-- Helper: Check if implicit cast is safe and wrap if needed
local function try_implicit_cast(expected_type, value_type, value_expr, context_msg, line, typechecker)
    if Fields.types_compatible(expected_type, value_type, typechecker) then
        return value_type  -- Types match, no cast needed
    end
    
    -- Types don't match - check if implicit cast is safe
    local function is_safe_implicit_cast(from_type, to_type, init_expr)
        if not from_type or not to_type then
            return false
        end
        
        -- Both must be named types (primitive types)
        if from_type.kind ~= "named_type" or to_type.kind ~= "named_type" then
            return false
        end
        
        local from_name = from_type.name
        local to_name = to_type.name
        
        -- Define type sizes and signedness
        local type_info = {
            i8 = {size = 8, signed = true},
            i16 = {size = 16, signed = true},
            i32 = {size = 32, signed = true},
            i64 = {size = 64, signed = true},
            u8 = {size = 8, signed = false},
            u16 = {size = 16, signed = false},
            u32 = {size = 32, signed = false},
            u64 = {size = 64, signed = false},
            f32 = {size = 32, signed = true, float = true},
            f64 = {size = 64, signed = true, float = true},
        }
        
        local from_info = type_info[from_name]
        local to_info = type_info[to_name]
        
        if not from_info or not to_info then
            return false
        end
        
        -- If init is a literal integer and target is any integer type, allow it
        if init_expr and init_expr.kind == "int" and not to_info.float then
            local value = init_expr.value
            if to_info.signed then
                local max = 2^(to_info.size - 1) - 1
                local min = -(2^(to_info.size - 1))
                if value >= min and value <= max then
                    return true
                end
            else
                local max = 2^to_info.size - 1
                if value >= 0 and value <= max then
                    return true
                end
            end
        end
        
        -- Otherwise, safe if same signedness and target is larger or equal
        return from_info.signed == to_info.signed and to_info.size >= from_info.size
    end
    
    if is_safe_implicit_cast(value_type, expected_type, value_expr) then
        -- Wrap in implicit cast
        local cast_node = {
            kind = "implicit_cast",
            target_type = expected_type,
            expr = value_expr,
            line = line
        }
        -- Replace the value expression with the cast
        -- Note: We need to modify the parent's reference, so we return the cast
        return expected_type, cast_node
    else
        -- Error: incompatible types
        typechecker:add_error(context_msg)
        return nil
    end
end

-- Infer the type of a field access
function Fields.infer_field_type(typechecker, expr)
    -- Check if object is a module alias (e.g., os in os.linux where cz.os is imported)
    if expr.object.kind == "identifier" then
        local obj_name = expr.object.name
        for _, import in ipairs(typechecker.imports) do
            if import.alias == obj_name then
                -- This is accessing a field on a module
                import.used = true
                
                -- Handle specific module types
                if import.path == "cz.os" then
                    -- This is accessing a field on the os module (e.g., os.linux)
                    -- The os module exposes an "os" struct with the OS fields
                    -- We treat the module alias as if it were an instance of the os struct
                    local os_type = { kind = "named_type", name = "os" }
                    expr.object.inferred_type = os_type
                    -- Continue to normal field inference which will look up fields in the os struct
                    break
                end
                -- For other modules, we can add handling as needed
            end
        end
    end
    
    -- Check if this is cz.os access (legacy - now use os.field directly)
    if expr.object.kind == "identifier" and expr.object.name == "cz" and expr.field == "os" then
        -- Check if cz.os module is imported
        local cz_os_imported = false
        for _, import in ipairs(typechecker.imports) do
            local import_path = type(import.path) == "table" and table.concat(import.path, ".") or import.path
            if import_path == "cz.os" or import.alias == "cz" then
                cz_os_imported = true
                import.used = true
                break
            end
        end
        
        if not cz_os_imported then
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = "Module 'cz.os' must be imported to use cz.os (use: #import cz.os)"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- Return _cz_os_t* (pointer to struct from raw C)
        local os_type = { kind = "nullable", to = { kind = "named_type", name = "_cz_os_t" } }
        expr.inferred_type = os_type
        return os_type
    end
    
    -- Check if this is enum member access (e.g., Status.SUCCESS)
    -- This happens when object is an identifier that refers to an enum type name
    if expr.object.kind == "identifier" then
        local enum_name = expr.object.name
        local enum_def = typechecker.enums[enum_name]
        if enum_def then
            -- This is an enum member access
            -- Check if the field is a valid enum value
            local found = false
            for _, value in ipairs(enum_def.values) do
                if value.name == expr.field then
                    found = true
                    break
                end
            end
            if found then
                -- Enum member access returns the enum type
                local enum_type = { kind = "named_type", name = enum_name }
                expr.inferred_type = enum_type
                return enum_type
            else
                local line = expr.line or (expr.object and expr.object.line) or 0
                local msg = string.format(
                    "Enum value '%s' not found in enum '%s'",
                    expr.field, enum_name
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
        end
    end
    
    local obj_type = Fields.infer_type(typechecker, expr.object)
    if not obj_type then
        return nil
    end
    
    -- Dereference pointer if accessing field through pointer
    local base_type = obj_type
    if obj_type.kind == "nullable" then
        base_type = obj_type.to
    end

    -- Handle map type fields
    if base_type.kind == "map" then
        if expr.field == "keys" then
            local keys_type = { kind = "slice", element_type = base_type.key_type }
            expr.inferred_type = keys_type
            return keys_type
        elseif expr.field == "values" then
            local values_type = { kind = "slice", element_type = base_type.value_type }
            expr.inferred_type = values_type
            return values_type
        elseif expr.field == "size" or expr.field == "capacity" then
            local int_type = { kind = "named_type", name = "i32" }
            expr.inferred_type = int_type
            return int_type
        else
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = string.format(
                "Field '%s' not found in map type (available: keys, values, size, capacity)",
                expr.field
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end
    
    -- Handle pair type fields
    if base_type.kind == "pair" then
        if expr.field == "left" then
            expr.inferred_type = base_type.left_type
            return base_type.left_type
        elseif expr.field == "right" then
            expr.inferred_type = base_type.right_type
            return base_type.right_type
        else
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = string.format(
                "Field '%s' not found in pair type (available: left, right)",
                expr.field
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end
    
    -- Handle string type fields (memory-safe: no direct data access)
    if base_type.kind == "string" then
        if expr.field == "length" then
            expr.inferred_type = { kind = "named_type", name = "i32" }
            return expr.inferred_type
        elseif expr.field == "capacity" then
            expr.inferred_type = { kind = "named_type", name = "i32" }
            return expr.inferred_type
        else
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = string.format(
                "Field '%s' not found in string type (available: length, capacity). Use .cstr() method for C-string access.",
                expr.field
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end
    
    -- Handle os struct fields (from cz.os module)
    if base_type.kind == "named_type" and base_type.name == "os" then
        if expr.field == "name" or expr.field == "version" or expr.field == "kernel" then
            -- String fields
            local string_ptr_type = { kind = "nullable", to = { kind = "named_type", name = "i8" } }
            expr.inferred_type = string_ptr_type
            return string_ptr_type
        elseif expr.field == "linux" or expr.field == "windows" or expr.field == "macos" then
            -- Boolean fields
            local bool_type = { kind = "named_type", name = "bool" }
            expr.inferred_type = bool_type
            return bool_type
        else
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = string.format(
                "Field '%s' not found in os module (available: name, version, kernel, linux, windows, macos)",
                expr.field
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end
    
    -- Handle _cz_os_t struct fields (special built-in struct from raw C)
    if base_type.kind == "named_type" and base_type.name == "_cz_os_t" then
        if expr.field == "name" or expr.field == "version" or expr.field == "kernel" then
            -- String fields
            local string_ptr_type = { kind = "nullable", to = { kind = "named_type", name = "i8" } }
            expr.inferred_type = string_ptr_type
            return string_ptr_type
        elseif expr.field == "linux" or expr.field == "windows" or expr.field == "macos" then
            -- Boolean fields
            local bool_type = { kind = "named_type", name = "bool" }
            expr.inferred_type = bool_type
            return bool_type
        else
            local line = expr.line or (expr.object and expr.object.line) or 0
            local msg = string.format(
                "Field '%s' not found in cz.os (available: name, version, kernel, linux, windows, macos)",
                expr.field
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    local type_name = Fields.get_base_type_name(base_type)
    local struct_def = Resolver.resolve_struct(typechecker, type_name)

    if struct_def then
        for _, field in ipairs(struct_def.fields) do
            if field.name == expr.field then
                -- Check if field is private (prv keyword)
                if field.is_private then
                    -- Private field can only be accessed from within methods of the same struct
                    local is_internal_access = false
                    if typechecker.current_function and typechecker.current_function.receiver_type then
                        if typechecker.current_function.receiver_type == type_name then
                            is_internal_access = true
                        end
                    end
                    
                    if not is_internal_access then
                        local line = expr.line or (expr.object and expr.object.line) or 0
                        local msg = string.format(
                            "Cannot access private field '%s' in '%s'",
                            expr.field, type_name
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.PRIVATE_ACCESS, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                        return nil
                    end
                end
                
                -- Check if struct itself is module-private (not marked pub)
                if not struct_def.is_public then
                    -- Check if we're accessing from the same module
                    -- Note: struct_def comes from the module that defined it
                    -- We need to track which module defined each struct
                    -- For now, if not public and we're in a different module context, block it
                    -- This is a simplification - proper implementation would track defining module
                end
                
                expr.inferred_type = field.type
                return field.type
            end
        end
        local line = expr.line or (expr.object and expr.object.line) or 0
        local msg = string.format(
            "Field '%s' not found in struct '%s'",
            expr.field, type_name
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.FIELD_NOT_FOUND, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    else
        local line = expr.line or (expr.object and expr.object.line) or 0
        local msg = string.format(
            "Cannot access field '%s' on non-struct type '%s'",
            expr.field, type_name or "unknown"
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end

    return nil
end

-- Infer the type of an array index access with bounds checking
function Fields.infer_index_type(typechecker, expr)
    local array_type = Fields.infer_type(typechecker, expr.array)
    local index_type = Fields.infer_type(typechecker, expr.index)

    if not array_type then
        return nil
    end

    -- Check that array is actually an array, slice, or varargs type
    if array_type.kind ~= "array" and array_type.kind ~= "slice" and array_type.kind ~= "varargs" then
        local line = expr.line or (expr.array and expr.array.line) or 0
        local msg = string.format(
            "Cannot index non-array type '%s'",
            Fields.type_to_string(array_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end

    -- Check that index is an integer type (only i8, i16, i32, i64, u8, u16, u32, u64)
    -- Floating point types are NOT allowed for array indices
    if not index_type or index_type.kind ~= "named_type" or
       not index_type.name:match("^[iu]%d+$") then
        local line = expr.line or (expr.index and expr.index.line) or 0
        local msg = string.format(
            "Array index must be an integer type, got '%s'",
            Fields.type_to_string(index_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end

    -- Compile-time bounds checking: check if index is a constant integer (only for arrays, not slices or varargs)
    if array_type.kind == "array" and expr.index.kind == "int" and array_type.size ~= "*" then
        local index_value = expr.index.value
        local array_size = array_type.size

        if index_value < 0 or index_value >= array_size then
            local line = expr.line or (expr.index and expr.index.line) or 0
            local msg = string.format(
                "Index %d is out of range [0, %d) for array of size %d.",
                index_value, array_size, array_size
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.ARRAY_INDEX_OUT_OF_BOUNDS, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    -- Return the element type of the array or slice
    expr.inferred_type = array_type.element_type
    return array_type.element_type
end

-- Infer the type of a struct literal
function Fields.infer_struct_literal_type(typechecker, expr)
    if not expr.struct_name and not expr.type_name then
        typechecker:add_error("Struct literal missing type_name")
        return nil
    end

    local struct_name = expr.struct_name or expr.type_name
    local struct_def = Resolver.resolve_struct(typechecker, struct_name)

    if struct_def then
        -- Update the expression to use the actual struct name (resolve aliases)
        local actual_struct_name = struct_def.name
        if expr.struct_name then
            expr.struct_name = actual_struct_name
        end
        if expr.type_name then
            expr.type_name = actual_struct_name
        end
        
        -- If using positional arguments, assign field names based on struct definition order
        if not assign_positional_field_names(expr, struct_def, actual_struct_name, typechecker) then
            return nil
        end
        
        -- Type check each field
        for _, field_init in ipairs(expr.fields) do
            local field_type = nil
            for _, field_def in ipairs(struct_def.fields) do
                if field_def.name == field_init.name then
                    field_type = field_def.type
                    break
                end
            end

            if field_type then
                local value_type = Fields.infer_type(typechecker, field_init.value)
                
                -- Store field type for codegen
                field_init.expected_type = field_type
                field_init.value_type = value_type
                
                local result_type, cast_node = try_implicit_cast(
                    field_type,
                    value_type,
                    field_init.value,
                    string.format(
                        "Type mismatch for field '%s' in struct '%s': expected %s, got %s",
                        field_init.name,
                        actual_struct_name,
                        Fields.type_to_string(field_type),
                        Fields.type_to_string(value_type)
                    ),
                    expr.line or 0,
                    typechecker
                )
                if cast_node then
                    -- Replace the value with the implicit cast
                    field_init.value = cast_node
                end
            end
        end

        local inferred = { kind = "named_type", name = actual_struct_name }
        expr.inferred_type = inferred
        return inferred
    else
        local line = expr.line or 0
        local msg = string.format("Undefined struct: %s", struct_name or "nil")
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.UNDEFINED_STRUCT, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
end

-- Infer the type of a new expression (heap or stack allocation)
function Fields.infer_new_type(typechecker, expr)
    local struct_def = Resolver.resolve_struct(typechecker, expr.type_name)

    if struct_def then
        -- If using positional arguments, assign field names based on struct definition order
        if not assign_positional_field_names(expr, struct_def, expr.type_name, typechecker) then
            return nil
        end
        
        -- Type check each field (similar to struct literal)
        for _, field_init in ipairs(expr.fields) do
            local field_type = nil
            for _, field_def in ipairs(struct_def.fields) do
                if field_def.name == field_init.name then
                    field_type = field_def.type
                    break
                end
            end

            if field_type then
                local value_type = Fields.infer_type(typechecker, field_init.value)
                local result_type, cast_node = try_implicit_cast(
                    field_type,
                    value_type,
                    field_init.value,
                    string.format(
                        "Type mismatch for field '%s' in struct '%s': expected %s, got %s",
                        field_init.name,
                        expr.type_name,
                        Fields.type_to_string(field_type),
                        Fields.type_to_string(value_type)
                    ),
                    expr.line or 0,
                    typechecker
                )
                if cast_node then
                    -- Replace the value with the implicit cast
                    field_init.value = cast_node
                end
            end
        end

        -- In explicit pointer model, new returns a pointer to the type
        local inferred = { kind = "nullable", to = { kind = "named_type", name = expr.type_name } }
        expr.inferred_type = inferred
        return inferred
    else
        local line = expr.line or 0
        local msg = string.format("Undefined struct: %s", expr.type_name or "nil")
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.UNDEFINED_STRUCT, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
end

return Fields
