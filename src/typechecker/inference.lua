-- Type inference and type checking utilities
-- Handles type inference for expressions and type compatibility checking

local Resolver = require("typechecker.resolver")
local Errors = require("errors")
local Directives = require("src.directives")

local Inference = {}

-- Infer the type of an expression
function Inference.infer_type(typechecker, expr)
    if not expr then
        return nil
    end

    if expr.kind == "int" then
        local inferred = { kind = "named_type", name = "i32" }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "bool" then
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "string" then
        local inferred = { kind = "pointer", to = { kind = "named_type", name = "char" } }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "null" then
        local inferred = { kind = "pointer", to = { kind = "named_type", name = "void" } }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "identifier" then
        local var_info = Resolver.resolve_name(typechecker, expr.name)
        if var_info then
            expr.inferred_type = var_info.type
            return var_info.type
        else
            local line = expr.line or 0
            local msg = string.format("Undeclared identifier: %s", expr.name)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    elseif expr.kind == "field" then
        return Inference.infer_field_type(typechecker, expr)
    elseif expr.kind == "index" then
        return Inference.infer_index_type(typechecker, expr)
    elseif expr.kind == "binary" then
        return Inference.infer_binary_type(typechecker, expr)
    elseif expr.kind == "unary" then
        return Inference.infer_unary_type(typechecker, expr)
    elseif expr.kind == "is_check" then
        -- Type check operator always returns bool
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "clone" then
        -- Clone operator returns a pointer to the cloned value
        if expr.target_type then
            -- clone<Type> returns Type*
            local ptr_type = { kind = "pointer", to = expr.target_type }
            expr.inferred_type = ptr_type
            return ptr_type
        else
            local source_type = Inference.infer_type(typechecker, expr.expr)
            -- If source is a pointer, keep it; otherwise wrap in pointer
            local result_type
            if source_type and source_type.kind == "pointer" then
                result_type = source_type
            else
                result_type = { kind = "pointer", to = source_type }
            end
            expr.inferred_type = result_type
            return result_type
        end
    elseif expr.kind == "null_check" then
        -- Null check operator (!) returns the operand type (asserts non-null)
        local operand_type = Inference.infer_type(typechecker, expr.operand)
        expr.inferred_type = operand_type
        return operand_type
    elseif expr.kind == "call" then
        return Inference.infer_call_type(typechecker, expr)
    elseif expr.kind == "method_call" then
        return Inference.infer_method_call_type(typechecker, expr)
    elseif expr.kind == "static_method_call" then
        return Inference.infer_static_method_call_type(typechecker, expr)
    elseif expr.kind == "struct_literal" then
        return Inference.infer_struct_literal_type(typechecker, expr)
    elseif expr.kind == "new_heap" or expr.kind == "new_stack" then
        return Inference.infer_new_type(typechecker, expr)
    elseif expr.kind == "new_array" then
        return Inference.infer_new_array_type(typechecker, expr)
    elseif expr.kind == "new_map" then
        return Inference.infer_new_map_type(typechecker, expr)
    elseif expr.kind == "cast" then
        local target_type = expr.to_type or expr.target_type
        expr.inferred_type = target_type
        return target_type
    elseif expr.kind == "optional_cast" then
        -- Optional cast returns the target type directly
        -- On failure, returns default/zero value that can be overridden by 'or'
        local target_type = expr.to_type or expr.target_type
        expr.inferred_type = target_type
        return target_type
    elseif expr.kind == "safe_cast" then
        -- #cast<Type>(value, fallback) - safe cast with fallback
        -- Delegate to Directives module
        return Directives.typecheck_safe_cast(expr, typechecker, Inference.infer_type, Inference.types_compatible, Inference.type_to_string)
    elseif expr.kind == "sizeof" or expr.kind == "type_of" then
        -- sizeof and type return i32 and string respectively
        -- sizeof returns the size in bytes as i32
        -- type_of returns a string
        local result_type
        if expr.kind == "sizeof" then
            result_type = { kind = "named_type", name = "i32" }
        else
            result_type = { kind = "pointer", to = { kind = "named_type", name = "char" } }
        end
        expr.inferred_type = result_type
        return result_type
    elseif expr.kind == "directive" then
        return Inference.infer_directive_type(expr)
    elseif expr.kind == "compound_assign" then
        return Inference.infer_type(typechecker, expr.target)
    elseif expr.kind == "array_literal" then
        return Inference.infer_array_literal_type(typechecker, expr)
    elseif expr.kind == "slice" then
        return Inference.infer_slice_type(typechecker, expr)
    end

    return nil
end

-- Infer the type of a field access
function Inference.infer_field_type(typechecker, expr)
    local obj_type = Inference.infer_type(typechecker, expr.object)
    if not obj_type then
        return nil
    end

    -- Handle map type fields
    if obj_type.kind == "map" then
        if expr.field == "keys" then
            local keys_type = { kind = "slice", element_type = obj_type.key_type }
            expr.inferred_type = keys_type
            return keys_type
        elseif expr.field == "values" then
            local values_type = { kind = "slice", element_type = obj_type.value_type }
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

    local type_name = Inference.get_base_type_name(obj_type)
    local struct_def = Resolver.resolve_struct(typechecker, type_name)

    if struct_def then
        for _, field in ipairs(struct_def.fields) do
            if field.name == expr.field then
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
function Inference.infer_index_type(typechecker, expr)
    local array_type = Inference.infer_type(typechecker, expr.array)
    local index_type = Inference.infer_type(typechecker, expr.index)

    if not array_type then
        return nil
    end

    -- Check that array is actually an array, slice, or varargs type
    if array_type.kind ~= "array" and array_type.kind ~= "slice" and array_type.kind ~= "varargs" then
        local line = expr.line or (expr.array and expr.array.line) or 0
        local msg = string.format(
            "Cannot index non-array type '%s'",
            Inference.type_to_string(array_type)
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
            Inference.type_to_string(index_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end

    -- Compile-time bounds checking: check if index is a constant integer (only for arrays, not slices or varargs)
    if array_type.kind == "array" and expr.index.kind == "int" then
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

-- Infer the type of a binary expression
function Inference.infer_binary_type(typechecker, expr)
    local left_type = Inference.infer_type(typechecker, expr.left)
    local right_type = Inference.infer_type(typechecker, expr.right)

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
            local left_is_pointer = left_type.kind == "pointer"
            local right_is_pointer = right_type.kind == "pointer"
            
            -- Check for incompatible type families
            -- Can't compare numeric with bool, or bool with pointer, etc.
            if (left_is_numeric and right_is_bool) or (left_is_bool and right_is_numeric) then
                local line = expr.line or (expr.left and expr.left.line) or 0
                local msg = string.format(
                    "Cannot compare %s with %s: incompatible types",
                    Inference.type_to_string(left_type),
                    Inference.type_to_string(right_type)
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
                    Inference.type_to_string(left_type),
                    Inference.type_to_string(right_type)
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
                    Inference.type_to_string(left_type),
                    Inference.type_to_string(right_type)
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
        local left_is_pointer = left_type and left_type.kind == "pointer"
        local right_is_pointer = right_type and right_type.kind == "pointer"
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
                "Cannot %s pointer and numeric type. " ..
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
function Inference.infer_unary_type(typechecker, expr)
    local operand_type = Inference.infer_type(typechecker, expr.operand)

    if expr.op == "&" then
        -- Address-of operator
        local inferred = { kind = "pointer", to = operand_type }
        expr.inferred_type = inferred
        return inferred
    elseif expr.op == "*" then
        -- Dereference operator
        if operand_type and operand_type.kind == "pointer" then
            expr.inferred_type = operand_type.to
            return operand_type.to
        else
            local line = expr.line or (expr.operand and expr.operand.line) or 0
            local msg = "Cannot dereference non-pointer type"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    elseif expr.op == "!" or expr.op == "not" then
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

-- Infer the type of a function call
function Inference.infer_call_type(typechecker, expr)
    if expr.callee.kind == "identifier" then
        local func_name = expr.callee.name
        local func_def = Resolver.resolve_function(typechecker, "__global__", func_name)

        if func_def then
            -- Check caller-controlled mutability
            for i, arg in ipairs(expr.args) do
                if i <= #func_def.params then
                    local param = func_def.params[i]
                    local caller_allows_mut = (arg.kind == "mut_arg" and arg.allows_mutation)

                    -- If callee wants mut but caller doesn't give it, error
                    if param.mutable and param.type.kind == "pointer" and not caller_allows_mut then
                        local line = expr.line or 0
                        local msg = string.format(
                            "Function '%s' parameter %d requires mutable pointer (mut %s*), but caller passes immutable. Use 'mut' at call site.",
                            func_name, i, param.type.to.name or "Type"
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.MUTABILITY_VIOLATION, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    end
                end
            end

            expr.inferred_type = func_def.return_type
            return func_def.return_type
        else
            local line = expr.line or (expr.callee and expr.callee.line) or 0
            local msg = string.format("Undefined function: %s", func_name)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    elseif expr.callee.kind == "method_ref" then
        -- Handle method reference calls (e.g., obj:method())
        local obj_type = Inference.infer_type(typechecker, expr.callee.object)
        if not obj_type then
            return nil
        end

        local type_name = Inference.get_base_type_name(obj_type)
        local method_def = Resolver.resolve_function(typechecker, type_name, expr.callee.method)

        if method_def then
            expr.inferred_type = method_def.return_type
            return method_def.return_type
        else
            local line = expr.line or (expr.callee and expr.callee.object and expr.callee.object.line) or 0
            local msg = string.format(
                "Method '%s' not found on type '%s'",
                expr.callee.method, type_name or "unknown"
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    return nil
end

-- Infer the type of a method call
function Inference.infer_method_call_type(typechecker, expr)
    local obj_type = Inference.infer_type(typechecker, expr.object)
    if not obj_type then
        return nil
    end

    local type_name = Inference.get_base_type_name(obj_type)
    local method_def = Resolver.resolve_function(typechecker, type_name, expr.method)

    if method_def then
        expr.inferred_type = method_def.return_type
        return method_def.return_type
    else
        local line = expr.line or (expr.object and expr.object.line) or 0
        local msg = string.format(
            "Method '%s' not found on type '%s'",
            expr.method, type_name or "unknown"
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
end

-- Infer the type of a static method call
function Inference.infer_static_method_call_type(typechecker, expr)
    local method_def = Resolver.resolve_function(typechecker, expr.type_name, expr.method)

    if method_def then
        expr.inferred_type = method_def.return_type
        return method_def.return_type
    else
        typechecker:add_error(string.format(
            "Static method '%s' not found on type '%s'",
            expr.method, expr.type_name
        ))
        return nil
    end
end

-- Infer the type of a struct literal
function Inference.infer_struct_literal_type(typechecker, expr)
    if not expr.struct_name and not expr.type_name then
        typechecker:add_error("Struct literal missing type_name")
        return nil
    end

    local struct_name = expr.struct_name or expr.type_name
    local struct_def = Resolver.resolve_struct(typechecker, struct_name)

    if struct_def then
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
                local value_type = Inference.infer_type(typechecker, field_init.value)
                if not Inference.types_compatible(field_type, value_type, typechecker) then
                    typechecker:add_error(string.format(
                        "Type mismatch for field '%s' in struct '%s': expected %s, got %s",
                        field_init.name,
                        struct_name,
                        Inference.type_to_string(field_type),
                        Inference.type_to_string(value_type)
                    ))
                end
            end
        end

        local inferred = { kind = "named_type", name = struct_name }
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

-- Infer the type of a directive
function Inference.infer_directive_type(expr)
    if expr.name == "FILE" or expr.name == "FUNCTION" then
        return { kind = "pointer", to = { kind = "named_type", name = "char" } }
    elseif expr.name == "DEBUG" then
        return { kind = "named_type", name = "bool" }
    end
    return nil
end

-- Infer the type of a new expression (heap or stack allocation)
function Inference.infer_new_type(typechecker, expr)
    local struct_def = Resolver.resolve_struct(typechecker, expr.type_name)

    if struct_def then
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
                local value_type = Inference.infer_type(typechecker, field_init.value)
                if not Inference.types_compatible(field_type, value_type, typechecker) then
                    typechecker:add_error(string.format(
                        "Type mismatch for field '%s' in struct '%s': expected %s, got %s",
                        field_init.name,
                        expr.type_name,
                        Inference.type_to_string(field_type),
                        Inference.type_to_string(value_type)
                    ))
                end
            end
        end

        -- In explicit pointer model, new returns a pointer to the type
        local inferred = { kind = "pointer", to = { kind = "named_type", name = expr.type_name } }
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

-- Resolve type alias to its target type
-- For simple cases like "char*", we need to handle this specially
-- Since the target_type_str is a string, we need to interpret it
function Inference.resolve_type_alias(typechecker, type_node)
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
            kind = "pointer",
            to = { kind = "named_type", name = base_type_match }
        }
    else
        -- It's a simple named type
        return { kind = "named_type", name = alias_target }
    end
end

-- Check if two types are compatible
function Inference.types_compatible(type1, type2, typechecker)
    if not type1 or not type2 then
        return false
    end

    -- Resolve type aliases if typechecker is available
    if typechecker then
        type1 = Inference.resolve_type_alias(typechecker, type1)
        type2 = Inference.resolve_type_alias(typechecker, type2)
    end

    -- Allow void* (null) to be compatible with any pointer type
    if type1.kind == "pointer" and type1.to and type1.to.name == "void" then
        if type2.kind == "pointer" or type2.kind == "named_type" then
            return true  -- null can be assigned to any pointer or struct type
        end
    end
    if type2.kind == "pointer" and type2.to and type2.to.name == "void" then
        if type1.kind == "pointer" or type1.kind == "named_type" then
            return true  -- any pointer or struct type can accept null
        end
    end

    if type1.kind == "named_type" and type2.kind == "named_type" then
        return type1.name == type2.name
    elseif type1.kind == "pointer" and type2.kind == "pointer" then
        return Inference.types_compatible(type1.to, type2.to, typechecker)
    elseif type1.kind == "pointer" and type1.is_clone and type2.kind == "named_type" then
        return Inference.types_compatible(type1.to, type2, typechecker)
    elseif type2.kind == "pointer" and type2.is_clone and type1.kind == "named_type" then
        return Inference.types_compatible(type2.to, type1, typechecker)
    elseif type1.kind == "array" and type2.kind == "array" then
        -- Arrays are compatible if element types match and sizes match
        if type1.size ~= type2.size then
            return false
        end
        return Inference.types_compatible(type1.element_type, type2.element_type, typechecker)
    elseif type1.kind == "slice" and type2.kind == "slice" then
        -- Slices are compatible if element types match
        return Inference.types_compatible(type1.element_type, type2.element_type, typechecker)
    elseif type1.kind == "map" and type2.kind == "map" then
        -- Maps are compatible if key and value types match
        return Inference.types_compatible(type1.key_type, type2.key_type, typechecker) and
               Inference.types_compatible(type1.value_type, type2.value_type, typechecker)
    end

    return false
end

-- Check if a type is bool
function Inference.is_bool_type(type_node)
    return type_node and
           type_node.kind == "named_type" and
           type_node.name == "bool"
end

-- Get the base type name from a type node
function Inference.get_base_type_name(type_node)
    if not type_node then
        return nil
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        return Inference.get_base_type_name(type_node.to)
    end

    return nil
end

-- Convert a type to a string representation
function Inference.type_to_string(type_node)
    if not type_node then
        return "unknown"
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        if type_node.is_clone then
            return Inference.type_to_string(type_node.to)
        else
            return Inference.type_to_string(type_node.to) .. "*"
        end
    elseif type_node.kind == "array" then
        return Inference.type_to_string(type_node.element_type) .. "[" .. tostring(type_node.size) .. "]"
    elseif type_node.kind == "slice" then
        return Inference.type_to_string(type_node.element_type) .. "[]"
    elseif type_node.kind == "varargs" then
        return Inference.type_to_string(type_node.element_type) .. "..."
    elseif type_node.kind == "map" then
        return "map[" .. Inference.type_to_string(type_node.key_type) .. "]" .. Inference.type_to_string(type_node.value_type)
    end

    return "unknown"
end

-- Infer the type of an array literal
function Inference.infer_array_literal_type(typechecker, expr)
    -- Infer element type from first element
    if #expr.elements == 0 then
        local line = expr.line or 0
        local msg = "Cannot infer type of empty array literal"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
    
    local element_type = Inference.infer_type(typechecker, expr.elements[1])
    if not element_type then
        return nil
    end
    
    -- Check that all elements have the same type
    for i = 2, #expr.elements do
        local elem_type = Inference.infer_type(typechecker, expr.elements[i])
        if not Inference.types_compatible(element_type, elem_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Array literal element %d has type '%s', expected '%s'",
                i, Inference.type_to_string(elem_type), Inference.type_to_string(element_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end
    
    -- Return array type with inferred size
    local inferred = { kind = "array", element_type = element_type, size = #expr.elements }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a heap-allocated array (new [elements...])
function Inference.infer_new_array_type(typechecker, expr)
    -- Similar to array_literal, but returns a pointer to the array
    if #expr.elements == 0 then
        local line = expr.line or 0
        local msg = "Cannot infer type of empty array in 'new' expression"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
    
    local element_type = Inference.infer_type(typechecker, expr.elements[1])
    if not element_type then
        return nil
    end
    
    -- Check that all elements have the same type
    for i = 2, #expr.elements do
        local elem_type = Inference.infer_type(typechecker, expr.elements[i])
        if not Inference.types_compatible(element_type, elem_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Array element %d has type '%s', expected '%s'",
                i, Inference.type_to_string(elem_type), Inference.type_to_string(element_type)
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
function Inference.infer_new_map_type(typechecker, expr)
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
        key_type = Inference.infer_type(typechecker, expr.entries[1].key)
        value_type = Inference.infer_type(typechecker, expr.entries[1].value)
        
        if not key_type or not value_type then
            return nil
        end
        
        -- Store inferred types back in expr for code generation
        expr.key_type = key_type
        expr.value_type = value_type
    end
    
    -- Type checking for map entries
    for i, entry in ipairs(expr.entries) do
        local entry_key_type = Inference.infer_type(typechecker, entry.key)
        local entry_value_type = Inference.infer_type(typechecker, entry.value)
        
        -- Check key type compatibility
        if not Inference.types_compatible(key_type, entry_key_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has key type '%s', expected '%s'",
                i, Inference.type_to_string(entry_key_type), Inference.type_to_string(key_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
        
        -- Check value type compatibility
        if not Inference.types_compatible(value_type, entry_value_type, typechecker) then
            local line = expr.line or 0
            local msg = string.format(
                "Map entry %d has value type '%s', expected '%s'",
                i, Inference.type_to_string(entry_value_type), Inference.type_to_string(value_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end
    
    -- Return a map type
    local inferred = { kind = "map", key_type = key_type, value_type = value_type }
    expr.inferred_type = inferred
    return inferred
end

-- Infer the type of a slice expression (array[start:end])
function Inference.infer_slice_type(typechecker, expr)
    local array_type = Inference.infer_type(typechecker, expr.array)
    
    if not array_type then
        return nil
    end
    
    -- Check that the source is an array
    if array_type.kind ~= "array" then
        local line = expr.line or (expr.array and expr.array.line) or 0
        local msg = string.format(
            "Cannot slice non-array type '%s'",
            Inference.type_to_string(array_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
    
    -- Type check the indices
    local start_type = Inference.infer_type(typechecker, expr.start)
    local end_type = Inference.infer_type(typechecker, expr.end_expr)
    
    -- Check that indices are integer types
    if start_type and (start_type.kind ~= "named_type" or not start_type.name:match("^[iu]%d+$")) then
        local line = expr.line or 0
        local msg = string.format(
            "Slice start index must be an integer type, got '%s'",
            Inference.type_to_string(start_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
    
    if end_type and (end_type.kind ~= "named_type" or not end_type.name:match("^[iu]%d+$")) then
        local line = expr.line or 0
        local msg = string.format(
            "Slice end index must be an integer type, got '%s'",
            Inference.type_to_string(end_type)
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

return Inference
