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
local asm_module = require("asm")
local compile = require("compile")
local build = require("build")
local run = require("run")
local test = require("test")
local format = require("format")
local clean = require("clean")

-- Simple file reader utility
-- Note: This is for legacy commands (lexer, parser, typechecker)
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
    io.stdout:write("  compile <file.cz>       Generate C code from .cz file (produces .c file)\n")
    io.stdout:write("  asm <file.c>            Generate assembly from .c file (produces .s file)\n")
    io.stdout:write("  build <file.cz>         Build binary from .cz file (depends on compile, produces a.out)\n")
    io.stdout:write("  run <file.cz>           Build and run binary (depends on build, then clean)\n")
    io.stdout:write("  test <file.cz>          Compile, run, and expect exit code 0\n")
    io.stdout:write("  format <file.cz>        Format .cz file (TODO: not implemented)\n")
    io.stdout:write("  clean [path]            Remove binaries and generated files (.c and .s)\n")
    io.stdout:write("\nOptions:\n")
    io.stdout:write("  --debug                 Enable memory tracking and print statistics on exit\n")
    os.exit(0)
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
        io.stderr:write("Error: 'build' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path
    local output_path = opts.output_path or "a.out"

    if not source_path then
        io.stderr:write("Error: 'build' requires a source file\n")
        usage()
    end

    -- Call build.lua (which calls compile.lua internally)
    local ok, result = build.build(source_path, output_path, { debug = opts.debug })
    if not ok then
        io.stderr:write(result .. "\n")
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

    -- Call run.lua (which calls build.lua which calls compile.lua internally)
    local ok, exit_code = run.run(source_path, { debug = opts.debug })
    if not ok then
        io.stderr:write(exit_code .. "\n")
        os.exit(1)
    end

    os.exit(exit_code)
end

local function cmd_asm(args)
    if #args < 1 then
        io.stderr:write("Error: 'asm' requires a source file\n")
        usage()
    end

    local source_path = args[1]

    local ok, result = asm_module.c_to_asm(source_path)
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

    io.stderr:write(string.format("Generated: %s\n", result))
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

    if command == "compile" then
        cmd_compile(cmd_args)
    elseif command == "asm" then
        cmd_asm(cmd_args)
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

