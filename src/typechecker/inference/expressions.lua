-- Expression type inference
-- Handles binary and unary expressions

local Errors = require("errors")

local Expressions = {}

-- Forward declaration - will be set from init.lua
Expressions.infer_type = nil
Expressions.type_to_string = nil

-- Infer the type of a binary expression
function Expressions.infer_binary_type(typechecker, expr)
    local left_type = Expressions.infer_type(typechecker, expr.left)
    local right_type = Expressions.infer_type(typechecker, expr.right)

    -- Check for division by zero literal
    if expr.op == "/" then
        if expr.right.kind == "int" and expr.right.value == 0 then
            local line = expr.line or (expr.right and expr.right.line) or 0
            local msg = "Division by zero"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.DIVISION_BY_ZERO, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    -- Comparison and logical operators return bool
    if expr.op == "==" or expr.op == "!=" or
       expr.op == "<" or expr.op == ">" or
       expr.op == "<=" or expr.op == ">=" then
        -- Check that both operands are of compatible types
        if left_type and right_type then
            local left_is_numeric = left_type.kind == "named_type" and
                                   (left_type.name:match("^[iuf]%d+$") ~= nil)
            local right_is_numeric = right_type.kind == "named_type" and
                                    (right_type.name:match("^[iuf]%d+$") ~= nil)
            local left_is_bool = left_type.kind == "named_type" and left_type.name == "bool"
            local right_is_bool = right_type.kind == "named_type" and right_type.name == "bool"
            local left_is_pointer = left_type.kind == "nullable"
            local right_is_pointer = right_type.kind == "nullable"
            
            -- Check for incompatible type families
            -- Can't compare numeric with bool, or bool with pointer, etc.
            if (left_is_numeric and right_is_bool) or (left_is_bool and right_is_numeric) then
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare %s with %s: incompatible types",
                    Expressions.type_to_string(left_type),
                    Expressions.type_to_string(right_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
            
            if (left_is_bool and right_is_pointer) or (left_is_pointer and right_is_bool) then
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare %s with %s: incompatible types",
                    Expressions.type_to_string(left_type),
                    Expressions.type_to_string(right_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
            
            if (left_is_numeric and right_is_pointer) or (left_is_pointer and right_is_numeric) then
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare %s with %s: incompatible types",
                    Expressions.type_to_string(left_type),
                    Expressions.type_to_string(right_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
            
            -- Check for struct/named type mismatches (except for built-in types)
            -- For == and !=, both types must be the same
            -- For <, >, <=, >=, both types must be numeric or both must be the same type
            if left_type.kind == "named_type" and right_type.kind == "named_type" then
                local ordering_op = (expr.op == "<" or expr.op == ">" or expr.op == "<=" or expr.op == ">=")
                
                -- Check if types are enums (enums are allowed in comparisons since they're int32_t in C)
                local left_is_enum = typechecker.enums[left_type.name] ~= nil
                local right_is_enum = typechecker.enums[right_type.name] ~= nil
                
                -- Check if types are user-defined structs (not built-in types or enums)
                local left_is_struct = not left_is_numeric and not left_is_bool and not left_is_enum and
                                      left_type.name ~= "void" and left_type.name ~= "any"
                local right_is_struct = not right_is_numeric and not right_is_bool and not right_is_enum and
                                       right_type.name ~= "void" and right_type.name ~= "any"
                
                -- For ordering operators, require both to be numeric or both to be enums
                if ordering_op and not (left_is_numeric and right_is_numeric) and not (left_is_enum and right_is_enum) then
                    local line = expr.line or (expr.left and expr.left.line) or 0
                    local msg = string.format(
                        "Cannot use ordering operator %s on non-numeric types %s and %s",
                        expr.op,
                        Expressions.type_to_string(left_type),
                        Expressions.type_to_string(right_type)
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                    return nil
                end
                
                -- For equality operators, don't allow struct comparisons (C doesn't support them)
                -- But allow enum comparisons (they're int32_t in C)
                if not ordering_op and left_is_struct and right_is_struct then
                    local line = expr.line or (expr.left and expr.left.line) or 0
                    local msg = string.format(
                        "Cannot compare struct types %s and %s directly (use field-by-field comparison)",
                        Expressions.type_to_string(left_type),
                        Expressions.type_to_string(right_type)
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                    return nil
                end
                
                -- For all comparison operators, types must match (or both be numeric for widening)
                if left_type.name ~= right_type.name then
                    -- Allow numeric widening comparisons (e.g., i32 vs i64)
                    if not (left_is_numeric and right_is_numeric) then
                        local line = expr.line or (expr.left and expr.left.line) or 0
                        local msg = string.format(
                            "Cannot compare %s with %s: incompatible types",
                            Expressions.type_to_string(left_type),
                            Expressions.type_to_string(right_type)
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                        return nil
                    end
                end
            end
            
            -- Check for array type mismatches
            if left_type.kind == "array" and right_type.kind == "array" then
                -- Arrays cannot be directly compared
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare arrays directly: %s and %s",
                    Expressions.type_to_string(left_type),
                    Expressions.type_to_string(right_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
            
            -- Check for array vs non-array mismatches
            if (left_type.kind == "array" and right_type.kind ~= "array") or
               (left_type.kind ~= "array" and right_type.kind == "array") then
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare %s with %s: incompatible types",
                    Expressions.type_to_string(left_type),
                    Expressions.type_to_string(right_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
        end
        
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    end
    
    if expr.op == "and" or expr.op == "or" or expr.op == "is" then
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    end

    -- Check for forbidden pointer arithmetic
    if expr.op == "+" or expr.op == "-" then
        local left_is_pointer = left_type and left_type.kind == "nullable"
        local right_is_pointer = right_type and right_type.kind == "nullable"
        -- Check for any numeric type including floats (i32, u64, f32, f64, etc.)
        -- We forbid ALL numeric + pointer operations for safety
        local left_is_numeric = left_type and left_type.kind == "named_type" and
                                (left_type.name:match("^[iuf]%d+$") ~= nil)
        local right_is_numeric = right_type and right_type.kind == "named_type" and
                                 (right_type.name:match("^[iuf]%d+$") ~= nil)

        -- Forbid pointer + numeric, numeric + pointer, pointer - numeric
        if (left_is_pointer and right_is_numeric) or (left_is_numeric and right_is_pointer) then
            local line = expr.line or (expr.left and expr.left.line) or 0
            local msg = string.format(
                "Cannot %s pointer and numeric type.",
                expr.op == "+" and "add" or "subtract"
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.POINTER_ARITHMETIC_FORBIDDEN, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end

        -- Forbid pointer - pointer (technically could be allowed but we're being strict)
        if left_is_pointer and right_is_pointer and expr.op == "-" then
            local line = expr.line or (expr.left and expr.left.line) or 0
            local msg = "Cannot subtract two pointers."
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.POINTER_ARITHMETIC_FORBIDDEN, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    -- Arithmetic operators return the left operand's type
    -- (In a more sophisticated system, we'd do numeric promotion)
    expr.inferred_type = left_type
    return left_type
end

-- Infer the type of a unary expression
function Expressions.infer_unary_type(typechecker, expr)
    local operand_type = Expressions.infer_type(typechecker, expr.operand)

    -- Removed & (address-of) and * (dereference) operators - they no longer exist
    if expr.op == "!" or expr.op == "not" then
        -- Logical not
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    else
        -- Other unary operators preserve the operand type
        expr.inferred_type = operand_type
        return operand_type
    end
end

return Expressions
