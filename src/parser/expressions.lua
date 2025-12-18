-- Parser module for expression parsing
-- Handles parsing of expressions (binary, unary, primary, etc.)

local Expressions = {}

function Expressions.parse_expression(parser)
    return Expressions.parse_assignment(parser)
end

function Expressions.parse_assignment(parser)
    local expr = Expressions.parse_binary_or(parser)
    if parser:match("EQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "assign", target = expr, value = value }
    elseif parser:match("PLUSEQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "compound_assign", target = expr, operator = "+", value = value }
    elseif parser:match("MINUSEQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "compound_assign", target = expr, operator = "-", value = value }
    elseif parser:match("STAREQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "compound_assign", target = expr, operator = "*", value = value }
    elseif parser:match("SLASHEQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "compound_assign", target = expr, operator = "/", value = value }
    elseif parser:match("PERCENTEQUAL") then
        local value = Expressions.parse_assignment(parser)
        return { kind = "compound_assign", target = expr, operator = "%", value = value }
    end
    return expr
end

function Expressions.parse_binary_or(parser)
    local left = Expressions.parse_binary_and(parser)
    while true do
        local tok = parser:current()
        if tok and tok.type == "KEYWORD" and tok.value == "or" then
            parser:advance()
            local right = Expressions.parse_binary_and(parser)
            left = { kind = "binary", op = "or", left = left, right = right }
        else
            break
        end
    end
    return left
end

function Expressions.parse_binary_and(parser)
    local left = Expressions.parse_bitwise_or(parser)
    while true do
        local tok = parser:current()
        if tok and tok.type == "KEYWORD" and tok.value == "and" then
            parser:advance()
            local right = Expressions.parse_bitwise_or(parser)
            left = { kind = "binary", op = "and", left = left, right = right }
        else
            break
        end
    end
    return left
end

function Expressions.parse_bitwise_or(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_bitwise_xor, { PIPE = true })
end

function Expressions.parse_bitwise_xor(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_bitwise_and, { CARET = true })
end

function Expressions.parse_bitwise_and(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_equality, { AMPERSAND = true })
end

function Expressions.parse_equality(parser)
    local Types = require("parser.types")
    local left = Expressions.parse_relational(parser)
    while true do
        local tok = parser:current()
        if tok and (tok.type == "EQ" or tok.type == "NEQ") then
            parser:advance()
            local right = Expressions.parse_relational(parser)
            left = { kind = "binary", op = tok.value, left = left, right = right }
        elseif tok and tok.type == "KEYWORD" and tok.value == "is" then
            -- Handle 'is' keyword for type checking
            parser:advance()
            local type_node = Types.parse_type(parser)
            left = { kind = "is_check", expr = left, type = type_node }
        else
            break
        end
    end
    return left
end

function Expressions.parse_relational(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_shift, { LT = true, GT = true, LTE = true, GTE = true })
end

function Expressions.parse_shift(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_additive, { SHL = true, SHR = true })
end

function Expressions.parse_additive(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_multiplicative, { PLUS = true, MINUS = true })
end

function Expressions.parse_multiplicative(parser)
    return Expressions.parse_binary_chain(parser, Expressions.parse_unary, { STAR = true, SLASH = true, PERCENT = true })
end

function Expressions.parse_binary_chain(parser, next_parser, ops)
    local left = next_parser(parser)
    while true do
        local tok = parser:current()
        if tok and ops[tok.type] then
            parser:advance()
            local right = next_parser(parser)
            left = { kind = "binary", op = tok.value, left = left, right = right }
        else
            break
        end
    end
    return left
end

function Expressions.parse_unary(parser)
    local tok = parser:current()
    if tok and (tok.type == "MINUS" or tok.type == "AMPERSAND" or tok.type == "STAR" or tok.type == "TILDE") then
        parser:advance()
        local operand = Expressions.parse_unary(parser)
        return { kind = "unary", op = tok.value, operand = operand }
    elseif tok and tok.type == "KEYWORD" and tok.value == "not" then
        parser:advance()
        local operand = Expressions.parse_unary(parser)
        return { kind = "unary", op = "not", operand = operand }
    elseif tok and (tok.type == "INCREMENT" or tok.type == "DECREMENT") then
        -- Prefix ++ or --
        parser:advance()
        local operand = Expressions.parse_unary(parser)
        return { kind = "prefix_op", op = tok.type == "INCREMENT" and "++" or "--", operand = operand }
    end
    return Expressions.parse_postfix(parser)
end

function Expressions.parse_postfix(parser)
    local Types = require("parser.types")
    local expr = Expressions.parse_primary(parser)
    while true do
        if parser:match("LPAREN") then
            local args = {}
            if not parser:check("RPAREN") then
                repeat
                    -- Check for mut keyword before argument
                    -- In caller-controlled mutability: mut means "I allow mutation"
                    local is_mut = parser:match("KEYWORD", "mut") ~= nil
                    
                    -- Check for named argument (name: value)
                    local arg_name = nil
                    if parser:check("IDENT") then
                        local next_pos = parser.pos + 1
                        if parser.tokens[next_pos] and parser.tokens[next_pos].type == "COLON" then
                            -- This is a named argument
                            arg_name = parser:advance().value  -- consume identifier
                            parser:advance()  -- consume colon
                        end
                    end
                    
                    local arg_expr = Expressions.parse_expression(parser)
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
                    if not parser:match("COMMA") then
                        break
                    end
                    -- Allow trailing comma: if next token is RPAREN, we're done
                    if parser:check("RPAREN") then
                        break
                    end
                until false
            end
            parser:expect("RPAREN")
            expr = { kind = "call", callee = expr, args = args }
        elseif parser:match("LBRACKET") then
            -- Array indexing: arr[index] or slice: arr[start:end]
            local start_index = Expressions.parse_expression(parser)
            
            -- Check if this is a slice (has a colon)
            if parser:match("COLON") then
                local end_index = Expressions.parse_expression(parser)
                parser:expect("RBRACKET")
                expr = { kind = "slice", array = expr, start = start_index, end_expr = end_index }
            else
                parser:expect("RBRACKET")
                expr = { kind = "index", array = expr, index = start_index }
            end
        elseif parser:match("BANG") then
            -- Null check operator: a! (postfix)
            expr = { kind = "null_check", operand = expr }
        elseif parser:check("COLON") and parser.tokens[parser.pos + 1] and parser.tokens[parser.pos + 1].type == "IDENT" and parser.tokens[parser.pos + 2] and parser.tokens[parser.pos + 2].type == "LPAREN" then
            -- Method call using colon: obj:method()
            -- Must be followed by LPAREN to distinguish from map entry syntax (key: value)
            parser:advance()  -- consume colon
            local method_name = parser:expect("IDENT").value
            expr = { kind = "method_ref", object = expr, method = method_name }
        elseif parser:match("DOT") then
            -- Could be field access or static method call Type.method(obj)
            local field = parser:expect("IDENT").value
            -- Check if this is followed by LPAREN for static method call
            if parser:check("LPAREN") and expr.kind == "identifier" and expr.name:match("^[A-Z]") then
                -- This looks like Type.method(args) - static method call
                parser:advance()  -- consume LPAREN
                local args = {}
                if not parser:check("RPAREN") then
                    repeat
                        -- Check for named argument (name: value)
                        local arg_name = nil
                        if parser:check("IDENT") then
                            local next_pos = parser.pos + 1
                            if parser.tokens[next_pos] and parser.tokens[next_pos].type == "COLON" then
                                -- This is a named argument
                                arg_name = parser:advance().value  -- consume identifier
                                parser:advance()  -- consume colon
                            end
                        end
                        
                        local arg_expr = Expressions.parse_expression(parser)
                        if arg_name then
                            arg_expr = { kind = "named_arg", name = arg_name, expr = arg_expr }
                        end
                        table.insert(args, arg_expr)
                    until not parser:match("COMMA")
                end
                parser:expect("RPAREN")
                expr = { kind = "static_method_call", type_name = expr.name, method = field, args = args }
            else
                -- Regular field access
                expr = { kind = "field", object = expr, field = field }
            end
        elseif expr.kind == "identifier" and parser:check("LBRACE") then
            -- Struct literal: only parse if we're not in a context where { starts a block
            -- We can check if the previous tokens/context suggests this is a struct literal
            -- For v0, let's be conservative: only parse as struct literal if identifier looks like a type
            -- (starts with uppercase) or if we're sure it's not a block context
            local name = expr.name
            if name:match("^[A-Z]") then
                expr = Expressions.parse_struct_literal(parser, expr)
            else
                break
            end
        -- Old cast syntax (as<Type>) is now deprecated, replaced with <Type> expr
        -- elseif parser:check("KEYWORD", "as") then
        --     ...removed...
        else
            break
        end
    end
    return expr
end

function Expressions.parse_primary(parser)
    local Macros = require("src.macros")
    local tok = parser:current()
    if not tok then
        error("unexpected end of input")
    end

    if tok.type == "INT" then
        parser:advance()
        return { kind = "int", value = tonumber(tok.value) }
    elseif tok.type == "STRING" then
        parser:advance()
        return { kind = "string", value = tok.value }
    elseif tok.type == "KEYWORD" and (tok.value == "true" or tok.value == "false") then
        parser:advance()
        return { kind = "bool", value = tok.value == "true" }
    elseif tok.type == "KEYWORD" and tok.value == "null" then
        parser:advance()
        return { kind = "null" }
    elseif tok.type == "KEYWORD" and tok.value == "type" then
        -- type expr - returns a const string with the type name
        parser:advance()
        local expr = Expressions.parse_unary(parser)  -- Parse next expression at unary level
        return { kind = "type_of", expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "sizeof" then
        -- sizeof expr - returns the size in bytes of the type
        parser:advance()
        local expr = Expressions.parse_unary(parser)  -- Parse next expression at unary level
        return { kind = "sizeof", expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "clone" then
        -- clone expr or clone<Type> expr
        parser:advance()
        local Types = require("parser.types")
        local target_type = nil
        if parser:match("LT") then
            target_type = Types.parse_type(parser)
            parser:expect("GT")
        end
        local expr = Expressions.parse_unary(parser)  -- Parse next expression at unary level
        return { kind = "clone", target_type = target_type, expr = expr }
    elseif tok.type == "KEYWORD" and tok.value == "new" then
        -- new [ elements... ] or new { key: value, ... } or new Type { ... }
        parser:advance()
        
        -- Check if this is a dynamic array: new [...]
        if parser:check("LBRACKET") then
            parser:advance()
            local elements = {}
            if not parser:check("RBRACKET") then
                repeat
                    table.insert(elements, Expressions.parse_expression(parser))
                until not parser:match("COMMA")
            end
            parser:expect("RBRACKET")
            return { kind = "new_array", elements = elements }
        end
        
        -- Check for new array [ ... ], new map { ... }, or new pair [ ... ]
        if parser:check("KEYWORD", "array") then
            parser:advance()
            parser:expect("LBRACKET")
            local elements = {}
            if not parser:check("RBRACKET") then
                repeat
                    table.insert(elements, Expressions.parse_expression(parser))
                    if not parser:match("COMMA") then
                        break
                    end
                    -- Allow trailing comma: if next token is RBRACKET, we're done
                    if parser:check("RBRACKET") then
                        break
                    end
                until false
            end
            parser:expect("RBRACKET")
            return { kind = "new_array", elements = elements }
        end
        
        if parser:check("KEYWORD", "map") then
            parser:advance()
            parser:expect("LBRACE")
            local entries = {}
            if not parser:check("RBRACE") then
                repeat
                    local key = Expressions.parse_expression(parser)
                    parser:expect("COLON")
                    local value = Expressions.parse_expression(parser)
                    table.insert(entries, { key = key, value = value })
                    if not parser:match("COMMA") then
                        break
                    end
                    -- Allow trailing comma: if next token is RBRACE, we're done
                    if parser:check("RBRACE") then
                        break
                    end
                until false
            end
            parser:expect("RBRACE")
            return { kind = "new_map", entries = entries }
        end
        
        if parser:check("KEYWORD", "pair") then
            parser:advance()
            parser:expect("LBRACKET")
            local left = Expressions.parse_expression(parser)
            parser:expect("COLON")
            local right = Expressions.parse_expression(parser)
            parser:match("COMMA")  -- Optional trailing comma
            parser:expect("RBRACKET")
            return { kind = "new_pair", left = left, right = right }
        end
        
        if parser:check("KEYWORD", "string") then
            parser:advance()
            local str_tok = parser:expect("STRING")
            return { kind = "new_string", value = str_tok.value }
        end
        
        -- Otherwise, it's a struct allocation: new Type { ... }
        local type_name_tok = parser:expect("IDENT")
        local type_name = type_name_tok.value
        parser:expect("LBRACE")
        local fields = {}
        if not parser:check("RBRACE") then
            repeat
                local name = parser:expect("IDENT").value
                parser:expect("COLON")
                local value = Expressions.parse_expression(parser)
                table.insert(fields, { name = name, value = value })
                if not parser:match("COMMA") then
                    break
                end
                -- Allow trailing comma: if next token is RBRACE, we're done
                if parser:check("RBRACE") then
                    break
                end
            until false
        end
        parser:expect("RBRACE")
        return { kind = "new_heap", type_name = type_name, fields = fields }
    elseif tok.type == "KEYWORD" and tok.value == "array" then
        -- Stack array literal: array [ expr, expr, ... ]
        parser:advance()
        parser:expect("LBRACKET")
        local elements = {}
        if not parser:check("RBRACKET") then
            repeat
                table.insert(elements, Expressions.parse_expression(parser))
                if not parser:match("COMMA") then
                    break
                end
                -- Allow trailing comma: if next token is RBRACKET, we're done
                if parser:check("RBRACKET") then
                    break
                end
            until false
        end
        parser:expect("RBRACKET")
        return { kind = "array_literal", elements = elements }
    elseif tok.type == "KEYWORD" and tok.value == "map" then
        -- Stack map literal: map { key: value, ... }
        parser:advance()
        parser:expect("LBRACE")
        local entries = {}
        if not parser:check("RBRACE") then
            repeat
                local key = Expressions.parse_expression(parser)
                parser:expect("COLON")
                local value = Expressions.parse_expression(parser)
                table.insert(entries, { key = key, value = value })
                if not parser:match("COMMA") then
                    break
                end
                -- Allow trailing comma: if next token is RBRACE, we're done
                if parser:check("RBRACE") then
                    break
                end
            until false
        end
        parser:expect("RBRACE")
        return { kind = "map_literal", entries = entries }
    elseif tok.type == "KEYWORD" and tok.value == "pair" then
        -- Stack pair literal: pair [ left: right ]
        parser:advance()
        parser:expect("LBRACKET")
        local left = Expressions.parse_expression(parser)
        parser:expect("COLON")
        local right = Expressions.parse_expression(parser)
        parser:match("COMMA")  -- Optional trailing comma
        parser:expect("RBRACKET")
        return { kind = "pair_literal", left = left, right = right }
    elseif tok.type == "KEYWORD" and tok.value == "string" then
        -- Stack string literal: string "text"
        parser:advance()
        local str_tok = parser:expect("STRING")
        return { kind = "string_literal", value = str_tok.value }
    elseif tok.type == "LT" then
        -- Cast operator: <Type> expr with optional !! or ?? fallback
        -- <Type> expr !! - unsafe cast (with warning, runtime abort on failure)
        -- <Type> expr ?? fallback - safe cast with fallback
        -- <Type> expr - compiler ERROR for unsafe casts
        local line = tok.line  -- Save line number for error reporting
        parser:advance()  -- consume '<'
        
        local Types = require("parser.types")
        local target_type = Types.parse_type(parser)
        
        if not parser:match("GT") then
            error("Expected '>' after type in cast at line " .. (parser:current() and parser:current().line or "?"))
        end
        
        -- Parse only the primary expression (to avoid consuming !! as postfix op)
        local expr = Expressions.parse_primary(parser)
        
        -- Check for !! or ?? suffix
        -- !! is two consecutive BANG tokens (not a compound token, to avoid conflict with null check)
        local current_pos = parser.pos
        local next_tok = parser.tokens[current_pos + 1]
        if parser:check("BANG") and next_tok and next_tok.type == "BANG" then
            parser:advance()  -- consume first !
            parser:advance()  -- consume second !
            -- Unsafe cast with explicit permission
            return { kind = "unsafe_cast", target_type = target_type, expr = expr, explicit_unsafe = true, line = line }
        elseif parser:match("FALLBACK") then
            -- Safe cast with fallback
            local fallback_expr = Expressions.parse_primary(parser)
            return { kind = "safe_cast", target_type = target_type, expr = expr, fallback = fallback_expr, line = line }
        else
            -- No suffix - will be validated in typechecker
            return { kind = "unsafe_cast", target_type = target_type, expr = expr, explicit_unsafe = false, line = line }
        end
    elseif tok.type == "IDENT" then
        local ident = parser:advance()
        return { kind = "identifier", name = ident.value, line = ident.line, col = ident.col }
    elseif tok.type == "DIRECTIVE" then
        local directive_tok = parser:advance()
        -- Delegate to centralized Macros module
        return Macros.parse_expression(parser, directive_tok)
    elseif tok.type == "LPAREN" then
        parser:advance()
        local expr = Expressions.parse_expression(parser)
        parser:expect("RPAREN")
        return expr
    elseif tok.type == "LBRACKET" then
        -- Array literal: [ expr, expr, ... ]
        parser:advance()
        local elements = {}
        if not parser:check("RBRACKET") then
            repeat
                table.insert(elements, Expressions.parse_expression(parser))
                if not parser:match("COMMA") then
                    break
                end
                -- Allow trailing comma: if next token is RBRACKET, we're done
                if parser:check("RBRACKET") then
                    break
                end
            until false
        end
        parser:expect("RBRACKET")
        return { kind = "array_literal", elements = elements }
    else
        local token_label = require("parser.utils").token_label
        error(string.format("unexpected token: %s", token_label(tok)))
    end
end

function Expressions.parse_struct_literal(parser, type_ident)
    parser:expect("LBRACE")
    local fields = {}
    if not parser:check("RBRACE") then
        repeat
            local name = parser:expect("IDENT").value
            parser:expect("COLON")
            local value = Expressions.parse_expression(parser)
            table.insert(fields, { name = name, value = value })
            if not parser:match("COMMA") then
                break
            end
            -- Allow trailing comma: if next token is RBRACE, we're done
            if parser:check("RBRACE") then
                break
            end
        until false
    end
    parser:expect("RBRACE")
    return { kind = "struct_literal", type_name = type_ident.name, fields = fields }
end

return Expressions
