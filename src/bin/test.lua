-- test module: compile, build, and run with expected exit code 0

local compile_module = require("compile")
local build = require("build")
local run = require("run")

local Test = {}
Test.__index = Test

function Test.test(source_path, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- Compile to .c and .s
    local ok, result = compile_module.compile(source_path, options)
    if not ok then
        return false, result  -- result contains error message
    end

    local c_path = result.c_path

    -- Build binary
    local output_path = "a.out"
    local ok, err = build.compile_c_to_binary(c_path, output_path)
    if not ok then
        return false, err
    end

    -- Run the binary
    local exit_code = run.run_binary(output_path)
    
    -- Clean up (remove binary, .c, and .s files)
    os.remove(output_path)
    os.remove(c_path)
    os.remove(result.s_path)
    
    -- Check exit code
    if exit_code ~= 0 then
        return false, string.format("Test failed with exit code %d (expected 0)", exit_code)
    end

    return true, nil
end

return Test
