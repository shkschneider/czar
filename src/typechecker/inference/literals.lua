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

-- Infer interpolated string type (also char*)
function Literals.infer_interpolated_string_type(typechecker, expr, infer_expr_fn)
    -- Parse the interpolation expressions using the lexer and parser
    local lex = require("lexer")
    local Expressions = require("parser.expressions")
    
    -- Create a minimal parser object for expression parsing
    local function make_parser(tokens, source)
        return {
            tokens = tokens,
            pos = 1,
            source = source,
            current = function(self)
                return self.tokens[self.pos]
            end,
            advance = function(self)
                local tok = self:current()
                if tok then self.pos = self.pos + 1 end
                return tok
            end,
            check = function(self, type_, value)
                local tok = self:current()
                if not tok then return false end
                if tok.type ~= type_ then return false end
                if value and tok.value ~= value then return false end
                return true
            end,
            match = function(self, type_, value)
                if self:check(type_, value) then
                    self:advance()
                    return true
                end
                return false
            end,
            expect = function(self, type_, value)
                local tok = self:current()
                if not tok or tok.type ~= type_ then
                    error(string.format("Expected %s but got %s", type_, tok and tok.type or "EOF"))
                end
                if value and tok.value ~= value then
                    error(string.format("Expected %s=%s but got %s", type_, value, tok.value))
                end
                self:advance()
                return tok
            end
        }
    end
    
    local parsed_exprs = {}
    for _, expr_str in ipairs(expr.interp_strings) do
        -- Lex the expression string
        local tokens = lex(expr_str)
        -- Create a minimal parser and parse the expression
        local parser = make_parser(tokens, expr_str)
        local expr_ast = Expressions.parse_expression(parser)
        table.insert(parsed_exprs, expr_ast)
    end
    
    -- Store parsed expressions for codegen to use
    expr.expressions = parsed_exprs
    
    -- Infer types for all the expressions
    for _, sub_expr in ipairs(parsed_exprs) do
        infer_expr_fn(typechecker, sub_expr)
    end
    
    -- The result is a char* string
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
