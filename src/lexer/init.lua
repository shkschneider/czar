-- Simple lexer for the Czar language.
-- Supports tokenizing the minimal v0 surface: structs, functions, blocks, pointers,
-- identifiers, integers, and comments.

local Lexer = {}
Lexer.__index = Lexer

local keywords = {
    ["struct"] = true,
    ["enum"] = true,
    ["iface"] = true,
    ["fn"] = true,
    ["return"] = true,
    ["mut"] = true,
    ["if"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["while"] = true,
    ["for"] = true,
    ["in"] = true,
    ["repeat"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["true"] = true,
    ["false"] = true,
    ["null"] = true,
    ["clone"] = true,
    ["new"] = true,
    ["free"] = true,
    ["is"] = true,
    ["as"] = true,
    ["type"] = true,
    ["sizeof"] = true,
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
    ["and"] = true,
    ["or"] = true,
    ["not"] = true,
    ["array"] = true,
    ["slice"] = true,
    ["map"] = true,
    ["pair"] = true,
    ["string"] = true,
    ["pub"] = true,
    ["prv"] = true,
}

local simple_tokens = {
    ["("] = "LPAREN",
    [")"] = "RPAREN",
    ["{"] = "LBRACE",
    ["}"] = "RBRACE",
    ["["] = "LBRACKET",
    ["]"] = "RBRACKET",
    [","] = "COMMA",
    [";"] = "SEMICOLON", -- only for inline
    [":"] = "COLON",
    ["."] = "DOT",
    ["+"] = "PLUS",
    ["-"] = "MINUS",
    ["*"] = "STAR",
    ["/"] = "SLASH",
    ["%"] = "PERCENT",
    ["&"] = "AMPERSAND",
    ["!"] = "BANG",
    ["?"] = "QUESTION",
    ["<"] = "LT",
    [">"] = "GT",
    ["="] = "EQUAL",
    ["~"] = "TILDE",
    ["|"] = "PIPE",
    ["^"] = "CARET",
    -- := declares = assigns == checks
}

local compound_tokens = {
    ["=="] = "EQ",
    ["!="] = "NEQ",
    ["<="] = "LTE",
    [">="] = "GTE",
    ["+="] = "PLUSEQUAL",
    ["-="] = "MINUSEQUAL",
    ["*="] = "STAREQUAL",
    ["/="] = "SLASHEQUAL",
    ["%="] = "PERCENTEQUAL",
    ["<<"] = "SHL",
    [">>"] = "SHR",
    ["++"] = "INCREMENT",
    ["--"] = "DECREMENT",
    ["&&"] = "AND",
    ["||"] = "OR",
    ["!!"] = "BANGBANG",
    ["??"] = "FALLBACK",
}

local function is_alpha(c)
    return c:match("[A-Za-z_]") ~= nil
end

local function is_digit(c)
    return c:match("%d") ~= nil
end

local function is_alnum(c)
    return is_alpha(c) or is_digit(c)
end

local function new_token(kind, value, line, col)
    return { type = kind, value = value, line = line, col = col }
end

function Lexer.new(input)
    local state = {
        input = input,
        pos = 1,
        line = 1,
        col = 1,
        tokens = {},
        length = #input,
    }
    return setmetatable(state, Lexer)
end

function Lexer:peek(offset)
    offset = offset or 0
    local idx = self.pos + offset
    if idx > self.length then return nil end
    return self.input:sub(idx, idx)
end

function Lexer:advance()
    local ch = self:peek()
    if not ch then return nil end
    self.pos = self.pos + 1
    if ch == "\n" then
        self.line = self.line + 1
        self.col = 1
    else
        self.col = self.col + 1
    end
    return ch
end

function Lexer:add_token(kind, value, line, col)
    table.insert(self.tokens, new_token(kind, value, line, col))
end

function Lexer:skip_whitespace()
    while true do
        local ch = self:peek()
        if not ch then break end
        if ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' then
            self:advance()
        else
            break
        end
    end
end

function Lexer:skip_comment()
    if self:peek() == '/' then
        if self:peek(1) == '/' then
            while self:peek() and self:peek() ~= '\n' do
                self:advance()
            end
            return true
        elseif self:peek(1) == '*' then
            self:advance(); self:advance() -- consume /*
            while self:peek() do
                if self:peek() == '*' and self:peek(1) == '/' then
                    self:advance(); self:advance()
                    break
                else
                    self:advance()
                end
            end
            return true
        end
    end
    return false
end

function Lexer:lex_number()
    local start_col = self.col
    local value = ""
    local is_float = false
    
    -- Read integer part
    while self:peek() and (is_digit(self:peek()) or self:peek() == "_") do
        local ch = self:advance()
        -- Skip underscores - they're just for readability
        if ch ~= "_" then
            value = value .. ch
        end
    end
    
    -- Check for decimal point followed by a digit
    if self:peek() == "." and self:peek(1) and is_digit(self:peek(1)) then
        is_float = true
        value = value .. self:advance()  -- Add the '.'
        
        -- Read fractional part
        while self:peek() and (is_digit(self:peek()) or self:peek() == "_") do
            local ch = self:advance()
            -- Skip underscores - they're just for readability
            if ch ~= "_" then
                value = value .. ch
            end
        end
    end
    
    -- Check for scientific notation (e or E)
    if self:peek() and (self:peek() == "e" or self:peek() == "E") then
        is_float = true
        value = value .. self:advance()  -- Add 'e' or 'E'
        
        -- Check for optional sign
        if self:peek() and (self:peek() == "+" or self:peek() == "-") then
            value = value .. self:advance()
        end
        
        -- Read exponent - at least one digit is required
        local exponent_start = #value
        while self:peek() and (is_digit(self:peek()) or self:peek() == "_") do
            local ch = self:advance()
            if ch ~= "_" then
                value = value .. ch
            end
        end
        
        -- Validate that at least one digit was found after 'e' or sign
        if #value == exponent_start then
            error(string.format("invalid float literal: exponent requires at least one digit at %d:%d", self.line, start_col))
        end
    end
    
    if is_float then
        self:add_token("FLOAT", value, self.line, start_col)
    else
        self:add_token("INT", value, self.line, start_col)
    end
end

function Lexer:lex_identifier()
    local start_col = self.col
    local value = ""
    while self:peek() and is_alnum(self:peek()) do
        value = value .. self:advance()
    end
    local kind = keywords[value] and "KEYWORD" or "IDENT"
    self:add_token(kind, value, self.line, start_col)
end

function Lexer:lex_directive()
    local start_col = self.col
    self:advance() -- consume '#'
    local value = ""
    while self:peek() and is_alnum(self:peek()) do
        value = value .. self:advance()
    end
    if value == "" then
        error(string.format("expected directive name after '#' at %d:%d", self.line, start_col))
    end
    self:add_token("DIRECTIVE", value, self.line, start_col)
end

function Lexer:lex_string()
    local start_col = self.col
    local start_line = self.line
    self:advance() -- opening quote
    
    -- Parse string and collect parts and interpolations
    local parts = {}  -- String literal parts
    local interp = {}  -- Interpolation expressions
    local current_part = ""
    local has_interpolation = false
    
    while true do
        local ch = self:peek()
        if not ch then
            error(string.format("unterminated string at %d:%d", start_line, start_col))
        end
        
        if ch == '"' then
            self:advance()
            -- Add final part
            table.insert(parts, current_part)
            break
        elseif ch == '\\' then
            -- Handle escape sequences
            self:advance()
            local next_ch = self:peek()
            if not next_ch then
                error(string.format("unterminated escape at %d:%d", self.line, self.col))
            end
            if next_ch == '{' then
                -- \{ -> literal {
                current_part = current_part .. '{'
                self:advance()
            elseif next_ch == '}' then
                -- \} -> literal }
                current_part = current_part .. '}'
                self:advance()
            else
                -- Other escape sequences: preserve them as-is for C
                current_part = current_part .. '\\' .. next_ch
                self:advance()
            end
        elseif ch == '{' then
            -- Start of interpolation
            has_interpolation = true
            table.insert(parts, current_part)
            current_part = ""
            
            self:advance() -- consume {
            
            -- Read the expression inside {}
            local expr = ""
            local depth = 1
            while true do
                local inner_ch = self:peek()
                if not inner_ch then
                    error(string.format("unterminated interpolation at %d:%d", self.line, self.col))
                end
                
                if inner_ch == '{' then
                    depth = depth + 1
                    expr = expr .. inner_ch
                    self:advance()
                elseif inner_ch == '}' then
                    depth = depth - 1
                    if depth == 0 then
                        self:advance() -- consume }
                        break
                    else
                        expr = expr .. inner_ch
                        self:advance()
                    end
                else
                    expr = expr .. inner_ch
                    self:advance()
                end
            end
            
            table.insert(interp, expr)
        else
            current_part = current_part .. ch
            self:advance()
        end
    end
    
    -- Create token with interpolation metadata
    if has_interpolation then
        self:add_token("INTERPOLATED_STRING", { parts = parts, interp = interp }, start_line, start_col)
    else
        -- Regular string without interpolation
        self:add_token("STRING", parts[1] or "", start_line, start_col)
    end
end

function Lexer:next_token()
    self:skip_whitespace()
    while self:skip_comment() do
        self:skip_whitespace()
    end

    local ch = self:peek()
    if not ch then return nil end

    -- Check for ellipsis (...) before checking for compound operators
    if ch == "." and self:peek(1) == "." and self:peek(2) == "." then
        local line, col = self.line, self.col
        self:advance(); self:advance(); self:advance()
        self:add_token("ELLIPSIS", "...", line, col)
        return true
    end

    -- compound operators
    local pair = ch .. (self:peek(1) or "")
    local compound = compound_tokens[pair]
    if compound then
        local line, col = self.line, self.col
        self:advance(); self:advance()
        self:add_token(compound, pair, line, col)
        return true
    end

    -- single character tokens
    local simple = simple_tokens[ch]
    if simple then
        local line, col = self.line, self.col
        self:advance()
        self:add_token(simple, ch, line, col)
        return true
    end

    if is_digit(ch) then
        self:lex_number()
        return true
    end

    if is_alpha(ch) then
        self:lex_identifier()
        return true
    end

    if ch == '"' then
        self:lex_string()
        return true
    end

    if ch == '#' then
        self:lex_directive()
        return true
    end

    error(string.format("unexpected character '%s' at %d:%d", ch, self.line, self.col))
end

function Lexer:tokenize()
    while self:next_token() do
        -- keep lexing
    end
    self:add_token("EOF", "", self.line, self.col)
    return self.tokens
end

return function(input)
    local lexer = Lexer.new(input)
    return lexer:tokenize()
end
