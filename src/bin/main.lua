#!/usr/bin/env lua
-- Czar compiler - standalone executable launcher

-- Get the directory where this script is located
local script_dir = arg[0]:match("(.*/)")
if script_dir then
    -- Since we're in src/bin/, add both bin/ and parent src/ to the path
    package.path = script_dir .. "?.lua;" .. script_dir .. "../?.lua;" .. package.path
end

local lexer = require("lexer")
local parser = require("parser")
local typechecker = require("typechecker")
local transpiler = require("transpiler")
local assemble = require("assemble")
local build = require("build")
local run = require("run")
local c_module = require("c")
local s_module = require("s")
local compile = require("compile")
local test = require("test")
local format = require("format")
local clean = require("clean")

-- Simple file reader utility
-- Note: This is duplicated in transpiler.lua to avoid circular dependencies
-- (transpiler needs it for its API, and main needs it for lexer/parser commands)
local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function usage()
    io.stdout:write("Usage: cz [command] [path] [options]\n")
    io.stdout:write("\nCommands:\n")
    io.stdout:write("  c <file.cz>             Generate C code from .cz file (produces .c file)\n")
    io.stdout:write("  s <file.c>              Generate assembly from .c file (produces .s file)\n")
    io.stdout:write("  compile <file.cz>       Generate C and assembly from .cz file (produces .c and .s files)\n")
    io.stdout:write("  build <file.cz>         Build binary from .cz file (depends on compile, produces a.out)\n")
    io.stdout:write("  run <file.cz>           Build and run binary (depends on build, then clean)\n")
    io.stdout:write("  test <file.cz>          Compile, run, and expect exit code 0\n")
    io.stdout:write("  format <file.cz>        Format .cz file (TODO: not implemented)\n")
    io.stdout:write("  clean [path]            Remove binaries and generated files (.c and .s)\n")
    io.stdout:write("\nOptions:\n")
    io.stdout:write("  --debug                 Enable memory tracking and print statistics on exit\n")
    os.exit(1)
end

-- Parse common options from args
local function parse_options(args)
    local options = {
        debug = false,
        source_path = nil,
        output_path = nil
    }

    local i = 1
    while i <= #args do
        if args[i] == "--debug" then
            options.debug = true
        elseif args[i] == "-o" then
            i = i + 1
            if i > #args then
                io.stderr:write("Error: -o requires an argument\n")
                usage()
            end
            options.output_path = args[i]
        elseif not options.source_path then
            options.source_path = args[i]
        else
            io.stderr:write(string.format("Error: unexpected argument '%s'\n", args[i]))
            usage()
        end
        i = i + 1
    end

    return options
end

local function serialize_tokens(tokens)
    local lines = {}
    for _, tok in ipairs(tokens) do
        table.insert(lines, string.format("%s '%s' at %d:%d",
            tok.type, tok.value, tok.line, tok.col))
    end
    return table.concat(lines, "\n")
end

local function serialize_ast(ast, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)

    if type(ast) ~= "table" then
        return tostring(ast)
    end

    local lines = {}
    if ast.kind then
        table.insert(lines, prefix .. "kind: " .. ast.kind)
    end

    for k, v in pairs(ast) do
        if k ~= "kind" then
            if type(v) == "table" then
                if #v > 0 and type(v[1]) == "table" then
                    -- Array of nodes
                    table.insert(lines, prefix .. k .. ":")
                    for i, item in ipairs(v) do
                        table.insert(lines, prefix .. "  [" .. i .. "]:")
                        table.insert(lines, serialize_ast(item, indent + 2))
                    end
                else
                    -- Single nested node
                    table.insert(lines, prefix .. k .. ":")
                    table.insert(lines, serialize_ast(v, indent + 1))
                end
            else
                table.insert(lines, prefix .. k .. ": " .. tostring(v))
            end
        end
    end

    return table.concat(lines, "\n")
end

local function cmd_build(args)
    if #args < 1 then
        io.stderr:write("Error: 'build' requires a source file (.c or .cz)\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path
    local output_path = opts.output_path or "a.out"

    if not source_path then
        io.stderr:write("Error: 'build' requires a source file\n")
        usage()
    end

    -- Check if source is .cz or .c
    local c_file_path
    local cleanup_c = false

    if source_path:match("%.cz$") then
        -- Generate C code from .cz file with options
        local c_source, err = transpiler.generate_c(source_path, { debug = opts.debug })
        if not c_source then
            io.stderr:write(err .. "\n")
            os.exit(1)
        end

        -- Write to temporary C file (named after source file)
        c_file_path = transpiler.make_temp_path(source_path, ".c")
        local ok, err = transpiler.write_c_file(c_source, c_file_path)
        if not ok then
            io.stderr:write(err .. "\n")
            os.exit(1)
        end
        cleanup_c = true
    elseif source_path:match("%.c$") then
        -- It's a .c file
        c_file_path = source_path
    else
        -- Invalid file extension
        io.stderr:write(string.format("Error: source file must have .c or .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Compile C to binary
    local ok, err = build.compile_c_to_binary(c_file_path, output_path)

    -- Clean up temporary C file if we created one
    if cleanup_c then
        os.remove(c_file_path)
    end

    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    return 0
end

local function cmd_run(args)
    if #args < 1 then
        io.stderr:write("Error: 'run' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path

    if not source_path then
        io.stderr:write("Error: 'run' requires a source file\n")
        usage()
    end

    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        io.stderr:write(string.format("Error: source file must have .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Generate C code with options
    local c_source, err = transpiler.generate_c(source_path, { debug = opts.debug })
    if not c_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Write to temporary C file (named after source file)
    local c_temp = transpiler.make_temp_path(source_path, ".c")
    local ok, err = transpiler.write_c_file(c_source, c_temp)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Compile to a.out
    local output_path = "a.out"
    local ok, err = build.compile_c_to_binary(c_temp, output_path)

    -- Clean up temporary C file
    os.remove(c_temp)

    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Run the binary
    local exit_code = run.run_binary(output_path)

    -- Clean up after running
    os.remove(output_path)

    os.exit(exit_code)
end

local function cmd_c(args)
    if #args < 1 then
        io.stderr:write("Error: 'c' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path

    if not source_path then
        io.stderr:write("Error: 'c' requires a source file\n")
        usage()
    end

    local ok, result = c_module.cz_to_c(source_path, { debug = opts.debug })
    if not ok then
        io.stderr:write(result .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Generated: %s\n", result))
    return 0
end

local function cmd_s(args)
    if #args < 1 then
        io.stderr:write("Error: 's' requires a source file\n")
        usage()
    end

    local source_path = args[1]

    local ok, result = s_module.c_to_s(source_path)
    if not ok then
        io.stderr:write(result .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Generated: %s\n", result))
    return 0
end

local function cmd_compile(args)
    if #args < 1 then
        io.stderr:write("Error: 'compile' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path

    if not source_path then
        io.stderr:write("Error: 'compile' requires a source file\n")
        usage()
    end

    local ok, result = compile.compile(source_path, { debug = opts.debug })
    if not ok then
        io.stderr:write(result .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Generated: %s, %s\n", result.c_path, result.s_path))
    return 0
end

local function cmd_test(args)
    if #args < 1 then
        io.stderr:write("Error: 'test' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path

    if not source_path then
        io.stderr:write("Error: 'test' requires a source file\n")
        usage()
    end

    local ok, err = test.test(source_path, { debug = opts.debug })
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Test passed: %s\n", source_path))
    return 0
end

local function cmd_format(args)
    if #args < 1 then
        io.stderr:write("Error: 'format' requires a source file\n")
        usage()
    end

    local source_path = args[1]

    local ok, err = format.format(source_path)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Formatted: %s\n", source_path))
    return 0
end

local function cmd_clean(args)
    local path = args[1] or "."

    local ok, result = clean.clean(path)

    if #result.removed > 0 then
        io.stderr:write("Removed files:\n")
        for _, file in ipairs(result.removed) do
            io.stderr:write(string.format("  %s\n", file))
        end
    end

    if #result.errors > 0 then
        io.stderr:write("Errors:\n")
        for _, err in ipairs(result.errors) do
            io.stderr:write(string.format("  %s\n", err))
        end
    end

    if not ok then
        os.exit(1)
    end

    return 0
end

local function main()
    if not arg or #arg < 1 then
        usage()
    end

    local command = arg[1]
    local cmd_args = {}
    for i = 2, #arg do
        table.insert(cmd_args, arg[i])
    end

    if command == "c" then
        cmd_c(cmd_args)
    elseif command == "s" then
        cmd_s(cmd_args)
    elseif command == "compile" then
        cmd_compile(cmd_args)
    elseif command == "build" then
        cmd_build(cmd_args)
    elseif command == "run" then
        cmd_run(cmd_args)
    elseif command == "test" then
        cmd_test(cmd_args)
    elseif command == "format" then
        cmd_format(cmd_args)
    elseif command == "clean" then
        cmd_clean(cmd_args)
    else
        io.stderr:write(string.format("Unknown command: %s\n", command))
        usage()
    end
end

main()

