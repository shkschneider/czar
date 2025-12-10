-- Simple C code generator for the Czar AST produced by parser.lua.
-- Supports structs, functions, blocks, variable declarations, expressions,
-- and struct literals sufficient for the example program.

local Codegen = {}
Codegen.__index = Codegen

local builtin_calls = {
    print_i32 = function(args)
        local _arg = tonumber(args[1]) or 0
        return ""
        -- FIXME return string.format("printf(\"" .. '%d' .. "\", %d)", _arg)
    end,
}

local function join(list, sep)
    return table.concat(list, sep or "")
end

function Codegen.new(ast)
    local self = {
        ast = ast,
        structs = {},
        out = {},
    }
    return setmetatable(self, Codegen)
end

function Codegen:emit(line)
    table.insert(self.out, line)
end

function Codegen:collect_structs()
    for _, item in ipairs(self.ast.items or {}) do
        if item.kind == "struct" then
            self.structs[item.name] = item
        end
    end
end

function Codegen:c_type(type_node)
    if not type_node then return "void" end
    if type_node.kind == "pointer" then
        return self:c_type(type_node.to) .. "*"
    elseif type_node.kind == "named_type" then
        local name = type_node.name
        if name == "i32" then
            return "int32_t"
        elseif name == "bool" then
            return "bool"
        elseif name == "void" then
            return "void"
        else
            return name
        end
    else
        error("unknown type node kind: " .. tostring(type_node.kind))
    end
end

function Codegen:gen_struct(item)
    self:emit("typedef struct " .. item.name .. " {")
    for _, field in ipairs(item.fields) do
        self:emit(string.format("    %s %s;", self:c_type(field.type), field.name))
    end
    self:emit("} " .. item.name .. ";")
    self:emit("")
end

function Codegen:gen_params(params)
    local parts = {}
    for _, p in ipairs(params) do
        table.insert(parts, string.format("%s %s", self:c_type(p.type), p.name))
    end
    return join(parts, ", ")
end

function Codegen:gen_block(block)
    self:emit("{")
    for _, stmt in ipairs(block.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    self:emit("}")
end

function Codegen:gen_statement(stmt)
    if stmt.kind == "return" then
        return "return " .. self:gen_expr(stmt.value) .. ";"
    elseif stmt.kind == "var_decl" then
        local prefix = stmt.mutable and "" or "const "
        local decl = string.format("%s%s %s", prefix, self:c_type(stmt.type), stmt.name)
        if stmt.init then
            decl = decl .. " = " .. self:gen_expr(stmt.init)
        end
        return decl .. ";"
    elseif stmt.kind == "expr_stmt" then
        return self:gen_expr(stmt.expression) .. ";"
    else
        error("unknown statement kind: " .. tostring(stmt.kind))
    end
end

function Codegen:gen_expr(expr)
    if expr.kind == "int" then
        return tostring(expr.value)
    elseif expr.kind == "string" then
        return string.format("\"%s\"", expr.value)
    elseif expr.kind == "bool" then
        return expr.value and "true" or "false"
    elseif expr.kind == "null" then
        return "NULL"
    elseif expr.kind == "identifier" then
        return expr.name
    elseif expr.kind == "binary" then
        return string.format("(%s %s %s)", self:gen_expr(expr.left), expr.op, self:gen_expr(expr.right))
    elseif expr.kind == "unary" then
        return string.format("(%s%s)", expr.op, self:gen_expr(expr.operand))
    elseif expr.kind == "assign" then
        return string.format("(%s = %s)", self:gen_expr(expr.target), self:gen_expr(expr.value))
    elseif expr.kind == "call" then
        local callee = self:gen_expr(expr.callee)
        local args = {}
        for _, a in ipairs(expr.args) do
            table.insert(args, self:gen_expr(a))
        end
        if builtin_calls[callee] then
            return builtin_calls[callee](args)
        end
        return string.format("%s(%s)", callee, join(args, ", "))
    elseif expr.kind == "field" then
        return string.format("%s.%s", self:gen_expr(expr.object), expr.field)
    elseif expr.kind == "struct_literal" then
        local parts = {}
        for _, f in ipairs(expr.fields) do
            table.insert(parts, string.format(".%s = %s", f.name, self:gen_expr(f.value)))
        end
        return string.format("(%s){ %s }", expr.type_name, join(parts, ", "))
    else
        error("unknown expression kind: " .. tostring(expr.kind))
    end
end

function Codegen:gen_function(fn)
    local name = fn.name
    local c_name = name == "main" and "main_main" or name
    local sig = string.format("%s %s(%s)", self:c_type(fn.return_type), c_name, self:gen_params(fn.params))
    self:emit(sig)
    self:gen_block(fn.body)
    self:emit("")
end

function Codegen:gen_wrapper(has_main)
    if has_main then
        self:emit("int main(void) { return main_main(); }")
    end
end

function Codegen:generate()
    self:collect_structs()
    self:emit("#include <stdint.h>")
    self:emit("#include <stdbool.h>")
    self:emit("#include <stdio.h>")
    self:emit("")

    for _, item in ipairs(self.ast.items) do
        if item.kind == "struct" then
            self:gen_struct(item)
        end
    end

    local has_main = false
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            if item.name == "main" then has_main = true end
            self:gen_function(item)
        end
    end

    self:gen_wrapper(has_main)

    return join(self.out, "\n") .. "\n"
end

return function(ast)
    local gen = Codegen.new(ast)
    return gen:generate()
end
