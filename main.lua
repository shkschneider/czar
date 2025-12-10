#!/usr/bin/env lua
-- Czar compiler - standalone executable launcher

-- Get the directory where this script is located
local script_dir = arg[0]:match("(.*/)")
if script_dir then
    package.path = script_dir .. "?.lua;" .. package.path
end

local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local function usage()
    io.stderr:write("Usage: cz <command> [options] <path>\n")
    io.stderr:write("\nCommands:\n")
    io.stderr:write("  run <file.cz>           Compile and run a single file\n")
    io.stderr:write("  build <file/dir>        Compile file or directory (requires single main entry-point)\n")
    io.stderr:write("  test <file/dir>         Compile each file independently for syntax check\n")
    io.stderr:write("\nOptions:\n")
    io.stderr:write("  -o <output>             Specify output binary name (for run/build, default: a.out)\n")
    io.stderr:write("\nExamples:\n")
    io.stderr:write("  cz run program.cz\n")
    io.stderr:write("  cz build src/\n")
    io.stderr:write("  cz test tests/\n")
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

local function is_directory(path)
    local ok, err, code = os.rename(path, path)
    if not ok then
        if code == 13 then  -- Permission denied, but exists
            return true
        end
        return false
    end
    -- Check if path ends with separator
    local handle = io.popen("test -d " .. path .. " && echo yes || echo no")
    local result = handle:read("*a")
    handle:close()
    return result:match("yes") ~= nil
end

local function find_cz_files(path)
    local files = {}
    if is_directory(path) then
        -- Find all .cz files in directory
        local handle = io.popen("find " .. path .. " -name '*.cz' -type f 2>/dev/null")
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    else
        -- Single file
        table.insert(files, path)
    end
    return files
end

local function compile_to_c(source_path)
    local source, err = read_file(source_path)
    if not source then
        io.stderr:write(string.format("Failed to read '%s': %s\n", source_path, err or "unknown error"))
        return nil, err
    end

    local ok, tokens = pcall(lexer, source)
    if not ok then
        return nil, string.format("Lexer error: %s", tokens)
    end

    local ok, ast = pcall(parser, tokens)
    if not ok then
        return nil, string.format("Parser error: %s", ast)
    end

    local ok, c_source = pcall(codegen, ast)
    if not ok then
        return nil, string.format("Codegen error: %s", c_source)
    end

    return c_source, nil
end

local function compile_and_link(source_path, output_path)
    -- Compile .cz to C
    local c_source, err = compile_to_c(source_path)
    if not c_source then
        io.stderr:write(err .. "\n")
        return false
    end

    -- Write C source to temporary file
    local c_temp = os.tmpname() .. ".c"
    local c_file = io.open(c_temp, "w")
    if not c_file then
        io.stderr:write("Failed to create temporary C file\n")
        return false
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
        return false
    end

    return true
end

local function cmd_run(args)
    if #args < 1 then
        io.stderr:write("Error: 'run' requires a source file\n")
        usage()
    end

    local source_path = args[1]
    local output_path = "a.out"

    -- Parse options
    local i = 2
    while i <= #args do
        if args[i] == "-o" then
            i = i + 1
            if i > #args then
                io.stderr:write("Error: -o requires an argument\n")
                usage()
            end
            output_path = args[i]
        else
            io.stderr:write(string.format("Unknown option: %s\n", args[i]))
            usage()
        end
        i = i + 1
    end

    -- Compile
    if not compile_and_link(source_path, output_path) then
        os.exit(1)
    end

    io.stderr:write(string.format("Successfully compiled %s to %s\n", source_path, output_path))

    -- Run and capture exit code
    local run_cmd = "./" .. output_path .. "; echo $?"
    local handle = io.popen(run_cmd)
    local output = handle:read("*a")
    handle:close()
    
    -- Extract exit code from last line
    local exit_code = output:match("(%d+)%s*$")
    if exit_code then
        os.exit(tonumber(exit_code))
    else
        os.exit(0)
    end
end

local function cmd_build(args)
    if #args < 1 then
        io.stderr:write("Error: 'build' requires a source file or directory\n")
        usage()
    end

    local source_path = args[1]
    local output_path = "a.out"

    -- Parse options
    local i = 2
    while i <= #args do
        if args[i] == "-o" then
            i = i + 1
            if i > #args then
                io.stderr:write("Error: -o requires an argument\n")
                usage()
            end
            output_path = args[i]
        else
            io.stderr:write(string.format("Unknown option: %s\n", args[i]))
            usage()
        end
        i = i + 1
    end

    -- Find .cz files
    local files = find_cz_files(source_path)
    if #files == 0 then
        io.stderr:write(string.format("Error: No .cz files found in %s\n", source_path))
        os.exit(1)
    end

    -- For build, we expect a single main entry-point
    -- If multiple files, we'd need to implement a linking strategy
    if #files == 1 then
        if not compile_and_link(files[1], output_path) then
            os.exit(1)
        end
        io.stderr:write(string.format("Successfully compiled %s to %s\n", files[1], output_path))
    else
        io.stderr:write("Error: build with multiple files not yet supported (requires single main entry-point)\n")
        os.exit(1)
    end
end

local function cmd_test(args)
    if #args < 1 then
        io.stderr:write("Error: 'test' requires a source file or directory\n")
        usage()
    end

    local source_path = args[1]

    -- Find .cz files
    local files = find_cz_files(source_path)
    if #files == 0 then
        io.stderr:write(string.format("Error: No .cz files found in %s\n", source_path))
        os.exit(1)
    end

    io.stderr:write(string.format("Testing %d file(s)...\n", #files))

    local passed = 0
    local failed = 0

    for _, file in ipairs(files) do
        io.stderr:write(string.format("  %s... ", file))
        local c_source, err = compile_to_c(file)
        if c_source then
            io.stderr:write("OK\n")
            passed = passed + 1
        else
            io.stderr:write("FAIL\n")
            io.stderr:write(string.format("    %s\n", err))
            failed = failed + 1
        end
    end

    io.stderr:write(string.format("\nResults: %d passed, %d failed\n", passed, failed))
    if failed > 0 then
        os.exit(1)
    end
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

    if command == "run" then
        cmd_run(cmd_args)
    elseif command == "build" then
        cmd_build(cmd_args)
    elseif command == "test" then
        cmd_test(cmd_args)
    else
        io.stderr:write(string.format("Unknown command: %s\n", command))
        usage()
    end
end

main()
