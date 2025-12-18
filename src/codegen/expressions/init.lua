-- Expression generation for code generation
-- Orchestrates specialized modules for different expression types

local Literals = require("codegen.expressions.literals")
local Operators = require("codegen.expressions.operators")
local Calls = require("codegen.expressions.calls")
local Collections = require("codegen.expressions.collections")

local Expressions = {}

function Expressions.gen_expr(expr)
    if not expr then
        error("gen_expr called with nil expression", 2)
    end
    -- Literals and simple expressions
    if expr.kind == "int" then
        return Literals.gen_int(expr)
    elseif expr.kind == "string" then
        return Literals.gen_string(expr)
    elseif expr.kind == "bool" then
        return Literals.gen_bool(expr)
    elseif expr.kind == "null" then
        return Literals.gen_null(expr)
    elseif expr.kind == "macro" then
        return Literals.gen_macro(expr)
    elseif expr.kind == "macro_call" then
        return Literals.gen_macro_call(expr)
    elseif expr.kind == "identifier" then
        return Literals.gen_identifier(expr)
    elseif expr.kind == "mut_arg" then
        return Literals.gen_mut_arg(expr, Expressions.gen_expr)
    -- Operators and casts
    elseif expr.kind == "implicit_cast" then
        return Operators.gen_implicit_cast(expr, Expressions.gen_expr)
    elseif expr.kind == "unsafe_cast" then
        return Operators.gen_unsafe_cast(expr, Expressions.gen_expr)
    elseif expr.kind == "safe_cast" then
        return Operators.gen_safe_cast(expr, Expressions.gen_expr)
    elseif expr.kind == "clone" then
        return Operators.gen_clone(expr, Expressions.gen_expr)
    elseif expr.kind == "binary" then
        return Operators.gen_binary(expr, Expressions.gen_expr)
    elseif expr.kind == "is_check" then
        return Operators.gen_is_check(expr)
    elseif expr.kind == "type_of" then
        return Operators.gen_type_of(expr)
    elseif expr.kind == "sizeof" then
        return Operators.gen_sizeof(expr)
    elseif expr.kind == "unary" then
        return Operators.gen_unary(expr, Expressions.gen_expr)
    elseif expr.kind == "prefix" then
        return Operators.gen_prefix(expr, Expressions.gen_expr)
    elseif expr.kind == "postfix" then
        return Operators.gen_postfix(expr, Expressions.gen_expr)
    elseif expr.kind == "null_check" then
        return Operators.gen_null_check(expr, Expressions.gen_expr)
    elseif expr.kind == "assign" then
        return Operators.gen_assign(expr, Expressions.gen_expr)
    elseif expr.kind == "compound_assign" then
        return Operators.gen_compound_assign(expr, Expressions.gen_expr)
    -- Calls and field/index access
    elseif expr.kind == "static_method_call" then
        return Calls.gen_static_method_call(expr, Expressions.gen_expr)
    elseif expr.kind == "call" then
        return Calls.gen_call(expr, Expressions.gen_expr)
    elseif expr.kind == "index" then
        return Calls.gen_index(expr, Expressions.gen_expr)
    elseif expr.kind == "field" then
        return Calls.gen_field(expr, Expressions.gen_expr)
    elseif expr.kind == "struct_literal" then
        return Calls.gen_struct_literal(expr, Expressions.gen_expr)
    -- Collections
    elseif expr.kind == "new_heap" then
        return Collections.gen_new_heap(expr, Expressions.gen_expr)
    elseif expr.kind == "new_array" then
        return Collections.gen_new_array(expr, Expressions.gen_expr)
    elseif expr.kind == "new_map" then
        return Collections.gen_new_map(expr, Expressions.gen_expr)
    elseif expr.kind == "array_literal" then
        return Collections.gen_array_literal(expr, Expressions.gen_expr)
    elseif expr.kind == "slice" then
        return Collections.gen_slice(expr, Expressions.gen_expr)
    elseif expr.kind == "new_pair" then
        return Collections.gen_new_pair(expr, Expressions.gen_expr)
    elseif expr.kind == "pair_literal" then
        return Collections.gen_pair_literal(expr, Expressions.gen_expr)
    elseif expr.kind == "map_literal" then
        return Collections.gen_map_literal(expr, Expressions.gen_expr)
    elseif expr.kind == "new_string" then
        return Collections.gen_new_string(expr)
    elseif expr.kind == "string_literal" then
        return Collections.gen_string_literal(expr)
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end

return Expressions
