-- Centralized handling of compiler macros
-- Provides parsing, validation, and code generation for all macros

local Macros = {}

-- ============================================================================
-- PARSER MACROS
-- ============================================================================

-- Parse top-level macros (#malloc, #free, #alias)
-- These appear at module scope and configure the compiler
function Macros.parse_top_level(parser, macro_tok)
    local macro_name = macro_tok.value:upper()
    
    -- #malloc and #free macros take a function name argument
    if macro_name == "MALLOC" or macro_name == "FREE" then
        -- Accept both IDENT and KEYWORD tokens (e.g., "malloc" and "free" are keywords)
        local func_name_tok = parser:current()
        if not func_name_tok or (func_name_tok.type ~= "IDENT" and func_name_tok.type ~= "KEYWORD") then
            error(string.format("expected function name after #%s but found %s", 
                macro_name:lower(), 
                parser.token_label and parser.token_label(func_name_tok) or tostring(func_name_tok)))
        end
        parser:advance()
        
        return { 
            kind = "allocator_macro", 
            macro_type = macro_name:lower(),
            function_name = func_name_tok.value,
            line = macro_tok.line,
            col = macro_tok.col
        }
    elseif macro_name == "ALIAS" then
        -- #alias mytype existing_type
        -- mytype is one word, existing_type can be multiple tokens (rest of the line)
        local alias_name_tok = parser:expect("IDENT")
        local alias_name = alias_name_tok.value
        
        -- Collect all remaining tokens until end of line/statement as the target type string
        local target_type_tokens = {}
        
        -- Keep reading tokens until we hit EOF, a macro, struct, or fn keyword
        while parser:current() and 
              not parser:check("EOF") and 
              not parser:check("DIRECTIVE") and
              not (parser:check("KEYWORD", "struct") or parser:check("KEYWORD", "fn")) do
            local tok = parser:current()
            table.insert(target_type_tokens, tok.value)
            parser:advance()
        end
        
        if #target_type_tokens == 0 then
            error(string.format("#alias requires a target type after '%s'", alias_name))
        end
        
        local target_type_str = table.concat(target_type_tokens, " ")
        
        return {
            kind = "alias_macro",
            alias_name = alias_name,
            target_type_str = target_type_str,
            line = macro_tok.line,
            col = macro_tok.col
        }
    else
        error(string.format("unknown top-level macro: #%s at %d:%d", 
            macro_tok.value, macro_tok.line, macro_tok.col))
    end
end

-- Parse statement-level macros (#assert, #log, #TODO, #FIXME)
-- These appear as statements and execute actions
function Macros.parse_statement(parser, macro_tok)
    local macro_name = macro_tok.value:upper()
    
    if macro_name == "ASSERT" then
        -- #assert(condition)
        parser:expect("LPAREN")
        local condition = parser:parse_expression()
        parser:expect("RPAREN")
        
        return {
            kind = "assert_stmt",
            condition = condition,
            line = macro_tok.line,
            col = macro_tok.col
        }
    elseif macro_name == "LOG" then
        -- #log("message")
        parser:expect("LPAREN")
        local message = parser:parse_expression()
        parser:expect("RPAREN")
        
        return {
            kind = "log_stmt",
            message = message,
            line = macro_tok.line,
            col = macro_tok.col
        }
    elseif macro_name == "TODO" or macro_name == "FIXME" then
        -- #TODO(message) or #FIXME(message)
        -- Message is optional, default is "TODO" or "FIXME"
        local message = nil
        if parser:check("LPAREN") then
            parser:advance()  -- consume (
            if not parser:check("RPAREN") then
                message = parser:parse_expression()
            end
            parser:expect("RPAREN")
        end
        
        return {
            kind = macro_name:lower() .. "_stmt",
            message = message,
            line = macro_tok.line,
            col = macro_tok.col
        }
    else
        error(string.format("unknown statement macro: #%s at %d:%d", 
            macro_tok.value, macro_tok.line, macro_tok.col))
    end
end

-- Parse expression-level macros (#FILE, #FUNCTION, #DEBUG)
-- These appear in expressions and get replaced with values
-- #DEBUG can also be a function call: #DEBUG() or #DEBUG(true/false)
function Macros.parse_expression(parser, macro_tok)
    local macro_name = macro_tok.value:upper()
    
    -- Check if #DEBUG is followed by parentheses (function call)
    if macro_name == "DEBUG" and parser:check("LPAREN") then
        parser:advance()  -- consume (
        
        -- Check if there's an argument
        local arg = nil
        if not parser:check("RPAREN") then
            -- Parse the boolean argument expression
            arg = parser:parse_expression()
        end
        
        parser:expect("RPAREN")
        
        return {
            kind = "macro_call",
            name = macro_tok.value,
            arg = arg,
            line = macro_tok.line,
            col = macro_tok.col
        }
    end
    
    -- Simple macros like #FILE, #FUNCTION, #DEBUG (without parens)
    return { 
        kind = "macro", 
        name = macro_tok.value, 
        line = macro_tok.line, 
        col = macro_tok.col 
    }
end

-- ============================================================================
-- CODEGEN MACROS
-- ============================================================================

-- Process allocator macros (#malloc, #free) and alias macros
-- Called during codegen initialization
function Macros.process_top_level(codegen, ast)
    local malloc_macro_count = 0
    local free_macro_count = 0
    local malloc_macro_line = nil
    local free_macro_line = nil
    
    for _, item in ipairs(ast.items) do
        if item.kind == "allocator_macro" then
            if item.macro_type == "malloc" then
                malloc_macro_count = malloc_macro_count + 1
                if malloc_macro_count > 1 then
                    error(string.format("duplicate #malloc macro at %d:%d (previous at %d:%d)", 
                        item.line, item.col, malloc_macro_line.line, malloc_macro_line.col))
                end
                codegen.custom_malloc = item.function_name
                malloc_macro_line = item
            elseif item.macro_type == "free" then
                free_macro_count = free_macro_count + 1
                if free_macro_count > 1 then
                    error(string.format("duplicate #free macro at %d:%d (previous at %d:%d)", 
                        item.line, item.col, free_macro_line.line, free_macro_line.col))
                end
                codegen.custom_free = item.function_name
                free_macro_line = item
            end
        elseif item.kind == "alias_macro" then
            -- Store type alias for replacement
            if codegen.type_aliases[item.alias_name] then
                error(string.format("duplicate #alias for '%s' at %d:%d", 
                    item.alias_name, item.line, item.col))
            end
            codegen.type_aliases[item.alias_name] = item.target_type_str
        end
    end
end

-- Generate code for expression macros (#FILE, #FUNCTION, #DEBUG)
-- Also handles #DEBUG() function calls
function Macros.generate_expression(expr, ctx)
    local macro_name = expr.name:upper()
    
    if macro_name == "FILE" then
        return string.format("\"%s\"", ctx.source_file)
    elseif macro_name == "FUNCTION" then
        local func_name = ctx.current_function or "unknown"
        return string.format("\"%s\"", func_name)
    elseif macro_name == "DEBUG" then
        -- #DEBUG without parens - read current state
        return "czar_debug_flag"
    else
        error(string.format("Unknown macro: #%s at %d:%d", expr.name, expr.line, expr.col))
    end
end

-- Generate code for macro calls (#DEBUG(true/false))
function Macros.generate_call(expr, ctx)
    local macro_name = expr.name:upper()
    
    if macro_name == "DEBUG" then
        if expr.arg then
            -- #DEBUG(bool) - set debug state and return the new state
            -- This is a compile-time operation that affects subsequent #DEBUG reads
            -- We need to evaluate the argument and update ctx.debug
            -- For now, we'll generate a statement expression that returns the value
            local Expressions = require("codegen.expressions")
            local arg_value = Expressions.gen_expr(expr.arg)
            -- Generate code that sets a runtime flag and returns the new value
            return string.format("({ czar_debug_flag = %s; czar_debug_flag; })", arg_value)
        else
            -- #DEBUG() - read debug state (same as #DEBUG without parens)
            return "czar_debug_flag"
        end
    else
        error(string.format("Unknown macro call: #%s() at %d:%d", expr.name, expr.line, expr.col))
    end
end

-- Generate code for statement macros (#assert, #log, #TODO, #FIXME)
function Macros.generate_statement(stmt, ctx)
    if stmt.kind == "assert_stmt" then
        -- #assert(condition) -> if (!(condition)) { abort(); }
        local Expressions = require("codegen.expressions")
        local condition_code = Expressions.gen_expr(stmt.condition)
        return string.format("if (!(%s)) { abort(); }", condition_code)
    elseif stmt.kind == "log_stmt" then
        -- #log("message") -> fprintf(stderr, "LOG in function() at filename:linenumber message\n")
        local Expressions = require("codegen.expressions")
        local message_code = Expressions.gen_expr(stmt.message)
        -- Escape % characters in filename to avoid format string issues
        local filename = ctx.source_file:gsub("%%", "%%%%")
        local line = stmt.line
        
        -- Build standard format: "LOG in function_name() at filename:linenumber "
        local prefix = "LOG "
        if ctx.current_function then
            prefix = string.format("LOG in %s() ", ctx.current_function)
        end
        prefix = prefix .. string.format("at %s:%d ", filename, line)
        
        return string.format("fprintf(stderr, \"%s\" %s \"\\n\")", prefix, message_code)
    elseif stmt.kind == "todo_stmt" or stmt.kind == "fixme_stmt" then
        -- #TODO(message) or #FIXME(message)
        -- Print to stderr during compilation
        local Expressions = require("codegen.expressions")
        local macro_type = stmt.kind == "todo_stmt" and "TODO" or "FIXME"
        local filename = ctx.source_file:gsub("%%", "%%%%")
        local line = stmt.line
        local col = stmt.col
        
        -- Determine message to display
        local display_message = macro_type  -- default message
        if stmt.message then
            -- If message is a string literal, extract it for compile-time display
            if stmt.message.kind == "string" and stmt.message.value then
                display_message = stmt.message.value
            else
                -- For non-literal expressions, use the default
                display_message = macro_type
            end
        end
        
        -- Build standard format for compile-time: "TYPE in function_name() at filename:linenumber message"
        local compile_prefix = macro_type .. " "
        if ctx.current_function then
            compile_prefix = string.format("%s in %s() ", macro_type, ctx.current_function)
        end
        compile_prefix = compile_prefix .. string.format("at %s:%d ", filename, line)
        
        -- Print to stderr during compilation
        io.stderr:write(compile_prefix .. display_message .. "\n")
        
        -- Generate runtime code that prints if #DEBUG is enabled
        local runtime_message
        if stmt.message then
            runtime_message = Expressions.gen_expr(stmt.message)
        else
            runtime_message = string.format("\"%s\"", macro_type)
        end
        
        -- Build standard format for runtime: "TYPE in function_name() at filename:linenumber "
        local runtime_prefix = macro_type .. " "
        if ctx.current_function then
            runtime_prefix = string.format("%s in %s() ", macro_type, ctx.current_function)
        end
        runtime_prefix = runtime_prefix .. string.format("at %s:%d ", filename, line)
        
        -- Generate code that prints at runtime only if czar_debug_flag is true
        return string.format("if (czar_debug_flag) { fprintf(stderr, \"%s\" %s \"\\n\"); }", 
                           runtime_prefix, runtime_message)
    else
        error(string.format("Unknown statement macro: %s at %d:%d", stmt.kind, stmt.line, stmt.col))
    end
end

return Macros
