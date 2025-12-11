-- Generator module: generates C code from .cz source file
-- Wraps lexer, parser, and codegen functionality

local lexer = require("lexer")
local parser = require("parser")
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

local function generate_c(source_path)
    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        return nil, string.format("Failed to read '%s': %s", source_path, err or "unknown error")
    end

    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        return nil, string.format("Lexer error: %s", tokens)
    end

    -- Parse
    local ok, ast = pcall(parser, tokens)
    if not ok then
        return nil, string.format("Parser error: %s", ast)
    end

    -- Generate C code
    local ok, c_source = pcall(codegen, ast)
    if not ok then
        return nil, string.format("Codegen error: %s", c_source)
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
