-- Parser module for type parsing
-- Handles parsing of type annotations and type expressions

local Types = {}

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

Types.TYPE_KEYWORDS = TYPE_KEYWORDS

function Types.is_type_token(tok)
    if not tok then return false end
    if tok.type == "IDENT" then return true end
    if tok.type == "KEYWORD" and TYPE_KEYWORDS[tok.value] then
        return true
    end
    return false
end

-- Helper to check if current token could start a type
function Types.is_type_start(parser)
    local tok = parser:current()
    if not tok then return false end
    -- Check for container type keywords
    if tok.type == "KEYWORD" and (tok.value == "array" or tok.value == "slice" or tok.value == "map" or tok.value == "pair" or tok.value == "string") then
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

function Types.parse_type(parser)
    local tok = parser:current()
    
    -- Check for explicit container types: array<T>, slice<T>, map<K:V>
    if parser:check("KEYWORD", "array") then
        parser:advance()
        parser:expect("LT")
        local element_type = Types.parse_type(parser)
        parser:expect("GT")
        -- array<Type> is represented as a slice internally (dynamic size)
        local base_type = { kind = "slice", element_type = element_type }
        -- Check if this is a nullable type (array<T>?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        return base_type
    end
    
    if parser:check("KEYWORD", "slice") then
        parser:advance()
        parser:expect("LT")
        local element_type = Types.parse_type(parser)
        parser:expect("GT")
        local base_type = { kind = "slice", element_type = element_type }
        -- Check if this is a nullable type (slice<T>?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        return base_type
    end
    
    if parser:check("KEYWORD", "map") then
        parser:advance()
        parser:expect("LT")
        local key_type = Types.parse_type(parser)
        parser:expect("COLON")
        local value_type = Types.parse_type(parser)
        parser:expect("GT")
        local base_type = { kind = "map", key_type = key_type, value_type = value_type }
        -- Check if this is a nullable type (map<K:V>?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        return base_type
    end
    
    if parser:check("KEYWORD", "pair") then
        parser:advance()
        parser:expect("LT")
        local left_type = Types.parse_type(parser)
        parser:expect("COLON")
        local right_type = Types.parse_type(parser)
        parser:expect("GT")
        local base_type = { kind = "pair", left_type = left_type, right_type = right_type }
        -- Check if this is a nullable type (pair<T:T>?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        return base_type
    end
    
    if parser:check("KEYWORD", "string") then
        parser:advance()
        local base_type = { kind = "string" }
        -- Check if this is a nullable type (string?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        return base_type
    end
    
    if Types.is_type_token(tok) then
        parser:advance()
        local base_type = { kind = "named_type", name = tok.value }
        -- Check if this is a nullable type (Type?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        -- Check if this is an array type (Type[size]) or slice type (Type[])
        if parser:match("LBRACKET") then
            -- Check for slice type: Type[]
            if parser:check("RBRACKET") then
                parser:advance()
                return { kind = "slice", element_type = base_type }
            end
            -- Check for implicit size: Type[*]
            if parser:match("STAR") then
                parser:expect("RBRACKET")
                return { kind = "array", element_type = base_type, size = "*" }
            end
            -- Explicit size: Type[N]
            local size_tok = parser:expect("INT")
            local size = tonumber(size_tok.value)
            parser:expect("RBRACKET")
            return { kind = "array", element_type = base_type, size = size }
        end
        return base_type
    end
    
    local token_label = require("parser.utils").token_label
    error(string.format("expected type but found %s", token_label(tok)))
end

-- Parse type (no shortcuts, explicit keywords required)
function Types.parse_type_with_map_shorthand(parser)
    local tok = parser:current()
    
    -- Check for explicit container types: array<T>, slice<T>, map<K:V>, pair<T:T>
    if parser:check("KEYWORD", "array") or parser:check("KEYWORD", "slice") or parser:check("KEYWORD", "map") or parser:check("KEYWORD", "pair") or parser:check("KEYWORD", "string") then
        return Types.parse_type(parser)
    end
    
    if Types.is_type_token(tok) then
        parser:advance()
        local base_type = { kind = "named_type", name = tok.value }
        -- Check if this is a nullable type (Type?)
        if parser:match("QUESTION") then
            return { kind = "nullable", to = base_type }
        end
        -- Check if this is an array type (Type[size]) or slice type (Type[])
        if parser:match("LBRACKET") then
            -- Check for slice type: Type[]
            if parser:check("RBRACKET") then
                parser:advance()
                return { kind = "slice", element_type = base_type }
            end
            -- Check for implicit size: Type[*]
            if parser:match("STAR") then
                parser:expect("RBRACKET")
                return { kind = "array", element_type = base_type, size = "*" }
            end
            -- Explicit size: Type[N]
            local size_tok = parser:expect("INT")
            local size = tonumber(size_tok.value)
            parser:expect("RBRACKET")
            return { kind = "array", element_type = base_type, size = size }
        end
        return base_type
    end
    
    local token_label = require("parser.utils").token_label
    error(string.format("expected type but found %s", token_label(tok)))
end

return Types
