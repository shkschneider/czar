-- Memory and scope management for code generation
-- Handles scope stack, variable tracking, and cleanup generation

local Memory = {}

local function ctx() return _G.Codegen end

function Memory.push_scope()
    table.insert(ctx().scope_stack, {})
    table.insert(ctx().heap_vars_stack, {})
end

function Memory.pop_scope()
    table.remove(ctx().scope_stack)
    table.remove(ctx().heap_vars_stack)
end

function Memory.add_var(name, type_node, mutable, needs_free)
    if #ctx().scope_stack > 0 then
        ctx().scope_stack[#ctx().scope_stack][name] = {
            type = type_node,
            mutable = mutable or false,
            needs_free = needs_free or false
        }
        if needs_free then
            table.insert(ctx().heap_vars_stack[#ctx().heap_vars_stack], name)
        end
    end
end

function Memory.mark_freed(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            var_info.needs_free = false
            for j = i, 1, -1 do
                local heap_vars = ctx().heap_vars_stack[j]
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

function Memory.get_scope_cleanup()    local cleanup = {}
    if #ctx().heap_vars_stack > 0 then
        local heap_vars = ctx().heap_vars_stack[#ctx().heap_vars_stack]
        for i = #heap_vars, 1, -1 do
            local var_name = heap_vars[i]
            local var_info = Memory.get_var_info(var_name)
            if var_info and var_info.needs_free then
                local var_type = var_info.type
                if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
                    local struct_name = var_type.to.name
                    local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, var_name)
                    if destructor_call then
                        table.insert(cleanup, destructor_call)
                    end
                end
                table.insert(cleanup, Memory.free_call(var_name, false) .. ";")
            end
        end
    end
    return cleanup
end

function Memory.get_all_scope_cleanup()    local cleanup = {}
    for scope_idx = #ctx().heap_vars_stack, 1, -1 do
        local heap_vars = ctx().heap_vars_stack[scope_idx]
        for i = #heap_vars, 1, -1 do
            local var_name = heap_vars[i]
            local var_info = Memory.get_var_info(var_name)
            if var_info and var_info.needs_free then
                local var_type = var_info.type
                if var_type and var_type.kind == "pointer" and var_type.to and var_type.to.kind == "named_type" then
                    local struct_name = var_type.to.name
                    local destructor_call = Codegen.Functions.gen_destructor_call(struct_name, var_name)
                    if destructor_call then
                        table.insert(cleanup, destructor_call)
                    end
                end
                table.insert(cleanup, Memory.free_call(var_name, false) .. ";")
            end
        end
    end
    return cleanup
end

function Memory.get_var_type(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            return var_info.type
        end
    end
    return nil
end

function Memory.get_var_info(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            return var_info
        end
    end
    return nil
end

function Memory.malloc_call(size_expr, is_explicit)
    -- Use custom malloc if set, otherwise use default or debug wrapper
    local malloc_func = ctx().custom_malloc
    
    if not malloc_func then
        -- No custom allocator, use default malloc
        return string.format("malloc(%s)", size_expr)
    elseif malloc_func == "malloc" then
        -- Explicitly reset to standard C malloc
        return string.format("malloc(%s)", size_expr)
    elseif malloc_func == "cz_malloc" then
        -- Using the debug wrapper which needs the is_explicit flag
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("cz_malloc(%s, %s)", size_expr, explicit_flag)
    else
        -- Custom allocator - assume it has standard malloc signature
        return string.format("%s(%s)", malloc_func, size_expr)
    end
end

function Memory.free_call(ptr_expr, is_explicit)
    -- Use custom free if set, otherwise use default or debug wrapper
    local free_func = ctx().custom_free
    
    if not free_func then
        -- No custom deallocator, use default free
        return string.format("free(%s)", ptr_expr)
    elseif free_func == "free" then
        -- Explicitly reset to standard C free
        return string.format("free(%s)", ptr_expr)
    elseif free_func == "cz_free" then
        -- Using the debug wrapper which needs the is_explicit flag
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("cz_free(%s, %s)", ptr_expr, explicit_flag)
    else
        -- Custom deallocator - assume it has standard free signature
        return string.format("%s(%s)", free_func, ptr_expr)
    end
end

function Memory.gen_memory_tracking_helpers()
    ctx():emit("// Memory tracking helpers")
    ctx():emit("static size_t _czar_explicit_alloc_count = 0;")
    ctx():emit("static size_t _czar_explicit_alloc_bytes = 0;")
    ctx():emit("static size_t _czar_implicit_alloc_count = 0;")
    ctx():emit("static size_t _czar_implicit_alloc_bytes = 0;")
    ctx():emit("static size_t _czar_explicit_free_count = 0;")
    ctx():emit("static size_t _czar_implicit_free_count = 0;")
    ctx():emit("static size_t _czar_current_alloc_count = 0;")
    ctx():emit("static size_t _czar_current_alloc_bytes = 0;")
    ctx():emit("static size_t _czar_peak_alloc_count = 0;")
    ctx():emit("static size_t _czar_peak_alloc_bytes = 0;")
    ctx():emit("")
    ctx():emit("void* cz_malloc(size_t size, int is_explicit) {")
    ctx():emit("    void* ptr = malloc(size);")
    ctx():emit("    if (ptr) {")
    ctx():emit("        if (is_explicit) {")
    ctx():emit("            _czar_explicit_alloc_count++;")
    ctx():emit("            _czar_explicit_alloc_bytes += size;")
    ctx():emit("        } else {")
    ctx():emit("            _czar_implicit_alloc_count++;")
    ctx():emit("            _czar_implicit_alloc_bytes += size;")
    ctx():emit("        }")
    ctx():emit("        _czar_current_alloc_count++;")
    ctx():emit("        _czar_current_alloc_bytes += size;")
    ctx():emit("        if (_czar_current_alloc_count > _czar_peak_alloc_count) {")
    ctx():emit("            _czar_peak_alloc_count = _czar_current_alloc_count;")
    ctx():emit("        }")
    ctx():emit("        if (_czar_current_alloc_bytes > _czar_peak_alloc_bytes) {")
    ctx():emit("            _czar_peak_alloc_bytes = _czar_current_alloc_bytes;")
    ctx():emit("        }")
    ctx():emit("    }")
    ctx():emit("    return ptr;")
    ctx():emit("}")
    ctx():emit("")
    ctx():emit("void cz_free(void* ptr, int is_explicit) {")
    ctx():emit("    if (ptr) {")
    ctx():emit("        if (is_explicit) {")
    ctx():emit("            _czar_explicit_free_count++;")
    ctx():emit("        } else {")
    ctx():emit("            _czar_implicit_free_count++;")
    ctx():emit("        }")
    ctx():emit("        _czar_current_alloc_count--;")
    ctx():emit("        // Note: current_alloc_bytes not decremented (would need size tracking)")
    ctx():emit("    }")
    ctx():emit("    free(ptr);")
    ctx():emit("}")
    ctx():emit("")
    ctx():emit("void _czar_print_memory_stats(void) {")
    ctx():emit("    size_t total_alloc_count = _czar_explicit_alloc_count + _czar_implicit_alloc_count;")
    ctx():emit("    size_t total_alloc_bytes = _czar_explicit_alloc_bytes + _czar_implicit_alloc_bytes;")
    ctx():emit("    size_t total_free_count = _czar_explicit_free_count + _czar_implicit_free_count;")
    ctx():emit("    fprintf(stderr, \"\\n=== Memory Summary ===\\n\");")
    ctx():emit("    fprintf(stderr, \"Allocations:\\n\");")
    ctx():emit("    fprintf(stderr, \"  Explicit: %zu (%zu bytes)\\n\", _czar_explicit_alloc_count, _czar_explicit_alloc_bytes);")
    ctx():emit("    fprintf(stderr, \"  Implicit: %zu (%zu bytes)\\n\", _czar_implicit_alloc_count, _czar_implicit_alloc_bytes);")
    ctx():emit("    fprintf(stderr, \"  Total:    %zu (%zu bytes)\\n\", total_alloc_count, total_alloc_bytes);")
    ctx():emit("    fprintf(stderr, \"\\n\");")
    ctx():emit("    fprintf(stderr, \"Frees:\\n\");")
    ctx():emit("    fprintf(stderr, \"  Explicit: %zu\\n\", _czar_explicit_free_count);")
    ctx():emit("    fprintf(stderr, \"  Implicit: %zu\\n\", _czar_implicit_free_count);")
    ctx():emit("    fprintf(stderr, \"  Total:    %zu\\n\", total_free_count);")
    ctx():emit("    fprintf(stderr, \"\\n\");")
    ctx():emit("    fprintf(stderr, \"Peak Usage:\\n\");")
    ctx():emit("    fprintf(stderr, \"  Count: %zu allocations\\n\", _czar_peak_alloc_count);")
    ctx():emit("    fprintf(stderr, \"  Bytes: %zu bytes\\n\", _czar_peak_alloc_bytes);")
    ctx():emit("    if (total_alloc_count != total_free_count) {")
    ctx():emit("        fprintf(stderr, \"\\n\");")
    ctx():emit("        fprintf(stderr, \"WARNING: Memory leak detected! %zu allocations not freed\\n\",")
    ctx():emit("                total_alloc_count - total_free_count);")
    ctx():emit("    }")
    ctx():emit("    fprintf(stderr, \"======================\\n\");")
    ctx():emit("}")
    ctx():emit("")
end

return Memory
