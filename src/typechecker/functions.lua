-- Typechecker function checking
-- Handles type checking of function definitions

local Errors = require("errors")
local Scopes = require("typechecker.scopes")
local Statements = require("typechecker.statements")
local Utils = require("typechecker.utils")

local Functions = {}

-- Type check all functions
function Functions.check_all_functions(typechecker)
    for _, item in ipairs(typechecker.ast.items) do
        if item.kind == "function" then
            Functions.check_function(typechecker, item)
        end
    end
end

-- Type check a single function
function Functions.check_function(typechecker, func)
    -- Store current function for return statement checking
    typechecker.current_function = func

    -- Create a new scope for this function
    Scopes.push_scope(typechecker)

    -- Add receiver (self) to scope if this is a method
    if func.receiver then
        local receiver_type = func.receiver.type
        local is_mutable = func.receiver.mutable
        Scopes.add_var(typechecker, "self", receiver_type, is_mutable)
    end

    -- Add parameters to scope and validate varargs
    local has_varargs = false
    for i, param in ipairs(func.params) do
        local param_type = param.type
        -- In explicit pointer model, check mutable field directly
        local is_mutable = param.mutable or false

        -- Check for varargs
        if param_type.kind == "varargs" then
            has_varargs = true
            -- Varargs cannot be mutable
            if is_mutable then
                local line = func.line or 0
                local msg = string.format("varargs parameter '%s' cannot be mutable (varargs are read-only like slices)", param.name)
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
            -- Varargs must be the last parameter (already checked in parser, but double-check)
            if i ~= #func.params then
                local line = func.line or 0
                local msg = string.format("varargs parameter '%s' must be the last parameter", param.name)
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
        end

        Scopes.add_var(typechecker, param.name, param_type, is_mutable)
    end

    -- Type check the function body
    Statements.check_block(typechecker, func.body)

    -- Check if non-void function has return statement
    if func.return_type.kind ~= "named_type" or func.return_type.name ~= "void" then
        local has_return = Utils.block_has_return(typechecker, func.body)
        if not has_return then
            local line = func.line or 0
            local msg = string.format(
                "Function '%s' with return type '%s' must return a value in all code paths",
                func.name,
                Utils.type_to_string(func.return_type)
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.MISSING_RETURN, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end

    -- Pop the function scope
    Scopes.pop_scope(typechecker)

    -- Clear current function
    typechecker.current_function = nil
end

return Functions
