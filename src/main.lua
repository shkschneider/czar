#!/usr/bin/env lua
-- Czar compiler - standalone executable launcher

-- Get the directory where this script is located
local script_dir = arg[0]:match("(.*/)")
if script_dir then
    package.path = script_dir .. "?.lua;" .. package.path
end

local lexer = require("lexer")
local parser = require("parser")
local generate = require("generate")
local assemble = require("assemble")
local build = require("build")
local run = require("run")

-- Simple file reader utility
-- Note: This is duplicated in generator.lua to avoid circular dependencies
-- (generator needs it for its API, and main needs it for lexer/parser commands)
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
    io.stderr:write("Usage: cz <command> <path> [options]\n")
    io.stderr:write("\nCommands:\n")
    io.stderr:write("  lexer <file.cz>         Print all tokens to stdout\n")
    io.stderr:write("  parser <file.cz>        Print AST to stdout\n")
    io.stderr:write("  generate <file.cz>      Generate C code from .cz file (prints to stdout and saves as .c)\n")
    io.stderr:write("  assemble <file.c|.cz>   Generate assembly from .c or .cz file (prints to stdout and saves as .s)\n")
    io.stderr:write("  build <file.c|.cz>      Compile .c or .cz file to binary\n")
    io.stderr:write("                          Options: -o <output> (default: a.out), --debug\n")
    io.stderr:write("  run <file.cz>           Compile and run a.out binary\n")
    io.stderr:write("                          Options: --debug\n")
    io.stderr:write("\nOptions:\n")
    io.stderr:write("  --debug                 Enable memory tracking and print statistics on exit\n")
    io.stderr:write("\nNote: Each command depends on the ones before it.\n")
    io.stderr:write("\nExamples:\n")
    io.stderr:write("  cz lexer program.cz\n")
    io.stderr:write("  cz parser program.cz\n")
    io.stderr:write("  cz generate program.cz\n")
    io.stderr:write("  cz generate program.cz --debug\n")
    io.stderr:write("  cz assemble program.cz\n")
    io.stderr:write("  cz build program.c\n")
    io.stderr:write("  cz build program.cz -o myapp\n")
    io.stderr:write("  cz build program.cz --debug\n")
    io.stderr:write("  cz run program.cz\n")
    io.stderr:write("  cz run program.cz --debug\n")
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

local function cmd_lexer(args)
    if #args < 1 then
        io.stderr:write("Error: 'lexer' requires a source file\n")
        usage()
    end

    local source_path = args[1]

    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        io.stderr:write(string.format("Error: source file must have .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        io.stderr:write(string.format("Failed to read '%s': %s\n", source_path, err or "unknown error"))
        os.exit(1)
    end

    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        io.stderr:write(string.format("Lexer error: %s\n", tokens))
        os.exit(1)
    end

    -- Print tokens to stdout
    print(serialize_tokens(tokens))

    return 0
end

local function cmd_parser(args)
    if #args < 1 then
        io.stderr:write("Error: 'parser' requires a source file\n")
        usage()
    end

    local source_path = args[1]

    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        io.stderr:write(string.format("Error: source file must have .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Read source file
    local source, err = read_file(source_path)
    if not source then
        io.stderr:write(string.format("Failed to read '%s': %s\n", source_path, err or "unknown error"))
        os.exit(1)
    end

    -- Lex
    local ok, tokens = pcall(lexer, source)
    if not ok then
        io.stderr:write(string.format("Lexer error: %s\n", tokens))
        os.exit(1)
    end

    -- Parse
    local ok, ast = pcall(parser, tokens)
    if not ok then
        io.stderr:write(string.format("Parser error: %s\n", ast))
        os.exit(1)
    end

    -- Print AST to stdout
    print(serialize_ast(ast))

    return 0
end

local function cmd_generate(args)
    if #args < 1 then
        io.stderr:write("Error: 'generate' requires a source file\n")
        usage()
    end

    local opts = parse_options(args)
    local source_path = opts.source_path

    if not source_path then
        io.stderr:write("Error: 'generate' requires a source file\n")
        usage()
    end

    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        io.stderr:write(string.format("Error: source file must have .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Generate C code with options
    local c_source, err = generate.generate_c(source_path, { debug = opts.debug })
    if not c_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Print C code to stdout
    print(c_source)

    -- Determine output path (.cz -> .c)
    local output_path = source_path:gsub("%.cz$", ".c")

    -- Write C file
    local ok, err = generate.write_c_file(c_source, output_path)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    return 0
end

local function cmd_assemble(args)
    if #args < 1 then
        io.stderr:write("Error: 'assemble' requires a source file (.c or .cz)\n")
        usage()
    end

    local source_path = args[1]

    -- Validate that the source file has a .c or .cz extension
    if not source_path:match("%.cz?$") then
        io.stderr:write(string.format("Error: source file must have .c or .cz extension, got: %s\n", source_path))
        os.exit(1)
    end

    -- Generate assembly code
    local asm_source, err = assemble.assemble_to_asm(source_path)
    if not asm_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Print assembly code to stdout
    print(asm_source)

    -- Determine output path (.cz/.c -> .s)
    local output_path = source_path:gsub("%.c?z?$", "") .. ".s"

    -- Write assembly file
    local ok, err = assemble.write_file(asm_source, output_path)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    return 0
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
        local c_source, err = generate.generate_c(source_path, { debug = opts.debug })
        if not c_source then
            io.stderr:write(err .. "\n")
            os.exit(1)
        end

        -- Write to temporary C file
        c_file_path = os.tmpname() .. ".c"
        local ok, err = generate.write_c_file(c_source, c_file_path)
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
    local c_source, err = generate.generate_c(source_path, { debug = opts.debug })
    if not c_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Write to temporary C file
    local c_temp = os.tmpname() .. ".c"
    local ok, err = generate.write_c_file(c_source, c_temp)
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
    os.exit(exit_code)
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

    if command == "lexer" then
        cmd_lexer(cmd_args)
    elseif command == "parser" then
        cmd_parser(cmd_args)
    elseif command == "generate" then
        cmd_generate(cmd_args)
    elseif command == "assemble" then
        cmd_assemble(cmd_args)
    elseif command == "build" then
        cmd_build(cmd_args)
    elseif command == "run" then
        cmd_run(cmd_args)
    else
        io.stderr:write(string.format("Unknown command: %s\n", command))
        usage()
    end
end

main()

