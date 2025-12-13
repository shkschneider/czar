-- Type inference and type checking utilities
-- Handles type inference for expressions and type compatibility checking

local Resolver = require("typechecker.resolver")

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
            typechecker:add_error(string.format("Undeclared identifier: %s", expr.name))
            return nil
        end
    elseif expr.kind == "field" then
        return Inference.infer_field_type(typechecker, expr)
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
        -- Clone operator returns the target type if specified, otherwise the source type
        if expr.target_type then
            expr.inferred_type = expr.target_type
            return expr.target_type
        else
            local source_type = Inference.infer_type(typechecker, expr.expr)
            expr.inferred_type = source_type
            return source_type
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
    elseif expr.kind == "cast" then
        local target_type = expr.to_type or expr.target_type
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
    elseif expr.kind == "directive" then
        return Inference.infer_directive_type(expr)
    elseif expr.kind == "compound_assign" then
        return Inference.infer_type(typechecker, expr.target)
    end
    
    return nil
end

-- Infer the type of a field access
function Inference.infer_field_type(typechecker, expr)
    local obj_type = Inference.infer_type(typechecker, expr.object)
    if not obj_type then
        return nil
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
        typechecker:add_error(string.format(
            "Field '%s' not found in struct '%s'",
            expr.field, type_name
        ))
    else
        typechecker:add_error(string.format(
            "Cannot access field '%s' on non-struct type '%s'",
            expr.field, type_name or "unknown"
        ))
    end
    
    return nil
end

-- Infer the type of a binary expression
function Inference.infer_binary_type(typechecker, expr)
    local left_type = Inference.infer_type(typechecker, expr.left)
    local right_type = Inference.infer_type(typechecker, expr.right)
    
    -- Comparison and logical operators return bool
    if expr.op == "==" or expr.op == "!=" or 
       expr.op == "<" or expr.op == ">" or 
       expr.op == "<=" or expr.op == ">=" or
       expr.op == "and" or expr.op == "or" or
       expr.op == "is" then
        local inferred = { kind = "named_type", name = "bool" }
        expr.inferred_type = inferred
        return inferred
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
            typechecker:add_error("Cannot dereference non-pointer type")
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
            expr.inferred_type = func_def.return_type
            return func_def.return_type
        else
            typechecker:add_error(string.format("Undefined function: %s", func_name))
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
            typechecker:add_error(string.format(
                "Method '%s' not found on type '%s'",
                expr.callee.method, type_name or "unknown"
            ))
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
        typechecker:add_error(string.format(
            "Method '%s' not found on type '%s'",
            expr.method, type_name or "unknown"
        ))
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
        typechecker:add_error(string.format("Undefined struct: %s", struct_name or "nil"))
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
        
        local inferred = { kind = "named_type", name = expr.type_name }
        expr.inferred_type = inferred
        return inferred
    else
        typechecker:add_error(string.format("Undefined struct: %s", expr.type_name or "nil"))
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
    if alias_target:match("^(%w+)%s*%*$") then
        -- It's a pointer type like "char*"
        local base_type = alias_target:match("^(%w+)%s*%*$")
        return {
            kind = "pointer",
            to = { kind = "named_type", name = base_type }
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
    
    -- Allow void* (null) to be compatible with any named type (for nullable pointers)
    if type1.kind == "pointer" and type1.to and type1.to.name == "void" then
        if type2.kind == "named_type" then
            return true  -- null can be assigned to any struct type
        end
    end
    if type2.kind == "pointer" and type2.to and type2.to.name == "void" then
        if type1.kind == "named_type" then
            return true  -- struct type can accept null
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
    end
    
    return "unknown"
end

return Inference
