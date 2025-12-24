-- Type system utilities for code generation
-- Handles type checking, inference, matching, and C type conversion

local Types = {}

local function ctx() return _G.Codegen end

function Types.is_unsafe_pointer(type_node)
    -- Unsafe pointers (Type?) may be null and generate C pointers
    return type_node and type_node.kind == "nullable"
end

-- Deprecated alias for backwards compatibility
function Types.is_pointer_type(type_node)
    return Types.is_unsafe_pointer(type_node)
end

function Types.is_safe_pointer(type_node)
    -- Safe pointers (Type) are guaranteed non-null named types
    return type_node and type_node.kind == "named_type"
end

function Types.c_type(type_node)
    if not type_node then return "void" end
    if type_node.kind == "nullable" then
        return Types.c_type(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        -- Arrays in C are declared with the size after the name, not in the type
        -- So we return just the element type here
        return Types.c_type(type_node.element_type)
    elseif type_node.kind == "slice" then
        -- Slices are represented as pointers to the element type
        return Types.c_type(type_node.element_type) .. "*"
    elseif type_node.kind == "varargs" then
        -- Varargs are represented as pointers to the element type (like slices)
        return Types.c_type(type_node.element_type) .. "*"
    elseif type_node.kind == "map" then
        -- Maps are represented as a pointer to a map struct
        -- We'll generate a generic map structure
        local key_type_str = Types.c_type(type_node.key_type):gsub("%*", "ptr")
        local value_type_str = Types.c_type(type_node.value_type):gsub("%*", "ptr")
        return "cz_map_" .. key_type_str .. "_" .. value_type_str .. "*"
    elseif type_node.kind == "pair" then
        -- Pairs are represented as a struct with left and right fields
        local left_type_str = Types.c_type(type_node.left_type):gsub("%*", "ptr")
        local right_type_str = Types.c_type(type_node.right_type):gsub("%*", "ptr")
        return "cz_pair_" .. left_type_str .. "_" .. right_type_str
    elseif type_node.kind == "string" then
        -- Strings are represented as a struct with capacity, length, and data fields
        -- Return the struct type itself, not a pointer
        -- Pointers are handled by the nullable wrapper
        return "cz_string"
    elseif type_node.kind == "named_type" then
        local name = type_node.name
        
        -- Special case: string is now a proper struct, map to cz_string
        if name == "string" then
            return "cz_string"
        end
                
        if name == "i8" then
            return "int8_t"
        elseif name == "i16" then
            return "int16_t"
        elseif name == "i32" then
            return "int32_t"
        elseif name == "i64" then
            return "int64_t"
        elseif name == "u8" then
            return "uint8_t"
        elseif name == "u16" then
            return "uint16_t"
        elseif name == "u32" then
            return "uint32_t"
        elseif name == "u64" then
            return "uint64_t"
        elseif name == "f32" then
            return "float"
        elseif name == "f64" then
            return "double"
        elseif name == "bool" then
            return "bool"
        elseif name == "void" then
            return "void"
        elseif name == "any" then
            return "void*"
        else
            return name
        end
    else
        error("unknown type node kind: " .. tostring(type_node.kind))
    end
end

function Types.c_type_in_struct(type_node, struct_name)
    if not type_node then return "void" end
    if type_node.kind == "nullable" then
        local base_type = type_node.to
        if base_type.kind == "named_type" and base_type.name == struct_name then
            -- Self-referential unsafe pointer (Type?), use "struct Name*"
            return "struct " .. base_type.name .. "*"
        else
            return Types.c_type(base_type) .. "*"
        end
    elseif type_node.kind == "named_type" then
        -- In new pointer model, non-nullable types are pointers in C but semantically values
        local c_type = Types.c_type(type_node)
        if type_node.name == struct_name then
            -- Self-referential value type (would be invalid in C, but keep for now)
            return "struct " .. type_node.name
        else
            return c_type
        end
    else
        return Types.c_type(type_node)
    end
end

function Types.get_expr_type(expr, depth)
    -- Helper function to determine the type of an expression
    depth = depth or 0
    if depth > 10 then
        return nil
    end

    if expr.kind == "identifier" then
        local var_type = Types.get_var_type(expr.name)
        if var_type then
            if type(var_type) == "table" and var_type.kind == "nullable" then
                return Types.type_name(var_type.to)
            else
                return Types.type_name(var_type)
            end
        end
    elseif expr.kind == "field" then
        local obj_type = Types.get_expr_type(expr.object, depth + 1)
        if obj_type and ctx().structs[obj_type] then
            local struct_def = ctx().structs[obj_type]
            for _, field in ipairs(struct_def.fields) do
                if field.name == expr.field then
                    return Types.type_name(field.type)
                end
            end
        end
    end
    return nil
end

function Types.type_name(type_node)
    if type(type_node) == "string" then
        return type_node
    elseif type(type_node) == "table" then
        if type_node.kind == "nullable" then
            return Types.type_name(type_node.to)
        elseif type_node.name then
            return type_node.name
        end
    end
    return nil
end

function Types.is_struct_type(type_node)
    local type_name = Types.type_name(type_node)
    return type_name and ctx().structs[type_name] ~= nil
end

function Types.is_pointer_var(name)
    local var_info = Types.get_var_info(name)
    return var_info and var_info.type and var_info.type.kind == "nullable"
end

function Types.get_var_type(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            return var_info.type
        end
    end
    return nil
end

function Types.get_var_info(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            return var_info
        end
    end
    return nil
end

function Types.infer_type(expr)
    if expr.kind == "int" then
        return { kind = "named_type", name = "i32" }
    elseif expr.kind == "bool" then
        return { kind = "named_type", name = "bool" }
    elseif expr.kind == "string" then
        return { kind = "nullable", to = { kind = "named_type", name = "char" } }
    elseif expr.kind == "null" then
        return { kind = "nullable", to = { kind = "named_type", name = "void" } }
    elseif expr.kind == "identifier" then
        return Types.get_var_type(expr.name)
    elseif expr.kind == "field" then
        local obj_type = Types.infer_type(expr.object)
        if obj_type then
            local type_name = Types.type_name(obj_type)
            if type_name and ctx().structs[type_name] then
                local struct_def = ctx().structs[type_name]
                for _, field in ipairs(struct_def.fields) do
                    if field.name == expr.field then
                        return field.type
                    end
                end
            end
        end
    elseif expr.kind == "binary" then
        if expr.op == "==" or expr.op == "!=" or expr.op == "<" or expr.op == ">" or
           expr.op == "<=" or expr.op == ">=" or expr.op == "and" or expr.op == "or" then
            return { kind = "named_type", name = "bool" }
        else
            return Types.infer_type(expr.left)
        end
    elseif expr.kind == "unary" then
        -- Removed & and * operators - they no longer exist in the new pointer model
        return Types.infer_type(expr.operand)
    elseif expr.kind == "call" then
        if expr.callee.kind == "identifier" then
            local func_name = expr.callee.name
            local func_info = ctx().functions["__global__"] and ctx().functions["__global__"][func_name]
            if func_info then
                return func_info.return_type
            end
        elseif expr.callee.kind == "method_ref" then
            local obj_type = Types.infer_type(expr.callee.object)
            if obj_type then
                local type_name = Types.type_name(obj_type)
                if type_name and ctx().functions[type_name] then
                    local method_info = ctx().functions[type_name][expr.callee.method]
                    if method_info then
                        return method_info.return_type
                    end
                end
            end
        end
    elseif expr.kind == "static_method_call" then
        if ctx().functions[expr.type_name] then
            local method_info = ctx().functions[expr.type_name][expr.method]
            if method_info then
                return method_info.return_type
            end
        end
    end
    return nil
end

function Types.types_match(type1, type2)
    if not type1 or not type2 then return false end

    if type1.kind == "named_type" and type2.kind == "named_type" then
        return type1.name == type2.name
    elseif type1.kind == "nullable" and type2.kind == "nullable" then
        return Types.types_match(type1.to, type2.to)
    elseif type1.kind == "nullable" and type1.is_clone and type2.kind == "named_type" then
        return Types.types_match(type1.to, type2)
    elseif type2.kind == "nullable" and type2.is_clone and type1.kind == "named_type" then
        return Types.types_match(type2.to, type1)
    end
    return false
end

function Types.type_name_string(type_node)
    if not type_node then return "unknown" end

    if type_node.kind == "named_type" then
        local type_name = type_node.name
        -- Check if this is a struct type
        if ctx().structs[type_name] then
            return "struct"
        end
        -- Check if this is an interface type
        if ctx().ifaces[type_name] then
            return "iface"
        end
        -- Return the type name as-is for primitives
        return type_name
    elseif type_node.kind == "nullable" then
        if type_node.is_clone then
            return Types.type_name_string(type_node.to)
        else
            return Types.type_name_string(type_node.to) .. "?"
        end
    end
    return "unknown"
end

function Types.sizeof_expr(type_node)
    -- Returns a C expression that evaluates to the size of a type at compile time
    if not type_node then
        return "sizeof(void)"
    end
    
    local c_type_str = Types.c_type(type_node)
    return "sizeof(" .. c_type_str .. ")"
end

return Types
