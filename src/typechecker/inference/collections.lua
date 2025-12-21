-- Collection type inference
-- Handles arrays, slices, maps, pairs, and string types

local Errors = require("errors")

local Collections = {}

-- Forward declarations - will be set from init.lua
Collections.infer_type = nil
Collections.type_to_string = nil
Collections.types_compatible = nil

-- Infer the type of an array literal
function Collections.infer_array_literal_type(typechecker, expr)
    -- Check if we have an expected type hint (e.g., from variable declaration)
    local element_type = nil
    if expr.expected_type and expr.expected_type.kind == "array" then
        element_type = expr.expected_type.element_type
    end
    
    -- Handle empty array literals
    if #expr.elements == 0 then
        if element_type then
            -- Empty array with expected type - this is valid for zero initialization
            -- Use the expected type's size if available
            local size = 0
            if expr.expected_type and expr.expected_type.size and expr.expected_type.size ~= "*" then
                size = expr.expected_type.size
            end
            local inferred = { kind = "array", element_type = element_type, size = size }
            expr.inferred_type = inferred
            return inferred
        else
            local line = expr.line or 0
            local msg = "Cannot infer type of empty array literal"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end
    
    if not element_type then
        -- Even without element_type from expected_type, we should check
        -- if elements have type hints to help with inference
        -- Set expected_type on literal elements if we have it from the array type
        if expr.expected_type and expr.expected_type.kind == "array" then
            local expected_elem_type = expr.expected_type.element_type
            for _, elem in ipairs(expr.elements) do
                if elem.kind == "int" or elem.kind == "float" then
                    elem.expected_type = expected_elem_type
                end
            end
        end
        
        element_type = Collections.infer_type(typechecker, expr.elements[1])
        if not element_type then
            return nil
        end
    else
        -- If we have an expected element type, set it as a hint on each element
        -- This allows integer literals to be type-directed
        for _, elem in ipairs(expr.elements) do
            if elem.kind == "int" or elem.kind == "float" then
                elem.expected_type = element_type
            end
        end
    end
    
    -- Check that all elements have the same type or are compatible
    for i, elem in ipairs(expr.elements) do
        local elem_type = Collections.infer_type(typechecker, elem)
        if not Collections.types_compatible(element_type, elem_type, typechecker) then
            -- Check if it's a safe implicit cast (e.g., integer literal to smaller type)
            local can_cast = false
            if elem.kind == "int" and element_type.kind == "named_type" then
                -- Integer literals can be implicitly cast to any integer type if in range
                local target_type = element_type.name
                if target_type:match("^[ui]%d+$") then
                    -- For now, allow any integer literal to any integer type
                    -- Proper range checking would be done at runtime or with warnings
                    can_cast = true
                    -- Store the target type for codegen to cast
                    elem.cast_to_type = element_type
                end
            end
            
            if not can_cast then
                local line = expr.line or 0
                local msg = string.format(
                    "Array literal element %d has type '%s', expected '%s'",
                    i, Collections.type_to_string(elem_type), Collections.type_to_string(element_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
        end
    end
    
    -- Return array type with inferred size
    local inferred = { kind = "array", element_type = element_type, size = #expr.elements }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a heap-allocated array (new [elements...])
function Collections.infer_new_array_type(typechecker, expr)
    -- Similar to array_literal, but returns a pointer to the array
    if #expr.elements == 0 then
        local line = expr.line or 0
        local msg = "Cannot infer type of empty array in 'new' expression"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
    
    local element_type = Collections.infer_type(typechecker, expr.elements[1])
    if not element_type then
        return nil
    end
    
    -- Check that all elements have the same type
    for i = 2, #expr.elements do
        local elem_type = Collections.infer_type(typechecker, expr.elements[i])
        if not Collections.types_compatible(element_type, elem_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Array element %d has type '%s', expected '%s'",
                i, Collections.type_to_string(elem_type), Collections.type_to_string(element_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end
    
    -- Return a slice type (pointer to element type), which is how dynamic arrays are represented
    local inferred = { kind = "slice", element_type = element_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a map allocation (new map[K]V { key: value, ... })
function Collections.infer_new_map_type(typechecker, expr)
    -- If key_type and value_type are not provided, infer from first entry
    local key_type = expr.key_type
    local value_type = expr.value_type
    
    if not key_type or not value_type then
        if #expr.entries == 0 then
            -- Empty map - cannot infer types
            local line = expr.line or 0
            local msg = "Cannot infer type of empty map literal, use explicit type annotation"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- Infer from first entry
        key_type = Collections.infer_type(typechecker, expr.entries[1].key)
        value_type = Collections.infer_type(typechecker, expr.entries[1].value)
        
        if not key_type or not value_type then
            return nil
        end
        
        -- Store inferred types back in expr for code generation
        expr.key_type = key_type
        expr.value_type = value_type
    end
    
    -- Type checking for map entries
    for i, entry in ipairs(expr.entries) do
        local entry_key_type = Collections.infer_type(typechecker, entry.key)
        local entry_value_type = Collections.infer_type(typechecker, entry.value)
        
        -- Check key type compatibility
        if not Collections.types_compatible(key_type, entry_key_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has key type '%s', expected '%s'",
                i, Collections.type_to_string(entry_key_type), Collections.type_to_string(key_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
        
        -- Check value type compatibility
        if not Collections.types_compatible(value_type, entry_value_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has value type '%s', expected '%s'",
                i, Collections.type_to_string(entry_value_type), Collections.type_to_string(value_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end
    
    -- Return a map type (which is already represented as a pointer in C)
    local inferred = { kind = "map", key_type = key_type, value_type = value_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a map literal (map { key: value, ... })
function Collections.infer_map_literal_type(typechecker, expr)
    -- Similar to infer_new_map_type but returns non-pointer type
    local key_type = expr.key_type
    local value_type = expr.value_type
    
    if not key_type or not value_type then
        if #expr.entries == 0 then
            -- Empty map - cannot infer types
            local line = expr.line or 0
            local msg = "Cannot infer type of empty map literal, use explicit type annotation"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- Infer from first entry
        key_type = Collections.infer_type(typechecker, expr.entries[1].key)
        value_type = Collections.infer_type(typechecker, expr.entries[1].value)
        
        if not key_type or not value_type then
            return nil
        end
        
        -- Store inferred types back in expr for code generation
        expr.key_type = key_type
        expr.value_type = value_type
    end
    
    -- Type checking for map entries
    for i, entry in ipairs(expr.entries) do
        local entry_key_type = Collections.infer_type(typechecker, entry.key)
        local entry_value_type = Collections.infer_type(typechecker, entry.value)
        
        -- Check key type compatibility
        if not Collections.types_compatible(key_type, entry_key_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has key type '%s', expected '%s'",
                i, Collections.type_to_string(entry_key_type), Collections.type_to_string(key_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
        
        -- Check value type compatibility
        if not Collections.types_compatible(value_type, entry_value_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has value type '%s', expected '%s'",
                i, Collections.type_to_string(entry_value_type), Collections.type_to_string(value_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end
    
    -- Return a map type (stack allocated)
    local inferred = { kind = "map", key_type = key_type, value_type = value_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a slice expression (array[start:end])
function Collections.infer_slice_type(typechecker, expr)
    local array_type = Collections.infer_type(typechecker, expr.array)
    
    if not array_type then
        return nil
    end
    
    -- Check that the source is an array
    if array_type.kind ~= "array" then
        local line = expr.line or (expr.array and expr.array.line) or 0
        local msg = string.format(
            "Cannot slice non-array type '%s'",
            Collections.type_to_string(array_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
    
    -- Type check the indices
    local start_type = Collections.infer_type(typechecker, expr.start)
    local end_type = Collections.infer_type(typechecker, expr.end_expr)
    
    -- Check that indices are integer types
    if start_type and (start_type.kind ~= "named_type" or not start_type.name:match("^[iu]%d+$")) then
        local line = expr.line or 0
        local msg = string.format(
            "Slice start index must be an integer type, got '%s'",
            Collections.type_to_string(start_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
    
    if end_type and (end_type.kind ~= "named_type" or not end_type.name:match("^[iu]%d+$")) then
        local line = expr.line or 0
        local msg = string.format(
            "Slice end index must be an integer type, got '%s'",
            Collections.type_to_string(end_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
    
    -- Return a slice type
    local slice_type = { kind = "slice", element_type = array_type.element_type }
    expr.inferred_type = slice_type
    return slice_type
end

-- Infer the type of a pair allocation (new pair { left, right })
function Collections.infer_new_pair_type(typechecker, expr)
    -- Infer types from the left and right expressions
    local left_type = Collections.infer_type(typechecker, expr.left)
    local right_type = Collections.infer_type(typechecker, expr.right)
    
    if not left_type or not right_type then
        return nil
    end
    
    -- Store inferred types back in expr for code generation
    expr.left_type = left_type
    expr.right_type = right_type
    
    -- Return a pointer to pair type (heap allocated)
    local pair_type = { kind = "pair", left_type = left_type, right_type = right_type }
    local inferred = { kind = "nullable", to = pair_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a pair literal (pair { left, right })
function Collections.infer_pair_literal_type(typechecker, expr)
    -- Infer types from the left and right expressions
    local left_type = Collections.infer_type(typechecker, expr.left)
    local right_type = Collections.infer_type(typechecker, expr.right)
    
    if not left_type or not right_type then
        return nil
    end
    
    -- Store inferred types back in expr for code generation
    expr.left_type = left_type
    expr.right_type = right_type
    
    -- Return a pair type (stack allocated)
    local inferred = { kind = "pair", left_type = left_type, right_type = right_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a new string (new string "text")
function Collections.infer_new_string_type(typechecker, expr)
    -- String literal value is stored in expr.value
    -- Return a pointer to string type (heap allocated)
    local string_type = { kind = "string" }
    local inferred = { kind = "nullable", to = string_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a string literal (string "text")
function Collections.infer_string_literal_type(typechecker, expr)
    -- String literal value is stored in expr.value
    -- Return a string type (stack allocated)
    local inferred = { kind = "string" }
    expr.inferred_type = inferred
    return inferred
end

return Collections
