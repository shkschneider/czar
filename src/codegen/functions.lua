-- Function generation and management
-- Handles function collection, argument resolution, constructors/destructors, and function generation

local Functions = {}

local function ctx() return _G.Codegen end

-- Constants
local SELF_PARAM_NAME = "self"

local function join(list, sep)
    return table.concat(list, sep or "")
end

-- Helper: Convert type to string for C name generation
local function type_to_c_name(type_node)
    if not type_node then
        return "unknown"
    end
    
    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "nullable" then
        return type_to_c_name(type_node.to) .. "_ptr"
    elseif type_node.kind == "array" then
        return type_to_c_name(type_node.element_type) .. "_arr"
    elseif type_node.kind == "slice" then
        return type_to_c_name(type_node.element_type) .. "_slice"
    elseif type_node.kind == "string" then
        return "string"
    end
    
    return "unknown"
end

-- Helper: Generate unique C name for overloaded function
-- For overloaded functions, append type signature to name
local function generate_c_function_name(func_name, params, is_overloaded, generic_concrete_type)
    if not is_overloaded and not generic_concrete_type then
        return func_name
    end
    
    -- For generic functions, use the concrete type in the name (e.g., add_u8, add_u32)
    if generic_concrete_type then
        return func_name .. "_" .. generic_concrete_type
    end
    
    -- For overloaded functions, generate a suffix based on parameter types
    local type_parts = {}
    for _, param in ipairs(params) do
        local type_str = type_to_c_name(param.type)
        table.insert(type_parts, type_str)
    end
    
    -- Join types with underscore (e.g., add_u8_u8, add_i32_i32, add_f32_f32)
    return func_name .. "_" .. table.concat(type_parts, "_")
end

-- Resolve function arguments, handling named arguments and default parameters
-- func_name: name of the function being called (for error messages)
-- args: list of arguments from the call site (may include named_arg nodes)
-- params: list of parameters from the function definition (may include default_value)
-- Returns: list of resolved argument expressions in the correct parameter order
function Functions.resolve_arguments(func_name, args, params)
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

    -- Check if last parameter is varargs
    local has_varargs = #params > 0 and params[#params].type.kind == "varargs"
    local fixed_param_count = has_varargs and (#params - 1) or #params

    -- Second pass: fill in resolved array with arguments in parameter order
    local positional_index = 1
    for i = 1, fixed_param_count do
        local param = params[i]
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
            error(string.format("Missing argument for parameter '%s' in call to function '%s' (no default value provided)", param.name, func_name))
        end
    end

    -- Handle varargs: collect remaining arguments
    if has_varargs then
        local varargs_list = {}
        -- Collect all remaining positional arguments
        while positional_index <= positional_count do
            local arg_index = 1
            for j, arg in ipairs(args) do
                if arg.kind ~= "named_arg" then
                    if arg_index == positional_index then
                        table.insert(varargs_list, arg)
                        break
                    end
                    arg_index = arg_index + 1
                end
            end
            positional_index = positional_index + 1
        end
        -- Store varargs list as a special marker
        resolved[#params] = { kind = "varargs_list", args = varargs_list }
    end

    return resolved
end

function Functions.collect_structs_and_functions()
    for _, item in ipairs(ctx().ast.items or {}) do
        if item.kind == "struct" then
            ctx().structs[item.name] = item
        elseif item.kind == "enum" then
            ctx().enums[item.name] = item
        elseif item.kind == "iface" then
            ctx().ifaces[item.name] = item
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
                local returns_null = Functions.function_returns_null(item)
                if returns_null and ctx().structs[item.return_type.name] then
                    -- Convert return type to pointer
                    item.return_type = { kind = "nullable", to = item.return_type }
                end
            end

            -- Store function info for method call resolution
            local func_name = item.name
            if item.receiver_type then
                -- Set the C name for methods now (needed for calls to #unsafe functions)
                -- Only set if not already set (module functions get c_name from import processing)
                if not item.c_name then
                    local c_name = item.name
                    if item.name == "init" then
                        c_name = "czar_" .. item.receiver_type .. "_init"
                    elseif item.name == "fini" then
                        c_name = "czar_" .. item.receiver_type .. "_fini"
                    else
                        c_name = "czar_" .. item.receiver_type .. "_" .. item.name
                    end
                    item.c_name = c_name
                end
                
                -- This is a method, store it by receiver type and method name
                if not ctx().functions[item.receiver_type] then
                    ctx().functions[item.receiver_type] = {}
                end
                -- Methods are stored as arrays to support overloading
                if not ctx().functions[item.receiver_type][item.name] then
                    ctx().functions[item.receiver_type][item.name] = {}
                end
                table.insert(ctx().functions[item.receiver_type][item.name], item)
            else
                -- Regular function, also check if it's an extension method
                if #item.params > 0 and item.params[1].name == SELF_PARAM_NAME then
                    -- Extension method: first param is self
                    local self_type = item.params[1].type
                    local receiver_type_name = nil
                    if self_type.kind == "nullable" and self_type.to.kind == "named_type" then
                        receiver_type_name = self_type.to.name
                    elseif self_type.kind == "named_type" then
                        receiver_type_name = self_type.name
                    end
                    if receiver_type_name then
                        if not ctx().functions[receiver_type_name] then
                            ctx().functions[receiver_type_name] = {}
                        end
                        if not ctx().functions[receiver_type_name][func_name] then
                            ctx().functions[receiver_type_name][func_name] = {}
                        end
                        table.insert(ctx().functions[receiver_type_name][func_name], item)
                    end
                end
                -- Store all regular functions by name for warning checks
                if not ctx().functions["__global__"] then
                    ctx().functions["__global__"] = {}
                end
                if not ctx().functions["__global__"][func_name] then
                    ctx().functions["__global__"][func_name] = {}
                end
                table.insert(ctx().functions["__global__"][func_name], item)
            end
        end
    end
end

-- Check if a struct has a constructor method (Type:new)
function Functions.has_constructor(struct_name)
    if ctx().functions[struct_name] and ctx().functions[struct_name]["init"] then
        local overloads = ctx().functions[struct_name]["init"]
        return #overloads > 0
    end
    return false
end

-- Check if a struct has a destructor method (Type:fini)
function Functions.has_destructor(struct_name)
    if ctx().functions[struct_name] and ctx().functions[struct_name]["fini"] then
        local overloads = ctx().functions[struct_name]["fini"]
        return #overloads > 0
    end
    return false
end

-- Generate constructor call for a struct variable
function Functions.gen_constructor_call(struct_name, var_name)
    if Functions.has_constructor(struct_name) then
        -- Get the actual c_name from the stored function
        local overloads = ctx().functions[struct_name]["init"]
        if overloads and #overloads > 0 and overloads[1].c_name then
            return string.format("%s(%s);", overloads[1].c_name, var_name)
        end
        -- Fallback for non-module structs
        return string.format("czar_%s_init(%s);", struct_name, var_name)
    end
    return nil
end

-- Generate destructor call for a struct variable
function Functions.gen_destructor_call(struct_name, var_name)
    if Functions.has_destructor(struct_name) then
        -- Get the actual c_name from the stored function
        local overloads = ctx().functions[struct_name]["fini"]
        if overloads and #overloads > 0 and overloads[1].c_name then
            return string.format("%s(%s);", overloads[1].c_name, var_name)
        end
        -- Fallback for non-module structs
        return string.format("czar_%s_fini(%s);", struct_name, var_name)
    end
    return nil
end

function Functions.function_returns_null(fn)
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
                if val.kind == "identifier" and Codegen.Types.is_pointer_var(val.name) then
                    return true
                end
                -- Returns new_heap, clone, null_check, new_array, etc.
                if val.kind == "new_heap" or val.kind == "clone" or val.kind == "null_check" or val.kind == "new_array" then
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

function Functions.gen_params(params)
    local parts = {}
    for i, p in ipairs(params) do
        local param_name = p.name
        -- Generate unique name for underscore parameters
        if param_name == "_" then
            param_name = "_unused_" .. i
        end

        local type_str = Codegen.Types.c_type(p.type)
        
        -- Handle varargs: generate pointer and count parameters (like slices)
        if p.type.kind == "varargs" then
            local element_type = Codegen.Types.c_type(p.type.element_type)
            -- Varargs are read-only (const), generate pointer and count
            table.insert(parts, string.format("const %s* %s", element_type, param_name))
            table.insert(parts, string.format("size_t %s_count", param_name))
        else
            -- In explicit pointer model with immutability by default:
            -- - Type* without mut → const Type* (immutable data through pointer)
            -- - mut Type* → Type* (mutable data through pointer)
            -- - any without mut → const void* (immutable)
            -- - mut any → void* (mutable)
            if p.type.kind == "nullable" then
                local base_type = Codegen.Types.c_type(p.type.to)
                if p.mutable then
                    -- mut Type* → Type* (can modify through pointer)
                    type_str = base_type .. "*"
                else
                    -- Type* → const Type* (cannot modify through pointer)
                    type_str = "const " .. base_type .. "*"
                end
            elseif p.type.kind == "named_type" and p.type.name == "any" then
                -- any is void* - apply const if not mutable
                if p.mutable then
                    type_str = "void*"
                else
                    type_str = "const void*"
                end
            end

            table.insert(parts, string.format("%s %s", type_str, param_name))
        end
    end
    return join(parts, ", ")
end

-- Generate forward declaration for a function
function Functions.gen_function_declaration(fn)
    -- Skip declaration for functions with #unsafe blocks - they're implemented in C
    if fn.has_unsafe_block then
        return ""
    end
    
    local name = fn.name
    local c_name = name

    -- Check if this function is overloaded
    local is_overloaded = false
    if fn.is_overloaded ~= nil then
        is_overloaded = fn.is_overloaded
    end

    -- Use pre-computed c_name if available (set during function collection or module import)
    if fn.c_name then
        c_name = fn.c_name
    -- Special handling for constructor/destructor methods
    elseif fn.receiver_type then
        local receiver = fn.receiver_type
        -- Use czar_ prefix for non-module structs
        if name == "init" then
            c_name = "czar_" .. receiver .. "_init"
        elseif name == "fini" then
            c_name = "czar_" .. receiver .. "_fini"
        else
            -- Regular instance/static methods use czar_ prefix too
            c_name = "czar_" .. receiver .. "_" .. name
        end
        fn.c_name = c_name
    elseif is_overloaded or fn.is_generic_instance then
        -- Generate unique C name for overloaded or generic functions
        c_name = generate_c_function_name(name, fn.params, is_overloaded, fn.generic_concrete_type)
        fn.c_name = c_name
    end

    -- In explicit pointer model, return types are as declared
    local return_type_str = Codegen.Types.c_type(fn.return_type)
    if fn.return_type and fn.return_type.kind == "nullable" then
        return_type_str = Codegen.Types.c_type(fn.return_type.to) .. "*"
    end

    -- Add inline attributes if specified
    local attributes = ""
    if fn.inline_directive == "inline" then
        attributes = "__attribute__((always_inline)) inline "
    elseif fn.inline_directive == "noinline" then
        attributes = "__attribute__((noinline)) "
    end

    local sig = string.format("%s%s %s(%s);", attributes, return_type_str, c_name, Functions.gen_params(fn.params))
    ctx():emit(sig)
end

function Functions.gen_function(fn)
    -- Skip generation for functions with #unsafe blocks - they're implemented in C
    if fn.has_unsafe_block then
        return ""
    end
    
    local name = fn.name
    local c_name = name

    -- Check if this function is overloaded
    local is_overloaded = false
    if fn.is_overloaded ~= nil then
        is_overloaded = fn.is_overloaded
    end

    -- Use pre-computed c_name if available (set during function collection or module import)
    if fn.c_name then
        c_name = fn.c_name
    -- Special handling for constructor/destructor methods
    elseif fn.receiver_type then
        local receiver = fn.receiver_type
        -- Use czar_ prefix for non-module structs
        if name == "init" then
            c_name = "czar_" .. receiver .. "_init"
        elseif name == "fini" then
            c_name = "czar_" .. receiver .. "_fini"
        else
            -- Regular instance/static methods use czar_ prefix too
            c_name = "czar_" .. receiver .. "_" .. name
        end
    elseif is_overloaded or fn.is_generic_instance then
        -- Generate unique C name for overloaded or generic functions
        c_name = generate_c_function_name(name, fn.params, is_overloaded, fn.generic_concrete_type)
    end

    -- Track current function for #FUNCTION directive
    ctx().current_function = name

    -- In explicit pointer model, return types are as declared
    local return_type_str = Codegen.Types.c_type(fn.return_type)
    if fn.return_type and fn.return_type.kind == "nullable" then
        return_type_str = Codegen.Types.c_type(fn.return_type.to) .. "*"
    end

    -- Add inline attributes if specified
    local attributes = ""
    if fn.inline_directive == "inline" then
        attributes = "__attribute__((always_inline)) inline "
    elseif fn.inline_directive == "noinline" then
        attributes = "__attribute__((noinline)) "
    end

    local sig = string.format("%s%s %s(%s)", attributes, return_type_str, c_name, Functions.gen_params(fn.params))
    ctx():emit(sig)
    ctx():push_scope()
    ctx():emit("{")

    -- Add unused parameter suppressions for underscore parameters
    for i, param in ipairs(fn.params) do
        if param.name == "_" then
            local param_name = "_unused_" .. i
            ctx():emit("    (void)" .. param_name .. ";")
        else
            -- Add regular parameters to scope
            -- In explicit pointer model, parameters track mutability via param.mutable field
            local param_type = param.type
            local is_mutable = param.mutable or false

            ctx():add_var(param.name, param_type, is_mutable)
        end
    end

    -- If this is main function, add stdlib init calls and debug allocator setup
    if name == "main" then
        -- Generate stdlib init calls based on parsed #init blocks from imports
        for import_path, init_blocks in pairs(ctx().stdlib_init_blocks or {}) do
            for _, init_block in ipairs(init_blocks) do
                -- Generate code for each statement in the init block
                for _, stmt in ipairs(init_block.statements) do
                    local stmt_code = ctx():gen_statement(stmt)
                    if stmt_code and stmt_code ~= "" then
                        -- For unsafe blocks, the code already includes its own formatting
                        -- (extracted as raw C from the source file between #unsafe { })
                        if stmt.kind == "unsafe_block" then
                            ctx():emit(stmt_code)
                        else
                            ctx():emit("    " .. stmt_code)
                        end
                    end
                end
            end
        end
    end

    -- Generate function body statements
    for _, stmt in ipairs(fn.body.statements) do
        ctx():emit("    " .. Codegen.Statements.gen_statement(stmt))
    end

    -- Insert cleanup code at end of function ONLY if last statement is not a return
    -- (return statements handle their own cleanup)
    local last_stmt = fn.body.statements[#fn.body.statements]
    if not last_stmt or last_stmt.kind ~= "return" then
        local cleanup = ctx():get_scope_cleanup()
        for _, cleanup_code in ipairs(cleanup) do
            ctx():emit("    " .. cleanup_code)
        end
        
        -- If this is main function with debug allocator, print memory stats before implicit return
        if name == "main" and ctx().custom_allocator_interface == "cz.alloc.debug" then
            ctx():emit("    _czar_print_memory_stats();")
        end
    end

    ctx():emit("}")
    ctx():pop_scope()
    ctx().current_function = nil  -- Clear current function tracking
    ctx():emit("")
end

function Functions.gen_struct(item)
    ctx():emit("typedef struct " .. item.name .. " {")
    for _, field in ipairs(item.fields) do
        ctx():emit(string.format("    %s %s;", Codegen.Types.c_type_in_struct(field.type, item.name), field.name))
    end
    ctx():emit("} " .. item.name .. ";")
    ctx():emit("")
end

function Functions.gen_enum(item)
    local Warnings = require("warnings")
    
    -- Check for non-uppercase enum values and emit warnings
    for _, value in ipairs(item.values) do
        local name = value.name
        if name ~= name:upper() then
            local msg = string.format(
                "Enum value '%s' in enum '%s' should be all uppercase (e.g., '%s')",
                name, item.name, name:upper()
            )
            Warnings.emit(
                ctx().source_file,
                value.line,
                Warnings.WarningType.ENUM_VALUE_NOT_UPPERCASE,
                msg,
                ctx().source_path,
                ctx().current_function
            )
        end
    end
    
    -- Generate typedef for enum type (as int32_t in C)
    ctx():emit(string.format("typedef int32_t %s;", item.name))
    
    -- Generate constants for enum values (e.g., MyEnum_ONE, MyEnum_TWO)
    for i, value in ipairs(item.values) do
        ctx():emit(string.format("#define %s_%s %d", item.name, value.name, i - 1))
    end
    ctx():emit("")
end

function Functions.gen_wrapper(has_main)
    -- No longer needed - main function is generated directly with init calls inline
    -- This function is kept for backward compatibility but does nothing
end

-- Export helper for c_name generation (used by init.lua)
function Functions.generate_c_name(func_name, params, is_overloaded, generic_concrete_type)
    return generate_c_function_name(func_name, params, is_overloaded, generic_concrete_type)
end

return Functions
