-- Parser module for declarations parsing
-- Handles parsing of top-level declarations (structs, enums, functions, modules, imports)

local Declarations = {}

-- Parse module declaration: module foo.bar
function Declarations.parse_module_declaration(parser)
    parser:expect("KEYWORD", "module")
    local parts = {}
    table.insert(parts, parser:expect("IDENT").value)
    
    while parser:match("DOT") do
        table.insert(parts, parser:expect("IDENT").value)
    end
    
    return {
        kind = "module",
        path = parts
    }
end

-- Parse import statement: import foo.bar [as baz] OR import C : header.h, ...
function Declarations.parse_import(parser)
    local start_tok = parser:expect("KEYWORD", "import")
    local parts = {}
    table.insert(parts, parser:expect("IDENT").value)
    
    -- Check if this is a C import: import C : header.h, ...
    if parts[1] == "C" and parser:match("COLON") then
        local headers = {}
        -- Parse header files (identifiers or strings with .h extension)
        repeat
            local header_tok = parser:current()
            if header_tok.type == "STRING" then
                table.insert(headers, header_tok.value)
                parser:advance()
            elseif header_tok.type == "IDENT" or header_tok.type == "KEYWORD" then
                -- Parse identifier/keyword with dots (e.g., stdio.h, string.h)
                -- We allow keywords here for header names like string.h
                local header_parts = { header_tok.value }
                parser:advance()
                while parser:match("DOT") do
                    local part_tok = parser:current()
                    if part_tok.type == "IDENT" or part_tok.type == "KEYWORD" then
                        table.insert(header_parts, part_tok.value)
                        parser:advance()
                    else
                        error("Expected identifier in header file name")
                    end
                end
                table.insert(headers, table.concat(header_parts, "."))
            else
                error("Expected header file name after 'import C :'")
            end
        until not parser:match("COMMA")
        
        return {
            kind = "c_import",
            headers = headers,
            line = start_tok.line,
            col = start_tok.col
        }
    end
    
    -- Regular module import: import foo.bar [as baz]
    while parser:match("DOT") do
        table.insert(parts, parser:expect("IDENT").value)
    end
    
    local alias = nil
    if parser:match("KEYWORD", "as") then
        alias = parser:expect("IDENT").value
    end
    
    return {
        kind = "import",
        path = parts,
        alias = alias,
        line = start_tok.line,
        col = start_tok.col
    }
end

function Declarations.parse_struct(parser)
    local Types = require("parser.types")
    local struct_tok = parser:expect("KEYWORD", "struct")
    local name = parser:expect("IDENT").value
    parser:expect("LBRACE")
    local fields = {}
    while not parser:check("RBRACE") do
        -- Check for prv modifier on fields
        local is_private = false
        if parser:check("KEYWORD", "prv") then
            parser:advance()
            is_private = true
        end
        
        -- No mut keyword on fields - mutability comes from variable
        local field_type = Types.parse_type(parser)
        local field_name = parser:expect("IDENT").value
        parser:match("SEMICOLON")  -- semicolons are optional
        
        -- If the field type is the same as the struct name, make it a pointer
        -- This handles self-referential types like: struct Node { Node next }
        if field_type.kind == "named_type" and field_type.name == name then
            field_type = { kind = "nullable", to = field_type }
        end
        
        table.insert(fields, { name = field_name, type = field_type, is_private = is_private })
        
        -- Support optional comma between fields
        parser:match("COMMA")
    end
    parser:expect("RBRACE")
    return { kind = "struct", name = name, fields = fields, line = struct_tok.line, col = struct_tok.col }
end

function Declarations.parse_enum(parser)
    local start_tok = parser:expect("KEYWORD", "enum")
    local name = parser:expect("IDENT").value
    parser:expect("LBRACE")
    local values = {}
    if not parser:check("RBRACE") then
        repeat
            local value_tok = parser:expect("IDENT")
            table.insert(values, { name = value_tok.value, line = value_tok.line, col = value_tok.col })
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
    return { kind = "enum", name = name, values = values, line = start_tok.line }
end

function Declarations.parse_function(parser)
    local Types = require("parser.types")
    local Statements = require("parser.statements")
    local fn_tok = parser:expect("KEYWORD", "fn")
    
    -- Check for #inline or #noinline directive
    local inline_directive = nil
    if parser:check("DIRECTIVE") then
        local directive_tok = parser:current()
        local directive_name = directive_tok.value:upper()
        if directive_name == "INLINE" or directive_name == "NOINLINE" then
            inline_directive = directive_name:lower()
            parser:advance()
        end
    end
    
    -- Parse generic types if present: <u8:u16:u32>
    local generic_types = nil
    if parser:match("LT") then
        generic_types = {}
        local first_type_kind = nil
        
        repeat
            local type_tok = parser:expect("KEYWORD")
            local type_name = type_tok.value
            
            -- Validate: only allow primitive types
            local primitive_types = {
                u8 = "unsigned", u16 = "unsigned", u32 = "unsigned", u64 = "unsigned",
                i8 = "signed", i16 = "signed", i32 = "signed", i64 = "signed",
                f32 = "float", f64 = "float"
            }
            
            local type_kind = primitive_types[type_name]
            if not type_kind then
                error(string.format("Generic type parameter must be a primitive type (u8/u16/u32/u64/i8/i16/i32/i64/f32/f64), got '%s'", type_name))
            end
            
            -- Validate: all types must be the same kind
            if not first_type_kind then
                first_type_kind = type_kind
            elseif first_type_kind ~= type_kind then
                error(string.format("All generic types must be of the same kind (all unsigned, all signed, or all float), got mix of '%s' and '%s'", first_type_kind, type_kind))
            end
            
            table.insert(generic_types, type_name)
        until not parser:match("COLON")
        parser:expect("GT")
        
        -- Validate: at least 2 types required
        if #generic_types < 2 then
            error("Generic type list must contain at least 2 types")
        end
    end
    
    local receiver_type = nil
    local is_static_method = false
    local name = parser:expect("IDENT").value
    
    -- Helper to parse method name (allows 'new' and 'free' as special method names)
    local function parse_method_name(parser)
        local tok = parser:current()
        if tok and tok.type == "KEYWORD" and (tok.value == "new" or tok.value == "free") then
            return parser:advance().value  -- Accept keyword as method name
        else
            return parser:expect("IDENT").value  -- Normal identifier
        end
    end
    
    -- Check if this is a method definition
    -- Type:method for instance methods (implicit mutable self)
    -- Type.method for static methods (no implicit self)
    if parser:match("COLON") then
        receiver_type = name  -- The first identifier is the type
        name = parse_method_name(parser)
        is_static_method = false  -- Instance method with implicit self
    elseif parser:match("DOT") then
        receiver_type = name  -- The first identifier is the type
        name = parse_method_name(parser)
        is_static_method = true  -- Static method, no implicit self
    end
    
    parser:expect("LPAREN")
    local params = {}
    
    -- For instance methods (Type:method), add implicit mutable self parameter
    if receiver_type and not is_static_method then
        local self_type = { kind = "named_type", name = receiver_type }
        -- In explicit pointer model, self is a pointer to the type
        local self_param_type = { kind = "nullable", to = self_type }
        table.insert(params, { name = "self", type = self_param_type, mutable = true })
    end
    
    if not parser:check("RPAREN") then
        repeat
            local is_mut = parser:match("KEYWORD", "mut") ~= nil
            local param_type = Types.parse_type_with_map_shorthand(parser)
            -- Check for varargs syntax (Type...)
            local is_varargs = parser:match("ELLIPSIS") ~= nil
            if is_varargs then
                -- Convert type to varargs type
                param_type = { kind = "varargs", element_type = param_type }
            end
            -- In explicit pointer model, mut is just a mutability flag, not an implicit pointer
            -- The user must use Type* for pointer parameters
            local param_name = parser:expect("IDENT").value
            local default_value = nil
            -- Check for default value (not allowed for varargs)
            if parser:match("EQUAL") then
                if is_varargs then
                    error(string.format("varargs parameter '%s' cannot have a default value", param_name))
                end
                local Expressions = require("parser.expressions")
                default_value = Expressions.parse_expression(parser)
            end
            table.insert(params, { name = param_name, type = param_type, mutable = is_mut, default_value = default_value })
            -- Varargs must be the last parameter
            if is_varargs and not parser:check("RPAREN") then
                error(string.format("varargs parameter '%s' must be the last parameter", param_name))
            end
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
    -- Return type is optional - if not present, defaults to void
    local return_type
    if parser:check("LBRACE") then
        -- No explicit return type, default to void
        return_type = { kind = "named_type", name = "void" }
    else
        return_type = Types.parse_type(parser)
    end
    local body = Statements.parse_block(parser)
    return { 
        kind = "function", 
        name = name, 
        receiver_type = receiver_type, 
        params = params, 
        return_type = return_type, 
        body = body, 
        inline_directive = inline_directive, 
        generic_types = generic_types,
        line = fn_tok.line, 
        col = fn_tok.col 
    }
end

return Declarations
