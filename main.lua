#!/usr/bin/env lua
-- Czar compiler - standalone executable launcher

-- Get the directory where this script is located
local script_dir = arg[0]:match("(.*/)")
if script_dir then
    package.path = script_dir .. "?.lua;" .. package.path
end

local lexer = require("lexer")
local parser = require("parser")
local generator = require("generator")
local build = require("build")

local function usage()
    io.stderr:write("Usage: cz <command> <path>\n")
    io.stderr:write("\nCommands:\n")
    io.stderr:write("  lexer <file.cz>         Print all tokens to stdout\n")
    io.stderr:write("  parser <file.cz>        Print AST to stdout\n")
    io.stderr:write("  generator <file.cz>     Generate C code from .cz file (saves as .c)\n")
    io.stderr:write("  build <file.c|.cz>      Compile .c or .cz file to binary\n")
    io.stderr:write("                          Options: -o <output> (default: a.out)\n")
    io.stderr:write("  run <file.cz>           Compile and run a.out binary\n")
    io.stderr:write("\nNote: Each command depends on the ones before it.\n")
    io.stderr:write("\nExamples:\n")
    io.stderr:write("  cz lexer program.cz\n")
    io.stderr:write("  cz parser program.cz\n")
    io.stderr:write("  cz generator program.cz\n")
    io.stderr:write("  cz build program.c\n")
    io.stderr:write("  cz build program.cz -o myapp\n")
    io.stderr:write("  cz run program.cz\n")
    os.exit(1)
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
    
    -- Read source file
    local source, err = generator.read_file(source_path)
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
end

local function cmd_parser(args)
    if #args < 1 then
        io.stderr:write("Error: 'parser' requires a source file\n")
        usage()
    end

    local source_path = args[1]
    
    -- Read source file
    local source, err = generator.read_file(source_path)
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
end

local function cmd_generator(args)
    if #args < 1 then
        io.stderr:write("Error: 'generator' requires a source file\n")
        usage()
    end

    local source_path = args[1]
    
    -- Generate C code
    local c_source, err = generator.generate_c(source_path)
    if not c_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Determine output path (.cz -> .c)
    local output_path = source_path:gsub("%.cz$", ".c")
    if output_path == source_path then
        -- No .cz extension, just append .c
        output_path = source_path .. ".c"
    end

    -- Write C file
    local ok, err = generator.write_c_file(c_source, output_path)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    io.stderr:write(string.format("Generated: %s\n", output_path))
end

local function cmd_build(args)
    if #args < 1 then
        io.stderr:write("Error: 'build' requires a source file (.c or .cz)\n")
        usage()
    end

    local source_path = args[1]
    local output_path = "a.out"
    
    -- Parse -o option if provided
    local i = 2
    while i <= #args do
        if args[i] == "-o" then
            i = i + 1
            if i > #args then
                io.stderr:write("Error: -o requires an argument\n")
                os.exit(1)
            end
            output_path = args[i]
        end
        i = i + 1
    end

    -- Check if source is .cz or .c
    local c_file_path
    local cleanup_c = false
    
    if source_path:match("%.cz$") then
        -- Generate C code from .cz file
        local c_source, err = generator.generate_c(source_path)
        if not c_source then
            io.stderr:write(err .. "\n")
            os.exit(1)
        end
        
        -- Write to temporary C file
        c_file_path = os.tmpname() .. ".c"
        local ok, err = generator.write_c_file(c_source, c_file_path)
        if not ok then
            io.stderr:write(err .. "\n")
            os.exit(1)
        end
        cleanup_c = true
    else
        -- Assume it's a .c file
        c_file_path = source_path
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

    io.stderr:write(string.format("Built: %s\n", output_path))
end

local function cmd_run(args)
    if #args < 1 then
        io.stderr:write("Error: 'run' requires a source file\n")
        usage()
    end

    local source_path = args[1]
    
    -- Generate C code
    local c_source, err = generator.generate_c(source_path)
    if not c_source then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    -- Write to temporary C file
    local c_temp = os.tmpname() .. ".c"
    local ok, err = generator.write_c_file(c_source, c_temp)
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
    local exit_code = build.run_binary(output_path)
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
    elseif command == "generator" then
        cmd_generator(cmd_args)
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

