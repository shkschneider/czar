-- Recursive descent / Pratt parser for the minimal Czar grammar.
-- Consumes the token stream from lexer.lua and produces an AST.

local Macros = require("src.macros")

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
    -- Delegate to centralized Macros module
    -- Store token_label as a module function for error messages
    Parser.token_label = token_label
    return Macros.parse_top_level(self, directive_tok)
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
            local param_type = self:parse_type_with_map_shorthand()
            -- Check for varargs syntax (Type...)
            local is_varargs = self:match("ELLIPSIS") ~= nil
            if is_varargs then
                -- Convert type to varargs type
                param_type = { kind = "varargs", element_type = param_type }
            end
            -- In explicit pointer model, mut is just a mutability flag, not an implicit pointer
            -- The user must use Type* for pointer parameters
            local param_name = self:expect("IDENT").value
            local default_value = nil
            -- Check for default value (not allowed for varargs)
            if self:match("EQUAL") then
                if is_varargs then
                    error(string.format("varargs parameter '%s' cannot have a default value", param_name))
                end
                default_value = self:parse_expression()
            end
            table.insert(params, { name = param_name, type = param_type, mutable = is_mut, default_value = default_value })
            -- Varargs must be the last parameter
            if is_varargs and not self:check("RPAREN") then
                error(string.format("varargs parameter '%s' must be the last parameter", param_name))
            end
        until not self:match("COMMA")
    end
    self:expect("RPAREN")
    local return_type = self:parse_type()
    local body = self:parse_block()
    return { kind = "function", name = name, receiver_type = receiver_type, params = params, return_type = return_type, body = body }
end

function Parser:parse_type()
    local tok = self:current()
    
    -- Check for explicit container types: array<T>, slice<T>, map<K:V>
    if self:check("KEYWORD", "array") then
        self:advance()
        self:expect("LT")
        local element_type = self:parse_type()
        self:expect("GT")
        -- array<Type> is represented as a slice internally (dynamic size)
        return { kind = "slice", element_type = element_type }
    end
    
    if self:check("KEYWORD", "slice") then
        self:advance()
        self:expect("LT")
        local element_type = self:parse_type()
        self:expect("GT")
        return { kind = "slice", element_type = element_type }
    end
    
    if self:check("KEYWORD", "map") then
        self:advance()
        self:expect("LT")
        local key_type = self:parse_type()
        self:expect("COLON")
        local value_type = self:parse_type()
        self:expect("GT")
        return { kind = "map", key_type = key_type, value_type = value_type }
    end
    
    if is_type_token(tok) then
        self:advance()
        local base_type = { kind = "named_type", name = tok.value }
        -- Check if this is a pointer type (Type*)
        if self:match("STAR") then
            return { kind = "pointer", to = base_type }
        end
        -- Check if this is an array type (Type[size]) or slice type (Type[])
        if self:match("LBRACKET") then
            -- Check for slice type: Type[]
            if self:check("RBRACKET") then
                self:advance()
                return { kind = "slice", element_type = base_type }
            end
            -- Check for implicit size: Type[*]
            if self:match("STAR") then
                self:expect("RBRACKET")
                return { kind = "array", element_type = base_type, size = "*" }
            end
            -- Explicit size: Type[N]
            local size_tok = self:expect("INT")
            local size = tonumber(size_tok.value)
            self:expect("RBRACKET")
            return { kind = "array", element_type = base_type, size = size }
        end
        return base_type
    end
    error(string.format("expected type but found %s", token_label(tok)))
end

-- Parse type with map shorthand support (Type{ValueType})
-- This is only safe to use in contexts where { cannot start a block
function Parser:parse_type_with_map_shorthand()
    local tok = self:current()
    
    -- Check for explicit container types: array<T>, slice<T>, map<K:V>
    if self:check("KEYWORD", "array") or self:check("KEYWORD", "slice") or self:check("KEYWORD", "map") then
        return self:parse_type()
    end
    
    if is_type_token(tok) then
        self:advance()
        local base_type = { kind = "named_type", name = tok.value }
        -- Check if this is a pointer type (Type*)
        if self:match("STAR") then
            return { kind = "pointer", to = base_type }
        end
        -- Check if this is a map type shorthand (KeyType{ValueType})
        if self:match("LBRACE") then
            local value_type = self:parse_type()
            self:expect("RBRACE")
            return { kind = "map", key_type = base_type, value_type = value_type }
        end
        -- Check if this is an array type (Type[size]) or slice type (Type[])
        if self:match("LBRACKET") then
            -- Check for slice type: Type[]
            if self:check("RBRACKET") then
                self:advance()
                return { kind = "slice", element_type = base_type }
            end
            -- Check for implicit size: Type[*]
            if self:match("STAR") then
                self:expect("RBRACKET")
                return { kind = "array", element_type = base_type, size = "*" }
            end
            -- Explicit size: Type[N]
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
    elseif self:check("KEYWORD", "for") then
        return self:parse_for()
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
            local success, type_node = pcall(function() return self:parse_type_with_map_shorthand() end)
            if success and self:check("IDENT") then
                local name_tok = self:current()
                self:advance()
                -- Check if this looks like end of variable declaration
                if self:is_var_decl_end(name_tok) then
                    -- This is a variable declaration
                    is_var_decl = true
                    self.pos = saved_pos  -- Reset to parse properly
                end
            end
        end
        
        if is_var_decl then
            -- Parse as variable declaration
            local mutable = false
            local start_tok = self:current()  -- Save start token for line number
            if self:match("KEYWORD", "mut") then
                mutable = true
            end
            local type_ = self:parse_type_with_map_shorthand()
            local name_tok = self:expect("IDENT")
            local name = name_tok.value
            local init = nil
            if self:match("EQUAL") then
                init = self:parse_expression()
            end
            self:match("SEMICOLON")
            return { kind = "var_decl", name = name, type = type_, mutable = mutable, init = init, line = start_tok.line, col = start_tok.col }
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
    -- Check for container type keywords
    if tok.type == "KEYWORD" and (tok.value == "array" or tok.value == "slice" or tok.value == "map") then
        return true
    end
    -- Check for type keywords or user-defined types (identifiers - could be aliases or structs)
    if tok.type == "KEYWORD" and TYPE_KEYWORDS[tok.value] then
        return true
    end
    if tok.type == "IDENT" then
        return true
    end
    return false
end

-- Helper to check if we're at the end of a variable declaration
-- This checks for patterns that indicate: Type name [= expr] or Type name
function Parser:is_var_decl_end(name_tok)
    -- Variable declaration can be with or without initialization
    -- Check for = (with init) or semicolon/newline (without init)
    if self:check("EQUAL") or self:check("SEMICOLON") or self:check("EOF") then
        return true
    end
    -- Check if next token is on a new line (implicit statement end)
    local curr = self:current()
    if curr and curr.line > name_tok.line then
        return true
    end
    -- Check if next token is a keyword (likely start of new statement)
    if curr and curr.type == "KEYWORD" then
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

function Parser:parse_for()
    self:expect("KEYWORD", "for")
    
    -- Parse index variable (can be _ or identifier)
    local index_name = nil
    local index_is_underscore = false
    if self:check("IDENT") and self:current().value == "_" then
        index_is_underscore = true
        self:advance()
    else
        index_name = self:expect("IDENT").value
    end
    
    self:expect("COMMA")
    
    -- Parse item variable (can be _ or identifier, and can have mut)
    local item_mutable = self:match("KEYWORD", "mut") ~= nil
    local item_name = nil
    local item_is_underscore = false
    if self:check("IDENT") and self:current().value == "_" then
        item_is_underscore = true
        self:advance()
    else
        item_name = self:expect("IDENT").value
    end
    
    self:expect("KEYWORD", "in")
    
    -- Parse the collection expression
    local collection = self:parse_expression()
    
    local body = self:parse_block()
    
    return {
        kind = "for",
        index_name = index_name,
        index_is_underscore = index_is_underscore,
        item_name = item_name,
        item_is_underscore = item_is_underscore,
        item_mutable = item_mutable,
        collection = collection,
        body = body
    }
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
    elseif self:match("PERCENTEQUAL") then
        local value = self:parse_assignment()
        return { kind = "compound_assign", target = expr, operator = "%", value = value }
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
    local left = self:parse_bitwise_or()
    while true do
        local tok = self:current()
        if tok and tok.type == "KEYWORD" and tok.value == "and" then
            self:advance()
            local right = self:parse_bitwise_or()
            left = { kind = "binary", op = "and", left = left, right = right }
        else
            break
        end
    end
    return left
end

function Parser:parse_bitwise_or()
    return self:parse_binary_chain(self.parse_bitwise_xor, { PIPE = true })
end

function Parser:parse_bitwise_xor()
    return self:parse_binary_chain(self.parse_bitwise_and, { CARET = true })
end

function Parser:parse_bitwise_and()
    return self:parse_binary_chain(self.parse_equality, { AMPERSAND = true })
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
    return self:parse_binary_chain(self.parse_shift, { LT = true, GT = true, LTE = true, GTE = true })
end

function Parser:parse_shift()
    return self:parse_binary_chain(self.parse_additive, { SHL = true, SHR = true })
end

function Parser:parse_additive()
    return self:parse_binary_chain(self.parse_multiplicative, { PLUS = true, MINUS = true })
end

function Parser:parse_multiplicative()
    return self:parse_binary_chain(self.parse_unary, { STAR = true, SLASH = true, PERCENT = true })
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
    if tok and (tok.type == "MINUS" or tok.type == "AMPERSAND" or tok.type == "STAR" or tok.type == "TILDE") then
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
            -- Array indexing: arr[index] or slice: arr[start:end]
            local start_index = self:parse_expression()
            
            -- Check if this is a slice (has a colon)
            if self:match("COLON") then
                local end_index = self:parse_expression()
                self:expect("RBRACKET")
                expr = { kind = "slice", array = expr, start = start_index, end_expr = end_index }
            else
                self:expect("RBRACKET")
                expr = { kind = "index", array = expr, index = start_index }
            end
        elseif self:match("BANG") then
            -- Null check operator: a! (postfix)
            expr = { kind = "null_check", operand = expr }
        elseif self:check("COLON") and self.tokens[self.pos + 1] and self.tokens[self.pos + 1].type == "IDENT" then
            -- Method call using colon: obj:method()
            -- Only match if followed by identifier (not a slice operator)
            self:advance()  -- consume colon
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
        elseif self:check("KEYWORD", "as") then
            -- Cast operator: expr as<Type> (unsafe) or expr as?<Type>(fallback) (safe)
            self:advance()  -- consume 'as'
            
            -- Check for safe cast: as?<Type>(fallback)
            local is_safe = false
            if self:match("QUESTION") then
                is_safe = true
            end
            
            -- Expect '<' for type parameter
            if not self:match("LT") then
                error("Expected '<' after 'as' at line " .. (self:current() and self:current().line or "?"))
            end
            
            local target_type = self:parse_type()
            
            -- Expect '>'
            if not self:match("GT") then
                error("Expected '>' after type in cast at line " .. (self:current() and self:current().line or "?"))
            end
            
            -- If safe cast, expect (fallback)
            local fallback_expr = nil
            if is_safe then
                -- Expect '(' for fallback
                if not self:match("LPAREN") then
                    error("Expected '(' after 'as?<Type>' at line " .. (self:current() and self:current().line or "?"))
                end
                
                -- Parse fallback expression
                fallback_expr = self:parse_expression()
                
                -- Expect ')'
                if not self:match("RPAREN") then
                    error("Expected ')' after fallback in safe cast at line " .. (self:current() and self:current().line or "?"))
                end
            end
            
            if is_safe then
                expr = { kind = "safe_cast", target_type = target_type, expr = expr, fallback = fallback_expr }
            else
                expr = { kind = "unsafe_cast", target_type = target_type, expr = expr }
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
        -- new [ elements... ] or new { key: value, ... } or new Type { ... }
        self:advance()
        
        -- Check if this is a dynamic array: new [...]
        if self:check("LBRACKET") then
            self:advance()
            local elements = {}
            if not self:check("RBRACKET") then
                repeat
                    table.insert(elements, self:parse_expression())
                until not self:match("COMMA")
            end
            self:expect("RBRACKET")
            return { kind = "new_array", elements = elements }
        end
        
        -- Check if this is a brace literal: new { ... }
        -- Could be either a map or a struct
        if self:check("LBRACE") then
            self:advance()
            
            -- Empty literal
            if self:check("RBRACE") then
                self:advance()
                -- Return as map literal with no entries (type will be inferred from context)
                return { kind = "new_map", entries = {} }
            end
            
            -- Parse first entry to determine if it's a map or struct
            -- Save position to backtrack if needed
            local saved_pos = self.pos
            
            -- Try to parse as map entry (expr : expr)
            local is_map = false
            local success = pcall(function() self:parse_expression() end)
            if success and self:check("COLON") then
                -- This looks like a map
                is_map = true
            end
            
            -- Restore position
            self.pos = saved_pos
            
            if is_map then
                -- Parse as map literal: new { key: value, ... }
                local entries = {}
                repeat
                    local key = self:parse_expression()
                    self:expect("COLON")
                    local value = self:parse_expression()
                    table.insert(entries, { key = key, value = value })
                until not self:match("COMMA")
                self:expect("RBRACE")
                return { kind = "new_map", entries = entries }
            else
                -- Parse as struct literal: new { field: value, ... }
                -- Need to get struct type from identifier before the brace
                -- But we already consumed "new {", so we can't parse this way
                -- This case should not happen with the new syntax
                error("new { ... } with field names requires struct type: use 'new StructName { ... }' for structs")
            end
        end
        
        -- Otherwise, it's a struct allocation: new Type { ... }
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
        return { kind = "identifier", name = ident.value, line = ident.line, col = ident.col }
    elseif tok.type == "DIRECTIVE" then
        local directive_tok = self:advance()
        -- Delegate to centralized Macros module
        return Macros.parse_expression(self, directive_tok)
    elseif tok.type == "LPAREN" then
        self:advance()
        local expr = self:parse_expression()
        self:expect("RPAREN")
        return expr
    elseif tok.type == "LBRACKET" then
        -- Array literal: [ expr, expr, ... ]
        self:advance()
        local elements = {}
        if not self:check("RBRACKET") then
            repeat
                table.insert(elements, self:parse_expression())
            until not self:match("COMMA")
        end
        self:expect("RBRACKET")
        return { kind = "array_literal", elements = elements }
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
