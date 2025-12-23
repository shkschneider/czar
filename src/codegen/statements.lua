-- Statement generation for code generation
-- Handles all statement types: return, free, var_decl, if, while, blocks

local Macros = require("src.macros")

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
        -- 3. If this is main with debug allocator, print memory stats
        -- 4. Then return
        -- We use a temporary variable to hold the return value
        local cleanup = ctx():get_all_scope_cleanup()
        
        -- Check if we need to add memory stats printing (main function with debug allocator)
        local need_memory_stats = ctx().current_function == "main" and 
                                  ctx().custom_allocator_interface == "cz.alloc.debug"
        
        if #cleanup > 0 or need_memory_stats then
            -- Need to use temporary for return value
            local return_expr = Codegen.Expressions.gen_expr(stmt.value)
            local parts = {}
            -- Create a block with temp variable to avoid use-after-free
            table.insert(parts, "{ ")
            table.insert(parts, "typeof(" .. return_expr .. ") _ret_val = " .. return_expr .. "; ")
            for _, cleanup_code in ipairs(cleanup) do
                table.insert(parts, cleanup_code .. " ")
            end
            if need_memory_stats then
                table.insert(parts, "_czar_print_memory_stats(); ")
            end
            table.insert(parts, "return _ret_val; }")
            return table.concat(parts, "")
        else
            -- No cleanup needed, simple return
            return "return " .. Codegen.Expressions.gen_expr(stmt.value) .. ";"
        end
    elseif stmt.kind == "break" then
        local level = stmt.level or 1
        if level == 1 then
            return "break;"
        else
            -- Multi-level break: use goto to break label
            local target_loop = ctx().loop_stack[#ctx().loop_stack - level + 1]
            if target_loop then
                return "goto " .. target_loop.break_label .. ";"
            else
                -- Should have been caught by typechecker
                return "break;"
            end
        end
    elseif stmt.kind == "continue" then
        local level = stmt.level or 1
        if level == 1 then
            return "continue;"
        else
            -- Multi-level continue: use goto to continue label
            local target_loop = ctx().loop_stack[#ctx().loop_stack - level + 1]
            if target_loop then
                return "goto " .. target_loop.continue_label .. ";"
            else
                -- Should have been caught by typechecker
                return "continue;"
            end
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
        if var_type and var_type.kind == "nullable" and var_type.to and var_type.to.kind == "named_type" then
            local struct_name = var_type.to.name
            local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, expr.name)
            if destructor_call then
                destructor_code = destructor_call .. "\n    "
            end
        end

        ctx():mark_freed(expr.name)
        return destructor_code .. ctx():free_call(expr.name, true) .. ";"  -- Explicit free statement
    elseif stmt.kind == "defer" then
        -- Defer statement - add to deferred stack for execution at scope exit
        -- The value can be either an expression (e.g., close(f)) or a statement (e.g., free p)
        local deferred_code
        if stmt.value.kind == "free" then
            -- Handle deferred free statement
            local expr = stmt.value.value
            if expr.kind ~= "identifier" then
                error("free can only be used with variable names, got " .. expr.kind)
            end
            -- Generate the free code (without marking as freed since it's deferred)
            local var_type = ctx():get_var_type(expr.name)
            local destructor_code = ""
            if var_type and var_type.kind == "nullable" and var_type.to and var_type.to.kind == "named_type" then
                local struct_name = var_type.to.name
                local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, expr.name)
                if destructor_call then
                    destructor_code = destructor_call .. "; "
                end
            end
            deferred_code = destructor_code .. ctx():free_call(expr.name, true) .. ";"
            -- Mark as freed so automatic cleanup doesn't try to free it again
            ctx():mark_freed(expr.name)
        else
            -- Handle deferred expression (function call, etc.)
            deferred_code = Codegen.Expressions.gen_expr(stmt.value) .. ";"
        end
        ctx():add_deferred(deferred_code)
        -- Return empty string - defer doesn't execute immediately
        return "// defer " .. deferred_code
    elseif stmt.kind == "assert_stmt" or stmt.kind == "log_stmt" or stmt.kind == "todo_stmt" or stmt.kind == "fixme_stmt" then
        -- Handle statement-level macros (#assert, #log, #TODO, #FIXME)
        return Macros.generate_statement(stmt, ctx()) .. ";"
    elseif stmt.kind == "unsafe_block" then
        -- Handle #unsafe { raw C code } blocks
        -- Emit the raw C code as-is without any processing
        return stmt.c_code
    elseif stmt.kind == "discard" then
        -- Discard statement: _ = expr becomes (void)expr;
        return "(void)(" .. Codegen.Expressions.gen_expr(stmt.value) .. ");"
    elseif stmt.kind == "var_decl" then
        -- Determine if this variable needs to be freed
        local needs_free = false
        if stmt.init then
            local init_kind = stmt.init.kind
            if init_kind == "new_heap" or init_kind == "clone" or init_kind == "new_array" then
                needs_free = true
            end
        end

        -- In explicit pointer model, check if the type itself is a pointer
        local is_pointer_type = stmt.type.kind == "nullable"
        local is_array_type = stmt.type.kind == "array"
        local is_slice_type = stmt.type.kind == "slice"
        
        local result_code

        if is_array_type then
            -- Array type declaration
            ctx():add_var(stmt.name, stmt.type, stmt.mutable, needs_free)
            local element_type = Codegen.Types.c_type(stmt.type.element_type)
            local array_size = stmt.type.size
            local prefix = stmt.mutable and "" or "const "
            local decl = string.format("%s%s %s[%d]", prefix, element_type, stmt.name, array_size)
            if stmt.init then
                decl = decl .. " = " .. Codegen.Expressions.gen_expr(stmt.init)
            end
            result_code = decl .. ";"
        elseif is_slice_type then
            -- Slice type declaration (always immutable)
            ctx():add_var(stmt.name, stmt.type, false, needs_free)
            local element_type = Codegen.Types.c_type(stmt.type.element_type)
            local decl = string.format("%s* const %s", element_type, stmt.name)
            if stmt.init then
                decl = decl .. " = " .. Codegen.Expressions.gen_expr(stmt.init)
            end
            result_code = decl .. ";"
        elseif is_pointer_type then
            -- This is an explicit pointer type (Type*)
            ctx():add_var(stmt.name, stmt.type, stmt.mutable, needs_free)
            
            -- Warning: check for immutable arena (immutable-arena)
            if stmt.type.to and stmt.type.to.kind == "named_type" and 
               stmt.type.to.name == "cz_alloc_arena" and not stmt.mutable then
                local Warnings = require("src.warnings")
                Warnings.emit(
                    ctx().source_file,
                    stmt.line,
                    Warnings.WarningType.IMMUTABLE_ARENA,
                    "Arena allocator declared as immutable doesn't make sense. " ..
                    "Arena needs to be mutable to allocate memory. Use 'mut cz_alloc_arena? " .. stmt.name .. " = ...'",
                    ctx().source_path,
                    ctx().current_function
                )
            end
            
            local base_type = Codegen.Types.c_type(stmt.type.to)
            local decl
            if stmt.mutable then
                -- Mutable pointer variable: can reassign pointer and modify through it
                decl = string.format("%s* %s", base_type, stmt.name)
            else
                -- Immutable pointer variable: can't reassign pointer but can modify through it
                decl = string.format("%s* const %s", base_type, stmt.name)
            end
            if stmt.init then
                local init_expr = Codegen.Expressions.gen_expr(stmt.init)
                
                -- Check if we need to take the address (safe to unsafe pointer conversion)
                if stmt.init_type and stmt.init.kind == "identifier" then
                    -- Safe pointer to unsafe pointer: Type -> Type?
                    if stmt.init_type.kind == "named_type" and stmt.type.kind == "nullable" then
                        init_expr = "&" .. init_expr
                    -- Safe pointer to any: Type -> any (void*)
                    elseif stmt.init_type.kind == "named_type" and stmt.type.kind == "named_type" and stmt.type.name == "any" then
                        init_expr = "&" .. init_expr
                    -- Unsafe pointer to any: Type? -> any (already a pointer, no & needed)
                    -- This is handled automatically since both are pointers
                    end
                end
                
                decl = decl .. " = " .. init_expr
            end

            -- Call constructor if the struct has one (dereference pointer to call)
            if stmt.type.to and stmt.type.to.kind == "named_type" then
                local struct_type_name = stmt.type.to.name
                local constructor_call = Codegen.Functions.gen_constructor_call(struct_type_name, stmt.name)
                if constructor_call then
                    result_code = decl .. ";\n    " .. constructor_call
                else
                    result_code = decl .. ";"
                end
            else
                result_code = decl .. ";"
            end
        else
            -- This is a value type (or any type which is void*)
            ctx():add_var(stmt.name, stmt.type, stmt.mutable, needs_free)
            
            -- Warning: check for arena allocated on stack (useless-arena-on-stack)
            if stmt.type and stmt.type.kind == "named_type" and stmt.type.name == "cz_alloc_arena" then
                local Warnings = require("src.warnings")
                Warnings.emit(
                    ctx().source_file,
                    stmt.line,
                    Warnings.WarningType.USELESS_ARENA_ON_STACK,
                    "Arena allocator 'cz_alloc_arena' allocated on stack is inefficient. " ..
                    "Arena allocators should be heap-allocated using 'new cz_alloc_arena { size: n }' " ..
                    "to properly manage heap memory.",
                    ctx().source_path,
                    ctx().current_function
                )
            end
            
            -- Warning: check for immutable arena (immutable-arena)
            if stmt.type and stmt.type.kind == "nullable" and stmt.type.to and 
               stmt.type.to.kind == "named_type" and stmt.type.to.name == "cz_alloc_arena" and
               not stmt.mutable then
                local Warnings = require("src.warnings")
                Warnings.emit(
                    ctx().source_file,
                    stmt.line,
                    Warnings.WarningType.IMMUTABLE_ARENA,
                    "Arena allocator declared as immutable doesn't make sense. " ..
                    "Arena needs to be mutable to allocate memory. Use 'mut cz_alloc_arena? " .. stmt.name .. " = ...'",
                    ctx().source_path,
                    ctx().current_function
                )
            end
            
            local prefix = stmt.mutable and "" or "const "
            local decl = string.format("%s%s %s", prefix, Codegen.Types.c_type(stmt.type), stmt.name)
            if stmt.init then
                local init_expr = Codegen.Expressions.gen_expr(stmt.init)
                
                -- Check if we need to take the address for any type
                if stmt.init_type and stmt.init_type.kind == "named_type" and 
                   stmt.type.kind == "named_type" and stmt.type.name == "any" and 
                   stmt.init.kind == "identifier" then
                    init_expr = "&" .. init_expr
                end
                
                decl = decl .. " = " .. init_expr
            end

            -- Call constructor if the type is a struct
            if stmt.type and stmt.type.kind == "named_type" and Codegen.Types.is_struct_type(stmt.type) then
                local struct_type_name = stmt.type.name
                local constructor_call = Codegen.Functions.gen_constructor_call(struct_type_name, "&" .. stmt.name)
                if constructor_call then
                    result_code = decl .. ";\n    " .. constructor_call
                else
                    result_code = decl .. ";"
                end
            else
                result_code = decl .. ";"
            end
        end
        
        -- Handle auto-defer: if #defer was specified after the init expression
        if stmt.auto_defer then
            -- Generate deferred free statement
            local var_type = ctx():get_var_type(stmt.name)
            local destructor_code = ""
            if var_type and var_type.kind == "nullable" and var_type.to and var_type.to.kind == "named_type" then
                local struct_name = var_type.to.name
                local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, stmt.name)
                if destructor_call then
                    destructor_code = destructor_call .. "; "
                end
            end
            local deferred_code = destructor_code .. ctx():free_call(stmt.name, true) .. ";"
            ctx():add_deferred(deferred_code)
            -- Mark as freed so automatic cleanup doesn't try to free it again
            ctx():mark_freed(stmt.name)
            -- Add comment about the auto-defer
            result_code = result_code .. "\n    // auto-defer free " .. stmt.name
        end
        
        return result_code
    elseif stmt.kind == "expr_stmt" then
        -- Check if this is an underscore assignment in expression form
        local expr = stmt.expression
        if expr.kind == "assign" and expr.target.kind == "identifier" and expr.target.name == "_" then
            -- Discard assignment: _ = expr becomes (void)expr;
            return "(void)(" .. Codegen.Expressions.gen_expr(expr.value) .. ");"
        end
        return Codegen.Expressions.gen_expr(stmt.expression) .. ";"
    elseif stmt.kind == "block" then
        -- Bare block statement (for nested scopes)
        local parts = {}
        table.insert(parts, "{")
        ctx():push_scope()
        for _, s in ipairs(stmt.statements) do
            table.insert(parts, "    " .. Statements.gen_statement(s))
        end
        -- Insert cleanup for this scope
        local cleanup = ctx():get_scope_cleanup()
        for _, cleanup_code in ipairs(cleanup) do
            table.insert(parts, "    " .. cleanup_code)
        end
        ctx():pop_scope()
        table.insert(parts, "}")
        return table.concat(parts, "\n    ")
    elseif stmt.kind == "if" then
        return Statements.gen_if(stmt)
    elseif stmt.kind == "while" then
        return Statements.gen_while(stmt)
    elseif stmt.kind == "for" then
        return Statements.gen_for(stmt)
    elseif stmt.kind == "repeat" then
        return Statements.gen_repeat(stmt)
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
    
    -- Generate unique labels for multi-level break/continue
    ctx().loop_label_counter = ctx().loop_label_counter + 1
    local loop_id = ctx().loop_label_counter
    local break_label = "_loop_break_" .. loop_id
    local continue_label = "_loop_continue_" .. loop_id
    
    -- Push loop info onto stack
    table.insert(ctx().loop_stack, {
        break_label = break_label,
        continue_label = continue_label
    })
    
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

    table.insert(parts, continue_label .. ": ;")
    table.insert(parts, "}")
    table.insert(parts, break_label .. ": ;")
    
    -- Pop loop info from stack
    table.remove(ctx().loop_stack)
    
    return join(parts, "\n    ")
end

function Statements.gen_for(stmt)
    local parts = {}
    
    -- Generate unique labels for multi-level break/continue
    ctx().loop_label_counter = ctx().loop_label_counter + 1
    local loop_id = ctx().loop_label_counter
    local break_label = "_loop_break_" .. loop_id
    local continue_label = "_loop_continue_" .. loop_id
    
    -- Push loop info onto stack
    table.insert(ctx().loop_stack, {
        break_label = break_label,
        continue_label = continue_label
    })
    
    -- Generate collection expression
    local collection_expr = Codegen.Expressions.gen_expr(stmt.collection)
    
    -- Get collection type from the collection identifier
    local collection_type = nil
    if stmt.collection.kind == "identifier" then
        collection_type = Codegen.Types.get_var_type(stmt.collection.name)
    end
    
    -- Determine the size expression
    local size_expr
    
    if collection_type and collection_type.kind == "array" then
        -- For arrays, use the compile-time size
        size_expr = tostring(collection_type.size)
    elseif collection_type and (collection_type.kind == "slice" or collection_type.kind == "varargs") then
        -- For slices and varargs, use the count variable
        if stmt.collection.kind == "identifier" then
            size_expr = stmt.collection.name .. "_count"
        else
            error("For loops over slices require explicit size tracking")
        end
    else
        -- Unknown type, use a fallback (should not happen after typechecking)
        size_expr = "0"
    end
    
    -- Generate index variable name
    local index_var = stmt.index_is_underscore and "_for_idx" or stmt.index_name
    
    -- Generate item variable name  
    local item_var = stmt.item_is_underscore and "_for_item" or stmt.item_name
    
    -- Generate for loop header
    table.insert(parts, string.format("for (int32_t %s = 0; %s < %s; %s++) {",
        index_var, index_var, size_expr, index_var))
    
    -- Push scope for for body
    ctx():push_scope()
    
    -- Add index variable to scope if not underscore
    if not stmt.index_is_underscore then
        ctx():add_var(stmt.index_name, { kind = "named_type", name = "i32" }, false)
    end
    
    -- Generate item variable declaration
    if not stmt.item_is_underscore and collection_type then
        local element_type = collection_type.element_type
        local c_type = Codegen.Types.c_type(element_type)
        
        -- Determine if item should be a pointer or value
        if stmt.item_mutable then
            -- Mutable item: get pointer to array element
            table.insert(parts, string.format("    %s* %s = &%s[%s];",
                c_type, item_var, collection_expr, index_var))
            -- Add to scope as pointer type, marked as reference for auto-dereferencing
            ctx():add_var(stmt.item_name, { kind = "nullable", to = element_type }, true, false, true)
        else
            -- Immutable item: copy value
            table.insert(parts, string.format("    const %s %s = %s[%s];",
                c_type, item_var, collection_expr, index_var))
            -- Add to scope as value type
            ctx():add_var(stmt.item_name, element_type, false)
        end
    end
    
    -- Generate body statements
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. Statements.gen_statement(s))
    end
    
    -- Insert cleanup for for body
    local cleanup = ctx():get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    ctx():pop_scope()

    table.insert(parts, continue_label .. ": ;")
    table.insert(parts, "}")
    table.insert(parts, break_label .. ": ;")
    
    -- Pop loop info from stack
    table.remove(ctx().loop_stack)
    
    return join(parts, "\n    ")
end

function Statements.gen_repeat(stmt)
    local parts = {}
    
    -- Generate unique labels for multi-level break/continue
    ctx().loop_label_counter = ctx().loop_label_counter + 1
    local loop_id = ctx().loop_label_counter
    local break_label = "_loop_break_" .. loop_id
    local continue_label = "_loop_continue_" .. loop_id
    
    -- Push loop info onto stack
    table.insert(ctx().loop_stack, {
        break_label = break_label,
        continue_label = continue_label
    })
    
    -- Generate count expression
    local count_expr = Codegen.Expressions.gen_expr(stmt.count)
    
    -- Generate a unique loop counter variable name using the repeat_counter
    ctx().repeat_counter = ctx().repeat_counter + 1
    local loop_var = "_repeat_i" .. ctx().repeat_counter
    
    -- Generate for loop header: for (int32_t _repeat_i1 = 0; _repeat_i1 < count; _repeat_i1++)
    table.insert(parts, string.format("for (int32_t %s = 0; %s < %s; %s++) {",
        loop_var, loop_var, count_expr, loop_var))
    
    -- Push scope for repeat body
    ctx():push_scope()
    
    -- Generate body statements
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. Statements.gen_statement(s))
    end
    
    -- Insert cleanup for repeat body
    local cleanup = ctx():get_scope_cleanup()
    for _, cleanup_code in ipairs(cleanup) do
        table.insert(parts, "    " .. cleanup_code)
    end
    ctx():pop_scope()

    table.insert(parts, continue_label .. ": ;")
    table.insert(parts, "}")
    table.insert(parts, break_label .. ": ;")
    
    -- Pop loop info from stack
    table.remove(ctx().loop_stack)

    return join(parts, "\n    ")
end

return Statements
