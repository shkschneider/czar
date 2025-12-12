-- Statement generation for code generation
-- Handles all statement types: return, free, var_decl, if, while, blocks

local Statements = {}

local function ctx() return _G.Codegen end

local function join(list, sep)
    return table.concat(list, sep or "")
end

function Statements.gen_block(block)
    ctx():push_scope()
    ctx():emit("{")
    for _, stmt in ipairs(block.statements) do
        ctx():emit("    " .. Statements.gen_statement(stmt))
    end
    -- Insert cleanup code at end of block
    local cleanup = ctx():get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        ctx():emit("    " .. cleanup_code)
    end
    ctx():emit("}")
    ctx():pop_scope()
end

function Statements.gen_statement(stmt)
    if stmt.kind == "return" then
        -- For return statements, we need to:
        -- 1. Evaluate the return expression FIRST
        -- 2. Then cleanup
        -- 3. Then return
        -- We use a temporary variable to hold the return value
        local cleanup = ctx():get_all_scope_cleanup()
        if #cleanup > 0 then
            -- Need to use temporary for return value
            local return_expr = Codegen.Expressions.gen_expr(stmt.value)
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
            return "return " .. Codegen.Expressions.gen_expr(stmt.value) .. ";"
        end
    elseif stmt.kind == "free" then
        -- Explicit free statement
        local expr = stmt.value
        if expr.kind ~= "identifier" then
            error("free can only be used with variable names, got " .. expr.kind)
        end

        -- Check if the variable is a struct with a destructor
        local var_type = ctx():get_var_type(expr.name)
        local destructor_code = ""
        if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
            local struct_name = var_type.to.name
            local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, expr.name)
            if destructor_call then
                destructor_code = destructor_call .. "\n    "
            end
        end

        ctx():mark_freed(expr.name)
        return destructor_code .. ctx():free_call(expr.name, true) .. ";"  -- Explicit free statement
    elseif stmt.kind == "discard" then
        -- Discard statement: _ = expr becomes (void)expr;
        return "(void)(" .. Codegen.Expressions.gen_expr(stmt.value) .. ");"
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
        local is_struct_type = Codegen.Types.is_struct_type(stmt.type)

        if is_struct_type then
            -- Struct types are always pointers in storage
            local ptr_type = { kind = "pointer", to = stmt.type, is_clone = true }
            ctx():add_var(stmt.name, ptr_type, stmt.mutable, needs_free)
            local prefix = stmt.mutable and "" or "const "
            local decl = string.format("%s%s* %s", prefix, Codegen.Types.c_type(stmt.type), stmt.name)
            if stmt.init then
                local init_expr = Codegen.Expressions.gen_expr(stmt.init)
                -- Struct literals are already addresses, others might need special handling
                decl = decl .. " = " .. init_expr
            end

            -- Call constructor if the struct has one
            if stmt.type and stmt.type.kind == "named_type" then
                local struct_type_name = stmt.type.name
                local constructor_call = Codegen.Functions.gen_constructor_call(struct_type_name, stmt.name)
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
                    is_pointer_expr = Codegen.Types.is_pointer_var(stmt.init.name)
                elseif init_kind == "call" and stmt.init.callee.kind == "identifier" then
                    local func_info = ctx().functions["__global__"] and ctx().functions["__global__"][stmt.init.callee.name]
                    if func_info and func_info.return_type and func_info.return_type.kind == "pointer" then
                        is_pointer_expr = true
                    end
                end
            end

            if is_pointer_expr then
                local ptr_type = { kind = "pointer", to = stmt.type, is_clone = true }
                ctx():add_var(stmt.name, ptr_type, stmt.mutable, needs_free)
                local prefix = stmt.mutable and "" or "const "
                local decl = string.format("%s%s* %s", prefix, Codegen.Types.c_type(stmt.type), stmt.name)
                if stmt.init then
                    decl = decl .. " = " .. Codegen.Expressions.gen_expr(stmt.init)
                end
                return decl .. ";"
            else
                ctx():add_var(stmt.name, stmt.type, stmt.mutable, needs_free)
                local prefix = stmt.mutable and "" or "const "
                local decl = string.format("%s%s %s", prefix, Codegen.Types.c_type(stmt.type), stmt.name)
                if stmt.init then
                    decl = decl .. " = " .. Codegen.Expressions.gen_expr(stmt.init)
                end
                return decl .. ";"
            end
        end
    elseif stmt.kind == "expr_stmt" then
        -- Check if this is an underscore assignment in expression form
        local expr = stmt.expression
        if expr.kind == "assign" and expr.target.kind == "identifier" and expr.target.name == "_" then
            -- Discard assignment: _ = expr becomes (void)expr;
            return "(void)(" .. Codegen.Expressions.gen_expr(expr.value) .. ");"
        end
        return Codegen.Expressions.gen_expr(stmt.expression) .. ";"
    elseif stmt.kind == "if" then
        return Statements.gen_if(stmt)
    elseif stmt.kind == "while" then
        return Statements.gen_while(stmt)
    else
        error("unknown statement kind: " .. tostring(stmt.kind))
    end
end

function Statements.gen_if(stmt)
    local parts = {}
    table.insert(parts, "if (" .. Codegen.Expressions.gen_expr(stmt.condition) .. ") {")

    -- Push scope for then block
    ctx():push_scope()
    for _, s in ipairs(stmt.then_block.statements) do
        table.insert(parts, "    " .. Statements.gen_statement(s))
    end
    -- Insert cleanup for then block
    local cleanup = ctx():get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    ctx():pop_scope()

    -- Handle else/elseif chain
    local current_else = stmt.else_block
    while current_else do
        -- Check if else_block is a single if statement (elseif pattern)
        if current_else.kind == "block" and
           #current_else.statements == 1 and
           current_else.statements[1].kind == "if" then
            -- Generate "else if" instead of "else { if"
            local nested_if = current_else.statements[1]
            table.insert(parts, "} else if (" .. Codegen.Expressions.gen_expr(nested_if.condition) .. ") {")

            -- Push scope for elseif block
            ctx():push_scope()
            for _, s in ipairs(nested_if.then_block.statements) do
                table.insert(parts, "    " .. Statements.gen_statement(s))
            end
            -- Insert cleanup for elseif block
            cleanup = ctx():get_scope_cleanup()
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, "    " .. cleanup_code)
            end
            ctx():pop_scope()

            -- Continue with the nested else_block
            current_else = nested_if.else_block
        else
            -- Normal else block (not an if statement)
            table.insert(parts, "} else {")

            -- Push scope for else block
            ctx():push_scope()
            for _, s in ipairs(current_else.statements) do
                table.insert(parts, "    " .. Statements.gen_statement(s))
            end
            -- Insert cleanup for else block
            cleanup = ctx():get_scope_cleanup()
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, "    " .. cleanup_code)
            end
            ctx():pop_scope()

            current_else = nil  -- End the chain
        end
    end

    table.insert(parts, "}")
    return join(parts, "\n    ")
end

function Statements.gen_while(stmt)
    local parts = {}
    table.insert(parts, "while (" .. Codegen.Expressions.gen_expr(stmt.condition) .. ") {")

    -- Push scope for while body
    ctx():push_scope()
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. Statements.gen_statement(s))
    end
    -- Insert cleanup for while body
    local cleanup = ctx():get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    ctx():pop_scope()

    table.insert(parts, "}")
    return join(parts, "\n    ")
end

return Statements
