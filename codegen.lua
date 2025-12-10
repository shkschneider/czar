-- Simple C code generator for the Czar AST produced by parser.lua.
-- Supports structs, functions, blocks, variable declarations, expressions,
-- and struct literals sufficient for the example program.

local Codegen = {}
Codegen.__index = Codegen

local builtin_calls = {
    print_i32 = function(args)
        return string.format('printf("%%d\\n", %s)', args[1])
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
        scope_stack = {},
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

function Codegen:is_pointer_type(type_node)
    return type_node and type_node.kind == "pointer"
end

function Codegen:c_type(type_node)
    if not type_node then return "void" end
    if type_node.kind == "pointer" then
        return self:c_type(type_node.to) .. "*"
    elseif type_node.kind == "named_type" then
        local name = type_node.name
        if name == "i32" then
            return "int32_t"
        elseif name == "i64" then
            return "int64_t"
        elseif name == "u32" then
            return "uint32_t"
        elseif name == "u64" then
            return "uint64_t"
        elseif name == "f32" then
            return "float"
        elseif name == "f64" then
            return "double"
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

function Codegen:push_scope()
    table.insert(self.scope_stack, {})
end

function Codegen:pop_scope()
    table.remove(self.scope_stack)
end

function Codegen:add_var(name, type_node)
    if #self.scope_stack > 0 then
        self.scope_stack[#self.scope_stack][name] = type_node
    end
end

function Codegen:get_var_type(name)
    for i = #self.scope_stack, 1, -1 do
        local type_node = self.scope_stack[i][name]
        if type_node then
            return type_node
        end
    end
    return nil
end

function Codegen:gen_params(params)
    local parts = {}
    for _, p in ipairs(params) do
        table.insert(parts, string.format("%s %s", self:c_type(p.type), p.name))
    end
    return join(parts, ", ")
end

function Codegen:gen_block(block)
    self:push_scope()
    self:emit("{")
    for _, stmt in ipairs(block.statements) do
        self:emit("    " .. self:gen_statement(stmt))
    end
    self:emit("}")
    self:pop_scope()
end

function Codegen:gen_statement(stmt)
    if stmt.kind == "return" then
        return "return " .. self:gen_expr(stmt.value) .. ";"
    elseif stmt.kind == "var_decl" then
        self:add_var(stmt.name, stmt.type)
        local prefix = stmt.mutable and "" or "const "
        local decl = string.format("%s%s %s", prefix, self:c_type(stmt.type), stmt.name)
        if stmt.init then
            decl = decl .. " = " .. self:gen_expr(stmt.init)
        end
        return decl .. ";"
    elseif stmt.kind == "expr_stmt" then
        return self:gen_expr(stmt.expression) .. ";"
    elseif stmt.kind == "if" then
        return self:gen_if(stmt)
    elseif stmt.kind == "while" then
        return self:gen_while(stmt)
    else
        error("unknown statement kind: " .. tostring(stmt.kind))
    end
end

function Codegen:gen_if(stmt)
    local parts = {}
    table.insert(parts, "if (" .. self:gen_expr(stmt.condition) .. ") {")
    for _, s in ipairs(stmt.then_block.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    if stmt.else_block then
        table.insert(parts, "} else {")
        for _, s in ipairs(stmt.else_block.statements) do
            table.insert(parts, "    " .. self:gen_statement(s))
        end
    end
    table.insert(parts, "}")
    return join(parts, "\n    ")
end

function Codegen:gen_while(stmt)
    local parts = {}
    table.insert(parts, "while (" .. self:gen_expr(stmt.condition) .. ") {")
    for _, s in ipairs(stmt.body.statements) do
        table.insert(parts, "    " .. self:gen_statement(s))
    end
    table.insert(parts, "}")
    return join(parts, "\n    ")
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
        local obj_expr = self:gen_expr(expr.object)
        -- Determine if we need -> or .
        -- Check if the object is an identifier and if its type is a pointer
        local use_arrow = false
        if expr.object.kind == "identifier" then
            local var_type = self:get_var_type(expr.object.name)
            if var_type and self:is_pointer_type(var_type) then
                use_arrow = true
            end
        elseif expr.object.kind == "unary" and expr.object.op == "*" then
            -- Explicit dereference, use .
            use_arrow = false
        end
        local accessor = use_arrow and "->" or "."
        return string.format("%s%s%s", obj_expr, accessor, expr.field)
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
    self:push_scope()
    -- Add function parameters to scope
    for _, param in ipairs(fn.params) do
        self:add_var(param.name, param.type)
    end
    self:gen_block(fn.body)
    self:pop_scope()
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
