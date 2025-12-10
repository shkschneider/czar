-- Recursive descent / Pratt parser for the minimal Czar grammar.
-- Consumes the token stream from lexer.lua and produces an AST.

local Parser = {}
Parser.__index = Parser

local function token_label(tok)
    if not tok then return "<eof>" end
    return string.format("%s('%s') at %d:%d", tok.type, tok.value, tok.line, tok.col)
end

local function is_type_token(tok)
    if not tok then return false end
    if tok.type == "IDENT" then return true end
    if tok.type == "KEYWORD" and (tok.value == "i32" or tok.value == "bool" or tok.value == "void") then
        return true
    end
    return false
end

function Parser.new(tokens)
    return setmetatable({ tokens = tokens, pos = 1 }, Parser)
end

function Parser:current()
    return self.tokens[self.pos]
end

function Parser:advance()
    local tok = self:current()
    if tok then self.pos = self.pos + 1 end
    return tok
end

function Parser:check(type_, value)
    local tok = self:current()
    if not tok then return false end
    if tok.type ~= type_ then return false end
    if value and tok.value ~= value then return false end
    return true
end

function Parser:match(type_, value)
    if self:check(type_, value) then
        return self:advance()
    end
    return nil
end

function Parser:expect(type_, value)
    local tok = self:current()
    if not self:match(type_, value) then
        error(string.format("expected %s but found %s", value or type_, token_label(tok)))
    end
    return tok
end

function Parser:parse_program()
    local items = {}
    while not self:check("EOF") do
        table.insert(items, self:parse_top_level())
    end
    return { kind = "program", items = items }
end

function Parser:parse_top_level()
    if self:check("KEYWORD", "struct") then
        return self:parse_struct()
    elseif self:check("KEYWORD", "fn") then
        return self:parse_function()
    else
        error(string.format("unexpected token in top-level: %s", token_label(self:current())))
    end
end

function Parser:parse_struct()
    self:expect("KEYWORD", "struct")
    local name = self:expect("IDENT").value
    self:expect("LBRACE")
    local fields = {}
    while not self:check("RBRACE") do
        local field_name = self:expect("IDENT").value
        self:expect("COLON")
        local field_type = self:parse_type()
        self:expect("SEMICOLON")
        table.insert(fields, { name = field_name, type = field_type })
    end
    self:expect("RBRACE")
    return { kind = "struct", name = name, fields = fields }
end

function Parser:parse_function()
    self:expect("KEYWORD", "fn")
    local name = self:expect("IDENT").value
    self:expect("LPAREN")
    local params = {}
    if not self:check("RPAREN") then
        repeat
            local param_name = self:expect("IDENT").value
            self:expect("COLON")
            local param_type = self:parse_type()
            table.insert(params, { name = param_name, type = param_type })
        until not self:match("COMMA")
    end
    self:expect("RPAREN")
    self:expect("ARROW")
    local return_type = self:parse_type()
    local body = self:parse_block()
    return { kind = "function", name = name, params = params, return_type = return_type, body = body }
end

function Parser:parse_type()
    if self:match("STAR") then
        return { kind = "pointer", to = self:parse_type() }
    end
    local tok = self:current()
    if is_type_token(tok) then
        self:advance()
        return { kind = "named_type", name = tok.value }
    end
    error(string.format("expected type but found %s", token_label(tok)))
end

function Parser:parse_block()
    self:expect("LBRACE")
    local statements = {}
    while not self:check("RBRACE") do
        table.insert(statements, self:parse_statement())
    end
    self:expect("RBRACE")
    return { kind = "block", statements = statements }
end

function Parser:parse_statement()
    if self:check("KEYWORD", "return") then
        self:advance()
        local expr = self:parse_expression()
        self:expect("SEMICOLON")
        return { kind = "return", value = expr }
    elseif self:check("KEYWORD", "var") or self:check("KEYWORD", "val") then
        return self:parse_var_decl()
    elseif self:check("KEYWORD", "if") then
        return self:parse_if()
    elseif self:check("KEYWORD", "while") then
        return self:parse_while()
    else
        local expr = self:parse_expression()
        self:expect("SEMICOLON")
        return { kind = "expr_stmt", expression = expr }
    end
end

function Parser:parse_var_decl()
    local mutable = self:match("KEYWORD", "var") ~= nil
    if not mutable then self:expect("KEYWORD", "val") end
    local name = self:expect("IDENT").value
    self:expect("COLON")
    local type_ = self:parse_type()
    local init = nil
    if self:match("EQUAL") then
        init = self:parse_expression()
    end
    self:expect("SEMICOLON")
    return { kind = "var_decl", name = name, type = type_, mutable = mutable, init = init }
end

function Parser:parse_if()
    self:expect("KEYWORD", "if")
    local condition = self:parse_expression()
    local then_block = self:parse_block()
    local else_block = nil
    if self:match("KEYWORD", "else") then
        if self:check("KEYWORD", "if") then
            -- else if - parse as nested if statement
            else_block = { kind = "block", statements = { self:parse_if() } }
        else
            else_block = self:parse_block()
        end
    end
    return { kind = "if", condition = condition, then_block = then_block, else_block = else_block }
end

function Parser:parse_while()
    self:expect("KEYWORD", "while")
    local condition = self:parse_expression()
    local body = self:parse_block()
    return { kind = "while", condition = condition, body = body }
end

-- Expression parsing

function Parser:parse_expression()
    return self:parse_assignment()
end

function Parser:parse_assignment()
    local expr = self:parse_binary_or()
    if self:match("EQUAL") then
        local value = self:parse_assignment()
        return { kind = "assign", target = expr, value = value }
    end
    return expr
end

function Parser:parse_binary_or()
    return self:parse_binary_chain(self.parse_binary_and, { OR = true })
end

function Parser:parse_binary_and()
    return self:parse_binary_chain(self.parse_equality, { AND = true })
end

function Parser:parse_equality()
    return self:parse_binary_chain(self.parse_relational, { EQ = true, NEQ = true })
end

function Parser:parse_relational()
    return self:parse_binary_chain(self.parse_additive, { LT = true, GT = true, LTE = true, GTE = true })
end

function Parser:parse_additive()
    return self:parse_binary_chain(self.parse_multiplicative, { PLUS = true, MINUS = true })
end

function Parser:parse_multiplicative()
    return self:parse_binary_chain(self.parse_unary, { STAR = true, SLASH = true })
end

function Parser:parse_binary_chain(next_parser, ops)
    local left = next_parser(self)
    while true do
        local tok = self:current()
        if tok and ops[tok.type] then
            self:advance()
            local right = next_parser(self)
            left = { kind = "binary", op = tok.value, left = left, right = right }
        else
            break
        end
    end
    return left
end

function Parser:parse_unary()
    local tok = self:current()
    if tok and (tok.type == "MINUS" or tok.type == "BANG" or tok.type == "AMPERSAND" or tok.type == "STAR") then
        self:advance()
        local operand = self:parse_unary()
        return { kind = "unary", op = tok.value, operand = operand }
    end
    return self:parse_postfix()
end

function Parser:parse_postfix()
    local expr = self:parse_primary()
    while true do
        if self:match("LPAREN") then
            local args = {}
            if not self:check("RPAREN") then
                repeat
                    table.insert(args, self:parse_expression())
                until not self:match("COMMA")
            end
            self:expect("RPAREN")
            expr = { kind = "call", callee = expr, args = args }
        elseif self:match("DOT") then
            local field = self:expect("IDENT").value
            expr = { kind = "field", object = expr, field = field }
        elseif expr.kind == "identifier" and self:check("LBRACE") then
            -- Struct literal: only parse if we're not in a context where { starts a block
            -- We can check if the previous tokens/context suggests this is a struct literal
            -- For v0, let's be conservative: only parse as struct literal if identifier looks like a type
            -- (starts with uppercase) or if we're sure it's not a block context
            local name = expr.name
            if name:match("^[A-Z]") then
                expr = self:parse_struct_literal(expr)
            else
                break
            end
        else
            break
        end
    end
    return expr
end

function Parser:parse_primary()
    local tok = self:current()
    if not tok then
        error("unexpected end of input")
    end

    if tok.type == "INT" then
        self:advance()
        return { kind = "int", value = tonumber(tok.value) }
    elseif tok.type == "STRING" then
        self:advance()
        return { kind = "string", value = tok.value }
    elseif tok.type == "KEYWORD" and (tok.value == "true" or tok.value == "false") then
        self:advance()
        return { kind = "bool", value = tok.value == "true" }
    elseif tok.type == "KEYWORD" and tok.value == "null" then
        self:advance()
        return { kind = "null" }
    elseif tok.type == "IDENT" then
        local ident = self:advance()
        return { kind = "identifier", name = ident.value }
    elseif tok.type == "LPAREN" then
        self:advance()
        local expr = self:parse_expression()
        self:expect("RPAREN")
        return expr
    else
        error(string.format("unexpected token: %s", token_label(tok)))
    end
end

function Parser:parse_struct_literal(type_ident)
    self:expect("LBRACE")
    local fields = {}
    if not self:check("RBRACE") then
        repeat
            local name = self:expect("IDENT").value
            self:expect("COLON")
            local value = self:parse_expression()
            table.insert(fields, { name = name, value = value })
        until not self:match("COMMA")
    end
    self:expect("RBRACE")
    return { kind = "struct_literal", type_name = type_ident.name, fields = fields }
end

return function(tokens)
    local parser = Parser.new(tokens)
    return parser:parse_program()
end
