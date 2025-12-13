-- Function generation and management
-- Handles function collection, argument resolution, constructors/destructors, and function generation

local Functions = {}

local function ctx() return _G.Codegen end

-- Constants
local SELF_PARAM_NAME = "self"

local function join(list, sep)
    return table.concat(list, sep or "")
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
            error(string.format("Missing argument for parameter '%s' in call to function '%s' (no default value provided)", param.name, func_name))
        end
    end

    return resolved
end

function Functions.collect_structs_and_functions()
    for _, item in ipairs(ctx().ast.items or {}) do
        if item.kind == "struct" then
            ctx().structs[item.name] = item
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
                    item.return_type = { kind = "pointer", to = item.return_type }
                end
            end

            -- Store function info for method call resolution
            local func_name = item.name
            if item.receiver_type then
                -- This is a method, store it by receiver type and method name
                if not ctx().functions[item.receiver_type] then
                    ctx().functions[item.receiver_type] = {}
                end
                ctx().functions[item.receiver_type][item.name] = item
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
                        if not ctx().functions[receiver_type_name] then
                            ctx().functions[receiver_type_name] = {}
                        end
                        ctx().functions[receiver_type_name][func_name] = item
                    end
                end
                -- Store all regular functions by name for warning checks
                if not ctx().functions["__global__"] then
                    ctx().functions["__global__"] = {}
                end
                ctx().functions["__global__"][func_name] = item
            end
        end
    end
end

-- Check if a struct has a constructor method (Type:new)
function Functions.has_constructor(struct_name)
    return ctx().functions[struct_name] and ctx().functions[struct_name]["new"]
end

-- Check if a struct has a destructor method (Type:free)
function Functions.has_destructor(struct_name)
    return ctx().functions[struct_name] and ctx().functions[struct_name]["free"]
end

-- Generate constructor call for a struct variable
function Functions.gen_constructor_call(struct_name, var_name)
    if Functions.has_constructor(struct_name) then
        return string.format("%s_constructor(%s);", struct_name, var_name)
    end
    return nil
end

-- Generate destructor call for a struct variable
function Functions.gen_destructor_call(struct_name, var_name)
    if Functions.has_destructor(struct_name) then
        return string.format("%s_destructor(%s);", struct_name, var_name)
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

function Functions.gen_params(params)    local parts = {}
    for i, p in ipairs(params) do
        local param_name = p.name
        -- Generate unique name for underscore parameters
        if param_name == "_" then
            param_name = "_unused_" .. i
        end

        local type_str = Codegen.Types.c_type(p.type)

        -- NEW SEMANTICS: Parameters receive VALUES unless marked mut
        -- - Non-mut parameters: receive struct by value (no pointer)
        -- - Mut parameters: receive pointer to struct (for modification)
        -- This is controlled by caller passing with/without mut keyword

        -- Check if parameter is mutable (mut keyword)
        local is_mut_param = p.mut or (p.type.kind == "pointer" and p.type.is_mut)

        if p.type.kind == "named_type" and Codegen.Types.is_struct_type(p.type) then
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

function Functions.gen_function(fn)
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

    -- Track current function for #FUNCTION directive
    ctx().current_function = name

    -- In implicit pointer model, struct return types should be pointers
    local return_type_str = Codegen.Types.c_type(fn.return_type)
    if fn.return_type and fn.return_type.kind == "named_type" and Codegen.Types.is_struct_type(fn.return_type) then
        return_type_str = return_type_str .. "*"
    end

    local sig = string.format("%s %s(%s)", return_type_str, c_name, Functions.gen_params(fn.params))
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
            -- NEW SEMANTICS: mut parameters are pointers, non-mut parameters are values
            local param_type = param.type
            local is_mut_param = param.mut or (param.type.kind == "pointer" and param.type.is_mut)

            if param.type.kind == "named_type" and Codegen.Types.is_struct_type(param.type) then
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
            ctx():add_var(param.name, param_type, is_mutable or false)
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
    end

    ctx():emit("}")
    ctx():pop_scope()
    ctx().current_function = nil  -- Clear current function tracking
    ctx():emit("")
end

function Functions.gen_struct(item)    ctx():emit("typedef struct " .. item.name .. " {")
    for _, field in ipairs(item.fields) do
        ctx():emit(string.format("    %s %s;", Codegen.Types.c_type_in_struct(field.type, item.name), field.name))
    end
    ctx():emit("} " .. item.name .. ";")
    ctx():emit("")
end

function Functions.gen_wrapper(has_main)
    if has_main then
        if ctx().debug then
            -- With memory tracking, capture return value and print stats
            ctx():emit("int main(void) {")
            ctx():emit("    int _ret = main_main();")
            ctx():emit("    _czar_print_memory_stats();")
            ctx():emit("    return _ret;")
            ctx():emit("}")
        else
            ctx():emit("int main(void) { return main_main(); }")
        end
    end
end

return Functions
