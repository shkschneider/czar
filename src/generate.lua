-- Generator module: generates C code from .cz source file
-- Wraps lexer, parser, typechecker, lowering, analysis, and codegen functionality

local lexer = require("lexer")
local parser = require("parser")
local typechecker = require("typechecker")
local lowering = require("lowering")
local analysis = require("analysis")
local codegen = require("codegen")

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function generate_c(source_path, options)
    options = options or {}
    
    -- Extract just the filename (not the full path) for #FILE
    local filename = source_path:match("([^/]+)$") or source_path
    options.source_file = filename
    options.source_path = source_path  -- Full path for reading source lines
    
    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        return nil, string.format("Failed to read '%s': %s", source_path, err or "unknown error")
    end

    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        -- Remove Lua error prefix
        local clean_error = tokens:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, string.format("Lexer error: %s", clean_error)
    end

    -- Parse
    local ok, ast = pcall(parser, tokens)
    if not ok then
        -- Remove Lua error prefix
        local clean_error = ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, string.format("Parser error: %s", clean_error)
    end

    -- Type check (distinct pass after AST construction)
    local ok, typed_ast = pcall(typechecker, ast, options)
    if not ok then
        -- Remove Lua error prefix like "[string "typechecker"]:0: "
        local clean_error = typed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, clean_error
    end

    -- Lowering (insert explicit pointer ops, canonicalize for codegen)
    local ok, lowered_ast = pcall(lowering, typed_ast, options)
    if not ok then
        -- Remove Lua error prefix
        local clean_error = lowered_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, clean_error
    end

    -- Escape analysis / lifetime checks
    local ok, analyzed_ast = pcall(analysis, lowered_ast, options)
    if not ok then
        -- Remove Lua error prefix
        local clean_error = analyzed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, clean_error
    end

    -- Generate C code (runs on typed/lowered/analyzed AST)
    local ok, c_source = pcall(codegen, analyzed_ast, options)
    if not ok then
        -- Remove Lua error prefix
        local clean_error = c_source:gsub("^%[string [^%]]+%]:%d+: ", "")
        return nil, string.format("Codegen error: %s", clean_error)
    end

    return c_source, nil
end

local function write_c_file(c_source, output_path)
    local handle, err = io.open(output_path, "w")
    if not handle then
        return false, string.format("Failed to create '%s': %s", output_path, err or "unknown error")
    end
    handle:write(c_source)
    handle:close()
    return true, nil
end

return {
    generate_c = generate_c,
    write_c_file = write_c_file,
    read_file = read_file
}
