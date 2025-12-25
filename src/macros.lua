-- Centralized handling of compiler macros
-- Provides parsing, validation, and code generation for all macros

local Macros = {}

-- ============================================================================
-- PARSER MACROS
-- ============================================================================

-- Parse top-level macros (#alloc)
-- These appear at module scope and configure the compiler
function Macros.parse_top_level(parser, macro_tok)
    local macro_name = macro_tok.value:upper()

    -- #alloc macro takes an interface name
    if macro_name == "ALLOC" then
        -- Accept IDENT tokens for interface name (e.g., cz.alloc)
        local interface_tokens = {}
        while parser:current() and
              not parser:check("EOF") and
              not parser:check("DIRECTIVE") and
              not (parser:check("KEYWORD", "struct") or parser:check("KEYWORD", "fn") or parser:check("KEYWORD", "iface")) do
            local tok = parser:current()
            if tok.type == "IDENT" or tok.type == "DOT" then
                table.insert(interface_tokens, tok.value)
                parser:advance()
            else
                break
            end
        end

        if #interface_tokens == 0 then
            error(string.format("expected interface name after #alloc at %d:%d",
                macro_tok.line, macro_tok.col))
        end

        local interface_name = table.concat(interface_tokens, "")

        return {
            kind = "allocator_macro",
            interface_name = interface_name,
            line = macro_tok.line,
            col = macro_tok.col
        }
    elseif macro_name == "INIT" then
        -- #init { ... }
        -- Runs initialization code when the module is imported
        local Statements = require("parser.statements")
        parser:expect("LBRACE")
        local statements = {}
        while not parser:check("RBRACE") do
            table.insert(statements, Statements.parse_statement(parser))
        end
        parser:expect("RBRACE")

        return {
            kind = "init_macro",
            statements = statements,
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

-- Process allocator macros (#alloc), and init macros (#init)
-- Called during codegen initialization
function Macros.process_top_level(codegen, ast)
    local alloc_macro_count = 0
    local alloc_macro_line = nil

    for _, item in ipairs(ast.items) do
        if item.kind == "allocator_macro" then
            alloc_macro_count = alloc_macro_count + 1
            if alloc_macro_count > 1 then
                error(string.format("duplicate #alloc macro at %d:%d (previous at %d:%d)",
                    item.line, item.col, alloc_macro_line.line, alloc_macro_line.col))
            end

            -- Check for useless #alloc cz.alloc directive (unspecified)
            if item.interface_name == "cz.alloc" then
                local Warnings = require("src.warnings")
                Warnings.emit(
                    codegen.source_file,
                    item.line,
                    Warnings.WarningType.USELESS_ALLOC_DIRECTIVE,
                    string.format("Unspecified allocator directive '#alloc cz.alloc' is useless. " ..
                                "Use '#alloc cz.alloc.default' or '#alloc cz.alloc.debug' explicitly, " ..
                                "or remove the directive to use the default allocator based on debug mode."),
                    codegen.source_path,
                    nil
                )
                -- Ignore this directive - let the default logic handle it
            else
                codegen.custom_allocator_interface = item.interface_name
            end
            alloc_macro_line = item
        elseif item.kind == "init_macro" then
            -- Collect init macro for execution during program initialization
            table.insert(codegen.init_macros, item)
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
        return "cz_debug_flag"
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
            return string.format("({ cz_debug_flag = %s; cz_debug_flag; })", arg_value)
        else
            -- #DEBUG() - read debug state (same as #DEBUG without parens)
            return "cz_debug_flag"
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

        -- Generate code that prints at runtime only if cz_debug_flag is true
        return string.format("if (cz_debug_flag) { fprintf(stderr, \"%s\" %s \"\\n\"); }",
                           runtime_prefix, runtime_message)
    else
        error(string.format("Unknown statement macro: %s at %d:%d", stmt.kind, stmt.line, stmt.col))
    end
end

return Macros
