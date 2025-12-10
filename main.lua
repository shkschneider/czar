#!/usr/bin/env lua
-- Czar compiler - standalone executable wrapper

-- Get the directory where this script is located
local script_dir = arg[0]:match("(.*/)")
if script_dir then
    package.path = script_dir .. "?.lua;" .. package.path
end

local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local function usage()
    io.stderr:write("Usage: cz <source.cz> [-o output]\n")
    io.stderr:write("  Compiles a .cz source file to C and then to a binary\n")
    io.stderr:write("\nOptions:\n")
    io.stderr:write("  -o <output>  Specify output binary name (default: a.out)\n")
    os.exit(1)
end

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function compile_to_c(source_path)
    local source, err = read_file(source_path)
    if not source then
        io.stderr:write(string.format("Failed to read '%s': %s\n", source_path, err or "unknown error"))
        os.exit(1)
    end

    local ok, tokens = pcall(lexer, source)
    if not ok then
        io.stderr:write(string.format("Lexer error: %s\n", tokens))
        os.exit(1)
    end

    local ok, ast = pcall(parser, tokens)
    if not ok then
        io.stderr:write(string.format("Parser error: %s\n", ast))
        os.exit(1)
    end

    local ok, c_source = pcall(codegen, ast)
    if not ok then
        io.stderr:write(string.format("Codegen error: %s\n", c_source))
        os.exit(1)
    end

    return c_source
end

local function main()
    if not arg or #arg < 1 then
        usage()
    end

    local source_path = arg[1]
    local output_path = "a.out"

    -- Parse command line arguments
    local i = 2
    while i <= #arg do
        if arg[i] == "-o" then
            i = i + 1
            if i > #arg then
                io.stderr:write("Error: -o requires an argument\n")
                usage()
            end
            output_path = arg[i]
        else
            io.stderr:write(string.format("Unknown option: %s\n", arg[i]))
            usage()
        end
        i = i + 1
    end

    -- Compile .cz to C
    local c_source = compile_to_c(source_path)

    -- Write C source to temporary file
    local c_temp = os.tmpname() .. ".c"
    local c_file = io.open(c_temp, "w")
    if not c_file then
        io.stderr:write("Failed to create temporary C file\n")
        os.exit(1)
    end
    c_file:write(c_source)
    c_file:close()

    -- Compile C to binary
    local cc_cmd = string.format("cc %s -o %s 2>&1", c_temp, output_path)
    local cc_output = io.popen(cc_cmd)
    local cc_result = cc_output:read("*a")
    local success = cc_output:close()

    -- Clean up temporary file
    os.remove(c_temp)

    if not success then
        io.stderr:write("C compilation failed:\n")
        io.stderr:write(cc_result)
        os.exit(1)
    end

    io.stderr:write(string.format("Successfully compiled %s to %s\n", source_path, output_path))
end

main()
