-- Literal and simple expression generation
-- Handles: int, float, char, string, bool, null, identifier, macro, macro_call, mut_arg

local Macros = require("src.macros")

local Literals = {}

local function ctx() return _G.Codegen end

-- Generate integer literal
function Literals.gen_int(expr)
    return tostring(expr.value)
end

-- Generate float literal
function Literals.gen_float(expr)
    -- Ensure we have at least one decimal place for C float literals
    local str = tostring(expr.value)
    if not str:match("%.") and not str:match("[eE]") then
        str = str .. ".0"
    end
    return str
end

-- Generate char literal (C-style single-quoted char)
function Literals.gen_char(expr)
    return string.format("'%s'", expr.value)
end

-- Generate string literal (C-style quoted string)
function Literals.gen_string(expr)
    return string.format("\"%s\"", expr.value)
end

-- Generate interpolated string (mustache-like templating)
-- Converts "Hello {name}" into a format string with arguments
function Literals.gen_interpolated_string(expr, gen_expr_fn)
    local parts = expr.parts
    
    -- Use pre-parsed expressions from typechecker
    local expressions = expr.expressions or {}
    
    -- Build the format string with appropriate type placeholders
    local format_str = ""
    for i, part in ipairs(parts) do
        -- Escape any existing % characters in the literal parts to prevent format string injection
        local escaped_part = part:gsub("%%", "%%%%")
        format_str = format_str .. escaped_part
        if i <= #expressions then
            -- Determine the format specifier based on the inferred type
            local sub_expr = expressions[i]
            local format_spec = "%s"  -- default to string
            
            if sub_expr.inferred_type then
                local type_kind = sub_expr.inferred_type.kind
                local type_name = sub_expr.inferred_type.name
                
                -- Check if it's a named type
                if type_kind == "named_type" then
                    if type_name == "i8" or type_name == "i16" or type_name == "i32" then
                        format_spec = "%d"
                    elseif type_name == "i64" then
                        format_spec = "%lld"
                    elseif type_name == "u8" or type_name == "u16" or type_name == "u32" then
                        format_spec = "%u"
                    elseif type_name == "u64" then
                        format_spec = "%llu"
                    elseif type_name == "f32" or type_name == "f64" then
                        format_spec = "%f"
                    elseif type_name == "bool" then
                        format_spec = "%d"
                    end
                end
            end
            
            format_str = format_str .. format_spec
        end
    end
    
    -- Generate code for the arguments
    local args = {}
    for _, expr_ast in ipairs(expressions) do
        local arg_code = gen_expr_fn(expr_ast)
        table.insert(args, arg_code)
    end
    
    -- Return as a sprintf-like expression
    if #args == 0 then
        -- No interpolation, just a regular string
        return string.format("\"%s\"", format_str)
    else
        -- Use snprintf to build the string safely
        -- Buffer size of 512 bytes should handle most interpolations
        -- For very long strings, consider using dynamic allocation
        local arg_list = table.concat(args, ", ")
        -- Use unique variable name to avoid conflicts
        local buf_name = string.format("_czar_interp_%d", expr.line or 0)
        local code = string.format(
            "({ char %s[512]; snprintf(%s, 512, \"%s\", %s); %s; })",
            buf_name, buf_name, format_str, arg_list, buf_name
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
    -- Check if this identifier is a reference that needs auto-dereferencing
    local var_info = ctx():get_var_info(expr.name)
    if var_info and var_info.is_reference then
        return "(*" .. expr.name .. ")"
    end
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
