-- Centralized handling of compiler directives/macros
-- Provides parsing, validation, and code generation for all directives

local Directives = {}

-- ============================================================================
-- PARSER DIRECTIVES
-- ============================================================================

-- Parse top-level directives (#malloc, #free, #alias)
-- These appear at module scope and configure the compiler
function Directives.parse_top_level(parser, directive_tok)
    local directive_name = directive_tok.value:upper()
    
    -- #malloc and #free directives take a function name argument
    if directive_name == "MALLOC" or directive_name == "FREE" then
        -- Accept both IDENT and KEYWORD tokens (e.g., "malloc" and "free" are keywords)
        local func_name_tok = parser:current()
        if not func_name_tok or (func_name_tok.type ~= "IDENT" and func_name_tok.type ~= "KEYWORD") then
            error(string.format("expected function name after #%s but found %s", 
                directive_name:lower(), 
                parser.token_label and parser.token_label(func_name_tok) or tostring(func_name_tok)))
        end
        parser:advance()
        
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
        local alias_name_tok = parser:expect("IDENT")
        local alias_name = alias_name_tok.value
        
        -- Collect all remaining tokens until end of line/statement as the target type string
        local target_type_tokens = {}
        
        -- Keep reading tokens until we hit EOF, a directive, struct, or fn keyword
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
            kind = "alias_directive",
            alias_name = alias_name,
            target_type_str = target_type_str,
            line = directive_tok.line,
            col = directive_tok.col
        }
    else
        error(string.format("unknown top-level directive: #%s at %d:%d", 
            directive_tok.value, directive_tok.line, directive_tok.col))
    end
end

-- Parse expression-level directives (#FILE, #FUNCTION, #DEBUG, #cast)
-- These appear in expressions and get replaced with values
function Directives.parse_expression(parser, directive_tok)
    local directive_name = directive_tok.value:upper()
    
    -- Handle #cast<Type>(value, fallback) directive
    if directive_name == "CAST" then
        parser:expect("LT")
        local target_type = parser:parse_type()
        parser:expect("GT")
        parser:expect("LPAREN")
        local value_expr = parser:parse_expression()
        parser:expect("COMMA")
        local fallback_expr = parser:parse_expression()
        parser:expect("RPAREN")
        return { 
            kind = "safe_cast", 
            target_type = target_type, 
            value = value_expr, 
            fallback = fallback_expr,
            line = directive_tok.line, 
            col = directive_tok.col 
        }
    else
        -- Simple directives like #FILE, #FUNCTION, #DEBUG
        return { 
            kind = "directive", 
            name = directive_tok.value, 
            line = directive_tok.line, 
            col = directive_tok.col 
        }
    end
end

-- ============================================================================
-- CODEGEN DIRECTIVES
-- ============================================================================

-- Process allocator directives (#malloc, #free) and alias directives
-- Called during codegen initialization
function Directives.process_top_level(codegen, ast)
    local malloc_directive_count = 0
    local free_directive_count = 0
    local malloc_directive_line = nil
    local free_directive_line = nil
    
    for _, item in ipairs(ast.items) do
        if item.kind == "allocator_directive" then
            if item.directive_type == "malloc" then
                malloc_directive_count = malloc_directive_count + 1
                if malloc_directive_count > 1 then
                    error(string.format("duplicate #malloc directive at %d:%d (previous at %d:%d)", 
                        item.line, item.col, malloc_directive_line.line, malloc_directive_line.col))
                end
                codegen.custom_malloc = item.function_name
                malloc_directive_line = item
            elseif item.directive_type == "free" then
                free_directive_count = free_directive_count + 1
                if free_directive_count > 1 then
                    error(string.format("duplicate #free directive at %d:%d (previous at %d:%d)", 
                        item.line, item.col, free_directive_line.line, free_directive_line.col))
                end
                codegen.custom_free = item.function_name
                free_directive_line = item
            end
        elseif item.kind == "alias_directive" then
            -- Store type alias for replacement
            if codegen.type_aliases[item.alias_name] then
                error(string.format("duplicate #alias for '%s' at %d:%d", 
                    item.alias_name, item.line, item.col))
            end
            codegen.type_aliases[item.alias_name] = item.target_type_str
        end
    end
end

-- Generate code for expression directives (#FILE, #FUNCTION, #DEBUG)
function Directives.generate_expression(expr, ctx)
    local directive_name = expr.name:upper()
    
    if directive_name == "FILE" then
        return string.format("\"%s\"", ctx.source_file)
    elseif directive_name == "FUNCTION" then
        local func_name = ctx.current_function or "unknown"
        return string.format("\"%s\"", func_name)
    elseif directive_name == "DEBUG" then
        return ctx.debug and "true" or "false"
    else
        error(string.format("Unknown directive: #%s at %d:%d", expr.name, expr.line, expr.col))
    end
end

-- Generate code for #cast<Type>(value, fallback) directive
function Directives.generate_safe_cast(expr, ctx, gen_expr_func, c_type_func)
    -- #cast<Type>(value, fallback) -> safe cast with fallback
    -- For now, just performs regular cast (no runtime checking)
    -- Future: add runtime validation and return fallback on failure
    local target_type_str = c_type_func(expr.target_type)
    local value_str = gen_expr_func(expr.value)
    local fallback_str = gen_expr_func(expr.fallback)
    
    -- Handle pointer casting
    if expr.target_type.kind == "pointer" then
        target_type_str = c_type_func(expr.target_type.to) .. "*"
    end

    -- For now, just cast (ignoring fallback)
    -- TODO: Add runtime check: if cast valid, return cast value, else return fallback
    return string.format("((%s)%s)", target_type_str, value_str)
end

-- ============================================================================
-- TYPE CHECKER DIRECTIVES
-- ============================================================================

-- Type check #cast<Type>(value, fallback) directive
function Directives.typecheck_safe_cast(expr, typechecker, infer_type_func, types_compatible_func, type_to_string_func)
    local target_type = expr.target_type
    infer_type_func(typechecker, expr.value)
    local fallback_type = infer_type_func(typechecker, expr.fallback)
    
    -- Verify fallback type matches target type
    if not types_compatible_func(target_type, fallback_type, typechecker) then
        error(string.format("#cast fallback type mismatch: expected %s, got %s at %d:%d",
            type_to_string_func(target_type),
            type_to_string_func(fallback_type),
            expr.line, expr.col))
    end
    
    expr.inferred_type = target_type
    return target_type
end

return Directives
