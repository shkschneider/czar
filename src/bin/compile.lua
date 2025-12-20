-- compile module: generates C code from .cz source file
-- Contains all transpilation logic (lexer, parser, typechecker, lowering, analysis, codegen)
-- This is the main compilation step that produces .c files
--
-- Returns:
--   success, result, exit_code
--   - success (boolean): true if compilation succeeded, false otherwise
--   - result (string): output file path on success, error message on failure
--   - exit_code (number): 0 on success, phase-specific error code on failure:
--       1 = lexer error
--       2 = parser error  
--       3 = typechecker error
--       4 = lowering error
--       5 = analysis error
--       6 = codegen error
--       7 = file write error

local lexer = require("lexer")
local parser = require("parser")
local typechecker = require("typechecker")
local lowering = require("lowering")
local analysis = require("analysis")
local codegen = require("codegen")

local Compile = {}
Compile.__index = Compile

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function write_file(content, output_path)
    local handle, err = io.open(output_path, "w")
    if not handle then
        return false, string.format("Failed to create '%s': %s", output_path, err or "unknown error")
    end
    handle:write(content)
    handle:close()
    return true, nil
end

function Compile.compile(source_path, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path), 1
    end

    -- Extract just the filename (not the full path) for #FILE
    local filename = source_path:match("([^/]+)$") or source_path
    options.source_file = filename
    options.source_path = source_path  -- Full path for reading source lines
    
    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        return false, string.format("Failed to read '%s': %s", source_path, err or "unknown error"), 1
    end

    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        local clean_error = tokens:gsub("^%[string [^%]]+%]:%d+: ", "")
        -- Extract line number if present in lexer error
        local line_match = clean_error:match("at (%d+)")
        if line_match then
            return false, string.format("ERROR at %s:%s lexer-error\n\t%s", source_path, line_match, clean_error), 1
        else
            return false, string.format("ERROR at %s lexer-error\n\t%s", source_path, clean_error), 1
        end
    end

    -- Parse (pass source for #unsafe blocks)
    local ok, ast = pcall(parser, tokens, source)
    if not ok then
        local clean_error = ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        -- Extract line number if present in error
        local line_match = clean_error:match("at (%d+)")
        if line_match then
            return false, string.format("ERROR at %s:%s parser-error\n\t%s", source_path, line_match, clean_error), 2
        else
            return false, string.format("ERROR at %s parser-error\n\t%s", source_path, clean_error), 2
        end
    end

    -- Type check
    local ok, typed_ast = pcall(typechecker, ast, options)
    if not ok then
        local clean_error = typed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return false, clean_error, 3
    end

    -- Lowering
    local ok, lowered_ast = pcall(lowering, typed_ast, options)
    if not ok then
        local clean_error = lowered_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        -- Extract line number if present
        local line_match = clean_error:match("at (%d+)")
        if line_match then
            return false, string.format("ERROR at %s:%s lowering-error\n\t%s", source_path, line_match, clean_error), 4
        else
            return false, string.format("ERROR at %s lowering-error\n\t%s", source_path, clean_error), 4
        end
    end

    -- Analysis
    local ok, analyzed_ast = pcall(analysis, lowered_ast, options)
    if not ok then
        local clean_error = analyzed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        -- Extract line number if present
        local line_match = clean_error:match("at (%d+)")
        if line_match then
            return false, string.format("ERROR at %s:%s analysis-error\n\t%s", source_path, line_match, clean_error), 5
        else
            return false, string.format("ERROR at %s analysis-error\n\t%s", source_path, clean_error), 5
        end
    end

    -- Generate C code
    local ok, c_source = pcall(codegen, analyzed_ast, options)
    if not ok then
        local clean_error = c_source:gsub("^%[string [^%]]+%]:%d+: ", "")
        -- Extract line number if present in error
        local line_match = clean_error:match("line (%d+)")
        if line_match then
            return false, string.format("ERROR at %s:%s codegen-error\n\t%s", source_path, line_match, clean_error), 6
        else
            return false, string.format("ERROR at %s codegen-error\n\t%s", source_path, clean_error), 6
        end
    end

    -- Determine output path (.cz -> .c)
    local output_path = source_path:gsub("%.cz$", ".c")

    -- Write C file
    local ok, err = write_file(c_source, output_path)
    if not ok then
        return false, err, 7
    end

    return true, output_path, 0
end

return Compile
