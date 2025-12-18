-- Function call and method call expression generation
-- Handles: call, static_method_call, field access, index access, struct_literal

local Builtins = require("src.builtins")

local Calls = {}

local function ctx() return _G.Codegen end

local function join(list, sep)
    return table.concat(list, sep or "")
end

-- Generate static method call
function Calls.gen_static_method_call(expr, gen_expr_fn)
    -- Static method call: Type.method(obj, args...)
    local type_name = expr.type_name
    local method_name = expr.method

    -- Look up the method
    local method = nil
    if ctx().functions[type_name] then
        method = ctx().functions[type_name][method_name]
    end

    if method then
        -- Resolve arguments with named args and defaults
        local resolved_args = ctx():resolve_arguments(method_name, expr.args, method.params)

        -- Generate function call - no automatic addressing/dereferencing in explicit model
        local args = {}
        for i, a in ipairs(resolved_args) do
            table.insert(args, gen_expr_fn(a))
        end
        return string.format("%s(%s)", method_name, join(args, ", "))
    else
        error(string.format("Unknown method %s on type %s", method_name, type_name))
    end
end

-- Helper to generate string method calls
local function gen_string_method(obj, obj_type, method_name, args, gen_expr_fn)
    local obj_expr = gen_expr_fn(obj)
    local is_ptr = (obj_type.kind == "pointer")
    
    if method_name == "append" then
        if #args ~= 1 then error("append() requires exactly 1 argument") end
        local arg_expr = gen_expr_fn(args[1])
        return is_ptr 
            and string.format("czar_string_append_string(%s, &%s)", obj_expr, arg_expr)
            or string.format("czar_string_append_string(&%s, &%s)", obj_expr, arg_expr)
    elseif method_name == "substring" then
        if #args ~= 2 then error("substring() requires exactly 2 arguments") end
        local start_expr = gen_expr_fn(args[1])
        local end_expr = gen_expr_fn(args[2])
        return is_ptr
            and string.format("czar_string_substring(%s, %s, %s)", obj_expr, start_expr, end_expr)
            or string.format("czar_string_substring(&%s, %s, %s)", obj_expr, start_expr, end_expr)
    elseif method_name == "find" or method_name == "index" then
        if #args ~= 1 then error(method_name .. "() requires exactly 1 argument") end
        local needle_expr = gen_expr_fn(args[1])
        return is_ptr
            and string.format("czar_string_index(%s, &%s)", obj_expr, needle_expr)
            or string.format("czar_string_index(&%s, &%s)", obj_expr, needle_expr)
    elseif method_name == "contains" then
        if #args ~= 1 then error("contains() requires exactly 1 argument") end
        local needle_expr = gen_expr_fn(args[1])
        return is_ptr
            and string.format("czar_string_contains(%s, &%s)", obj_expr, needle_expr)
            or string.format("czar_string_contains(&%s, &%s)", obj_expr, needle_expr)
    elseif method_name == "cut" then
        if #args ~= 1 then error("cut() requires exactly 1 argument") end
        local sep_expr = gen_expr_fn(args[1])
        return is_ptr
            and string.format("czar_string_cut(%s, &%s)", obj_expr, sep_expr)
            or string.format("czar_string_cut(&%s, &%s)", obj_expr, sep_expr)
    elseif method_name == "prefix" then
        if #args ~= 1 then error("prefix() requires exactly 1 argument") end
        local prefix_expr = gen_expr_fn(args[1])
        return is_ptr
            and string.format("czar_string_prefix(%s, &%s)", obj_expr, prefix_expr)
            or string.format("czar_string_prefix(&%s, &%s)", obj_expr, prefix_expr)
    elseif method_name == "suffix" then
        if #args ~= 1 then error("suffix() requires exactly 1 argument") end
        local suffix_expr = gen_expr_fn(args[1])
        return is_ptr
            and string.format("czar_string_suffix(%s, &%s)", obj_expr, suffix_expr)
            or string.format("czar_string_suffix(&%s, &%s)", obj_expr, suffix_expr)
    elseif method_name == "upper" or method_name == "lower" then
        if #args ~= 0 then error(method_name .. "() takes no arguments") end
        return is_ptr
            and string.format("czar_string_%s(%s)", method_name, obj_expr)
            or string.format("czar_string_%s(&%s)", method_name, obj_expr)
    elseif method_name == "words" then
        if #args ~= 0 then error("words() takes no arguments") end
        error("words() is not yet fully implemented")
    elseif method_name == "trim" or method_name == "ltrim" or method_name == "rtrim" then
        if #args ~= 0 then error(method_name .. "() takes no arguments") end
        return is_ptr
            and string.format("czar_string_%s(%s)", method_name, obj_expr)
            or string.format("czar_string_%s(&%s)", method_name, obj_expr)
    elseif method_name == "cstr" then
        return is_ptr
            and string.format("czar_string_cstr(%s)", obj_expr)
            or string.format("czar_string_cstr(&%s)", obj_expr)
    end
    
    return nil
end

-- Helper to check if type is a string type
local function is_string_type(obj_type)
    return obj_type and (obj_type.kind == "string" or (obj_type.kind == "pointer" and obj_type.to.kind == "string"))
end

-- Generate function call expression
function Calls.gen_call(expr, gen_expr_fn)
    -- Check if this is a method call (callee is a method_ref or field expression)
    if expr.callee.kind == "method_ref" then
        -- Method call using colon: obj:method()
        local obj = expr.callee.object
        local method_name = expr.callee.method

        -- Determine the type of the object
        local obj_type = nil
        if obj.kind == "identifier" then
            obj_type = ctx():get_var_type(obj.name)
        end
        
        -- Special handling for string methods with : syntax
        if is_string_type(obj_type) then
            local result = gen_string_method(obj, obj_type, method_name, expr.args, gen_expr_fn)
            if result then return result end
        end

        -- Get the receiver type name
        local receiver_type_name = nil
        if obj_type then
            if obj_type.kind == "pointer" and obj_type.to.kind == "named_type" then
                receiver_type_name = obj_type.to.name
            elseif obj_type.kind == "named_type" then
                receiver_type_name = obj_type.name
            end
        end

        -- Look up the method
        local method = nil
        if receiver_type_name and ctx().functions[receiver_type_name] then
            method = ctx().functions[receiver_type_name][method_name]
        end

        if method then
            -- This is a method call, transform to function call with object as first arg
            local args = {}

            -- Add the object as the first argument
            -- Check if we need to address it
            local first_param_type = method.params[1].type
            local obj_expr = gen_expr_fn(obj)

            if first_param_type.kind == "pointer" then
                -- Method expects a pointer
                if obj_type and obj_type.kind ~= "pointer" then
                    -- Object is a value, add &
                    obj_expr = "&" .. obj_expr
                end
            end

            table.insert(args, obj_expr)

            -- Resolve the remaining arguments (excluding self)
            local method_params_without_self = {}
            for i = 2, #method.params do
                table.insert(method_params_without_self, method.params[i])
            end
            local resolved_args = ctx():resolve_arguments(method_name, expr.args, method_params_without_self)

            -- Add the rest of the arguments
            for _, a in ipairs(resolved_args) do
                table.insert(args, gen_expr_fn(a))
            end

            return string.format("%s(%s)", method_name, join(args, ", "))
        else
            error(string.format("Unknown method %s on type %s", method_name, receiver_type_name or "unknown"))
        end
    elseif expr.callee.kind == "field" then
        local obj = expr.callee.object
        local method_name = expr.callee.field

        -- Determine the type of the object
        local obj_type = nil
        if obj.kind == "identifier" then
            obj_type = ctx():get_var_type(obj.name)
        end

        -- Special handling for string methods
        if is_string_type(obj_type) then
            local result = gen_string_method(obj, obj_type, method_name, expr.args, gen_expr_fn)
            if result then return result end
        end

        -- Get the receiver type name
        local receiver_type_name = nil
        if obj_type then
            if obj_type.kind == "pointer" and obj_type.to.kind == "named_type" then
                receiver_type_name = obj_type.to.name
            elseif obj_type.kind == "named_type" then
                receiver_type_name = obj_type.name
            end
        end

        -- Look up the method
        local method = nil
        if receiver_type_name and ctx().functions[receiver_type_name] then
            method = ctx().functions[receiver_type_name][method_name]
        end

        if method then
            -- This is a method call, transform to function call with object as first arg
            local args = {}

            -- Add the object as the first argument
            -- Check if we need to address it
            local first_param_type = method.params[1].type
            local obj_expr = gen_expr_fn(obj)

            if first_param_type.kind == "pointer" then
                -- Method expects a pointer
                if obj_type and obj_type.kind ~= "pointer" then
                    -- Object is a value, add &
                    obj_expr = "&" .. obj_expr
                end
            end

            table.insert(args, obj_expr)

            -- Resolve the remaining arguments (excluding self)
            local method_params_without_self = {}
            for i = 2, #method.params do
                table.insert(method_params_without_self, method.params[i])
            end
            local resolved_args = ctx():resolve_arguments(method_name, expr.args, method_params_without_self)

            -- Add the rest of the arguments
            for _, a in ipairs(resolved_args) do
                table.insert(args, gen_expr_fn(a))
            end

            return string.format("%s(%s)", method_name, join(args, ", "))
        end
    end

    -- Regular function call
    local callee = gen_expr_fn(expr.callee)
    local args = {}

    -- In explicit pointer model, no automatic conversions
    -- User must use & and * explicitly
    if expr.callee.kind == "identifier" and ctx().functions["__global__"] then
        local func_overloads = ctx().functions["__global__"][expr.callee.name]
        local func_def = nil
        
        -- Use the resolved function from typechecker if available
        if expr.resolved_function then
            func_def = expr.resolved_function
        elseif func_overloads then
            -- Fallback: use first overload if no resolution info
            if type(func_overloads) == "table" and #func_overloads > 0 then
                func_def = func_overloads[1]
            else
                func_def = func_overloads
            end
        end
        
        if func_def then
            -- Generate the C name for the function
            -- Check if this function is overloaded
            local func_name = expr.callee.name
            local type_name = "__global__"
            local overloads = ctx().functions[type_name] and ctx().functions[type_name][func_name]
            local is_overloaded = overloads and type(overloads) == "table" and #overloads > 1
            
            if is_overloaded then
                -- Generate unique C name for overloaded functions
                local function type_to_c_name(type_node)
                    if not type_node then return "unknown" end
                    if type_node.kind == "named_type" then
                        return type_node.name
                    elseif type_node.kind == "pointer" then
                        return type_to_c_name(type_node.to) .. "_ptr"
                    elseif type_node.kind == "string" then
                        return "string"
                    end
                    return "unknown"
                end
                
                local type_suffix = ""
                for _, param in ipairs(func_def.params) do
                    local type_name = type_to_c_name(param.type)
                    if type_suffix == "" then
                        type_suffix = type_name
                    end
                end
                callee = func_name .. "_" .. type_suffix
            else
                -- Use regular name (already set by gen_expr_fn)
                callee = func_name == "main" and "main_main" or func_name
            end
            
            -- Resolve arguments (handle named args and defaults)
            local resolved_args = ctx():resolve_arguments(expr.callee.name, expr.args, func_def.params)
            for _, a in ipairs(resolved_args) do
                if a.kind == "varargs_list" then
                    -- Generate varargs array
                    if #a.args == 0 then
                        -- No varargs provided, pass NULL and 0
                        table.insert(args, "NULL")
                        table.insert(args, "0")
                    else
                        -- Generate compound literal for varargs array
                        local varargs_exprs = {}
                        for _, varg in ipairs(a.args) do
                            table.insert(varargs_exprs, gen_expr_fn(varg))
                        end
                        local Types = require("codegen.types")
                        local element_type = Types.c_type(func_def.params[#func_def.params].type.element_type)
                        local array_literal = string.format("(%s[]){%s}", element_type, join(varargs_exprs, ", "))
                        table.insert(args, array_literal)
                        table.insert(args, tostring(#a.args))
                    end
                else
                    table.insert(args, gen_expr_fn(a))
                end
            end
        else
            for _, a in ipairs(expr.args) do
                table.insert(args, gen_expr_fn(a))
            end
        end
    else
        for _, a in ipairs(expr.args) do
            table.insert(args, gen_expr_fn(a))
        end
    end

    if Builtins.calls[callee] then
        return Builtins.calls[callee](args)
    end
    return string.format("%s(%s)", callee, join(args, ", "))
end

-- Generate array index access
function Calls.gen_index(expr, gen_expr_fn)
    -- Array indexing: arr[index]
    local array_expr = gen_expr_fn(expr.array)
    local index_expr = gen_expr_fn(expr.index)
    return string.format("%s[%s]", array_expr, index_expr)
end

-- Generate field access
function Calls.gen_field(expr, gen_expr_fn)
    -- Check if this is enum member access (e.g., Status.SUCCESS)
    if expr.object.kind == "identifier" then
        local enum_name = expr.object.name
        if ctx().enums[enum_name] then
            -- This is an enum member access, generate: EnumName_VALUE
            return string.format("%s_%s", enum_name, expr.field)
        end
    end
    
    local obj_expr = gen_expr_fn(expr.object)
    -- Determine if we need -> or .
    -- Check if the object is an identifier and if its type is a pointer or map
    local use_arrow = false
    if expr.object.kind == "identifier" then
        local var_type = ctx():get_var_type(expr.object.name)
        if var_type then
            if ctx():is_pointer_type(var_type) then
                use_arrow = true
            elseif var_type.kind == "map" then
                -- Maps are always pointers
                use_arrow = true
            end
        end
    elseif expr.object.kind == "unary" and expr.object.op == "*" then
        -- Explicit dereference, use .
        use_arrow = false
    elseif expr.object.inferred_type and expr.object.inferred_type.kind == "map" then
        -- Map type always uses arrow
        use_arrow = true
    end
    local accessor = use_arrow and "->" or "."
    return string.format("%s%s%s", obj_expr, accessor, expr.field)
end

-- Generate struct literal
function Calls.gen_struct_literal(expr, gen_expr_fn)
    local parts = {}
    for _, f in ipairs(expr.fields) do
        table.insert(parts, string.format(".%s = %s", f.name, gen_expr_fn(f.value)))
    end
    -- In explicit pointer model, struct literals are just values
    -- Use compound literal syntax: (Type){ fields... }
    return string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
end

return Calls
