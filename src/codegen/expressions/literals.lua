-- Literal and simple expression generation
-- Handles: int, string, bool, null, identifier, macro, macro_call, mut_arg

local Macros = require("src.macros")

local Literals = {}

local function ctx() return _G.Codegen end

-- Generate integer literal
function Literals.gen_int(expr)
    return tostring(expr.value)
end

-- Generate string literal (C-style quoted string)
function Literals.gen_string(expr)
    return string.format("\"%s\"", expr.value)
end

-- Generate boolean literal
function Literals.gen_bool(expr)
    return expr.value and "true" or "false"
end

-- Generate null literal
function Literals.gen_null(expr)
    return "NULL"
end

-- Generate macro expression (#FILE, #FUNCTION, #DEBUG)
function Literals.gen_macro(expr)
    return Macros.generate_expression(expr, ctx())
end

-- Generate macro call (#assert, #log, etc.)
function Literals.gen_macro_call(expr)
    return Macros.generate_call(expr, ctx())
end

-- Generate identifier reference
function Literals.gen_identifier(expr)
    ctx():mark_var_used(expr.name)
    return expr.name
end

-- Generate mut_arg (caller-controlled mutability)
function Literals.gen_mut_arg(expr, gen_expr_fn)
    -- Caller-controlled mutability: mut arg means caller allows mutation
    -- If the expression is already a pointer type, just pass it
    -- If it's a value type, take its address
    local inner_expr = gen_expr_fn(expr.expr)
    
    -- Check if the inner expression is already a pointer
    local is_pointer = false
    if expr.expr.kind == "identifier" then
        local var_type = ctx():get_var_type(expr.expr.name)
        if var_type and var_type.kind == "pointer" then
            is_pointer = true
        end
    elseif expr.expr.kind == "new_heap" or expr.expr.kind == "clone" or expr.expr.kind == "new_array" then
        -- new, new_array, and clone always return pointers
        is_pointer = true
    end
    
    if is_pointer then
        -- Already a pointer, just pass it
        return inner_expr
    else
        -- Value type, take address
        return "&" .. inner_expr
    end
end

return Literals
