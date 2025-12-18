-- Type utility functions for type checking
-- Handles type compatibility checking, type aliases, and type-to-string conversions

local Types = {}

-- Resolve type aliases
function Types.resolve_type_alias(typechecker, type_node)
    if not type_node or type_node.kind ~= "named_type" then
        return type_node
    end

    local alias_target = typechecker.type_aliases[type_node.name]
    if not alias_target then
        return type_node
    end

    -- Parse the alias target string
    -- Handle pointer types like "char*" or "char *" (with optional spaces)
    local base_type_match = alias_target:match("^(%w+)%s*%*$")
    if base_type_match then
        -- It's a pointer type like "char*"
        return {
            kind = "nullable",
            to = { kind = "named_type", name = base_type_match }
        }
    else
        -- It's a simple named type
        return { kind = "named_type", name = alias_target }
    end
end

-- Check if two types are compatible
function Types.types_compatible(type1, type2, typechecker)
    if not type1 or not type2 then
        return false
    end

    -- Resolve type aliases if typechecker is available
    if typechecker then
        type1 = Types.resolve_type_alias(typechecker, type1)
        type2 = Types.resolve_type_alias(typechecker, type2)
    end

    -- Allow void? (null) to be compatible with any unsafe pointer type
    if type1.kind == "nullable" and type1.to and type1.to.name == "void" then
        if type2.kind == "nullable" then
            return true  -- null can be assigned to any unsafe pointer
        end
    end
    if type2.kind == "nullable" and type2.to and type2.to.name == "void" then
        if type1.kind == "nullable" then
            return true  -- any unsafe pointer can accept null
        end
    end

    -- Allow any type (void?) to accept any pointer/struct
    -- any can hold any pointer, so any Type (safe) or Type? (unsafe) can be assigned to any
    if type1.kind == "named_type" and type1.name == "any" then
        -- any can accept:
        -- - Any named type (struct, etc.) - safe pointer - will take its address
        -- - Any unsafe pointer type (Type?)
        if type2.kind == "named_type" or type2.kind == "nullable" then
            return true
        end
    end

    if type1.kind == "named_type" and type2.kind == "named_type" then
        return type1.name == type2.name
    elseif type1.kind == "nullable" and type2.kind == "named_type" then
        -- Allow safe pointer to be assigned to unsafe pointer (safe conversion)
        -- e.g., Data (safe) can be assigned to Data? (unsafe)
        -- Check if the safe pointer type (type2) matches the inner type of unsafe pointer (type1.to)
        return Types.types_compatible(type1.to, type2, typechecker)
    elseif type1.kind == "nullable" and type2.kind == "nullable" then
        return Types.types_compatible(type1.to, type2.to, typechecker)
    elseif type1.kind == "nullable" and type1.is_clone and type2.kind == "named_type" then
        return Types.types_compatible(type1.to, type2, typechecker)
    elseif type2.kind == "nullable" and type2.is_clone and type1.kind == "named_type" then
        return Types.types_compatible(type2.to, type1, typechecker)
    elseif type1.kind == "array" and type2.kind == "array" then
        -- Arrays are compatible if element types match and sizes match
        if type1.size ~= type2.size then
            return false
        end
        return Types.types_compatible(type1.element_type, type2.element_type, typechecker)
    elseif type1.kind == "slice" and type2.kind == "slice" then
        -- Slices are compatible if element types match
        return Types.types_compatible(type1.element_type, type2.element_type, typechecker)
    elseif type1.kind == "map" and type2.kind == "map" then
        -- Maps are compatible if key and value types match
        return Types.types_compatible(type1.key_type, type2.key_type, typechecker) and
               Types.types_compatible(type1.value_type, type2.value_type, typechecker)
    elseif type1.kind == "pair" and type2.kind == "pair" then
        -- Pairs are compatible if left and right types match
        return Types.types_compatible(type1.left_type, type2.left_type, typechecker) and
               Types.types_compatible(type1.right_type, type2.right_type, typechecker)
    elseif type1.kind == "string" and type2.kind == "string" then
        -- Strings are always compatible
        return true
    end

    return false
end

-- Check if a type is bool
function Types.is_bool_type(type_node)
    return type_node and
           type_node.kind == "named_type" and
           type_node.name == "bool"
end

-- Get the base type name from a type node
function Types.get_base_type_name(type_node)
    if not type_node then
        return nil
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "nullable" then
        return Types.get_base_type_name(type_node.to)
    end

    return nil
end

-- Convert a type to a string representation
function Types.type_to_string(type_node)
    if not type_node then
        return "unknown"
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "nullable" then
        if type_node.is_clone then
            return Types.type_to_string(type_node.to)
        else
            return Types.type_to_string(type_node.to) .. "?"
        end
    elseif type_node.kind == "array" then
        return Types.type_to_string(type_node.element_type) .. "[" .. tostring(type_node.size) .. "]"
    elseif type_node.kind == "slice" then
        return Types.type_to_string(type_node.element_type) .. "[]"
    elseif type_node.kind == "varargs" then
        return Types.type_to_string(type_node.element_type) .. "..."
    elseif type_node.kind == "map" then
        return "map[" .. Types.type_to_string(type_node.key_type) .. "]" .. Types.type_to_string(type_node.value_type)
    elseif type_node.kind == "pair" then
        return "pair<" .. Types.type_to_string(type_node.left_type) .. ":" .. Types.type_to_string(type_node.right_type) .. ">"
    elseif type_node.kind == "string" then
        return "string"
    end

    return "unknown"
end

return Types
