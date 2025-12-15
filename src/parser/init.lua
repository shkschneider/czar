-- Recursive descent / Pratt parser for the minimal Czar grammar.
-- Consumes the token stream from lexer.lua and produces an AST.

local Parser = {}
Parser.__index = Parser

-- Shared type keywords table
local TYPE_KEYWORDS = {
    ["i8"] = true,
    ["i16"] = true,
    ["i32"] = true,
    ["i64"] = true,
    ["u8"] = true,
    ["u16"] = true,
    ["u32"] = true,
    ["u64"] = true,
    ["f32"] = true,
    ["f64"] = true,
    ["bool"] = true,
    ["void"] = true,
    ["any"] = true,
}

local function token_label(tok)
    if not tok then return "<eof>" end
    return string.format("%s('%s') at %d:%d", tok.type, tok.value, tok.line, tok.col)
end

local function is_type_token(tok)
    if not tok then return false end
    if tok.type == "IDENT" then return true end
    if tok.type == "KEYWORD" and TYPE_KEYWORDS[tok.value] then
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
    elseif self:check("DIRECTIVE") then
        return self:parse_top_level_directive()
    else
        error(string.format("unexpected token in top-level: %s", token_label(self:current())))
    end
end

function Parser:parse_top_level_directive()
    local directive_tok = self:expect("DIRECTIVE")
    local directive_name = directive_tok.value:upper()
    
    -- #malloc and #free directives take a function name argument
    if directive_name == "MALLOC" or directive_name == "FREE" then
        -- Accept both IDENT and KEYWORD tokens (e.g., "malloc" and "free" are keywords)
        local func_name_tok = self:current()
        if not func_name_tok or (func_name_tok.type ~= "IDENT" and func_name_tok.type ~= "KEYWORD") then
            error(string.format("expected function name after #%s but found %s", directive_name:lower(), token_label(func_name_tok)))
        end
        self:advance()
        
        return { 
            kind = "allocator_directive", 
            directive_type = directive_name:lower(),
            function_name = func_name_tok.value,
            line = directive_tok.line,
            col = directive_tok.col
        }
    elseif directive_name == "ALIAS" then
        -- #alias mytype existing_type
        -- mytype is one word, existing_type can be multiple tokens (rest of the line)
        local alias_name_tok = self:expect("IDENT")
        local alias_name = alias_name_tok.value
        
        -- Collect all remaining tokens until end of line/statement as the target type string
        -- We'll collect tokens and concatenate them with appropriate spacing
        local target_type_tokens = {}
        
        -- Keep reading tokens until we hit EOF, a directive, struct, or fn keyword
        while self:current() and 
              not self:check("EOF") and 
              not self:check("DIRECTIVE") and
              not (self:check("KEYWORD", "struct") or self:check("KEYWORD", "fn")) do
            local tok = self:current()
            table.insert(target_type_tokens, tok.value)
            self:advance()
        end
        
        if #target_type_tokens == 0 then
            error(string.format("expected target type after #alias %s at %d:%d", 
                alias_name, directive_tok.line, directive_tok.col))
        end
        
        -- Join tokens to form the target type string
        local target_type_str = table.concat(target_type_tokens, " ")
        
        return {
            kind = "alias_directive",
            alias_name = alias_name,
            target_type_str = target_type_str,
            line = directive_tok.line,
            col = directive_tok.col
        }
    else
        error(string.format("unknown top-level directive: #%s at %d:%d", directive_tok.value, directive_tok.line, directive_tok.col))
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
    
    -- Helper to parse method name (allows 'new' and 'free' as special method names)
    local function parse_method_name(self)
        local tok = self:current()
        if tok and tok.type == "KEYWORD" and (tok.value == "new" or tok.value == "free") then
            return self:advance().value  -- Accept keyword as method name
        else
            return self:expect("IDENT").value  -- Normal identifier
        end
    end
    
    -- Check if this is a method definition
    -- Type:method for instance methods (implicit mutable self)
    -- Type.method for static methods (no implicit self)
    if self:match("COLON") then
        receiver_type = name  -- The first identifier is the type
        name = parse_method_name(self)
        is_static_method = false  -- Instance method with implicit self
    elseif self:match("DOT") then
        receiver_type = name  -- The first identifier is the type
        name = parse_method_name(self)
        is_static_method = true  -- Static method, no implicit self
    end
    
    self:expect("LPAREN")
    local params = {}
    
    -- For instance methods (Type:method), add implicit mutable self parameter
    if receiver_type and not is_static_method then
        local self_type = { kind = "named_type", name = receiver_type }
        -- In explicit pointer model, self is a pointer to the type
        local self_param_type = { kind = "pointer", to = self_type }
        table.insert(params, { name = "self", type = self_param_type, mutable = true })
    end
    
    if not self:check("RPAREN") then
        repeat
            local is_mut = self:match("KEYWORD", "mut") ~= nil
            local param_type = self:parse_type()
            -- In explicit pointer model, mut is just a mutability flag, not an implicit pointer
            -- The user must use Type* for pointer parameters
            local param_name = self:expect("IDENT").value
            local default_value = nil
            -- Check for default value
            if self:match("EQUAL") then
                default_value = self:parse_expression()
            end
            table.insert(params, { name = param_name, type = param_type, mutable = is_mut, default_value = default_value })
        until not self:match("COMMA")
    end
    self:expect("RPAREN")
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
        -- Check if this is an array type (Type[size])
        if self:match("LBRACKET") then
            local size_tok = self:expect("INT")
            local size = tonumber(size_tok.value)
            self:expect("RBRACKET")
            return { kind = "array", element_type = base_type, size = size }
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
    elseif self:check("KEYWORD", "free") then
        self:advance()
        local expr = self:parse_expression()
        self:match("SEMICOLON")  -- semicolons are optional
        return { kind = "free", value = expr }
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
                -- Variable declaration can be with or without initialization
                -- Check for = (with init) or semicolon/newline (without init)
                if self:check("EQUAL") or self:check("SEMICOLON") or self:check("EOF") or 
                   (self:current() and (self:current().line > name_tok.line or self:current().type == "KEYWORD")) then
                    -- This is a variable declaration
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
    -- Check for type keywords or user-defined types (identifiers - could be aliases or structs)
    if tok.type == "KEYWORD" and TYPE_KEYWORDS[tok.value] then
        return true
    end
    if tok.type == "IDENT" then
        return true
    end
    return false
end

function Parser:parse_if()
    self:expect("KEYWORD", "if")
    local condition = self:parse_expression()
    local then_block = self:parse_block()
    local else_block = nil
    if self:match("KEYWORD", "elseif") then
        -- elseif - parse condition and treat as nested if statement
        local elseif_condition = self:parse_expression()
        local elseif_then_block = self:parse_block()
        -- Create nested if statement for the elseif
        local nested_if = { kind = "if", condition = elseif_condition, then_block = elseif_then_block, else_block = nil }
        -- Check for more elseif or else
        if self:check("KEYWORD", "elseif") or self:check("KEYWORD", "else") then
            -- Recursively handle more elseif/else by parsing the rest
            nested_if.else_block = self:parse_if_continuation()
        end
        else_block = { kind = "block", statements = { nested_if } }
    elseif self:match("KEYWORD", "else") then
        if self:check("KEYWORD", "if") then
            -- else if - parse as nested if statement (for backward compatibility)
            else_block = { kind = "block", statements = { self:parse_if() } }
        else
            else_block = self:parse_block()
        end
    end
    return { kind = "if", condition = condition, then_block = then_block, else_block = else_block }
end

function Parser:parse_if_continuation()
    -- Parse the continuation of an if statement (elseif/else part only)
    if self:match("KEYWORD", "elseif") then
        local elseif_condition = self:parse_expression()
        local elseif_then_block = self:parse_block()
        local nested_if = { kind = "if", condition = elseif_condition, then_block = elseif_then_block, else_block = nil }
        if self:check("KEYWORD", "elseif") or self:check("KEYWORD", "else") then
            nested_if.else_block = self:parse_if_continuation()
        end
        return { kind = "block", statements = { nested_if } }
    elseif self:match("KEYWORD", "else") then
        return self:parse_block()
    end
    return nil
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

function Parser:parse_binary_or()
    local left = self:parse_binary_and()
    while true do
        local tok = self:current()
        if tok and tok.type == "KEYWORD" and tok.value == "or" then
            self:advance()
            local right = self:parse_binary_and()
            left = { kind = "binary", op = "or", left = left, right = right }
        else
            break
        end
    end
    return left
end

function Parser:parse_binary_and()
    local left = self:parse_equality()
    while true do
        local tok = self:current()
        if tok and tok.type == "KEYWORD" and tok.value == "and" then
            self:advance()
            local right = self:parse_equality()
            left = { kind = "binary", op = "and", left = left, right = right }
        else
            break
        end
    end
    return left
end

function Parser:parse_equality()
    local left = self:parse_relational()
    while true do
        local tok = self:current()
        if tok and (tok.type == "EQ" or tok.type == "NEQ") then
            self:advance()
            local right = self:parse_relational()
            left = { kind = "binary", op = tok.value, left = left, right = right }
        elseif tok and tok.type == "KEYWORD" and tok.value == "is" then
            -- Handle 'is' keyword for type checking
            self:advance()
            local type_node = self:parse_type()
            left = { kind = "is_check", expr = left, type = type_node }
        else
            break
        end
    end
    return left
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
    if tok and (tok.type == "MINUS" or tok.type == "AMPERSAND" or tok.type == "STAR") then
        self:advance()
        local operand = self:parse_unary()
        return { kind = "unary", op = tok.value, operand = operand }
    elseif tok and tok.type == "KEYWORD" and tok.value == "not" then
        self:advance()
        local operand = self:parse_unary()
        return { kind = "unary", op = "not", operand = operand }
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
                    -- In caller-controlled mutability: mut means "I allow mutation"
                    local is_mut = self:match("KEYWORD", "mut") ~= nil
                    
                    -- Check for named argument (name: value)
                    local arg_name = nil
                    if self:check("IDENT") then
                        local next_pos = self.pos + 1
                        if self.tokens[next_pos] and self.tokens[next_pos].type == "COLON" then
                            -- This is a named argument
                            arg_name = self:advance().value  -- consume identifier
                            self:advance()  -- consume colon
                        end
                    end
                    
                    local arg_expr = self:parse_expression()
                    if is_mut then
                        -- Wrap in mut_arg to indicate caller allows mutation
                        -- The callee can opt-in to receive mut or not
                        arg_expr = { kind = "mut_arg", expr = arg_expr, allows_mutation = true }
                    end
                    if arg_name then
                        -- This is a named argument
                        arg_expr = { kind = "named_arg", name = arg_name, expr = arg_expr }
                    end
                    table.insert(args, arg_expr)
                until not self:match("COMMA")
            end
            self:expect("RPAREN")
            expr = { kind = "call", callee = expr, args = args }
        elseif self:match("LBRACKET") then
            -- Array indexing: arr[index]
            local index = self:parse_expression()
            self:expect("RBRACKET")
            expr = { kind = "index", array = expr, index = index }
        elseif self:match("BANG") then
            -- Null check operator: a! (postfix)
            expr = { kind = "null_check", operand = expr }
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
                        -- Check for named argument (name: value)
                        local arg_name = nil
                        if self:check("IDENT") then
                            local next_pos = self.pos + 1
                            if self.tokens[next_pos] and self.tokens[next_pos].type == "COLON" then
                                -- This is a named argument
                                arg_name = self:advance().value  -- consume identifier
                                self:advance()  -- consume colon
                            end
                        end
                        
                        local arg_expr = self:parse_expression()
                        if arg_name then
                            arg_expr = { kind = "named_arg", name = arg_name, expr = arg_expr }
                        end
                        table.insert(args, arg_expr)
                    until not self:match("COMMA")
                end
                self:expect("RPAREN")
                expr = { kind = "static_method_call", type_name = expr.name, method = field, args = args }
            else
                -- Regular field access
                expr = { kind = "field", object = expr, field = field }
            end
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
    elseif tok.type == "KEYWORD" and tok.value == "type" then
        -- type expr - returns a const string with the type name
        self:advance()
        local expr = self:parse_unary()  -- Parse next expression at unary level
        return { kind = "type_of", expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "sizeof" then
        -- sizeof expr - returns the size in bytes of the type
        self:advance()
        local expr = self:parse_unary()  -- Parse next expression at unary level
        return { kind = "sizeof", expr = expr }
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
    elseif tok.type == "DIRECTIVE" then
        local directive = self:advance()
        return { kind = "directive", name = directive.value, line = directive.line, col = directive.col }
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
