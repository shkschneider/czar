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
local todo = require("todo")
local fixme = require("fixme")

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

-- Check if path is a directory
local function is_directory(path)
    local handle = io.popen("test -d " .. path:gsub("'", "'\\''") .. " && echo yes || echo no")
    local result = handle:read("*a"):match("^%s*(.-)%s*$")
    handle:close()
    return result == "yes"
end

-- Get all .cz files from a directory
local function get_cz_files_in_dir(dir)
    local files = {}
    local handle = io.popen("find " .. dir:gsub("'", "'\\''") .. " -type f -name '*.cz' 2>/dev/null")
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

-- Expand arguments to handle directories and multiple files
local function expand_file_args(args)
    local files = {}
    local options = {}
    
    local i = 1
    while i <= #args do
        if args[i] == "--debug" then
            options.debug = true
        elseif args[i] == "-o" then
            i = i + 1
            if i > #args then
                io.stderr:write("Error: -o requires an argument\n")
                return nil, "Missing argument for -o"
            end
            options.output = args[i]
        elseif args[i]:sub(1, 1) == "-" then
            return nil, string.format("Unknown option: %s", args[i])
        else
            -- It's a file or directory
            local path = args[i]
            if is_directory(path) then
                local dir_files = get_cz_files_in_dir(path)
                for _, file in ipairs(dir_files) do
                    table.insert(files, file)
                end
            else
                table.insert(files, path)
            end
        end
        i = i + 1
    end
    
    return files, options
end

local function usage()
    io.stdout:write("Usage: cz [command] [files...] [options]\n")
    io.stdout:write("\nCommands:\n")
    io.stdout:write("  compile <files...>      Generate C code from .cz files (produces .c files)\n")
    io.stdout:write("                          Accepts: file.cz, file1.cz file2.cz, or path/to/dir/\n")
    io.stdout:write("  asm <files...>          Generate assembly from .cz files (produces .s files)\n")
    io.stdout:write("                          Accepts: file.cz, file1.cz file2.cz, or path/to/dir/\n")
    io.stdout:write("  build <files...>        Build binary from .cz files (finds file with main function)\n")
    io.stdout:write("                          Accepts: file.cz, file1.cz file2.cz, or path/to/dir/\n")
    io.stdout:write("  run <files...>          Build and run binary (finds file with main function)\n")
    io.stdout:write("                          Accepts: file.cz, file1.cz file2.cz, or path/to/dir/\n")
    io.stdout:write("  test <files...>         Compile, run, and expect exit code 0 for each file\n")
    io.stdout:write("  format <files...>       Format .cz files (TODO: not implemented)\n")
    io.stdout:write("  clean [path]            Remove binaries and generated files (.c and .s)\n")
    io.stdout:write("  todo [path]             List all #TODO markers in .cz files (defaults to CWD)\n")
    io.stdout:write("  fixme [path]            List all #FIXME markers in .cz files (defaults to CWD)\n")
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
        io.stderr:write("Error: 'build' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    -- For build, if multiple files are provided, find the one with main function
    -- or error if none or multiple have main
    local main_file = nil
    if #files > 1 then
        for _, file in ipairs(files) do
            -- Quick check if file likely has main function
            local f = io.open(file, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content:match("fn%s+main%s*%(") then
                    if main_file then
                        io.stderr:write(string.format("Error: multiple files with main function found: %s and %s\n", main_file, file))
                        os.exit(1)
                    end
                    main_file = file
                end
            end
        end
        
        if not main_file then
            io.stderr:write("Error: no file with main function found in provided files\n")
            os.exit(1)
        end
    else
        main_file = files[1]
    end

    local output_path = options.output or "a.out"

    -- Call build.lua (which calls compile.lua internally)
    local ok, result = build.build(main_file, output_path, { debug = options.debug })
    if not ok then
        io.stderr:write(result .. "\n")
        os.exit(1)
    end

    return 0
end

local function cmd_run(args)
    if #args < 1 then
        io.stderr:write("Error: 'run' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    -- For run, if multiple files are provided, find the one with main function
    -- or error if none or multiple have main
    local main_file = nil
    if #files > 1 then
        for _, file in ipairs(files) do
            -- Quick check if file likely has main function
            local f = io.open(file, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content:match("fn%s+main%s*%(") then
                    if main_file then
                        io.stderr:write(string.format("Error: multiple files with main function found: %s and %s\n", main_file, file))
                        os.exit(1)
                    end
                    main_file = file
                end
            end
        end
        
        if not main_file then
            io.stderr:write("Error: no file with main function found in provided files\n")
            os.exit(1)
        end
    else
        main_file = files[1]
    end

    -- Call run.lua (which calls build.lua which calls compile.lua internally)
    local ok, exit_code = run.run(main_file, { debug = options.debug })
    if not ok then
        io.stderr:write(exit_code .. "\n")
        os.exit(1)
    end

    os.exit(exit_code)
end

local function cmd_asm(args)
    if #args < 1 then
        io.stderr:write("Error: 'asm' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    local success_count = 0
    local fail_count = 0

    for _, source_path in ipairs(files) do
        local ok, result = asm_module.generate_asm(source_path, options)
        if not ok then
            io.stderr:write(string.format("%s: %s\n", source_path, result))
            fail_count = fail_count + 1
        else
            io.stderr:write(string.format("Generated: %s\n", result))
            success_count = success_count + 1
        end
    end

    if fail_count > 0 then
        io.stderr:write(string.format("\nCompleted: %d succeeded, %d failed\n", success_count, fail_count))
        os.exit(1)
    end

    return 0
end

local function cmd_compile(args)
    if #args < 1 then
        io.stderr:write("Error: 'compile' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    local success_count = 0
    local fail_count = 0

    for _, source_path in ipairs(files) do
        local ok, result = compile.compile(source_path, options)
        if not ok then
            io.stderr:write(string.format("%s: %s\n", source_path, result))
            fail_count = fail_count + 1
        else
            io.stderr:write(string.format("Generated: %s\n", result))
            success_count = success_count + 1
        end
    end

    if fail_count > 0 then
        io.stderr:write(string.format("\nCompleted: %d succeeded, %d failed\n", success_count, fail_count))
        os.exit(1)
    end

    return 0
end

local function cmd_test(args)
    if #args < 1 then
        io.stderr:write("Error: 'test' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    local success_count = 0
    local fail_count = 0

    for _, source_path in ipairs(files) do
        local ok, err = test.test(source_path, options)
        if not ok then
            io.stderr:write(string.format("%s: %s\n", source_path, err))
            fail_count = fail_count + 1
        else
            io.stderr:write(string.format("Test passed: %s\n", source_path))
            success_count = success_count + 1
        end
    end

    if fail_count > 0 then
        io.stderr:write(string.format("\nCompleted: %d passed, %d failed\n", success_count, fail_count))
        os.exit(1)
    end

    return 0
end

local function cmd_format(args)
    if #args < 1 then
        io.stderr:write("Error: 'format' requires at least one source file or directory\n")
        usage()
    end

    local files, options = expand_file_args(args)
    if not files then
        io.stderr:write(options .. "\n")  -- options contains error message
        os.exit(1)
    end

    if #files == 0 then
        io.stderr:write("Error: no .cz files found\n")
        os.exit(1)
    end

    for _, source_path in ipairs(files) do
        local ok, err = format.format(source_path)
        if not ok then
            io.stderr:write(string.format("%s: %s\n", source_path, err))
            os.exit(1)
        end
        io.stderr:write(string.format("Formatted: %s\n", source_path))
    end

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

local function cmd_todo(args)
    local path = args[1] or "."

    local ok, err = todo.todo(path)
    if not ok then
        io.stderr:write(err .. "\n")
        os.exit(1)
    end

    return 0
end

local function cmd_fixme(args)
    local path = args[1] or "."

    local ok, err = fixme.fixme(path)
    if not ok then
        io.stderr:write(err .. "\n")
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
    elseif command == "todo" then
        cmd_todo(cmd_args)
    elseif command == "fixme" then
        cmd_fixme(cmd_args)
    else
        io.stderr:write(string.format("Unknown command: %s\n", command))
        usage()
    end
end

main()

