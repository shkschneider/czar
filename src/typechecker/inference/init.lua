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
Inference.resolve_type_alias = Types.resolve_type_alias
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
    elseif expr.kind == "bool" then
        return Literals.infer_bool_type(expr)
    elseif expr.kind == "string" then
        return Literals.infer_string_type(expr)
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
            local ptr_type = { kind = "pointer", to = expr.target_type }
            expr.inferred_type = ptr_type
            return ptr_type
        else
            local source_type = infer_type(typechecker, expr.expr)
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
        local operand_type = infer_type(typechecker, expr.operand)
        expr.inferred_type = operand_type
        return operand_type
    elseif expr.kind == "unsafe_cast" then
        -- Unsafe cast: expr as<Type>
        -- Emit warning during type checking
        local target_type = expr.to_type or expr.target_type
        local source_type = infer_type(typechecker, expr.expr)
        
        -- Print warning for unsafe cast
        print("Warning: Unsafe cast from " .. Inference.type_to_string(source_type) .. " to " .. Inference.type_to_string(target_type))
        
        expr.inferred_type = target_type
        return target_type
    elseif expr.kind == "safe_cast" then
        -- Safe cast: expr as?<Type>(fallback)
        -- Type-check that fallback matches target type
        local target_type = expr.to_type or expr.target_type
        infer_type(typechecker, expr.expr)
        
        local fallback_type = infer_type(typechecker, expr.fallback)
        
        -- Check that fallback type matches target type
        if not Inference.types_compatible(target_type, fallback_type) then
            error("Safe cast fallback type mismatch: expected " .. Inference.type_to_string(target_type) .. 
                  ", got " .. Inference.type_to_string(fallback_type))
        end
        
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
            result_type = { kind = "pointer", to = { kind = "named_type", name = "char" } }
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
    end

    return nil
end

-- Export the main inference function
Inference.infer_type = infer_type

return Inference
