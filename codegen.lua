-- Simple C code generator for the Czar AST produced by parser.lua.
-- Supports structs, functions, blocks, variable declarations, expressions,
-- and struct literals sufficient for the example program.

local Codegen = {}
Codegen.__index = Codegen

-- Constants
local SELF_PARAM_NAME = "self"

local builtin_calls = {
    print_i32 = function(args)
        return string.format('printf("%%d\\n", %s)', args[1])
    end,
}

local function join(list, sep)
    return table.concat(list, sep or "")
end

function Codegen.new(ast)
    local self = {
        ast = ast,
        structs = {},
        functions = {},  -- Store function/method definitions indexed by receiver type for method call resolution
        out = {},
        scope_stack = {},
    }
    return setmetatable(self, Codegen)
end

function Codegen:emit(line)
    table.insert(self.out, line)
end

function Codegen:collect_structs_and_functions()
    for _, item in ipairs(self.ast.items or {}) do
        if item.kind == "struct" then
            self.structs[item.name] = item
        elseif item.kind == "function" then
            -- Check if this function returns null (making return type a pointer)
            if item.return_type and item.return_type.kind == "named_type" then
                local returns_null = self:function_returns_null(item)
                if returns_null and self.structs[item.return_type.name] then
                    -- Convert return type to pointer
                    item.return_type = { kind = "pointer", to = item.return_type }
                end
            end
            
            -- Store function info for method call resolution
            local func_name = item.name
            if item.receiver_type then
                -- This is a method, store it by receiver type and method name
                if not self.functions[item.receiver_type] then
                    self.functions[item.receiver_type] = {}
                end
                self.functions[item.receiver_type][item.name] = item
            else
                -- Regular function, also check if it's an extension method
                if #item.params > 0 and item.params[1].name == SELF_PARAM_NAME then
                    -- Extension method: first param is self
                    local self_type = item.params[1].type
                    local receiver_type_name = nil
                    if self_type.kind == "pointer" and self_type.to.kind == "named_type" then
                        receiver_type_name = self_type.to.name
                    elseif self_type.kind == "named_type" then
                        receiver_type_name = self_type.name
                    end
                    if receiver_type_name then
                        if not self.functions[receiver_type_name] then
                            self.functions[receiver_type_name] = {}
                        end
                        self.functions[receiver_type_name][func_name] = item
                    end
                end
                -- Store all regular functions by name for warning checks
                if not self.functions["__global__"] then
                    self.functions["__global__"] = {}
                end
                self.functions["__global__"][func_name] = item
            end
        end
    end
end

function Codegen:function_returns_null(fn)
    -- Recursively check if function body contains return null or returns a pointer expression
    local function check_stmt(stmt)
        if stmt.kind == "return" then
            if stmt.value then
                local val = stmt.value
                -- Direct null return
                if val.kind == "null" then
                    return true
                end
                -- Returns identifier that's a pointer
                if val.kind == "identifier" and self:is_pointer_var(val.name) then
                    return true
                end
                -- Returns new_heap, clone, null_check, etc.
                if val.kind == "new_heap" or val.kind == "clone" or val.kind == "null_check" then
                    return true
                end
            end
        elseif stmt.kind == "if" then
            if check_stmt(stmt.then_block) then return true end
            if stmt.else_block and check_stmt(stmt.else_block) then return true end
        elseif stmt.kind == "while" then
            if check_stmt(stmt.body) then return true end
        end
        return false
    end
    
    local function check_block(block)
        for _, stmt in ipairs(block.statements or {}) do
            if check_stmt(stmt) then
                return true
            end
        end
        return false
    end
    
    return check_block(fn.body)
end

function Codegen:is_pointer_type(type_node)
    return type_node and type_node.kind == "pointer"
end

function Codegen:c_type(type_node)
    if not type_node then return "void" end
    if type_node.kind == "pointer" then
        return self:c_type(type_node.to) .. "*"
    elseif type_node.kind == "named_type" then
        local name = type_node.name
        if name == "i32" then
            return "int32_t"
        elseif name == "i64" then
            return "int64_t"
        elseif name == "u32" then
            return "uint32_t"
        elseif name == "u64" then
            return "uint64_t"
        elseif name == "f32" then
            return "float"
        elseif name == "f64" then
            return "double"
        elseif name == "bool" then
            return "bool"
        elseif name == "void" then
            return "void"
        else
            return name
        end
    else
        error("unknown type node kind: " .. tostring(type_node.kind))
    end
end

function Codegen:c_type_in_struct(type_node, struct_name)
    if not type_node then return "void" end
    if type_node.kind == "pointer" then
        local base_type = type_node.to
        if base_type.kind == "named_type" and base_type.name == struct_name then
            -- Self-referential pointer, use "struct Name*"
            return "struct " .. base_type.name .. "*"
        else
            return self:c_type(base_type) .. "*"
        end
    elseif type_node.kind == "named_type" then
        -- In implicit pointer model, struct-typed fields should be pointers
        if self:is_struct_type(type_node) then
            -- Check for self-referential (non-pointer) - treat as pointer
            if type_node.name == struct_name then
                return "struct " .. type_node.name .. "*"
            else
                return self:c_type(type_node) .. "*"
            end
        else
            return self:c_type(type_node)
        end
    else
        return self:c_type(type_node)
    end
end

function Codegen:gen_struct(item)
    self:emit("typedef struct " .. item.name .. " {")
    for _, field in ipairs(item.fields) do
        self:emit(string.format("    %s %s;", self:c_type_in_struct(field.type, item.name), field.name))
    end
    self:emit("} " .. item.name .. ";")
    self:emit("")
end

function Codegen:push_scope()
    table.insert(self.scope_stack, {})
end

function Codegen:pop_scope()
    table.remove(self.scope_stack)
end

function Codegen:add_var(name, type_node, mutable)
    if #self.scope_stack > 0 then
        self.scope_stack[#self.scope_stack][name] = {
            type = type_node,
            mutable = mutable or false
        }
    end
end

function Codegen:get_var_type(name)
    for i = #self.scope_stack, 1, -1 do
        local var_info = self.scope_stack[i][name]
        if var_info then
            return var_info.type
        end
    end
    return nil
end

function Codegen:get_var_info(name)
    for i = #self.scope_stack, 1, -1 do
        local var_info = self.scope_stack[i][name]
        if var_info then
            return var_info
        end
    end
    return nil
end

function Codegen:get_expr_type(expr, depth)
    -- Helper function to determine the type of an expression
    -- depth parameter prevents infinite recursion
    depth = depth or 0
    if depth > 10 then
        -- Prevent infinite recursion for deeply nested expressions
        return nil
    end
    
    if expr.kind == "identifier" then
        local var_type = self:get_var_type(expr.name)
        if var_type then
            -- If it's a pointer type, return the pointed-to type
            if type(var_type) == "table" and var_type.kind == "pointer" then
                return self:type_name(var_type.to)
            else
                return self:type_name(var_type)
            end
        end
    elseif expr.kind == "field" then
        -- Get the type of the object and look up the field type
        local obj_type = self:get_expr_type(expr.object, depth + 1)
        if obj_type and self.structs[obj_type] then
            local struct_def = self.structs[obj_type]
            for _, field in ipairs(struct_def.fields) do
                if field.name == expr.field then
                    return self:type_name(field.type)
                end
            end
        end
    end
    return nil
end

function Codegen:type_name(type_node)
    -- Helper to extract type name from a type node
    if type(type_node) == "string" then
        return type_node
    elseif type(type_node) == "table" then
        if type_node.kind == "pointer" then
            return self:type_name(type_node.to)
        elseif type_node.name then
            return type_node.name
        end
    end
    return nil
end

function Codegen:is_struct_type(type_node)
    -- Check if a type is a struct type
    local type_name = self:type_name(type_node)
    return type_name and self.structs[type_name] ~= nil
end

function Codegen:is_pointer_var(name)
    -- Check if a variable is stored as a pointer type
    local var_info = self:get_var_info(name)
    return var_info and var_info.type and var_info.type.kind == "pointer"
end

function Codegen:gen_params(params)
    local parts = {}
    for i, p in ipairs(params) do
        local param_name = p.name
        -- Generate unique name for underscore parameters
        if param_name == "_" then
            param_name = "_unused_" .. i
        end
        
        local type_str = self:c_type(p.type)
        
        -- For parameters, check if this is a mutable pointer (mut parameter)
        -- If it's a pointer type with is_mut flag, it should be non-const
        -- Otherwise, struct pointers should be const (for pass-by-value semantics with implicit pointers)
        if p.type.kind == "pointer" and p.type.is_mut then
            -- Mutable parameter - no const
            table.insert(parts, string.format("%s %s", type_str, param_name))
        else
            -- For other parameters, leave as-is (c_type handles it)
            table.insert(parts, string.format("%s %s", type_str, param_name))
        end
    end
    return join(parts, ", ")
end

function Codegen:gen_block(block)
    self:push_scope()
    self:emit("{")
    for _, stmt in ipairs(block.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    self:emit("}")
    self:pop_scope()
end

function Codegen:gen_statement(stmt)
    if stmt.kind == "return" then
        return "return " .. self:gen_expr(stmt.value) .. ";"
    elseif stmt.kind == "discard" then
        -- Discard statement: _ = expr becomes (void)expr;
        return "(void)(" .. self:gen_expr(stmt.value) .. ");"
    elseif stmt.kind == "var_decl" then
        -- In implicit pointer model, all struct-typed variables are pointers
        local is_struct_type = self:is_struct_type(stmt.type)
        
        if is_struct_type then
            -- Struct types are always pointers in storage
            local ptr_type = { kind = "pointer", to = stmt.type, is_clone = true }
            self:add_var(stmt.name, ptr_type, stmt.mutable)
            local prefix = stmt.mutable and "" or "const "
            local decl = string.format("%s%s* %s", prefix, self:c_type(stmt.type), stmt.name)
            if stmt.init then
                local init_expr = self:gen_expr(stmt.init)
                -- Struct literals are already addresses, others might need special handling
                decl = decl .. " = " .. init_expr
            end
            return decl .. ";"
        else
            -- Non-struct types: check for special initializers
            local is_pointer_expr = false
            if stmt.init then
                local init_kind = stmt.init.kind
                if init_kind == "clone" or init_kind == "new_heap" or init_kind == "null" or 
                   init_kind == "null_check" or init_kind == "null_coalesce" or init_kind == "safe_nav" then
                    is_pointer_expr = true
                elseif init_kind == "identifier" then
                    is_pointer_expr = self:is_pointer_var(stmt.init.name)
                elseif init_kind == "call" and stmt.init.callee.kind == "identifier" then
                    local func_info = self.functions["__global__"] and self.functions["__global__"][stmt.init.callee.name]
                    if func_info and func_info.return_type and func_info.return_type.kind == "pointer" then
                        is_pointer_expr = true
                    end
                end
            end
            
            if is_pointer_expr then
                local ptr_type = { kind = "pointer", to = stmt.type, is_clone = true }
                self:add_var(stmt.name, ptr_type, stmt.mutable)
                local prefix = stmt.mutable and "" or "const "
                local decl = string.format("%s%s* %s", prefix, self:c_type(stmt.type), stmt.name)
                if stmt.init then
                    decl = decl .. " = " .. self:gen_expr(stmt.init)
                end
                return decl .. ";"
            else
                self:add_var(stmt.name, stmt.type, stmt.mutable)
                local prefix = stmt.mutable and "" or "const "
                local decl = string.format("%s%s %s", prefix, self:c_type(stmt.type), stmt.name)
                if stmt.init then
                    decl = decl .. " = " .. self:gen_expr(stmt.init)
                end
                return decl .. ";"
            end
        end
    elseif stmt.kind == "expr_stmt" then
        -- Check if this is an underscore assignment in expression form
        local expr = stmt.expression
        if expr.kind == "assign" and expr.target.kind == "identifier" and expr.target.name == "_" then
            -- Discard assignment: _ = expr becomes (void)expr;
            return "(void)(" .. self:gen_expr(expr.value) .. ");"
        end
        return self:gen_expr(stmt.expression) .. ";"
    elseif stmt.kind == "if" then
        return self:gen_if(stmt)
    elseif stmt.kind == "while" then
        return self:gen_while(stmt)
    else
        error("unknown statement kind: " .. tostring(stmt.kind))
    end
end

function Codegen:gen_if(stmt)
    local parts = {}
    table.insert(parts, "if (" .. self:gen_expr(stmt.condition) .. ") {")
    for _, s in ipairs(stmt.then_block.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    if stmt.else_block then
        table.insert(parts, "} else {")
        for _, s in ipairs(stmt.else_block.statements) do
            table.insert(parts, "    " .. self:gen_statement(s))
        end
    end
    table.insert(parts, "}")
    return join(parts, "\n    ")
end

function Codegen:gen_while(stmt)
    local parts = {}
    table.insert(parts, "while (" .. self:gen_expr(stmt.condition) .. ") {")
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    table.insert(parts, "}")
    return join(parts, "\n    ")
end

function Codegen:gen_expr(expr)
    if expr.kind == "int" then
        return tostring(expr.value)
    elseif expr.kind == "string" then
        return string.format("\"%s\"", expr.value)
    elseif expr.kind == "bool" then
        return expr.value and "true" or "false"
    elseif expr.kind == "null" then
        return "NULL"
    elseif expr.kind == "identifier" then
        -- Check if this is a clone variable that needs dereferencing
        local var_type = self:get_var_type(expr.name)
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
            local var_type = self:get_var_type(expr.expr.name)
            if var_type and var_type.kind == "pointer" and var_type.is_clone then
                -- This is a heap-allocated value (clone or new), already a pointer
                return self:gen_expr(expr.expr)
            end
        end
        local inner_expr = self:gen_expr(expr.expr)
        return "&" .. inner_expr
    elseif expr.kind == "cast" then
        -- cast<Type> expr -> (Type)expr
        local target_type_str = self:c_type(expr.target_type)
        local expr_str = self:gen_expr(expr.expr)
        
        -- Check if we're casting a clone variable that needs dereferencing
        if expr.expr.kind == "identifier" then
            local var_type = self:get_var_type(expr.expr.name)
            if var_type and var_type.kind == "pointer" and var_type.is_clone then
                expr_str = "*" .. expr_str
            end
        end
        
        return string.format("((%s)%s)", target_type_str, expr_str)
    elseif expr.kind == "clone" then
        -- clone(expr) or clone<Type>(expr)
        -- Allocate on heap and copy the value
        local expr_str = self:gen_expr(expr.expr)
        local source_type = nil
        local target_type = nil
        
        -- Determine source type from expression
        if expr.expr.kind == "identifier" then
            source_type = self:get_var_type(expr.expr.name)
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
        
        local target_type_str = self:c_type(actual_type)
        local source_expr = needs_deref and ("*" .. expr_str) or expr_str
        
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = *source_ptr; _ptr; })
        if expr.target_type and source_type then
            -- With cast
            return string.format("({ %s* _ptr = malloc(sizeof(%s)); *_ptr = (%s)%s; _ptr; })", 
                target_type_str, target_type_str, target_type_str, source_expr)
        else
            -- Without cast
            return string.format("({ %s* _ptr = malloc(sizeof(%s)); *_ptr = %s; _ptr; })", 
                target_type_str, target_type_str, source_expr)
        end
    elseif expr.kind == "binary" then
        -- Handle null coalescing operator
        if expr.op == "??" then
            local left = self:gen_expr(expr.left)
            local right = self:gen_expr(expr.right)
            -- For null coalescing, we use a statement expression with a temporary
            -- This works for pointer types primarily
            return string.format("({ __auto_type _tmp = %s; _tmp ? _tmp : (%s); })", left, right)
        else
            return string.format("(%s %s %s)", self:gen_expr(expr.left), expr.op, self:gen_expr(expr.right))
        end
    elseif expr.kind == "unary" then
        return string.format("(%s%s)", expr.op, self:gen_expr(expr.operand))
    elseif expr.kind == "null_check" then
        -- Null check operator: expr!!
        local operand = self:gen_expr(expr.operand)
        -- Generate: assert-like behavior
        return string.format("({ __auto_type _tmp = %s; if (!_tmp) { fprintf(stderr, \"null check failed\\n\"); abort(); } _tmp; })", operand)
    elseif expr.kind == "safe_nav" then
        -- Safe navigation: expr?.field
        local obj_expr = self:gen_expr(expr.object)
        -- Determine if we need -> or .
        local use_arrow = false
        if expr.object.kind == "identifier" then
            local var_type = self:get_var_type(expr.object.name)
            if var_type and self:is_pointer_type(var_type) then
                use_arrow = true
            end
        end
        local accessor = use_arrow and "->" or "."
        -- For safe navigation, return the field or a default value (0 for numbers, NULL for pointers)
        return string.format("({ __auto_type _obj = %s; _obj ? _obj%s%s : 0; })", obj_expr, accessor, expr.field)
    elseif expr.kind == "assign" then
        -- Check if target is an immutable variable
        if expr.target.kind == "identifier" then
            local var_type = self:get_var_type(expr.target.name)
            if var_type then
                -- Check if variable is immutable (we need to track this)
                local var_info = self:get_var_info(expr.target.name)
                if var_info and not var_info.mutable then
                    error(string.format("Cannot assign to immutable variable '%s'", expr.target.name))
                end
            end
        elseif expr.target.kind == "field" then
            -- Check if target object variable is mutable
            -- In the new model, field mutability comes from the variable, not the field
            if expr.target.object.kind == "identifier" then
                local var_info = self:get_var_info(expr.target.object.name)
                if var_info and not var_info.mutable then
                    error(string.format("Cannot assign to field '%s' of immutable variable '%s'", expr.target.field, expr.target.object.name))
                end
            end
        end
        
        -- Handle assignment with implicit pointer conversion
        -- If target is a pointer and value is not, we need to heap-allocate
        local target_expr = self:gen_expr(expr.target)
        local value_expr = self:gen_expr(expr.value)
        
        -- Check if target is a pointer variable
        if expr.target.kind == "identifier" then
            local var_info = self:get_var_info(expr.target.name)
            if var_info and var_info.type and var_info.type.kind == "pointer" then
                -- Target is a pointer. Check if value is a struct literal or identifier
                if expr.value.kind == "struct_literal" or 
                   (expr.value.kind == "identifier" and not self:is_pointer_var(expr.value.name)) then
                    -- Wrap value in heap allocation (new)
                    local type_name = self:c_type(var_info.type.to)
                    value_expr = string.format("({ %s* _ptr = malloc(sizeof(%s)); *_ptr = %s; _ptr; })", 
                        type_name, type_name, value_expr)
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
        if self.functions[type_name] then
            method = self.functions[type_name][method_name]
        end

        if method then
            -- Generate function call with auto-addressing if needed
            local args = {}
            for i, a in ipairs(expr.args) do
                local arg_expr = self:gen_expr(a)

                -- Handle auto-addressing for first parameter (self)
                if i == 1 and #method.params > 0 then
                    local first_param_type = method.params[1].type
                    if first_param_type.kind == "pointer" then
                        -- Method expects a pointer, check if arg is a value
                        local arg_type = nil
                        if a.kind == "identifier" then
                            arg_type = self:get_var_type(a.name)
                        end

                        if arg_type and arg_type.kind ~= "pointer" then
                            -- Arg is a value, add &
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
        return string.format("(%s = %s %s %s)", self:gen_expr(expr.target), self:gen_expr(expr.target), expr.operator, self:gen_expr(expr.value))
    elseif expr.kind == "call" then
        -- Check if this is a method call (callee is a method_ref or field expression)
        if expr.callee.kind == "method_ref" then
            -- Method call using colon: obj:method()
            local obj = expr.callee.object
            local method_name = expr.callee.method

            -- Determine the type of the object
            local obj_type = nil
            if obj.kind == "identifier" then
                obj_type = self:get_var_type(obj.name)
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
            if receiver_type_name and self.functions[receiver_type_name] then
                method = self.functions[receiver_type_name][method_name]
            end

            if method then
                -- This is a method call, transform to function call with object as first arg
                local args = {}

                -- Add the object as the first argument
                -- Check if we need to address it
                local first_param_type = method.params[1].type
                local obj_expr = self:gen_expr(obj)

                if first_param_type.kind == "pointer" then
                    -- Method expects a pointer
                    if obj_type and obj_type.kind ~= "pointer" then
                        -- Object is a value, add &
                        obj_expr = "&" .. obj_expr
                    end
                end

                table.insert(args, obj_expr)

                -- Add the rest of the arguments
                for _, a in ipairs(expr.args) do
                    table.insert(args, self:gen_expr(a))
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
                obj_type = self:get_var_type(obj.name)
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
            if receiver_type_name and self.functions[receiver_type_name] then
                method = self.functions[receiver_type_name][method_name]
            end

            if method then
                -- This is a method call, transform to function call with object as first arg
                local args = {}

                -- Add the object as the first argument
                -- Check if we need to address it
                local first_param_type = method.params[1].type
                local obj_expr = self:gen_expr(obj)

                if first_param_type.kind == "pointer" then
                    -- Method expects a pointer
                    if obj_type and obj_type.kind ~= "pointer" then
                        -- Object is a value, add &
                        obj_expr = "&" .. obj_expr
                    end
                end

                table.insert(args, obj_expr)

                -- Add the rest of the arguments
                for _, a in ipairs(expr.args) do
                    table.insert(args, self:gen_expr(a))
                end

                return string.format("%s(%s)", method_name, join(args, ", "))
            end
        end

        -- Regular function call
        local callee = self:gen_expr(expr.callee)
        local args = {}
        
        -- Check for mut argument warnings and handle properly
        if expr.callee.kind == "identifier" and self.functions["__global__"] then
            local func_def = self.functions["__global__"][expr.callee.name]
            if func_def then
                for i, a in ipairs(expr.args) do
                    if a.kind == "mut_arg" and func_def.params[i] then
                        local param = func_def.params[i]
                        -- Check if parameter is not a pointer (not mut)
                        if param.type.kind ~= "pointer" or not param.type.is_mut then
                            io.stderr:write(string.format("Warning: passing mut argument %d to function '%s' but parameter '%s' is not mut. Modifications will not affect caller.\n", 
                                i, expr.callee.name, param.name))
                            -- Generate without & since parameter is not mut
                            table.insert(args, self:gen_expr(a.expr))
                        else
                            -- Parameter is mut, generate with &
                            table.insert(args, self:gen_expr(a))
                        end
                    else
                        -- Regular argument - check if we need to dereference struct pointers
                        local arg_expr = self:gen_expr(a)
                        
                        -- In implicit pointer model, all struct variables are pointers
                        -- If passing to a non-mut parameter, dereference to copy the value
                        if a.kind == "identifier" and func_def.params[i] then
                            local var_type = self:get_var_type(a.name)
                            local param_type = func_def.params[i].type
                            local param_is_mut = param_type.kind == "pointer" and param_type.is_mut
                            
                            -- If var is a struct pointer and param is NOT mut, dereference for value copy
                            if var_type and var_type.kind == "pointer" and not param_is_mut then
                                if param_type.kind ~= "pointer" then
                                    -- Parameter expects value type, dereference the pointer
                                    arg_expr = "*" .. arg_expr
                                end
                            end
                        end
                        
                        table.insert(args, arg_expr)
                    end
                end
            else
                for _, a in ipairs(expr.args) do
                    table.insert(args, self:gen_expr(a))
                end
            end
        else
            for _, a in ipairs(expr.args) do
                table.insert(args, self:gen_expr(a))
            end
        end
        
        if builtin_calls[callee] then
            return builtin_calls[callee](args)
        end
        return string.format("%s(%s)", callee, join(args, ", "))
    elseif expr.kind == "field" then
        local obj_expr = self:gen_expr(expr.object)
        -- Determine if we need -> or .
        -- Check if the object is an identifier and if its type is a pointer
        local use_arrow = false
        if expr.object.kind == "identifier" then
            local var_type = self:get_var_type(expr.object.name)
            if var_type and self:is_pointer_type(var_type) then
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
            table.insert(parts, string.format(".%s = %s", f.name, self:gen_expr(f.value)))
        end
        -- In implicit pointer model, struct literals should return addresses (pointers)
        return string.format("&(%s){ %s }", expr.type_name, join(parts, ", "))
    elseif expr.kind == "new_heap" then
        -- new Type { fields... }
        -- Allocate on heap and initialize fields
        -- Note: Manual memory management - caller responsible for free()
        -- TODO: Scope-based cleanup (RAII/defer) could be added in future
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, self:gen_expr(f.value)))
        end
        local initializer = string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = (Type){ fields... }; _ptr; })
        return string.format("({ %s* _ptr = malloc(sizeof(%s)); *_ptr = %s; _ptr; })", 
            expr.type_name, expr.type_name, initializer)
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end

function Codegen:gen_function(fn)
    local name = fn.name
    local c_name = name == "main" and "main_main" or name
    
    -- In implicit pointer model, struct return types should be pointers
    local return_type_str = self:c_type(fn.return_type)
    if fn.return_type and fn.return_type.kind == "named_type" and self:is_struct_type(fn.return_type) then
        return_type_str = return_type_str .. "*"
    end
    
    local sig = string.format("%s %s(%s)", return_type_str, c_name, self:gen_params(fn.params))
    self:emit(sig)
    self:push_scope()
    self:emit("{")

    -- Add unused parameter suppressions for underscore parameters
    for i, param in ipairs(fn.params) do
        if param.name == "_" then
            local param_name = "_unused_" .. i
            self:emit("    (void)" .. param_name .. ";")
        else
            -- Add regular parameters to scope (parameters with mut are mutable)
            -- Check both param.mut and param.type.is_mut for pointer types
            local is_mutable = param.mut or (param.type.kind == "pointer" and param.type.is_mut)
            self:add_var(param.name, param.type, is_mutable or false)
        end
    end

    -- Generate function body statements
    for _, stmt in ipairs(fn.body.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    self:emit("}")
    self:pop_scope()
    self:emit("")
end

function Codegen:gen_wrapper(has_main)
    if has_main then
        self:emit("int main(void) { return main_main(); }")
    end
end

function Codegen:generate()
    self:collect_structs_and_functions()
    self:emit("#include <stdint.h>")
    self:emit("#include <stdbool.h>")
    self:emit("#include <stdio.h>")
    self:emit("#include <stdlib.h>")
    self:emit("")

    for _, item in ipairs(self.ast.items) do
        if item.kind == "struct" then
            self:gen_struct(item)
        end
    end

    local has_main = false
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            if item.name == "main" then has_main = true end
            self:gen_function(item)
        end
    end

    self:gen_wrapper(has_main)

    return join(self.out, "\n") .. "\n"
end

return function(ast)
    local gen = Codegen.new(ast)
    return gen:generate()
end
