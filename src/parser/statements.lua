-- Parser module for statement parsing
-- Handles parsing of statements (if, while, for, return, etc.)

local Statements = {}

function Statements.parse_block(parser)
    parser:expect("LBRACE")
    local statements = {}
    while not parser:check("RBRACE") do
        table.insert(statements, Statements.parse_statement(parser))
    end
    parser:expect("RBRACE")
    return { kind = "block", statements = statements }
end

function Statements.parse_statement(parser)
    local Macros = require("src.macros")
    local Expressions = require("parser.expressions")
    
    if parser:check("KEYWORD", "return") then
        parser:advance()
        local expr = Expressions.parse_expression(parser)
        parser:match("SEMICOLON")  -- semicolons are optional
        return { kind = "return", value = expr }
    elseif parser:check("KEYWORD", "break") then
        parser:advance()
        -- Check for optional level (break N)
        local level = nil
        if parser:check("INT") then
            level = tonumber(parser:current().value)
            parser:advance()
        end
        parser:match("SEMICOLON")  -- semicolons are optional
        return { kind = "break", level = level }
    elseif parser:check("KEYWORD", "continue") then
        parser:advance()
        -- Check for optional level (continue N)
        local level = nil
        if parser:check("INT") then
            level = tonumber(parser:current().value)
            parser:advance()
        end
        parser:match("SEMICOLON")  -- semicolons are optional
        return { kind = "continue", level = level }
    elseif parser:check("KEYWORD", "free") then
        parser:advance()
        local expr = Expressions.parse_expression(parser)
        parser:match("SEMICOLON")  -- semicolons are optional
        return { kind = "free", value = expr }
    elseif parser:check("DIRECTIVE") then
        -- Statement-level directives like #assert, #log, #defer
        local directive_tok = parser:advance()
        
        -- Check if this is a #defer directive
        if directive_tok.value:upper() == "DEFER" then
            -- #defer can defer either a statement or an expression
            -- Check if it's a free statement (special case)
            if parser:check("KEYWORD", "free") then
                parser:advance()  -- consume 'free'
                local expr = Expressions.parse_expression(parser)
                parser:match("SEMICOLON")  -- semicolons are optional
                -- Return a defer that wraps a free statement
                return { 
                    kind = "defer", 
                    value = { kind = "free", value = expr },
                    line = directive_tok.line, 
                    col = directive_tok.col 
                }
            else
                -- Parse as expression (for function calls, etc.)
                local expr = Expressions.parse_expression(parser)
                parser:match("SEMICOLON")  -- semicolons are optional
                return { kind = "defer", value = expr, line = directive_tok.line, col = directive_tok.col }
            end
        end
        
        -- Check if this is an #unsafe block
        if directive_tok.value:upper() == "UNSAFE" then
            -- Parse #unsafe { raw C code }
            -- We need to extract the raw source text between the braces
            if not parser.source then
                error("#unsafe requires source text to be available")
            end
            
            local lbrace_tok = parser:expect("LBRACE")
            local start_line = lbrace_tok.line
            local start_col = lbrace_tok.col + 1  -- After the {
            
            -- Find the matching closing brace by counting depth
            local brace_count = 1
            local end_tok = nil
            
            while brace_count > 0 and not parser:check("EOF") do
                local tok = parser:current()
                
                if tok.type == "LBRACE" then
                    brace_count = brace_count + 1
                elseif tok.type == "RBRACE" then
                    brace_count = brace_count - 1
                    if brace_count == 0 then
                        end_tok = tok
                        break
                    end
                end
                
                parser:advance()
            end
            
            if not end_tok then
                error("Unclosed #unsafe block")
            end
            
            -- Extract raw source text from start_line:start_col to end_tok.line:end_tok.col
            local raw_code = parser:extract_source_range(start_line, start_col, end_tok.line, end_tok.col)
            
            -- Advance past the closing brace
            parser:advance()
            
            return {
                kind = "unsafe_block",
                c_code = raw_code,
                line = directive_tok.line,
                col = directive_tok.col
            }
        end
        
        local stmt = Macros.parse_statement(parser, directive_tok)
        parser:match("SEMICOLON")  -- semicolons are optional
        return stmt
    elseif parser:check("KEYWORD", "if") then
        return Statements.parse_if(parser)
    elseif parser:check("KEYWORD", "while") then
        return Statements.parse_while(parser)
    elseif parser:check("KEYWORD", "for") then
        return Statements.parse_for(parser)
    elseif parser:check("KEYWORD", "repeat") then
        return Statements.parse_repeat(parser)
    elseif parser:check("LBRACE") then
        -- Bare block statement (for scoping)
        return Statements.parse_block(parser)
    else
        -- Try to parse as variable declaration (mut Type name = ... or Type name = ...)
        -- Save position to backtrack if needed
        local saved_pos = parser.pos
        local is_var_decl = false
        local is_mutable = false
        
        -- Check for optional mut keyword
        if parser:check("KEYWORD", "mut") then
            is_mutable = true
            parser:advance()
        end
        
        -- Check if this looks like a type declaration
        local Types = require("parser.types")
        if Types.is_type_start(parser) then
            local success, type_node = pcall(function() return Types.parse_type_with_map_shorthand(parser) end)
            if success and parser:check("IDENT") then
                local name_tok = parser:current()
                parser:advance()
                -- Check if this looks like end of variable declaration
                if Statements.is_var_decl_end(parser, name_tok) then
                    -- This is a variable declaration
                    is_var_decl = true
                    parser.pos = saved_pos  -- Reset to parse properly
                end
            end
        end
        
        if is_var_decl then
            -- Parse as variable declaration
            local mutable = false
            local start_tok = parser:current()  -- Save start token for line number
            if parser:match("KEYWORD", "mut") then
                mutable = true
            end
            local type_ = Types.parse_type_with_map_shorthand(parser)
            local name_tok = parser:expect("IDENT")
            local name = name_tok.value
            local init = nil
            if parser:match("EQUAL") then
                init = Expressions.parse_expression(parser)
            end
            parser:match("SEMICOLON")
            return { kind = "var_decl", name = name, type = type_, mutable = mutable, init = init, line = start_tok.line, col = start_tok.col }
        else
            -- Reset and parse as expression statement
            parser.pos = saved_pos
            local expr = Expressions.parse_expression(parser)
            parser:match("SEMICOLON")  -- semicolons are optional
            return { kind = "expr_stmt", expression = expr }
        end
    end
end

-- Helper to check if we're at the end of a variable declaration
-- This checks for patterns that indicate: Type name [= expr] or Type name
function Statements.is_var_decl_end(parser, name_tok)
    -- Variable declaration can be with or without initialization
    -- Check for = (with init) or semicolon/newline (without init)
    if parser:check("EQUAL") or parser:check("SEMICOLON") or parser:check("EOF") then
        return true
    end
    -- Check if next token is on a new line (implicit statement end)
    local curr = parser:current()
    if curr and curr.line > name_tok.line then
        return true
    end
    -- Check if next token is a keyword (likely start of new statement)
    if curr and curr.type == "KEYWORD" then
        return true
    end
    return false
end

function Statements.parse_if(parser)
    parser:expect("KEYWORD", "if")
    local Expressions = require("parser.expressions")
    local condition = Expressions.parse_expression(parser)
    local then_block = Statements.parse_block(parser)
    local else_block = nil
    if parser:match("KEYWORD", "elseif") then
        -- elseif - parse condition and treat as nested if statement
        local elseif_condition = Expressions.parse_expression(parser)
        local elseif_then_block = Statements.parse_block(parser)
        -- Create nested if statement for the elseif
        local nested_if = { kind = "if", condition = elseif_condition, then_block = elseif_then_block, else_block = nil }
        -- Check for more elseif or else
        if parser:check("KEYWORD", "elseif") or parser:check("KEYWORD", "else") then
            -- Recursively handle more elseif/else by parsing the rest
            nested_if.else_block = Statements.parse_if_continuation(parser)
        end
        else_block = { kind = "block", statements = { nested_if } }
    elseif parser:match("KEYWORD", "else") then
        if parser:check("KEYWORD", "if") then
            -- else if - parse as nested if statement (for backward compatibility)
            else_block = { kind = "block", statements = { Statements.parse_if(parser) } }
        else
            else_block = Statements.parse_block(parser)
        end
    end
    return { kind = "if", condition = condition, then_block = then_block, else_block = else_block }
end

function Statements.parse_if_continuation(parser)
    local Expressions = require("parser.expressions")
    -- Parse the continuation of an if statement (elseif/else part only)
    if parser:match("KEYWORD", "elseif") then
        local elseif_condition = Expressions.parse_expression(parser)
        local elseif_then_block = Statements.parse_block(parser)
        local nested_if = { kind = "if", condition = elseif_condition, then_block = elseif_then_block, else_block = nil }
        if parser:check("KEYWORD", "elseif") or parser:check("KEYWORD", "else") then
            nested_if.else_block = Statements.parse_if_continuation(parser)
        end
        return { kind = "block", statements = { nested_if } }
    elseif parser:match("KEYWORD", "else") then
        return Statements.parse_block(parser)
    end
    return nil
end

function Statements.parse_while(parser)
    parser:expect("KEYWORD", "while")
    local Expressions = require("parser.expressions")
    local condition = Expressions.parse_expression(parser)
    local body = Statements.parse_block(parser)
    return { kind = "while", condition = condition, body = body }
end

function Statements.parse_for(parser)
    parser:expect("KEYWORD", "for")
    local Expressions = require("parser.expressions")
    
    -- Parse index variable (can be _ or identifier)
    local index_name = nil
    local index_is_underscore = false
    if parser:check("IDENT") and parser:current().value == "_" then
        index_is_underscore = true
        parser:advance()
    else
        index_name = parser:expect("IDENT").value
    end
    
    parser:expect("COMMA")
    
    -- Parse item variable (can be _ or identifier, and can have mut)
    local item_mutable = parser:match("KEYWORD", "mut") ~= nil
    local item_name = nil
    local item_is_underscore = false
    if parser:check("IDENT") and parser:current().value == "_" then
        item_is_underscore = true
        parser:advance()
    else
        item_name = parser:expect("IDENT").value
    end
    
    parser:expect("KEYWORD", "in")
    
    -- Parse the collection expression
    local collection = Expressions.parse_expression(parser)
    
    local body = Statements.parse_block(parser)
    
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

function Statements.parse_repeat(parser)
    parser:expect("KEYWORD", "repeat")
    local Expressions = require("parser.expressions")
    
    -- Parse the count expression
    local count = Expressions.parse_expression(parser)
    
    -- Parse the body block
    local body = Statements.parse_block(parser)
    
    return {
        kind = "repeat",
        count = count,
        body = body
    }
end

return Statements
