-- Expression generation for code generation
-- Handles all expression types: literals, operators, calls, casts, etc.

local Expressions = {}

local function ctx() return _G.Codegen end

local builtin_calls = {
    print_i32 = function(args)
        return string.format('printf("%%d\\n", %s)', args[1])
    end,
}

local function join(list, sep)
    return table.concat(list, sep or "")
end

function Expressions.gen_expr(expr)
    if not expr then
        error("gen_expr called with nil expression", 2)
    end
    if expr.kind == "int" then
        return tostring(expr.value)
    elseif expr.kind == "string" then
        return string.format("\"%s\"", expr.value)
    elseif expr.kind == "bool" then
        return expr.value and "true" or "false"
    elseif expr.kind == "null" then
        return "NULL"
    elseif expr.kind == "directive" then
        -- Handle compiler directives: #FILE, #FUNCTION, #DEBUG
        local directive_name = expr.name:upper()
        if directive_name == "FILE" then
            return string.format("\"%s\"", ctx().source_file)
        elseif directive_name == "FUNCTION" then
            local func_name = ctx().current_function or "unknown"
            return string.format("\"%s\"", func_name)
        elseif directive_name == "DEBUG" then
            return ctx().debug_memory and "true" or "false"
        else
            error(string.format("Unknown directive: #%s at %d:%d", expr.name, expr.line, expr.col))
        end
    elseif expr.kind == "identifier" then
        -- Check if this is a clone variable that needs dereferencing
        local var_type = ctx():get_var_type(expr.name)
        if var_type and var_type.kind == "pointer" and var_type.is_clone then
            -- For clone variables used directly (not in field access), dereference them
            -- But we need context to know if this is a field access or not
            -- For now, just return the name - field access will handle it
            return expr.name
        end
        return expr.name
    elseif expr.kind == "mut_arg" then
        -- mut argument: automatically take address
        -- But if the variable is heap-allocated (stored as pointer), don't take address
        if expr.expr.kind == "identifier" then
            local var_type = ctx():get_var_type(expr.expr.name)
            if var_type and var_type.kind == "pointer" and var_type.is_clone then
                -- This is a heap-allocated value (clone or new), already a pointer
                return Expressions.gen_expr(expr.expr)
            end
        end
        local inner_expr = Expressions.gen_expr(expr.expr)
        return "&" .. inner_expr
    elseif expr.kind == "cast" then
        -- cast<Type> expr -> (Type)expr
        local target_type_str = ctx():c_type(expr.target_type)
        local expr_str = Expressions.gen_expr(expr.expr)

        -- Determine source type for special handling
        local source_type = nil
        if expr.expr.kind == "identifier" then
            source_type = ctx():get_var_type(expr.expr.name)
        elseif expr.expr.kind == "field" then
            -- Get the type of the field
            source_type = ctx():infer_type(expr.expr)
        end

        -- Check if we're casting a clone variable that needs dereferencing
        if expr.expr.kind == "identifier" and source_type and source_type.kind == "pointer" and source_type.is_clone then
            expr_str = "*" .. expr_str
        end

        -- Special case: when casting to 'any' (void*), struct pointers don't need dereferencing
        -- They are already pointers in the implicit pointer model
        if expr.target_type.kind == "named_type" and expr.target_type.name == "any" then
            if expr.expr.kind == "identifier" and source_type and source_type.kind == "pointer" then
                -- This is a struct pointer, just cast it directly
                return string.format("((%s)%s)", target_type_str, expr.expr.name)
            end
            -- For other expressions casting to 'any', use the generated expression
            return string.format("((%s)%s)", target_type_str, expr_str)
        end

        -- Special case: when casting from 'any' (void*) to a struct type
        -- We need to cast to a pointer type since structs are pointers in Czar's model
        if source_type and source_type.kind == "named_type" and source_type.name == "any" then
            if expr.target_type.kind == "named_type" and ctx().structs[expr.target_type.name] then
                -- Casting from any to a struct, cast to pointer type
                return string.format("((%s*)%s)", target_type_str, expr_str)
            end
            -- For other types from 'any', use normal cast
            return string.format("((%s)%s)", target_type_str, expr_str)
        end

        -- Default: normal cast
        return string.format("((%s)%s)", target_type_str, expr_str)
    elseif expr.kind == "clone" then
        -- clone(expr) or clone<Type>(expr)
        -- Allocate on heap and copy the value
        local expr_str = Expressions.gen_expr(expr.expr)
        local source_type = nil
        local target_type = nil

        -- Determine source type from expression
        if expr.expr.kind == "identifier" then
            source_type = ctx():get_var_type(expr.expr.name)
        end

        -- If target type specified, use it; otherwise use source type
        if expr.target_type then
            target_type = expr.target_type
        else
            target_type = source_type
        end

        if not target_type then
            error("Cannot determine type for clone operation")
        end

        -- In implicit pointer model, struct variables are pointers
        -- We need to dereference them to clone the value
        local actual_type = target_type
        local needs_deref = false

        if target_type.kind == "pointer" then
            -- Source is a pointer, need to dereference it
            actual_type = target_type.to
            needs_deref = true
        end

        local target_type_str = ctx():c_type(actual_type)
        local source_expr = needs_deref and ("*" .. expr_str) or expr_str

        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = *source_ptr; _ptr; })
        if expr.target_type and source_type then
            -- With cast (implicit allocation - clone)
            return string.format("({ %s* _ptr = %s; *_ptr = (%s)%s; _ptr; })",
                target_type_str, ctx():malloc_call("sizeof(" .. target_type_str .. ")", false), target_type_str, source_expr)
        else
            -- Without cast (implicit allocation - clone)
            return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
                target_type_str, ctx():malloc_call("sizeof(" .. target_type_str .. ")", false), source_expr)
        end
    elseif expr.kind == "binary" then
        -- Handle special operators
        if expr.op == "or" then
            local left = Expressions.gen_expr(expr.left)
            local right = Expressions.gen_expr(expr.right)
            -- 'or' is used for both logical OR and null coalescing
            -- For null coalescing, we use a statement expression with a temporary
            return string.format("({ __auto_type _tmp = %s; _tmp ? _tmp : (%s); })", left, right)
        elseif expr.op == "and" then
            -- 'and' is logical AND
            return string.format("(%s && %s)", Expressions.gen_expr(expr.left), Expressions.gen_expr(expr.right))
        else
            return string.format("(%s %s %s)", Expressions.gen_expr(expr.left), expr.op, Expressions.gen_expr(expr.right))
        end
    elseif expr.kind == "is_check" then
        -- Handle 'is' keyword for type checking
        -- This is a compile-time check that always returns true or false
        local expr_type = ctx():infer_type(expr.expr)
        if not expr_type then
            error("Cannot infer type for 'is' check expression")
        end
        local target_type = expr.type
        local matches = ctx():types_match(expr_type, target_type)
        return matches and "true" or "false"
    elseif expr.kind == "type_of" then
        -- Handle 'type' built-in that returns a const string
        local expr_type = ctx():infer_type(expr.expr)
        if not expr_type then
            error("Cannot infer type for 'type' built-in expression")
        end
        local type_name = ctx():type_name_string(expr_type)
        return string.format("\"%s\"", type_name)
    elseif expr.kind == "unary" then
        return string.format("(%s%s)", expr.op, Expressions.gen_expr(expr.operand))
    elseif expr.kind == "null_check" then
        -- Null check operator: expr!!
        local operand = Expressions.gen_expr(expr.operand)
        -- Generate: assert-like behavior
        return string.format("({ __auto_type _tmp = %s; if (!_tmp) { fprintf(stderr, \"null check failed\\n\"); abort(); } _tmp; })", operand)
    elseif expr.kind == "assign" then
        -- Check if target is an immutable variable
        if expr.target.kind == "identifier" then
            local var_type = ctx():get_var_type(expr.target.name)
            if var_type then
                -- Check if variable is immutable (we need to track this)
                local var_info = ctx():get_var_info(expr.target.name)
                if var_info and not var_info.mutable then
                    error(string.format("Cannot assign to immutable variable '%s'", expr.target.name))
                end
            end
        elseif expr.target.kind == "field" then
            -- Check if target object variable is mutable
            -- In the new model, field mutability comes from the variable, not the field
            if expr.target.object.kind == "identifier" then
                local var_info = ctx():get_var_info(expr.target.object.name)
                if var_info and not var_info.mutable then
                    error(string.format("Cannot assign to field '%s' of immutable variable '%s'", expr.target.field, expr.target.object.name))
                end
            end
        end

        -- Handle assignment with implicit pointer conversion
        -- If target is a pointer and value is not, we need to heap-allocate
        local target_expr = Expressions.gen_expr(expr.target)
        local value_expr = Expressions.gen_expr(expr.value)

        -- Check if target is a pointer variable
        if expr.target.kind == "identifier" then
            local var_info = ctx():get_var_info(expr.target.name)
            if var_info and var_info.type and var_info.type.kind == "pointer" then
                -- Target is a pointer. Check if value is a struct literal or identifier
                if expr.value.kind == "struct_literal" or
                   (expr.value.kind == "identifier" and not ctx():is_pointer_var(expr.value.name)) then
                    -- Wrap value in heap allocation (implicit allocation - assignment)
                    local type_name = ctx():c_type(var_info.type.to)
                    value_expr = string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
                        type_name, ctx():malloc_call("sizeof(" .. type_name .. ")", false), value_expr)
                end
            end
        end

        return string.format("(%s = %s)", target_expr, value_expr)
    elseif expr.kind == "static_method_call" then
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

            -- Generate function call with caller-controlled mutability semantics
            local args = {}
            for i, a in ipairs(resolved_args) do
                local arg_expr = Expressions.gen_expr(a)

                -- Apply caller-controlled mutability semantics
                if #method.params >= i then
                    local param = method.params[i]
                    local param_is_mut = param.mut or (param.type.kind == "pointer" and param.type.is_mut)

                    if a.kind == "identifier" then
                        local arg_type = ctx():get_var_type(a.name)

                        -- If arg is a struct pointer and param is NOT mut (expects value), dereference
                        if arg_type and arg_type.kind == "pointer" and not param_is_mut then
                            local base_type = arg_type.to
                            if base_type and base_type.kind == "named_type" and ctx():is_struct_type(base_type) then
                                -- Dereference to pass by value
                                arg_expr = "*" .. arg_expr
                            end
                        elseif arg_type and arg_type.kind ~= "pointer" and param_is_mut then
                            -- Arg is a value but param expects pointer, add &
                            arg_expr = "&" .. arg_expr
                        end
                    end
                end

                table.insert(args, arg_expr)
            end
            return string.format("%s(%s)", method_name, join(args, ", "))
        else
            error(string.format("Unknown method %s on type %s", method_name, type_name))
        end
    elseif expr.kind == "compound_assign" then
        -- Compound assignment: x += y becomes x = x + y
        return string.format("(%s = %s %s %s)", Expressions.gen_expr(expr.target), Expressions.gen_expr(expr.target), expr.operator, Expressions.gen_expr(expr.value))
    elseif expr.kind == "call" then
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
                local obj_expr = Expressions.gen_expr(obj)

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
                    table.insert(args, Expressions.gen_expr(a))
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
                local obj_expr = Expressions.gen_expr(obj)

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
                    table.insert(args, Expressions.gen_expr(a))
                end

                return string.format("%s(%s)", method_name, join(args, ", "))
            end
        end

        -- Regular function call
        local callee = Expressions.gen_expr(expr.callee)
        local args = {}

        -- NEW SEMANTICS: Caller controls mutability
        -- - Without mut: pass value (dereference struct pointers)
        -- - With mut: pass pointer (keep struct pointers as-is)
        if expr.callee.kind == "identifier" and ctx().functions["__global__"] then
            local func_def = ctx().functions["__global__"][expr.callee.name]
            if func_def then
                -- Resolve arguments (handle named args and defaults)
                local resolved_args = ctx():resolve_arguments(expr.callee.name, expr.args, func_def.params)

                for i, a in ipairs(resolved_args) do
                    if a.kind == "mut_arg" then
                        -- Caller uses mut keyword - wants to pass by reference
                        local param = func_def.params[i]
                        local param_is_mut = param and (param.mut or (param.type.kind == "pointer" and param.type.is_mut))

                        if not param_is_mut then
                            -- Parameter doesn't accept mut - ignore the mut from caller
                            -- Treat it as a regular (non-mut) argument instead
                            io.stderr:write(string.format("Warning: passing mut argument %d to function '%s' but parameter '%s' is not mut. Ignoring mut keyword.\n",
                                i, expr.callee.name, param.name))

                            -- Generate as if it were a non-mut argument
                            local arg_expr = Expressions.gen_expr(a.expr)

                            -- Dereference if it's a struct pointer and param expects value
                            if a.expr.kind == "identifier" then
                                local var_type = ctx():get_var_type(a.expr.name)
                                if var_type and var_type.kind == "pointer" and not param_is_mut then
                                    local base_type = var_type.to
                                    if base_type and base_type.kind == "named_type" and ctx():is_struct_type(base_type) then
                                        -- Dereference to pass by value
                                        arg_expr = "*" .. arg_expr
                                    end
                                end
                            end
                            table.insert(args, arg_expr)
                        else
                            -- Parameter is mut - pass by reference as intended
                            local arg_expr = Expressions.gen_expr(a.expr)
                            -- If the argument is a struct variable (which is internally a pointer),
                            -- just pass it as-is (it's already a pointer)
                            table.insert(args, arg_expr)
                        end
                    else
                        -- Regular argument (no mut keyword) - caller wants pass-by-value
                        local arg_expr = Expressions.gen_expr(a)

                        -- If argument is a struct variable (internally a pointer)
                        -- and parameter expects a value, dereference it
                        if a.kind == "identifier" and func_def.params[i] then
                            local var_type = ctx():get_var_type(a.name)
                            local param = func_def.params[i]
                            local param_is_mut = param.mut or (param.type.kind == "pointer" and param.type.is_mut)

                            -- If var is a struct pointer and param is NOT mut (expects value), dereference
                            if var_type and var_type.kind == "pointer" and not param_is_mut then
                                local base_type = var_type.to
                                if base_type and base_type.kind == "named_type" and ctx():is_struct_type(base_type) then
                                    -- Dereference to pass by value
                                    arg_expr = "*" .. arg_expr
                                end
                            end
                        end

                        table.insert(args, arg_expr)
                    end
                end
            else
                for _, a in ipairs(expr.args) do
                    table.insert(args, Expressions.gen_expr(a))
                end
            end
        else
            for _, a in ipairs(expr.args) do
                table.insert(args, Expressions.gen_expr(a))
            end
        end

        if builtin_calls[callee] then
            return builtin_calls[callee](args)
        end
        return string.format("%s(%s)", callee, join(args, ", "))
    elseif expr.kind == "field" then
        local obj_expr = Expressions.gen_expr(expr.object)
        -- Determine if we need -> or .
        -- Check if the object is an identifier and if its type is a pointer
        local use_arrow = false
        if expr.object.kind == "identifier" then
            local var_type = ctx():get_var_type(expr.object.name)
            if var_type and ctx():is_pointer_type(var_type) then
                use_arrow = true
            end
        elseif expr.object.kind == "unary" and expr.object.op == "*" then
            -- Explicit dereference, use .
            use_arrow = false
        end
        local accessor = use_arrow and "->" or "."
        return string.format("%s%s%s", obj_expr, accessor, expr.field)
    elseif expr.kind == "struct_literal" then
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, Expressions.gen_expr(f.value)))
        end
        -- In implicit pointer model, struct literals should return heap-allocated pointers
        -- to avoid dangling pointer issues when returned from functions.
        -- 
        -- Memory management note: The allocated memory must be managed by the caller.
        -- If assigned to a variable, automatic scope-based cleanup will free it.
        -- Temporary struct literals not assigned to variables will leak memory
        -- (this is acceptable for short-lived programs but should be improved).
        local initializer = string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = (Type){ fields... }; _ptr; })
        return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
            expr.type_name, ctx():malloc_call("sizeof(" .. expr.type_name .. ")", false), initializer)
    elseif expr.kind == "new_heap" then
        -- new Type { fields... }
        -- Allocate on heap and initialize fields
        -- Note: Automatic scope-based cleanup implemented - freed at scope exit
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, Expressions.gen_expr(f.value)))
        end
        local initializer = string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = (Type){ fields... }; _ptr; })
        -- Explicit allocation with 'new' keyword
        return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
            expr.type_name, ctx():malloc_call("sizeof(" .. expr.type_name .. ")", true), initializer)
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end


return Expressions
