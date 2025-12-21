-- Recursive descent / Pratt parser for the minimal Czar grammar.
-- Consumes the token stream from lexer.lua and produces an AST.

local Macros = require("src.macros")
local Utils = require("parser.utils")
local Types = require("parser.types")
local Declarations = require("parser.declarations")
local Statements = require("parser.statements")
local Expressions = require("parser.expressions")

local Parser = {}
Parser.__index = Parser

function Parser.new(tokens, source)
    return setmetatable({ tokens = tokens, pos = 1, source = source }, Parser)
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
        error(string.format("expected %s but found %s", value or type_, Utils.token_label(tok)))
    end
    return tok
end

-- Extract raw source text from (start_line, start_col) to (end_line, end_col)
function Parser:extract_source_range(start_line, start_col, end_line, end_col)
    if not self.source then
        error("Source text not available")
    end
    
    local lines = {}
    local current_line = 1
    local current_col = 1
    local pos = 1
    local in_range = false
    local result = {}
    
    for line in (self.source .. "\n"):gmatch("([^\n]*)\n") do
        if current_line == start_line then
            -- Starting line - skip to start_col
            in_range = true
            if current_line == end_line then
                -- All on one line
                local text = line:sub(start_col, end_col - 1)
                return text
            else
                local text = line:sub(start_col)
                table.insert(result, text)
            end
        elseif current_line == end_line then
            -- Ending line - take up to end_col
            local text = line:sub(1, end_col - 1)
            table.insert(result, text)
            break
        elseif in_range then
            -- Middle line - take all
            table.insert(result, line)
        end
        
        current_line = current_line + 1
    end
    
    return table.concat(result, "\n")
end

function Parser:parse_program()
    local module_decl = nil
    local imports = {}
    local uses = {}
    local items = {}
    
    -- Parse optional #module declaration (must be first)
    if self:check("DIRECTIVE") and self:current().value == "module" then
        local directive_tok = self:current()
        self:advance() -- consume DIRECTIVE
        module_decl = Declarations.parse_module_declaration(self, directive_tok)
    end
    
    -- Parse #import and #use directives (must come before other declarations)
    -- Support inline syntax: #import foo ; #use foo
    -- Support shorthand: #import foo #use (automatically uses foo)
    while self:check("DIRECTIVE") do
        local directive_tok = self:current()
        if directive_tok.value == "import" then
            self:advance() -- consume DIRECTIVE
            local import_node = Declarations.parse_import(self, directive_tok)
            table.insert(imports, import_node)
            
            -- Check for shorthand: #import module #use
            -- This means: use the module that was just imported
            if self:check("DIRECTIVE") and self:current().value == "use" then
                local use_tok = self:current()
                self:advance() -- consume #use DIRECTIVE
                
                -- Check if there's a module name after #use
                if self:check("IDENT") then
                    -- Regular #use with module name
                    local use_node = Declarations.parse_use(self, use_tok)
                    table.insert(uses, use_node)
                else
                    -- Shorthand: #import module #use (without module name)
                    -- Automatically use the imported module
                    if import_node.kind == "import" then
                        -- Create a use node for the imported module
                        local use_node = {
                            kind = "use",
                            path = import_node.path,
                            line = use_tok.line,
                            col = use_tok.col
                        }
                        table.insert(uses, use_node)
                    else
                        error("Shorthand #use can only be used with regular module imports, not C imports")
                    end
                end
            end
            
            -- Check for optional semicolon and continue parsing directives
            self:match("SEMICOLON")
        elseif directive_tok.value == "use" then
            self:advance() -- consume DIRECTIVE
            local use_node = Declarations.parse_use(self, directive_tok)
            table.insert(uses, use_node)
            -- Check for optional semicolon and continue parsing directives
            self:match("SEMICOLON")
        else
            -- Not an import/use directive, stop parsing directives
            break
        end
    end
    
    -- Parse remaining top-level items
    while not self:check("EOF") do
        table.insert(items, self:parse_top_level())
    end
    
    return { 
        kind = "program", 
        module = module_decl,
        imports = imports,
        uses = uses,
        items = items
    }
end

function Parser:parse_top_level()
    -- Check for pub or prv modifier
    local is_public = false
    local is_private = false
    if self:check("KEYWORD", "pub") then
        self:advance()
        is_public = true
    elseif self:check("KEYWORD", "prv") then
        self:advance()
        is_private = true
    end
    
    if self:check("KEYWORD", "struct") then
        local struct_node = Declarations.parse_struct(self)
        struct_node.is_public = is_public
        struct_node.is_private = is_private
        return struct_node
    elseif self:check("KEYWORD", "enum") then
        local enum_node = Declarations.parse_enum(self)
        enum_node.is_public = is_public
        enum_node.is_private = is_private
        return enum_node
    elseif self:check("KEYWORD", "fn") then
        local func_node = Declarations.parse_function(self)
        func_node.is_public = is_public
        func_node.is_private = is_private
        return func_node
    elseif self:check("DIRECTIVE") then
        if is_public or is_private then
            error("pub/prv modifier cannot be used with preprocessor directives like #assert or #log")
        end
        return self:parse_top_level_directive()
    else
        error(string.format("unexpected token in top-level: %s", Utils.token_label(self:current())))
    end
end

function Parser:parse_top_level_directive()
    local directive_tok = self:expect("DIRECTIVE")
    -- Delegate to centralized Macros module
    -- Store token_label as a module function for error messages
    Parser.token_label = Utils.token_label
    return Macros.parse_top_level(self, directive_tok)
end

-- Delegate method for expression parsing (used by macros)
function Parser:parse_expression()
    return Expressions.parse_expression(self)
end

return function(tokens, source)
    local parser = Parser.new(tokens, source)
    return parser:parse_program()
end
