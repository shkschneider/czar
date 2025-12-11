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
    local type_keywords = {
        ["i32"] = true,
        ["i64"] = true,
        ["u32"] = true,
        ["u64"] = true,
        ["f32"] = true,
        ["f64"] = true,
        ["bool"] = true,
        ["void"] = true,
    }
    if tok.type == "KEYWORD" and type_keywords[tok.value] then
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
        -- No mut keyword on fields - mutability comes from variable
        local field_type = self:parse_type()
        local field_name = self:expect("IDENT").value
        self:match("SEMICOLON")  -- semicolons are optional
        
        -- If the field type is the same as the struct name, make it a pointer
        -- This handles self-referential types like: struct Node { Node next }
        if field_type.kind == "named_type" and field_type.name == name then
            field_type = { kind = "pointer", to = field_type }
        end
        
        table.insert(fields, { name = field_name, type = field_type })
    end
    self:expect("RBRACE")
    return { kind = "struct", name = name, fields = fields }
end

function Parser:parse_function()
    self:expect("KEYWORD", "fn")
    local receiver_type = nil
    local is_static_method = false
    local name = self:expect("IDENT").value
    
    -- Check if this is a method definition
    -- Type:method for instance methods (implicit mutable self)
    -- Type.method for static methods (no implicit self)
    if self:match("COLON") then
        receiver_type = name  -- The first identifier is the type
        name = self:expect("IDENT").value  -- The second identifier is the method name
        is_static_method = false  -- Instance method with implicit self
    elseif self:match("DOT") then
        receiver_type = name  -- The first identifier is the type
        name = self:expect("IDENT").value  -- The second identifier is the method name
        is_static_method = true  -- Static method, no implicit self
    end
    
    self:expect("LPAREN")
    local params = {}
    
    -- For instance methods (Type:method), add implicit mutable self parameter
    if receiver_type and not is_static_method then
        local self_type = { kind = "named_type", name = receiver_type }
        local self_param_type = { kind = "pointer", to = self_type, is_mut = true }
        table.insert(params, { name = "self", type = self_param_type })
    end
    
    if not self:check("RPAREN") then
        repeat
            local is_mut = self:match("KEYWORD", "mut") ~= nil
            local param_type = self:parse_type()
            -- If mut is specified, wrap the type in a pointer internally
            if is_mut then
                param_type = { kind = "pointer", to = param_type, is_mut = true }
            end
            local param_name = self:expect("IDENT").value
            table.insert(params, { name = param_name, type = param_type })
        until not self:match("COMMA")
    end
    self:expect("RPAREN")
    self:expect("ARROW")
    local return_type = self:parse_type()
    local body = self:parse_block()
    return { kind = "function", name = name, receiver_type = receiver_type, params = params, return_type = return_type, body = body }
end

function Parser:parse_type()
    local tok = self:current()
    if is_type_token(tok) then
        self:advance()
        local base_type = { kind = "named_type", name = tok.value }
        -- Check if this is a pointer type (Type*)
        if self:match("STAR") then
            return { kind = "pointer", to = base_type }
        end
        return base_type
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
        self:match("SEMICOLON")  -- semicolons are optional
        return { kind = "return", value = expr }
    elseif self:check("KEYWORD", "if") then
        return self:parse_if()
    elseif self:check("KEYWORD", "while") then
        return self:parse_while()
    else
        -- Try to parse as variable declaration (mut Type name = ... or Type name = ...)
        -- Save position to backtrack if needed
        local saved_pos = self.pos
        local is_var_decl = false
        local is_mutable = false
        
        -- Check for optional mut keyword
        if self:check("KEYWORD", "mut") then
            is_mutable = true
            self:advance()
        end
        
        -- Check if this looks like a type declaration
        if self:is_type_start() then
            local success, type_node = pcall(function() return self:parse_type() end)
            if success and self:check("IDENT") then
                local name_tok = self:current()
                self:advance()
                if self:check("EQUAL") then
                    -- This is a variable declaration: mut Type name = expr or Type name = expr
                    is_var_decl = true
                    self.pos = saved_pos  -- Reset to parse properly
                end
            end
        end
        
        if is_var_decl then
            -- Parse as variable declaration
            local mutable = false
            if self:match("KEYWORD", "mut") then
                mutable = true
            end
            local type_ = self:parse_type()
            local name = self:expect("IDENT").value
            local init = nil
            if self:match("EQUAL") then
                init = self:parse_expression()
            end
            self:match("SEMICOLON")
            return { kind = "var_decl", name = name, type = type_, mutable = mutable, init = init }
        else
            -- Reset and parse as expression statement
            self.pos = saved_pos
            local expr = self:parse_expression()
            self:match("SEMICOLON")  -- semicolons are optional
            return { kind = "expr_stmt", expression = expr }
        end
    end
end

-- Helper to check if current token could start a type
function Parser:is_type_start()
    local tok = self:current()
    if not tok then return false end
    -- Check for type keywords or identifiers that look like types
    if tok.type == "KEYWORD" and (tok.value == "i32" or tok.value == "i64" or 
                                   tok.value == "u32" or tok.value == "u64" or 
                                   tok.value == "f32" or tok.value == "f64" or 
                                   tok.value == "bool" or tok.value == "void") then
        return true
    end
    -- Check for user-defined types (identifiers starting with uppercase)
    if tok.type == "IDENT" and tok.value:match("^[A-Z]") then
        return true
    end
    return false
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
    local expr = self:parse_null_coalesce()
    if self:match("EQUAL") then
        local value = self:parse_assignment()
        return { kind = "assign", target = expr, value = value }
    elseif self:match("PLUSEQUAL") then
        local value = self:parse_assignment()
        return { kind = "compound_assign", target = expr, operator = "+", value = value }
    elseif self:match("MINUSEQUAL") then
        local value = self:parse_assignment()
        return { kind = "compound_assign", target = expr, operator = "-", value = value }
    elseif self:match("STAREQUAL") then
        local value = self:parse_assignment()
        return { kind = "compound_assign", target = expr, operator = "*", value = value }
    elseif self:match("SLASHEQUAL") then
        local value = self:parse_assignment()
        return { kind = "compound_assign", target = expr, operator = "/", value = value }
    end
    return expr
end

function Parser:parse_null_coalesce()
    return self:parse_binary_chain(self.parse_binary_or, { NULLCOALESCE = true })
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
                    -- Check for mut keyword before argument
                    local is_mut = self:match("KEYWORD", "mut") ~= nil
                    local arg_expr = self:parse_expression()
                    if is_mut then
                        -- Wrap the argument expression to indicate it should be passed as mutable
                        arg_expr = { kind = "mut_arg", expr = arg_expr }
                    end
                    table.insert(args, arg_expr)
                until not self:match("COMMA")
            end
            self:expect("RPAREN")
            expr = { kind = "call", callee = expr, args = args }
        elseif self:match("SAFENAV") then
            -- Safe navigation operator: a?.b
            local field = self:expect("IDENT").value
            expr = { kind = "safe_nav", object = expr, field = field }
        elseif self:match("COLON") then
            -- Method call using colon: obj:method()
            local method_name = self:expect("IDENT").value
            expr = { kind = "method_ref", object = expr, method = method_name }
        elseif self:match("DOT") then
            -- Could be field access or static method call Type.method(obj)
            local field = self:expect("IDENT").value
            -- Check if this is followed by LPAREN for static method call
            if self:check("LPAREN") and expr.kind == "identifier" and expr.name:match("^[A-Z]") then
                -- This looks like Type.method(args) - static method call
                self:advance()  -- consume LPAREN
                local args = {}
                if not self:check("RPAREN") then
                    repeat
                        table.insert(args, self:parse_expression())
                    until not self:match("COMMA")
                end
                self:expect("RPAREN")
                expr = { kind = "static_method_call", type_name = expr.name, method = field, args = args }
            else
                -- Regular field access
                expr = { kind = "field", object = expr, field = field }
            end
        elseif self:match("BANGBANG") then
            -- Null check operator: a!!
            expr = { kind = "null_check", operand = expr }
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
    elseif tok.type == "KEYWORD" and tok.value == "cast" then
        -- cast<Type> expr
        self:advance()
        self:expect("LT")
        local target_type = self:parse_type()
        self:expect("GT")
        local expr = self:parse_unary()  -- Parse next expression at unary level
        return { kind = "cast", target_type = target_type, expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "clone" then
        -- clone expr or clone<Type> expr
        self:advance()
        local target_type = nil
        if self:match("LT") then
            target_type = self:parse_type()
            self:expect("GT")
        end
        local expr = self:parse_unary()  -- Parse next expression at unary level
        return { kind = "clone", target_type = target_type, expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "new" then
        -- new Type { fields... }
        self:advance()
        local type_name_tok = self:expect("IDENT")
        local type_name = type_name_tok.value
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
        return { kind = "new_heap", type_name = type_name, fields = fields }
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
