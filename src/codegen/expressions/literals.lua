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

-- Generate interpolated string (mustache-like templating)
-- Converts "Hello {name}" into a format string with arguments
function Literals.gen_interpolated_string(expr, gen_expr_fn)
    local parts = expr.parts
    local expressions = expr.expressions
    
    -- Build the format string
    local format_str = ""
    for i, part in ipairs(parts) do
        format_str = format_str .. part
        if i <= #expressions then
            -- Add a placeholder - we need to determine the type
            -- For now, we'll use %s for strings and pointers, %d for integers
            -- This is a simplification; ideally we'd do type inference
            format_str = format_str .. "%s"
        end
    end
    
    -- Generate code for the arguments
    local args = {}
    for _, expr_ast in ipairs(expressions) do
        local arg_code = gen_expr_fn(expr_ast)
        table.insert(args, arg_code)
    end
    
    -- Return as a sprintf-like expression that can be used inline
    -- We'll use a statement expression (GCC extension) to build the string
    if #args == 0 then
        -- No interpolation, just a regular string
        return string.format("\"%s\"", format_str)
    else
        -- We need to build a temporary string
        -- For simplicity, we'll use a static buffer approach
        -- This is allocated on the stack and returned
        local arg_list = table.concat(args, ", ")
        
        -- Use snprintf to build the string safely
        -- We'll allocate a reasonable buffer size (256 bytes should be enough for most cases)
        local code = string.format(
            "({ char _interp_buf[256]; snprintf(_interp_buf, 256, \"%s\", %s); _interp_buf; })",
            format_str,
            arg_list
        )
        return code
    end
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
        if var_type and var_type.kind == "nullable" then
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
