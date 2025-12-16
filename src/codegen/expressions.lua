-- Expression generation for code generation
-- Handles all expression types: literals, operators, calls, casts, etc.

local Expressions = {}

local function ctx() return _G.Codegen end

-- Constants
local MAP_MIN_CAPACITY = 16  -- Minimum capacity for newly allocated maps

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
            return ctx().debug and "true" or "false"
        else
            error(string.format("Unknown directive: #%s at %d:%d", expr.name, expr.line, expr.col))
        end
    elseif expr.kind == "identifier" then
        return expr.name
    elseif expr.kind == "mut_arg" then
        -- Caller-controlled mutability: mut arg means caller allows mutation
        -- If the expression is already a pointer type, just pass it
        -- If it's a value type, take its address
        local inner_expr = Expressions.gen_expr(expr.expr)
        
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
    elseif expr.kind == "cast" then
        -- expr as Type -> (Type)expr
        local target_type_str = ctx():c_type(expr.target_type)
        local expr_str = Expressions.gen_expr(expr.expr)
        
        -- Handle pointer casting
        if expr.target_type.kind == "pointer" then
            target_type_str = ctx():c_type(expr.target_type.to) .. "*"
        end

        return string.format("((%s)%s)", target_type_str, expr_str)
    elseif expr.kind == "optional_cast" then
        -- expr as? Type -> returns Type directly (not pointer)
        -- For now, performs regular cast. Future: add runtime validation
        local target_type_str = ctx():c_type(expr.target_type)
        local expr_str = Expressions.gen_expr(expr.expr)
        
        -- Handle pointer casting
        if expr.target_type.kind == "pointer" then
            target_type_str = ctx():c_type(expr.target_type.to) .. "*"
        end

        -- Perform the cast (same as regular cast for now)
        -- TODO: Add runtime type checking to return sentinel/zero on failure
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
    elseif expr.kind == "sizeof" then
        -- Handle 'sizeof' built-in that returns the size in bytes
        local expr_type = ctx():infer_type(expr.expr)
        if not expr_type then
            error("Cannot infer type for 'sizeof' expression")
        end
        return ctx():sizeof_expr(expr_type)
    elseif expr.kind == "unary" then
        if expr.op == "not" then
            return string.format("(!%s)", Expressions.gen_expr(expr.operand))
        else
            return string.format("(%s%s)", expr.op, Expressions.gen_expr(expr.operand))
        end
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
                
                -- Warning: reassigning a pointer to another address
                if var_type.kind == "pointer" then
                    io.stderr:write(string.format("Warning: Reassigning pointer '%s' to another address (potential dangling pointer risk)\n", expr.target.name))
                end
            end
        elseif expr.target.kind == "field" then
            -- Check if target object variable is mutable
            if expr.target.object.kind == "identifier" then
                local var_info = ctx():get_var_info(expr.target.object.name)
                if var_info then
                    local var_type = ctx():get_var_type(expr.target.object.name)
                    -- For pointers: need the variable to be mutable to modify through it
                    if var_type and var_type.kind == "pointer" then
                        if not var_info.mutable then
                            error(string.format("Cannot assign to field '%s' through immutable pointer '%s'", expr.target.field, expr.target.object.name))
                        end
                    elseif not var_info.mutable then
                        -- Value type and not mutable - error
                        error(string.format("Cannot assign to field '%s' of immutable variable '%s'", expr.target.field, expr.target.object.name))
                    end
                end
            end
        end

        local target_expr = Expressions.gen_expr(expr.target)
        local value_expr = Expressions.gen_expr(expr.value)

        -- In explicit pointer model, no automatic conversions
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

            -- Generate function call - no automatic addressing/dereferencing in explicit model
            local args = {}
            for i, a in ipairs(resolved_args) do
                table.insert(args, Expressions.gen_expr(a))
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

        -- In explicit pointer model, no automatic conversions
        -- User must use & and * explicitly
        if expr.callee.kind == "identifier" and ctx().functions["__global__"] then
            local func_def = ctx().functions["__global__"][expr.callee.name]
            if func_def then
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
                                table.insert(varargs_exprs, Expressions.gen_expr(varg))
                            end
                            local element_type = Codegen.Types.c_type(func_def.params[#func_def.params].type.element_type)
                            local array_literal = string.format("(%s[]){%s}", element_type, join(varargs_exprs, ", "))
                            table.insert(args, array_literal)
                            table.insert(args, tostring(#a.args))
                        end
                    else
                        table.insert(args, Expressions.gen_expr(a))
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
    elseif expr.kind == "index" then
        -- Array indexing: arr[index]
        local array_expr = Expressions.gen_expr(expr.array)
        local index_expr = Expressions.gen_expr(expr.index)
        return string.format("%s[%s]", array_expr, index_expr)
    elseif expr.kind == "field" then
        local obj_expr = Expressions.gen_expr(expr.object)
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
    elseif expr.kind == "struct_literal" then
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, Expressions.gen_expr(f.value)))
        end
        -- In explicit pointer model, struct literals are just values
        -- Use compound literal syntax: (Type){ fields... }
        return string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
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
    elseif expr.kind == "new_array" then
        -- new [elements...] - heap-allocated array
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type) * N); _ptr[0] = elem1; _ptr[1] = elem2; ...; _ptr; })
        local element_parts = {}
        for i, elem in ipairs(expr.elements) do
            table.insert(element_parts, Expressions.gen_expr(elem))
        end
        
        -- Get element type from inferred type
        local element_type = expr.inferred_type and expr.inferred_type.element_type
        if not element_type then
            error("new_array expression missing inferred type")
        end
        local element_type_str = ctx():c_type(element_type)
        local array_size = #expr.elements
        
        -- Build the expression statement block
        local statements = {}
        table.insert(statements, string.format("%s* _ptr = %s", 
            element_type_str, 
            ctx():malloc_call(string.format("sizeof(%s) * %d", element_type_str, array_size), true)))
        
        for i, elem_expr in ipairs(element_parts) do
            table.insert(statements, string.format("_ptr[%d] = %s", i-1, elem_expr))
        end
        
        table.insert(statements, "_ptr")
        
        return string.format("({ %s; })", join(statements, "; "))
    elseif expr.kind == "new_map" then
        -- new map[K]V { key: value, ... } - heap-allocated map
        -- Generate a simple linear search implementation for now
        local key_type = expr.key_type
        local value_type = expr.value_type
        local key_type_str = ctx():c_type(key_type)
        local value_type_str = ctx():c_type(value_type)
        
        -- Generate map struct type name
        local map_type_name = "czar_map_" .. key_type_str:gsub("%*", "ptr") .. "_" .. value_type_str:gsub("%*", "ptr")
        
        -- Register map type for later struct generation
        if not ctx().map_types then
            ctx().map_types = {}
        end
        local map_key = key_type_str .. "_" .. value_type_str
        if not ctx().map_types[map_key] then
            ctx().map_types[map_key] = {
                map_type_name = map_type_name,
                key_type = key_type,
                value_type = value_type,
                key_type_str = key_type_str,
                value_type_str = value_type_str
            }
        end
        
        -- Build initialization code
        local statements = {}
        local capacity = math.max(MAP_MIN_CAPACITY, #expr.entries * 2)
        table.insert(statements, string.format("%s* _map = %s", 
            map_type_name, 
            ctx():malloc_call(string.format("sizeof(%s)", map_type_name), true)))
        table.insert(statements, string.format("_map->capacity = %d", capacity))
        table.insert(statements, string.format("_map->size = %d", #expr.entries))
        table.insert(statements, string.format("_map->keys = %s", 
            ctx():malloc_call(string.format("sizeof(%s) * %d", key_type_str, capacity), true)))
        table.insert(statements, string.format("_map->values = %s", 
            ctx():malloc_call(string.format("sizeof(%s) * %d", value_type_str, capacity), true)))
        
        -- Initialize entries
        for i, entry in ipairs(expr.entries) do
            local key_expr = Expressions.gen_expr(entry.key)
            local value_expr = Expressions.gen_expr(entry.value)
            table.insert(statements, string.format("_map->keys[%d] = %s", i-1, key_expr))
            table.insert(statements, string.format("_map->values[%d] = %s", i-1, value_expr))
        end
        
        table.insert(statements, "_map")
        
        return string.format("({ %s; })", join(statements, "; "))
    elseif expr.kind == "array_literal" then
        -- Array literal: { expr1, expr2, ... }
        local parts = {}
        for _, elem in ipairs(expr.elements) do
            table.insert(parts, Expressions.gen_expr(elem))
        end
        return string.format("{ %s }", join(parts, ", "))
    elseif expr.kind == "slice" then
        -- Slice: arr[start:end]
        -- In C, this is a pointer to the start element
        -- We'll generate: &arr[start]
        local array_expr = Expressions.gen_expr(expr.array)
        local start_expr = Expressions.gen_expr(expr.start)
        return string.format("&%s[%s]", array_expr, start_expr)
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end


return Expressions
