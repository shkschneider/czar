#!/usr/bin/env lua

-- Czar Lexer
-- Tokenizes .cz source files for the Czar language
-- Host language: Lua
-- Target language: C (generates tokens for C code generation)

local Lexer = {}

-- Token types
Lexer.TokenType = {
    -- Keywords
    STRUCT = "STRUCT",
    FN = "FN",
    RETURN = "RETURN",
    IF = "IF",
    ELSE = "ELSE",
    WHILE = "WHILE",
    VAR = "VAR",
    VAL = "VAL",
    
    -- Built-in types
    I32 = "I32",
    BOOL = "BOOL",
    VOID = "VOID",
    
    -- Literals
    NUMBER = "NUMBER",
    TRUE = "TRUE",
    FALSE = "FALSE",
    NULL = "NULL",
    
    -- Identifiers
    IDENTIFIER = "IDENTIFIER",
    
    -- Operators
    PLUS = "PLUS",           -- +
    MINUS = "MINUS",         -- -
    STAR = "STAR",           -- *
    SLASH = "SLASH",         -- /
    PERCENT = "PERCENT",     -- %
    AMPERSAND = "AMPERSAND", -- &
    ARROW = "ARROW",         -- ->
    DOT = "DOT",             -- .
    EQ = "EQ",               -- =
    EQEQ = "EQEQ",           -- ==
    NE = "NE",               -- !=
    LT = "LT",               -- <
    LE = "LE",               -- <=
    GT = "GT",               -- >
    GE = "GE",               -- >=
    AND = "AND",             -- &&
    OR = "OR",               -- ||
    NOT = "NOT",             -- !
    
    -- Punctuation
    LPAREN = "LPAREN",       -- (
    RPAREN = "RPAREN",       -- )
    LBRACE = "LBRACE",       -- {
    RBRACE = "RBRACE",       -- }
    LBRACKET = "LBRACKET",   -- [
    RBRACKET = "RBRACKET",   -- ]
    COLON = "COLON",         -- :
    SEMICOLON = "SEMICOLON", -- ;
    COMMA = "COMMA",         -- ,
    
    -- Special
    EOF = "EOF",
    -- Note: NEWLINE token type is reserved for future use if needed
    -- Currently, whitespace including newlines is skipped during tokenization
}

-- Keywords mapping
local keywords = {
    ["struct"] = Lexer.TokenType.STRUCT,
    ["fn"] = Lexer.TokenType.FN,
    ["return"] = Lexer.TokenType.RETURN,
    ["if"] = Lexer.TokenType.IF,
    ["else"] = Lexer.TokenType.ELSE,
    ["while"] = Lexer.TokenType.WHILE,
    ["var"] = Lexer.TokenType.VAR,
    ["val"] = Lexer.TokenType.VAL,
    ["i32"] = Lexer.TokenType.I32,
    ["bool"] = Lexer.TokenType.BOOL,
    ["void"] = Lexer.TokenType.VOID,
    ["true"] = Lexer.TokenType.TRUE,
    ["false"] = Lexer.TokenType.FALSE,
    ["null"] = Lexer.TokenType.NULL,
}

-- Token constructor
function Lexer.Token(type, value, line, column)
    return {
        type = type,
        value = value,
        line = line,
        column = column
    }
end

-- Lexer state
function Lexer.new(source)
    local self = {
        source = source,
        position = 1,
        line = 1,
        column = 1,
        tokens = {}
    }
    
    -- Get current character
    function self:current()
        if self.position <= #self.source then
            return self.source:sub(self.position, self.position)
        end
        return nil
    end
    
    -- Peek ahead n characters
    function self:peek(n)
        n = n or 1
        local pos = self.position + n
        if pos <= #self.source then
            return self.source:sub(pos, pos)
        end
        return nil
    end
    
    -- Advance position
    function self:advance()
        local ch = self:current()
        self.position = self.position + 1
        if ch == '\n' then
            self.line = self.line + 1
            self.column = 1
        else
            self.column = self.column + 1
        end
        return ch
    end
    
    -- Skip whitespace (except newlines, which are significant for some contexts)
    function self:skipWhitespace()
        while self:current() and self:current():match("[ \t\r\n]") do
            self:advance()
        end
    end
    
    -- Skip single-line comment
    function self:skipLineComment()
        while self:current() and self:current() ~= '\n' do
            self:advance()
        end
    end
    
    -- Skip block comment
    function self:skipBlockComment()
        self:advance() -- skip *
        while self:current() do
            if self:current() == '*' and self:peek(1) == '/' then
                self:advance() -- skip *
                self:advance() -- skip /
                break
            end
            self:advance()
        end
    end
    
    -- Read identifier or keyword
    function self:readIdentifier()
        local start_line = self.line
        local start_column = self.column
        local value = ""
        
        while self:current() and (self:current():match("[a-zA-Z0-9_]")) do
            value = value .. self:current()
            self:advance()
        end
        
        -- Check if it's a keyword
        local token_type = keywords[value] or Lexer.TokenType.IDENTIFIER
        return Lexer.Token(token_type, value, start_line, start_column)
    end
    
    -- Read number literal
    function self:readNumber()
        local start_line = self.line
        local start_column = self.column
        local value = ""
        
        while self:current() and self:current():match("[0-9]") do
            value = value .. self:current()
            self:advance()
        end
        
        return Lexer.Token(Lexer.TokenType.NUMBER, value, start_line, start_column)
    end
    
    -- Tokenize the source
    function self:tokenize()
        while self:current() do
            self:skipWhitespace()
            
            if not self:current() then
                break
            end
            
            local ch = self:current()
            local line = self.line
            local column = self.column
            
            -- Comments
            if ch == '/' and self:peek(1) == '/' then
                self:skipLineComment()
            elseif ch == '/' and self:peek(1) == '*' then
                self:advance() -- skip /
                self:skipBlockComment()
            
            -- Identifiers and keywords
            elseif ch:match("[a-zA-Z_]") then
                table.insert(self.tokens, self:readIdentifier())
            
            -- Numbers
            elseif ch:match("[0-9]") then
                table.insert(self.tokens, self:readNumber())
            
            -- Two-character operators
            elseif ch == '-' and self:peek(1) == '>' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.ARROW, "->", line, column))
            
            elseif ch == '=' and self:peek(1) == '=' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.EQEQ, "==", line, column))
            
            elseif ch == '!' and self:peek(1) == '=' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.NE, "!=", line, column))
            
            elseif ch == '<' and self:peek(1) == '=' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.LE, "<=", line, column))
            
            elseif ch == '>' and self:peek(1) == '=' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.GE, ">=", line, column))
            
            elseif ch == '&' and self:peek(1) == '&' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.AND, "&&", line, column))
            
            elseif ch == '|' and self:peek(1) == '|' then
                self:advance()
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.OR, "||", line, column))
            
            -- Single-character operators and punctuation
            elseif ch == '+' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.PLUS, "+", line, column))
            
            elseif ch == '-' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.MINUS, "-", line, column))
            
            elseif ch == '*' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.STAR, "*", line, column))
            
            elseif ch == '/' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.SLASH, "/", line, column))
            
            elseif ch == '%' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.PERCENT, "%", line, column))
            
            elseif ch == '&' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.AMPERSAND, "&", line, column))
            
            elseif ch == '.' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.DOT, ".", line, column))
            
            elseif ch == '=' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.EQ, "=", line, column))
            
            elseif ch == '<' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.LT, "<", line, column))
            
            elseif ch == '>' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.GT, ">", line, column))
            
            elseif ch == '!' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.NOT, "!", line, column))
            
            elseif ch == '(' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.LPAREN, "(", line, column))
            
            elseif ch == ')' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.RPAREN, ")", line, column))
            
            elseif ch == '{' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.LBRACE, "{", line, column))
            
            elseif ch == '}' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.RBRACE, "}", line, column))
            
            elseif ch == '[' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.LBRACKET, "[", line, column))
            
            elseif ch == ']' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.RBRACKET, "]", line, column))
            
            elseif ch == ':' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.COLON, ":", line, column))
            
            elseif ch == ';' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.SEMICOLON, ";", line, column))
            
            elseif ch == ',' then
                self:advance()
                table.insert(self.tokens, Lexer.Token(Lexer.TokenType.COMMA, ",", line, column))
            
            else
                error(string.format("Unexpected character '%s' at line %d, column %d", ch, line, column))
            end
        end
        
        -- Add EOF token
        table.insert(self.tokens, Lexer.Token(Lexer.TokenType.EOF, "", self.line, self.column))
        
        return self.tokens
    end
    
    return self
end

-- Main entry point for command-line usage
-- Detect if this script is being run directly (not required as a module)
if arg and arg[0] and #arg >= 1 then
    -- Check if we're at the main chunk level (not inside a require call)
    local info = debug.getinfo(2, 'S')
    -- When run directly: info is nil or info.what is 'C' or 'main'
    -- When required: info.what is 'Lua'
    if not info or info.what ~= 'Lua' then
        local filename = arg[1]
        local file = io.open(filename, "r")
        if not file then
            print("Error: Could not open file " .. filename)
            os.exit(1)
        end
        
        local source = file:read("*all")
        file:close()
        
        local lexer = Lexer.new(source)
        local tokens = lexer:tokenize()
        
        -- Print tokens
        for i, token in ipairs(tokens) do
            print(string.format("%3d: %-15s '%s' at %d:%d", 
                i, token.type, token.value, token.line, token.column))
        end
    end
end

return Lexer
