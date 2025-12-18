-- Literal type inference
-- Handles basic literals like integers, booleans, strings, null, identifiers, and macros

local Resolver = require("typechecker.resolver")
local Errors = require("errors")

local Literals = {}

-- Infer integer literal type
function Literals.infer_int_type(expr)
    local inferred = { kind = "named_type", name = "i32" }
    expr.inferred_type = inferred
    return inferred
end

-- Infer boolean literal type
function Literals.infer_bool_type(expr)
    local inferred = { kind = "named_type", name = "bool" }
    expr.inferred_type = inferred
    return inferred
end

-- Infer string literal type (C-style char*)
function Literals.infer_string_type(expr)
    local inferred = { kind = "nullable", to = { kind = "named_type", name = "char" } }
    expr.inferred_type = inferred
    return inferred
end

-- Infer null literal type (void*)
function Literals.infer_null_type(expr)
    local inferred = { kind = "nullable", to = { kind = "named_type", name = "void" } }
    expr.inferred_type = inferred
    return inferred
end

-- Infer identifier type
function Literals.infer_identifier_type(typechecker, expr)
    local var_info = Resolver.resolve_name(typechecker, expr.name)
    if var_info then
        expr.inferred_type = var_info.type
        return var_info.type
    else
        local line = expr.line or 0
        local msg = string.format("Undeclared identifier: %s", expr.name)
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
end

-- Infer the type of a macro
function Literals.infer_macro_type(expr)
    if expr.name == "FILE" or expr.name == "FUNCTION" then
        return { kind = "nullable", to = { kind = "named_type", name = "char" } }
    elseif expr.name == "DEBUG" then
        -- #DEBUG, #DEBUG(), and #DEBUG(bool) all return bool
        return { kind = "named_type", name = "bool" }
    end
    return nil
end

return Literals
