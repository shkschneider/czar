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

function Codegen.new(ast, options)
    options = options or {}
    local self = {
        ast = ast,
        structs = {},
        functions = {},  -- Store function/method definitions indexed by receiver type for method call resolution
        out = {},
        scope_stack = {},
        heap_vars_stack = {},  -- Track heap-allocated variables per scope for automatic cleanup
        debug_memory = options.debug_memory or false,  -- Enable memory tracking and statistics
    }
    return setmetatable(self, Codegen)
end

function Codegen:emit(line)
    table.insert(self.out, line)
end

-- Get the malloc function call (with or without debug wrapper)
-- is_explicit: true for explicit 'new' allocations, false for implicit (clone, etc.)
function Codegen:malloc_call(size_expr, is_explicit)
    if self.debug_memory then
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("_czar_malloc(%s, %s)", size_expr, explicit_flag)
    else
        return string.format("malloc(%s)", size_expr)
    end
end

-- Get the free function call (with or without debug wrapper)
-- is_explicit: true for explicit 'free' statements, false for implicit scope cleanup
function Codegen:free_call(ptr_expr, is_explicit)
    if self.debug_memory then
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("_czar_free(%s, %s)", ptr_expr, explicit_flag)
    else
        return string.format("free(%s)", ptr_expr)
    end
end

-- Resolve function arguments, handling named arguments and default parameters
-- args: list of arguments from the call site (may include named_arg nodes)
-- params: list of parameters from the function definition (may include default_value)
-- Returns: list of resolved argument expressions in the correct parameter order
function Codegen:resolve_arguments(args, params)
    local resolved = {}
    local named_args = {}
    local positional_count = 0
    
    -- First pass: separate positional and named arguments
    for _, arg in ipairs(args) do
        if arg.kind == "named_arg" then
            named_args[arg.name] = arg.expr
        else
            positional_count = positional_count + 1
        end
    end
    
    -- Second pass: fill in resolved array with arguments in parameter order
    local positional_index = 1
    for i, param in ipairs(params) do
        if named_args[param.name] then
            -- Named argument provided
            resolved[i] = named_args[param.name]
        elseif positional_index <= positional_count then
            -- Positional argument provided
            -- Find the next positional argument (skip named ones)
            local arg_index = 1
            for j, arg in ipairs(args) do
                if arg.kind ~= "named_arg" then
                    if arg_index == positional_index then
                        resolved[i] = arg
                        break
                    end
                    arg_index = arg_index + 1
                end
            end
            positional_index = positional_index + 1
        elseif param.default_value then
            -- No argument provided, use default value
            resolved[i] = param.default_value
        else
            -- No argument and no default - this is an error
            error(string.format("Missing argument for parameter '%s' (no default value)", param.name))
        end
    end
    
    return resolved
end

function Codegen:collect_structs_and_functions()
    for _, item in ipairs(self.ast.items or {}) do
        if item.kind == "struct" then
            self.structs[item.name] = item
        elseif item.kind == "function" then
            -- Validate constructor/destructor signatures (new requirement)
            if item.receiver_type and (item.name == "new" or item.name == "free") then
                -- Constructor and destructor methods must have only self as parameter
                if not item.params or #item.params ~= 1 or item.params[1].name ~= "self" then
                    error(string.format("%s:%s() can only have self as parameter", item.receiver_type, item.name))
                end
            end
            
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

-- Check if a struct has a constructor method (Type:new)
function Codegen:has_constructor(struct_name)
    return self.functions[struct_name] and self.functions[struct_name]["new"]
end

-- Check if a struct has a destructor method (Type:free)
function Codegen:has_destructor(struct_name)
    return self.functions[struct_name] and self.functions[struct_name]["free"]
end

-- Generate constructor call for a struct variable
function Codegen:gen_constructor_call(struct_name, var_name)
    if self:has_constructor(struct_name) then
        return string.format("%s_constructor(%s);", struct_name, var_name)
    end
    return nil
end

-- Generate destructor call for a struct variable
function Codegen:gen_destructor_call(struct_name, var_name)
    if self:has_destructor(struct_name) then
        return string.format("%s_destructor(%s);", struct_name, var_name)
    end
    return nil
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
        elseif name == "any" then
            return "void*"
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
        local c_type = self:c_type(type_node)
        -- In implicit pointer model, check if this is a non-primitive type
        -- Primitive types: int32_t, int64_t, uint32_t, uint64_t, float, double, bool, void, void* (any)
        local is_primitive = c_type == "int32_t" or c_type == "int64_t" or 
                            c_type == "uint32_t" or c_type == "uint64_t" or
                            c_type == "float" or c_type == "double" or
                            c_type == "bool" or c_type == "void" or c_type == "void*"
        
        if not is_primitive then
            -- Non-primitive types (structs) should be pointers in implicit pointer model
            if type_node.name == struct_name then
                -- Self-referential
                return "struct " .. type_node.name .. "*"
            else
                return c_type .. "*"
            end
        else
            return c_type
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
    table.insert(self.heap_vars_stack, {})  -- Track heap vars for this scope
end

function Codegen:pop_scope()
    table.remove(self.scope_stack)
    table.remove(self.heap_vars_stack)
end

function Codegen:add_var(name, type_node, mutable, needs_free)
    if #self.scope_stack > 0 then
        self.scope_stack[#self.scope_stack][name] = {
            type = type_node,
            mutable = mutable or false,
            needs_free = needs_free or false
        }
        -- Track heap-allocated variables for automatic cleanup
        if needs_free then
            table.insert(self.heap_vars_stack[#self.heap_vars_stack], name)
        end
    end
end

function Codegen:mark_freed(name)
    -- Mark variable as already freed to prevent double-free at scope exit
    -- Note: While this has O(n²) complexity in worst case, it's acceptable because:
    -- 1. Number of variables per scope is typically small (< 10)
    -- 2. Early return after finding the variable minimizes actual iterations
    -- 3. Most variables are freed at scope exit, explicit free is rare
    for i = #self.scope_stack, 1, -1 do
        local var_info = self.scope_stack[i][name]
        if var_info then
            var_info.needs_free = false
            -- Remove from heap_vars_stack at the same scope level
            -- Start search from the scope where we found the variable
            for j = i, 1, -1 do
                local heap_vars = self.heap_vars_stack[j]
                if heap_vars then
                    for k, var_name in ipairs(heap_vars) do
                        if var_name == name then
                            table.remove(heap_vars, k)
                            return
                        end
                    end
                end
            end
            return
        end
    end
end

function Codegen:get_scope_cleanup()
    -- Generate free() calls for heap-allocated variables in current scope
    -- Returns cleanup code in reverse order (LIFO)
    local cleanup = {}
    if #self.heap_vars_stack > 0 then
        local heap_vars = self.heap_vars_stack[#self.heap_vars_stack]
        for i = #heap_vars, 1, -1 do  -- Reverse order (LIFO)
            local var_name = heap_vars[i]
            local var_info = self:get_var_info(var_name)
            if var_info and var_info.needs_free then
                -- Check if the variable is a struct with a destructor
                local var_type = var_info.type
                if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
                    local struct_name = var_type.to.name
                    local destructor_call = self:gen_destructor_call(struct_name, var_name)
                    if destructor_call then
                        table.insert(cleanup, destructor_call)
                    end
                end
                table.insert(cleanup, self:free_call(var_name, false) .. ";")  -- Implicit free (scope cleanup)
            end
        end
    end
    return cleanup
end

function Codegen:get_all_scope_cleanup()
    -- Generate free() calls for ALL heap-allocated variables in all active scopes
    -- Used for early returns to cleanup everything before exiting function
    -- Returns cleanup code in reverse order (LIFO - newest first, then older scopes)
    local cleanup = {}
    -- Iterate through all active scopes from innermost to outermost
    for scope_idx = #self.heap_vars_stack, 1, -1 do
        local heap_vars = self.heap_vars_stack[scope_idx]
        -- Within each scope, reverse order (LIFO)
        for i = #heap_vars, 1, -1 do
            local var_name = heap_vars[i]
            local var_info = self:get_var_info(var_name)
            if var_info and var_info.needs_free then
                -- Check if the variable is a struct with a destructor
                local var_type = var_info.type
                if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
                    local struct_name = var_type.to.name
                    local destructor_call = self:gen_destructor_call(struct_name, var_name)
                    if destructor_call then
                        table.insert(cleanup, destructor_call)
                    end
                end
                table.insert(cleanup, self:free_call(var_name, false) .. ";")  -- Implicit free (scope cleanup)
            end
        end
    end
    return cleanup
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

function Codegen:infer_type(expr)
    -- Infer the type of an expression
    if expr.kind == "int" then
        return { kind = "named_type", name = "i32" }
    elseif expr.kind == "bool" then
        return { kind = "named_type", name = "bool" }
    elseif expr.kind == "string" then
        return { kind = "pointer", to = { kind = "named_type", name = "char" } }
    elseif expr.kind == "null" then
        return { kind = "pointer", to = { kind = "named_type", name = "void" } }
    elseif expr.kind == "identifier" then
        return self:get_var_type(expr.name)
    elseif expr.kind == "field" then
        local obj_type = self:infer_type(expr.object)
        if obj_type then
            local type_name = self:type_name(obj_type)
            if type_name and self.structs[type_name] then
                local struct_def = self.structs[type_name]
                for _, field in ipairs(struct_def.fields) do
                    if field.name == expr.field then
                        return field.type
                    end
                end
            end
        end
    elseif expr.kind == "binary" then
        if expr.op == "==" or expr.op == "!=" or expr.op == "<" or expr.op == ">" or 
           expr.op == "<=" or expr.op == ">=" or expr.op == "and" or expr.op == "or" then
            return { kind = "named_type", name = "bool" }
        else
            return self:infer_type(expr.left)
        end
    elseif expr.kind == "unary" then
        if expr.op == "&" then
            local inner_type = self:infer_type(expr.operand)
            return { kind = "pointer", to = inner_type }
        elseif expr.op == "*" then
            local inner_type = self:infer_type(expr.operand)
            if inner_type and inner_type.kind == "pointer" then
                return inner_type.to
            end
        else
            return self:infer_type(expr.operand)
        end
    elseif expr.kind == "call" then
        if expr.callee.kind == "identifier" then
            local func_name = expr.callee.name
            local func_info = self.functions["__global__"] and self.functions["__global__"][func_name]
            if func_info then
                return func_info.return_type
            end
        elseif expr.callee.kind == "method_ref" then
            -- Handle method calls: obj:method()
            local obj_type = self:infer_type(expr.callee.object)
            if obj_type then
                local type_name = self:type_name(obj_type)
                if type_name and self.functions[type_name] then
                    local method_info = self.functions[type_name][expr.callee.method]
                    if method_info then
                        return method_info.return_type
                    end
                end
            end
        end
    elseif expr.kind == "static_method_call" then
        -- Handle static method calls: Type.method(args)
        if self.functions[expr.type_name] then
            local method_info = self.functions[expr.type_name][expr.method]
            if method_info then
                return method_info.return_type
            end
        end
    end
    return nil
end

function Codegen:types_match(type1, type2)
    -- Check if two types match
    if not type1 or not type2 then return false end
    
    if type1.kind == "named_type" and type2.kind == "named_type" then
        return type1.name == type2.name
    elseif type1.kind == "pointer" and type2.kind == "pointer" then
        return self:types_match(type1.to, type2.to)
    elseif type1.kind == "pointer" and type1.is_clone and type2.kind == "named_type" then
        -- Special case: clone types match their base type
        return self:types_match(type1.to, type2)
    elseif type2.kind == "pointer" and type2.is_clone and type1.kind == "named_type" then
        -- Special case: clone types match their base type (symmetric)
        return self:types_match(type2.to, type1)
    end
    return false
end

function Codegen:type_name_string(type_node)
    -- Return a string representation of the type for the 'type' built-in
    if not type_node then return "unknown" end
    
    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        if type_node.is_clone then
            -- For clone variables, return the base type name
            return self:type_name_string(type_node.to)
        else
            return self:type_name_string(type_node.to) .. "*"
        end
    end
    return "unknown"
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
        
        -- NEW SEMANTICS: Parameters receive VALUES unless marked mut
        -- - Non-mut parameters: receive struct by value (no pointer)
        -- - Mut parameters: receive pointer to struct (for modification)
        -- This is controlled by caller passing with/without mut keyword
        
        -- Check if parameter is mutable (mut keyword)
        local is_mut_param = p.mut or (p.type.kind == "pointer" and p.type.is_mut)
        
        if p.type.kind == "named_type" and self:is_struct_type(p.type) then
            -- Struct type parameter
            if is_mut_param then
                -- mut parameter: receives pointer for modification
                type_str = type_str .. "*"
            else
                -- Non-mut parameter: receives value (copy)
                -- No pointer, just the struct type
            end
        elseif p.type.kind == "pointer" then
            -- Already a pointer type - keep as is
        end
        
        table.insert(parts, string.format("%s %s", type_str, param_name))
    end
    return join(parts, ", ")
end

function Codegen:gen_block(block)
    self:push_scope()
    self:emit("{")
    for _, stmt in ipairs(block.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    -- Insert cleanup code at end of block
    local cleanup = self:get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        self:emit("    " .. cleanup_code)
    end
    self:emit("}")
    self:pop_scope()
end

function Codegen:gen_statement(stmt)
    if stmt.kind == "return" then
        -- For return statements, we need to:
        -- 1. Evaluate the return expression FIRST
        -- 2. Then cleanup 
        -- 3. Then return
        -- We use a temporary variable to hold the return value
        local cleanup = self:get_all_scope_cleanup()
        if #cleanup > 0 then
            -- Need to use temporary for return value
            local return_expr = self:gen_expr(stmt.value)
            local parts = {}
            -- Create a block with temp variable to avoid use-after-free
            table.insert(parts, "{ ")
            table.insert(parts, "typeof(" .. return_expr .. ") _ret_val = " .. return_expr .. "; ")
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, cleanup_code .. " ")
            end
            table.insert(parts, "return _ret_val; }")
            return table.concat(parts, "")
        else
            -- No cleanup needed, simple return
            return "return " .. self:gen_expr(stmt.value) .. ";"
        end
    elseif stmt.kind == "free" then
        -- Explicit free statement
        local expr = stmt.value
        if expr.kind ~= "identifier" then
            error("free can only be used with variable names, got " .. expr.kind)
        end
        
        -- Check if the variable is a struct with a destructor
        local var_type = self:get_var_type(expr.name)
        local destructor_code = ""
        if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
            local struct_name = var_type.to.name
            local destructor_call = self:gen_destructor_call(struct_name, expr.name)
            if destructor_call then
                destructor_code = destructor_call .. "\n    "
            end
        end
        
        self:mark_freed(expr.name)
        return destructor_code .. self:free_call(expr.name, true) .. ";"  -- Explicit free statement
    elseif stmt.kind == "discard" then
        -- Discard statement: _ = expr becomes (void)expr;
        return "(void)(" .. self:gen_expr(stmt.value) .. ");"
    elseif stmt.kind == "var_decl" then
        -- Determine if this variable needs to be freed
        local needs_free = false
        if stmt.init then
            local init_kind = stmt.init.kind
            if init_kind == "new_heap" or init_kind == "clone" then
                needs_free = true
            end
        end
        
        -- In implicit pointer model, all struct-typed variables are pointers
        local is_struct_type = self:is_struct_type(stmt.type)
        
        if is_struct_type then
            -- Struct types are always pointers in storage
            local ptr_type = { kind = "pointer", to = stmt.type, is_clone = true }
            self:add_var(stmt.name, ptr_type, stmt.mutable, needs_free)
            local prefix = stmt.mutable and "" or "const "
            local decl = string.format("%s%s* %s", prefix, self:c_type(stmt.type), stmt.name)
            if stmt.init then
                local init_expr = self:gen_expr(stmt.init)
                -- Struct literals are already addresses, others might need special handling
                decl = decl .. " = " .. init_expr
            end
            
            -- Call constructor if the struct has one
            if stmt.type and stmt.type.kind == "named_type" then
                local struct_type_name = stmt.type.name
                local constructor_call = self:gen_constructor_call(struct_type_name, stmt.name)
                if constructor_call then
                    return decl .. ";\n    " .. constructor_call
                end
            end
            
            return decl .. ";"
        else
            -- Non-struct types: check for special initializers
            local is_pointer_expr = false
            if stmt.init then
                local init_kind = stmt.init.kind
                if init_kind == "clone" or init_kind == "new_heap" or init_kind == "null" or 
                   init_kind == "null_check" then
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
                self:add_var(stmt.name, ptr_type, stmt.mutable, needs_free)
                local prefix = stmt.mutable and "" or "const "
                local decl = string.format("%s%s* %s", prefix, self:c_type(stmt.type), stmt.name)
                if stmt.init then
                    decl = decl .. " = " .. self:gen_expr(stmt.init)
                end
                return decl .. ";"
            else
                self:add_var(stmt.name, stmt.type, stmt.mutable, needs_free)
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
    
    -- Push scope for then block
    self:push_scope()
    for _, s in ipairs(stmt.then_block.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    -- Insert cleanup for then block
    local cleanup = self:get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    self:pop_scope()
    
    -- Handle else/elseif chain
    local current_else = stmt.else_block
    while current_else do
        -- Check if else_block is a single if statement (elseif pattern)
        if current_else.kind == "block" and 
           #current_else.statements == 1 and 
           current_else.statements[1].kind == "if" then
            -- Generate "else if" instead of "else { if"
            local nested_if = current_else.statements[1]
            table.insert(parts, "} else if (" .. self:gen_expr(nested_if.condition) .. ") {")
            
            -- Push scope for elseif block
            self:push_scope()
            for _, s in ipairs(nested_if.then_block.statements) do
                table.insert(parts, "    " .. self:gen_statement(s))
            end
            -- Insert cleanup for elseif block
            cleanup = self:get_scope_cleanup()
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, "    " .. cleanup_code)
            end
            self:pop_scope()
            
            -- Continue with the nested else_block
            current_else = nested_if.else_block
        else
            -- Normal else block (not an if statement)
            table.insert(parts, "} else {")
            
            -- Push scope for else block
            self:push_scope()
            for _, s in ipairs(current_else.statements) do
                table.insert(parts, "    " .. self:gen_statement(s))
            end
            -- Insert cleanup for else block
            cleanup = self:get_scope_cleanup()
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, "    " .. cleanup_code)
            end
            self:pop_scope()
            
            current_else = nil  -- End the chain
        end
    end
    
    table.insert(parts, "}")
    return join(parts, "\n    ")
end

function Codegen:gen_while(stmt)
    local parts = {}
    table.insert(parts, "while (" .. self:gen_expr(stmt.condition) .. ") {")
    
    -- Push scope for while body
    self:push_scope()
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    -- Insert cleanup for while body
    local cleanup = self:get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    self:pop_scope()
    
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
        
        -- Determine source type for special handling
        local source_type = nil
        if expr.expr.kind == "identifier" then
            source_type = self:get_var_type(expr.expr.name)
        elseif expr.expr.kind == "field" then
            -- Get the type of the field
            source_type = self:infer_type(expr.expr)
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
            if expr.target_type.kind == "named_type" and self.structs[expr.target_type.name] then
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
            -- With cast (implicit allocation - clone)
            return string.format("({ %s* _ptr = %s; *_ptr = (%s)%s; _ptr; })", 
                target_type_str, self:malloc_call("sizeof(" .. target_type_str .. ")", false), target_type_str, source_expr)
        else
            -- Without cast (implicit allocation - clone)
            return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })", 
                target_type_str, self:malloc_call("sizeof(" .. target_type_str .. ")", false), source_expr)
        end
    elseif expr.kind == "binary" then
        -- Handle special operators
        if expr.op == "or" then
            local left = self:gen_expr(expr.left)
            local right = self:gen_expr(expr.right)
            -- 'or' is used for both logical OR and null coalescing
            -- For null coalescing, we use a statement expression with a temporary
            return string.format("({ __auto_type _tmp = %s; _tmp ? _tmp : (%s); })", left, right)
        elseif expr.op == "and" then
            -- 'and' is logical AND
            return string.format("(%s && %s)", self:gen_expr(expr.left), self:gen_expr(expr.right))
        else
            return string.format("(%s %s %s)", self:gen_expr(expr.left), expr.op, self:gen_expr(expr.right))
        end
    elseif expr.kind == "is_check" then
        -- Handle 'is' keyword for type checking
        -- This is a compile-time check that always returns true or false
        local expr_type = self:infer_type(expr.expr)
        if not expr_type then
            error("Cannot infer type for 'is' check expression")
        end
        local target_type = expr.type
        local matches = self:types_match(expr_type, target_type)
        return matches and "true" or "false"
    elseif expr.kind == "type_of" then
        -- Handle 'type' built-in that returns a const string
        local expr_type = self:infer_type(expr.expr)
        if not expr_type then
            error("Cannot infer type for 'type' built-in expression")
        end
        local type_name = self:type_name_string(expr_type)
        return string.format("\"%s\"", type_name)
    elseif expr.kind == "unary" then
        return string.format("(%s%s)", expr.op, self:gen_expr(expr.operand))
    elseif expr.kind == "null_check" then
        -- Null check operator: expr!!
        local operand = self:gen_expr(expr.operand)
        -- Generate: assert-like behavior
        return string.format("({ __auto_type _tmp = %s; if (!_tmp) { fprintf(stderr, \"null check failed\\n\"); abort(); } _tmp; })", operand)
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
                    -- Wrap value in heap allocation (implicit allocation - assignment)
                    local type_name = self:c_type(var_info.type.to)
                    value_expr = string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })", 
                        type_name, self:malloc_call("sizeof(" .. type_name .. ")", false), value_expr)
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
            -- Resolve arguments with named args and defaults
            local resolved_args = self:resolve_arguments(expr.args, method.params)
            
            -- Generate function call with caller-controlled mutability semantics
            local args = {}
            for i, a in ipairs(resolved_args) do
                local arg_expr = self:gen_expr(a)

                -- Apply caller-controlled mutability semantics
                if #method.params >= i then
                    local param = method.params[i]
                    local param_is_mut = param.mut or (param.type.kind == "pointer" and param.type.is_mut)
                    
                    if a.kind == "identifier" then
                        local arg_type = self:get_var_type(a.name)
                        
                        -- If arg is a struct pointer and param is NOT mut (expects value), dereference
                        if arg_type and arg_type.kind == "pointer" and not param_is_mut then
                            local base_type = arg_type.to
                            if base_type and base_type.kind == "named_type" and self:is_struct_type(base_type) then
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

                -- Resolve the remaining arguments (excluding self)
                local method_params_without_self = {}
                for i = 2, #method.params do
                    table.insert(method_params_without_self, method.params[i])
                end
                local resolved_args = self:resolve_arguments(expr.args, method_params_without_self)
                
                -- Add the rest of the arguments
                for _, a in ipairs(resolved_args) do
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

                -- Resolve the remaining arguments (excluding self)
                local method_params_without_self = {}
                for i = 2, #method.params do
                    table.insert(method_params_without_self, method.params[i])
                end
                local resolved_args = self:resolve_arguments(expr.args, method_params_without_self)
                
                -- Add the rest of the arguments
                for _, a in ipairs(resolved_args) do
                    table.insert(args, self:gen_expr(a))
                end

                return string.format("%s(%s)", method_name, join(args, ", "))
            end
        end

        -- Regular function call
        local callee = self:gen_expr(expr.callee)
        local args = {}
        
        -- NEW SEMANTICS: Caller controls mutability
        -- - Without mut: pass value (dereference struct pointers)
        -- - With mut: pass pointer (keep struct pointers as-is)
        if expr.callee.kind == "identifier" and self.functions["__global__"] then
            local func_def = self.functions["__global__"][expr.callee.name]
            if func_def then
                -- Resolve arguments (handle named args and defaults)
                local resolved_args = self:resolve_arguments(expr.args, func_def.params)
                
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
                            local arg_expr = self:gen_expr(a.expr)
                            
                            -- Dereference if it's a struct pointer and param expects value
                            if a.expr.kind == "identifier" then
                                local var_type = self:get_var_type(a.expr.name)
                                if var_type and var_type.kind == "pointer" and not param_is_mut then
                                    local base_type = var_type.to
                                    if base_type and base_type.kind == "named_type" and self:is_struct_type(base_type) then
                                        -- Dereference to pass by value
                                        arg_expr = "*" .. arg_expr
                                    end
                                end
                            end
                            table.insert(args, arg_expr)
                        else
                            -- Parameter is mut - pass by reference as intended
                            local arg_expr = self:gen_expr(a.expr)
                            -- If the argument is a struct variable (which is internally a pointer),
                            -- just pass it as-is (it's already a pointer)
                            table.insert(args, arg_expr)
                        end
                    else
                        -- Regular argument (no mut keyword) - caller wants pass-by-value
                        local arg_expr = self:gen_expr(a)
                        
                        -- If argument is a struct variable (internally a pointer)
                        -- and parameter expects a value, dereference it
                        if a.kind == "identifier" and func_def.params[i] then
                            local var_type = self:get_var_type(a.name)
                            local param = func_def.params[i]
                            local param_is_mut = param.mut or (param.type.kind == "pointer" and param.type.is_mut)
                            
                            -- If var is a struct pointer and param is NOT mut (expects value), dereference
                            if var_type and var_type.kind == "pointer" and not param_is_mut then
                                local base_type = var_type.to
                                if base_type and base_type.kind == "named_type" and self:is_struct_type(base_type) then
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
        -- Note: Automatic scope-based cleanup implemented - freed at scope exit
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, self:gen_expr(f.value)))
        end
        local initializer = string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
        -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = (Type){ fields... }; _ptr; })
        -- Explicit allocation with 'new' keyword
        return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })", 
            expr.type_name, self:malloc_call("sizeof(" .. expr.type_name .. ")", true), initializer)
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end

function Codegen:gen_function(fn)
    local name = fn.name
    local c_name = name == "main" and "main_main" or name
    
    -- Special handling for constructor/destructor methods to avoid C name conflicts
    if fn.receiver_type then
        if name == "new" then
            c_name = fn.receiver_type .. "_constructor"
        elseif name == "free" then
            c_name = fn.receiver_type .. "_destructor"
        end
    end
    
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
            -- Add regular parameters to scope
            -- NEW SEMANTICS: mut parameters are pointers, non-mut parameters are values
            local param_type = param.type
            local is_mut_param = param.mut or (param.type.kind == "pointer" and param.type.is_mut)
            
            if param.type.kind == "named_type" and self:is_struct_type(param.type) then
                if is_mut_param then
                    -- mut parameter: it's a pointer in the function
                    param_type = { kind = "pointer", to = param.type, is_mut = true }
                else
                    -- Non-mut parameter: it's a value (struct by value)
                    -- Keep param_type as is (named_type)
                end
            end
            
            -- Parameters with mut are mutable
            local is_mutable = is_mut_param
            self:add_var(param.name, param_type, is_mutable or false)
        end
    end

    -- Generate function body statements
    for _, stmt in ipairs(fn.body.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    
    -- Insert cleanup code at end of function ONLY if last statement is not a return
    -- (return statements handle their own cleanup)
    local last_stmt = fn.body.statements[#fn.body.statements]
    if not last_stmt or last_stmt.kind ~= "return" then
        local cleanup = self:get_scope_cleanup()
        for _, cleanup_code in ipairs(cleanup) do
            self:emit("    " .. cleanup_code)
        end
    end
    
    self:emit("}")
    self:pop_scope()
    self:emit("")
end

function Codegen:gen_wrapper(has_main)
    if has_main then
        if self.debug_memory then
            -- With memory tracking, capture return value and print stats
            self:emit("int main(void) {")
            self:emit("    int _ret = main_main();")
            self:emit("    _czar_print_memory_stats();")
            self:emit("    return _ret;")
            self:emit("}")
        else
            self:emit("int main(void) { return main_main(); }")
        end
    end
end

function Codegen:gen_memory_tracking_helpers()
    self:emit("// Memory tracking helpers")
    self:emit("static size_t _czar_explicit_alloc_count = 0;")
    self:emit("static size_t _czar_explicit_alloc_bytes = 0;")
    self:emit("static size_t _czar_implicit_alloc_count = 0;")
    self:emit("static size_t _czar_implicit_alloc_bytes = 0;")
    self:emit("static size_t _czar_explicit_free_count = 0;")
    self:emit("static size_t _czar_implicit_free_count = 0;")
    self:emit("static size_t _czar_current_alloc_count = 0;")
    self:emit("static size_t _czar_current_alloc_bytes = 0;")
    self:emit("static size_t _czar_peak_alloc_count = 0;")
    self:emit("static size_t _czar_peak_alloc_bytes = 0;")
    self:emit("")
    self:emit("void* _czar_malloc(size_t size, int is_explicit) {")
    self:emit("    void* ptr = malloc(size);")
    self:emit("    if (ptr) {")
    self:emit("        if (is_explicit) {")
    self:emit("            _czar_explicit_alloc_count++;")
    self:emit("            _czar_explicit_alloc_bytes += size;")
    self:emit("        } else {")
    self:emit("            _czar_implicit_alloc_count++;")
    self:emit("            _czar_implicit_alloc_bytes += size;")
    self:emit("        }")
    self:emit("        _czar_current_alloc_count++;")
    self:emit("        _czar_current_alloc_bytes += size;")
    self:emit("        if (_czar_current_alloc_count > _czar_peak_alloc_count) {")
    self:emit("            _czar_peak_alloc_count = _czar_current_alloc_count;")
    self:emit("        }")
    self:emit("        if (_czar_current_alloc_bytes > _czar_peak_alloc_bytes) {")
    self:emit("            _czar_peak_alloc_bytes = _czar_current_alloc_bytes;")
    self:emit("        }")
    self:emit("    }")
    self:emit("    return ptr;")
    self:emit("}")
    self:emit("")
    self:emit("void _czar_free(void* ptr, int is_explicit) {")
    self:emit("    if (ptr) {")
    self:emit("        if (is_explicit) {")
    self:emit("            _czar_explicit_free_count++;")
    self:emit("        } else {")
    self:emit("            _czar_implicit_free_count++;")
    self:emit("        }")
    self:emit("        _czar_current_alloc_count--;")
    self:emit("        // Note: current_alloc_bytes not decremented (would need size tracking)")
    self:emit("    }")
    self:emit("    free(ptr);")
    self:emit("}")
    self:emit("")
    self:emit("void _czar_print_memory_stats(void) {")
    self:emit("    size_t total_alloc_count = _czar_explicit_alloc_count + _czar_implicit_alloc_count;")
    self:emit("    size_t total_alloc_bytes = _czar_explicit_alloc_bytes + _czar_implicit_alloc_bytes;")
    self:emit("    size_t total_free_count = _czar_explicit_free_count + _czar_implicit_free_count;")
    self:emit("    fprintf(stderr, \"\\n=== Memory Summary ===\\n\");")
    self:emit("    fprintf(stderr, \"Allocations:\\n\");")
    self:emit("    fprintf(stderr, \"  Explicit: %zu (%zu bytes)\\n\", _czar_explicit_alloc_count, _czar_explicit_alloc_bytes);")
    self:emit("    fprintf(stderr, \"  Implicit: %zu (%zu bytes)\\n\", _czar_implicit_alloc_count, _czar_implicit_alloc_bytes);")
    self:emit("    fprintf(stderr, \"  Total:    %zu (%zu bytes)\\n\", total_alloc_count, total_alloc_bytes);")
    self:emit("    fprintf(stderr, \"\\n\");")
    self:emit("    fprintf(stderr, \"Frees:\\n\");")
    self:emit("    fprintf(stderr, \"  Explicit: %zu\\n\", _czar_explicit_free_count);")
    self:emit("    fprintf(stderr, \"  Implicit: %zu\\n\", _czar_implicit_free_count);")
    self:emit("    fprintf(stderr, \"  Total:    %zu\\n\", total_free_count);")
    self:emit("    fprintf(stderr, \"\\n\");")
    self:emit("    fprintf(stderr, \"Peak Usage:\\n\");")
    self:emit("    fprintf(stderr, \"  Count: %zu allocations\\n\", _czar_peak_alloc_count);")
    self:emit("    fprintf(stderr, \"  Bytes: %zu bytes\\n\", _czar_peak_alloc_bytes);")
    self:emit("    if (total_alloc_count != total_free_count) {")
    self:emit("        fprintf(stderr, \"\\n\");")
    self:emit("        fprintf(stderr, \"WARNING: Memory leak detected! %zu allocations not freed\\n\",")
    self:emit("                total_alloc_count - total_free_count);")
    self:emit("    }")
    self:emit("    fprintf(stderr, \"======================\\n\");")
    self:emit("}")
    self:emit("")
end

function Codegen:generate()
    self:collect_structs_and_functions()
    self:emit("#include <stdint.h>")
    self:emit("#include <stdbool.h>")
    self:emit("#include <stdio.h>")
    self:emit("#include <stdlib.h>")
    self:emit("")

    -- Add memory tracking helpers if debug_memory is enabled
    if self.debug_memory then
        self:gen_memory_tracking_helpers()
    end

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

return function(ast, options)
    local gen = Codegen.new(ast, options)
    return gen:generate()
end
