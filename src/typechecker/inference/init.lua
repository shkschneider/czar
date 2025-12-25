-- Type inference and type checking utilities
-- Handles type inference for expressions and type compatibility checking
-- Orchestrates specialized modules for different expression types

local Literals = require("typechecker.inference.literals")
local Expressions = require("typechecker.inference.expressions")
local Calls = require("typechecker.inference.calls")
local Fields = require("typechecker.inference.fields")
local Collections = require("typechecker.inference.collections")
local Types = require("typechecker.inference.types")

local Inference = {}

-- Re-export type utility functions from Types module
Inference.types_compatible = Types.types_compatible
Inference.is_bool_type = Types.is_bool_type
Inference.get_base_type_name = Types.get_base_type_name
Inference.type_to_string = Types.type_to_string

-- Forward declare infer_type for circular dependencies
local infer_type

-- Set up circular dependencies - pass infer_type and utility functions to sub-modules
Expressions.infer_type = function(...) return infer_type(...) end
Expressions.type_to_string = Inference.type_to_string

Calls.infer_type = function(...) return infer_type(...) end
Calls.get_base_type_name = Inference.get_base_type_name

Fields.infer_type = function(...) return infer_type(...) end
Fields.get_base_type_name = Inference.get_base_type_name
Fields.type_to_string = Inference.type_to_string
Fields.types_compatible = Inference.types_compatible

Collections.infer_type = function(...) return infer_type(...) end
Collections.type_to_string = Inference.type_to_string
Collections.types_compatible = Inference.types_compatible

-- Infer the type of an expression
function infer_type(typechecker, expr)
    if not expr then
        return nil
    end

    -- Basic literals
    if expr.kind == "int" then
        return Literals.infer_int_type(expr)
    elseif expr.kind == "float" then
        return Literals.infer_float_type(expr)
    elseif expr.kind == "char" then
        return Literals.infer_char_type(expr)
    elseif expr.kind == "bool" then
        return Literals.infer_bool_type(expr)
    elseif expr.kind == "string" then
        return Literals.infer_string_type(expr)
    elseif expr.kind == "interpolated_string" then
        return Literals.infer_interpolated_string_type(typechecker, expr, infer_type)
    elseif expr.kind == "null" then
        return Literals.infer_null_type(expr)
    elseif expr.kind == "identifier" then
        return Literals.infer_identifier_type(typechecker, expr)
    elseif expr.kind == "macro" or expr.kind == "macro_call" then
        return Literals.infer_macro_type(expr)
    
    -- Field and index access
    elseif expr.kind == "field" then
        return Fields.infer_field_type(typechecker, expr)
    elseif expr.kind == "index" then
        return Fields.infer_index_type(typechecker, expr)
    
    -- Binary and unary expressions
    elseif expr.kind == "binary" then
        return Expressions.infer_binary_type(typechecker, expr)
    elseif expr.kind == "unary" then
        return Expressions.infer_unary_type(typechecker, expr)
    
    -- Special operators
    elseif expr.kind == "is_check" then
        -- Type check operator always returns bool
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
    elseif expr.kind == "clone" then
        -- Clone operator returns a pointer to the cloned value
        if expr.target_type then
            -- clone<Type> returns Type*
            local ptr_type = { kind = "nullable", to = expr.target_type }
            expr.inferred_type = ptr_type
            return ptr_type
        else
            local source_type = infer_type(typechecker, expr.expr)
            -- If source is a pointer, keep it; otherwise wrap in pointer
            local result_type
            if source_type and source_type.kind == "nullable" then
                result_type = source_type
            else
                result_type = { kind = "nullable", to = source_type }
            end
            expr.inferred_type = result_type
            return result_type
        end
    elseif expr.kind == "null_check" then
        -- Null check operator (!) or (!!) returns the operand type (asserts non-null)
        local operand_type = infer_type(typechecker, expr.operand)
        
        -- Check if this is !! on a nullable type that stays nullable (useless)
        if expr.double_bang and operand_type and operand_type.kind == "nullable" then
            -- Double bang on nullable type - emit warning about useless-pointer-safety
            local Warnings = require("warnings")
            local msg = "Using !! on nullable pointer that remains nullable has no effect"
            local function_name = typechecker.current_function and typechecker.current_function.name or nil
            Warnings.emit(typechecker.source_file, expr.line or 0,
                "USELESS_POINTER_SAFETY", msg, typechecker.source_path, function_name)
        end
        
        expr.inferred_type = operand_type
        return operand_type
    elseif expr.kind == "unsafe_cast" then
        -- Unsafe cast: <Type> expr with optional !!
        -- ERROR if not explicitly marked unsafe with !!
        local target_type = expr.to_type or expr.target_type
        local source_type = infer_type(typechecker, expr.expr)
        
        -- Helper: Check if cast is a safe widening cast
        local function is_safe_widening_cast(from_type, to_type)
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
            }
            
            local from_info = type_info[from_name]
            local to_info = type_info[to_name]
            
            if not from_info or not to_info then
                return false
            end
            
            -- Safe if same signedness and target is larger or equal
            return from_info.signed == to_info.signed and to_info.size >= from_info.size
        end
        
        local is_safe_cast = is_safe_widening_cast(source_type, target_type)
        
        -- Check if this cast requires explicit unsafe marker
        if not is_safe_cast and not expr.explicit_unsafe then
            -- ERROR: unsafe cast without !!
            local Errors = require("errors")
            local msg = string.format(
                "Unsafe cast from '%s' to '%s' requires explicit '!!' marker. Use: <type> expr !!",
                Inference.type_to_string(source_type),
                Inference.type_to_string(target_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                Errors.ErrorType.UNSAFE_CAST, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
        -- Note: Warning for explicit unsafe cast (with !!) is emitted during codegen phase
        
        expr.inferred_type = target_type
        return target_type
    elseif expr.kind == "safe_cast" then
        -- Safe cast: <Type> expr ?? fallback
        -- Fallback value is implicitly converted to target type
        local target_type = expr.to_type or expr.target_type
        infer_type(typechecker, expr.expr)
        
        -- Infer fallback type but allow implicit conversion
        infer_type(typechecker, expr.fallback)
        
        -- Note: We allow implicit conversion of fallback to target type
        -- The programmer's responsibility to provide compatible fallback
        
        expr.inferred_type = target_type
        return target_type
    elseif expr.kind == "sizeof" or expr.kind == "type_of" then
        -- sizeof and type return i32 and string respectively
        -- sizeof returns the size in bytes as i32
        -- type_of returns a string
        local result_type
        if expr.kind == "sizeof" then
            result_type = { kind = "named_type", name = "i32" }
        else
            result_type = { kind = "named_type", name = "cstr" }
        end
        expr.inferred_type = result_type
        return result_type
    elseif expr.kind == "compound_assign" then
        return infer_type(typechecker, expr.target)
    
    -- Function and method calls
    elseif expr.kind == "call" then
        return Calls.infer_call_type(typechecker, expr)
    elseif expr.kind == "method_call" then
        return Calls.infer_method_call_type(typechecker, expr)
    elseif expr.kind == "static_method_call" then
        return Calls.infer_static_method_call_type(typechecker, expr)
    
    -- Struct and new expressions
    elseif expr.kind == "struct_literal" then
        return Fields.infer_struct_literal_type(typechecker, expr)
    elseif expr.kind == "new_heap" or expr.kind == "new_stack" then
        return Fields.infer_new_type(typechecker, expr)
    
    -- Collection types
    elseif expr.kind == "array_literal" then
        return Collections.infer_array_literal_type(typechecker, expr)
    elseif expr.kind == "new_array" then
        return Collections.infer_new_array_type(typechecker, expr)
    elseif expr.kind == "new_map" then
        return Collections.infer_new_map_type(typechecker, expr)
    elseif expr.kind == "map_literal" then
        return Collections.infer_map_literal_type(typechecker, expr)
    elseif expr.kind == "slice" then
        return Collections.infer_slice_type(typechecker, expr)
    elseif expr.kind == "new_pair" then
        return Collections.infer_new_pair_type(typechecker, expr)
    elseif expr.kind == "pair_literal" then
        return Collections.infer_pair_literal_type(typechecker, expr)
    elseif expr.kind == "new_string" then
        return Collections.infer_new_string_type(typechecker, expr)
    elseif expr.kind == "string_literal" then
        return Collections.infer_string_literal_type(typechecker, expr)
    
    -- Anonymous functions and structures
    elseif expr.kind == "anonymous_function" then
        -- Anonymous function: fn(params) return_type { body }
        -- For now, treat it as a function pointer type
        -- Return type is a function pointer (represented as void* for simplicity)
        local result_type = { kind = "named_type", name = "any" }
        expr.inferred_type = result_type
        return result_type
    elseif expr.kind == "anonymous_struct" then
        -- Anonymous struct: struct { field: value, ... }
        -- Create an anonymous struct type
        local result_type = { kind = "named_type", name = "anonymous" }
        expr.inferred_type = result_type
        return result_type
    end

    return nil
end

-- Export the main inference function
Inference.infer_type = infer_type

return Inference
