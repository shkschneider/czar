-- test module: compile, build, and run with expected exit code 0
-- Depends on compile and build modules

local compile_module = require("compile")
local build_module = require("build")

local Test = {}
Test.__index = Test

local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

function Test.test(source_path, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- Step 1: Compile to .c (calls compile.lua)
    local ok, c_path = compile_module.compile(source_path, options)
    if not ok then
        return false, c_path  -- c_path contains error message
    end

    -- Step 2: Build binary
    local output_path = "a.out"
    local cc_cmd = string.format("cc %s -o %s 2>&1; echo \"EXIT_CODE:$?\"",
        shell_escape(c_path), shell_escape(output_path))
    local cc_output = io.popen(cc_cmd)
    local cc_result = cc_output:read("*a")
    cc_output:close()

    local exit_code = cc_result:match("EXIT_CODE:(%d+)")
    if exit_code and tonumber(exit_code) ~= 0 then
        return false, "C compilation failed:\n" .. cc_result:gsub("EXIT_CODE:%d+%s*$", "")
    end

    -- Step 3: Run the binary and capture exit code
    local run_cmd = shell_escape("./" .. output_path)
    local ret = os.execute(run_cmd)

    local run_exit_code
    if type(ret) == "number" then
        run_exit_code = math.floor(ret / 256)
    else
        local ok, _, code = ret
        run_exit_code = code or (ok and 0 or 1)
    end
    
    -- Step 4: Clean up (remove binary and .c file)
    os.remove(output_path)
    os.remove(c_path)
    
    -- Check exit code
    if run_exit_code ~= 0 then
        return false, string.format("Test failed with exit code %d (expected 0)", run_exit_code)
    end

    return true, nil
end

return Test
