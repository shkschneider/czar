-- Memory and scope management for code generation
-- Handles scope stack, variable tracking, and cleanup generation

local Memory = {}

local function ctx() return _G.Codegen end

function Memory.push_scope()
    table.insert(ctx().scope_stack, {})
    table.insert(ctx().heap_vars_stack, {})
    table.insert(ctx().deferred_stack, {})
end

function Memory.pop_scope()
    table.remove(ctx().scope_stack)
    table.remove(ctx().heap_vars_stack)
    table.remove(ctx().deferred_stack)
end

function Memory.add_var(name, type_node, mutable, needs_free, is_reference)
    if #ctx().scope_stack > 0 then
        ctx().scope_stack[#ctx().scope_stack][name] = {
            type = type_node,
            mutable = mutable or false,
            needs_free = needs_free or false,
            is_reference = is_reference or false,  -- Track if variable is a reference (auto-dereference)
            used = false,  -- Track if variable is used
            declared_at = debug.getinfo(2, "l").currentline  -- Track declaration location
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

function Memory.add_deferred(stmt_code)
    -- Add a deferred statement to the current scope
    if #ctx().deferred_stack == 0 then
        error("Cannot use #defer outside of a scope")
    end
    table.insert(ctx().deferred_stack[#ctx().deferred_stack], stmt_code)
end

function Memory.get_scope_cleanup()
    local cleanup = {}
    -- First, add deferred statements in reverse order (LIFO)
    if #ctx().deferred_stack > 0 then
        local deferred = ctx().deferred_stack[#ctx().deferred_stack]
        for i = #deferred, 1, -1 do
            table.insert(cleanup, deferred[i])
        end
    end
    -- Then add automatic free calls for heap-allocated variables
    -- Note: With defer, automatic cleanup only applies to implicit pointers (is_reference = true)
    -- Explicit pointers (nullable types) require manual #defer or free
    if #ctx().heap_vars_stack > 0 then
        local heap_vars = ctx().heap_vars_stack[#ctx().heap_vars_stack]
        for i = #heap_vars, 1, -1 do
            local var_name = heap_vars[i]
            local var_info = Memory.get_var_info(var_name)
            -- Only auto-free implicit pointers (is_reference = true)
            if var_info and var_info.needs_free and var_info.is_reference then
                local var_type = var_info.type
                if var_type and var_type.kind == "nullable" and var_type.to and var_type.to.kind == "named_type" then
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

function Memory.get_all_scope_cleanup()
    local cleanup = {}
    for scope_idx = #ctx().heap_vars_stack, 1, -1 do
        -- Add deferred statements for this scope in reverse order (LIFO)
        if ctx().deferred_stack[scope_idx] then
            local deferred = ctx().deferred_stack[scope_idx]
            for i = #deferred, 1, -1 do
                table.insert(cleanup, deferred[i])
            end
        end
        -- Add automatic free calls for heap-allocated variables
        -- Note: With defer, automatic cleanup only applies to implicit pointers (is_reference = true)
        -- Explicit pointers (nullable types) require manual #defer or free
        local heap_vars = ctx().heap_vars_stack[scope_idx]
        for i = #heap_vars, 1, -1 do
            local var_name = heap_vars[i]
            local var_info = Memory.get_var_info(var_name)
            -- Only auto-free implicit pointers (is_reference = true)
            if var_info and var_info.needs_free and var_info.is_reference then
                local var_type = var_info.type
                if var_type and var_type.kind == "nullable" and var_type.to and var_type.to.kind == "named_type" then
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

-- Mark a variable as used
function Memory.mark_var_used(name)
    for i = #ctx().scope_stack, 1, -1 do
        local var_info = ctx().scope_stack[i][name]
        if var_info then
            var_info.used = true
            return
        end
    end
end

-- Check for unused variables in current scope and emit warnings
function Memory.check_unused_vars()
    local Warnings = require("warnings")
    if #ctx().scope_stack > 0 then
        local scope = ctx().scope_stack[#ctx().scope_stack]
        for var_name, var_info in pairs(scope) do
            -- Skip underscore variables (intentionally unused)
            if not var_info.used and var_name ~= "_" and not var_name:match("^_unused_") then
                Warnings.emit(
                    ctx().source_file,
                    nil,  -- We don't have line info stored yet
                    Warnings.WarningType.UNUSED_VARIABLE,
                    string.format("Variable '%s' is declared but never used", var_name),
                    ctx().source_path,
                    ctx().current_function
                )
            end
        end
    end
end

function Memory.alloc_call(size_expr, is_explicit)
    -- Use custom allocator interface if set, otherwise use default alloc
    local allocator_interface = ctx().custom_allocator_interface
    
    if allocator_interface == "cz.alloc.debug" then
        -- Use our debug tracking allocator with explicit flag
        local alloc_prefix = allocator_interface:gsub("%.", "_")
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("%s_alloc(%s, %s)", alloc_prefix, size_expr, explicit_flag)
    elseif allocator_interface == "cz.alloc.default" then
        -- Use standard C malloc for cz.alloc.default
        return string.format("malloc(%s)", size_expr)
    elseif allocator_interface then
        -- Use custom allocator interface's alloc function (no tracking)
        local alloc_prefix = allocator_interface:gsub("%.", "_")
        return string.format("%s_alloc(%s)", alloc_prefix, size_expr)
    else
        -- No custom allocator, use default malloc
        return string.format("malloc(%s)", size_expr)
    end
end

-- Keep old name for backward compatibility
Memory.malloc_call = Memory.alloc_call

function Memory.free_call(ptr_expr, is_explicit)
    -- Use custom allocator interface if set, otherwise use default free
    local allocator_interface = ctx().custom_allocator_interface
    
    if allocator_interface == "cz.alloc.debug" then
        -- Use our debug tracking allocator with explicit flag
        local alloc_prefix = allocator_interface:gsub("%.", "_")
        local explicit_flag = is_explicit and "1" or "0"
        return string.format("%s_free(%s, %s)", alloc_prefix, ptr_expr, explicit_flag)
    elseif allocator_interface == "cz.alloc.default" then
        -- Use standard C free for cz.alloc.default
        return string.format("free(%s)", ptr_expr)
    elseif allocator_interface then
        -- Use custom allocator interface's free function (no tracking)
        local alloc_prefix = allocator_interface:gsub("%.", "_")
        return string.format("%s_free(%s)", alloc_prefix, ptr_expr)
    else
        -- No custom deallocator, use default free
        return string.format("free(%s)", ptr_expr)
    end
end

function Memory.gen_memory_tracking_helpers()
    local allocator_interface = ctx().custom_allocator_interface or "cz.alloc.default"
    local alloc_prefix = allocator_interface:gsub("%.", "_")
    
    ctx():emit("// Memory tracking helpers for " .. allocator_interface)
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
    ctx():emit("void* " .. alloc_prefix .. "_malloc(size_t size, int is_explicit) {")
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
    ctx():emit("void* " .. alloc_prefix .. "_realloc(void* ptr, size_t new_size) {")
    ctx():emit("    // Note: tracking for realloc is simplified - doesn't track size changes")
    ctx():emit("    return realloc(ptr, new_size);")
    ctx():emit("}")
    ctx():emit("")
    ctx():emit("void " .. alloc_prefix .. "_free(void* ptr, int is_explicit) {")
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
    ctx():emit("    fprintf(stderr, \"\\n=== Memory Summary (" .. allocator_interface .. ") ===\\n\");")
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
