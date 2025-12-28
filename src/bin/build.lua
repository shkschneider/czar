-- Build module: builds binary from .cz source file
-- Depends on compile module (calls compile.lua to generate .c first)

local compile_module = require("compile")

local Build = {}
Build.__index = Build

local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

function Build.build(source_path, output_path, options)
    options = options or {}
    output_path = output_path or "a.out"
    
    -- Allow both .cz files and directories
    local is_dir = false
    if not source_path:match("%.cz$") then
        -- Check if it's a directory
        local handle = io.popen("test -d " .. source_path:gsub("'", "'\\''") .. " && echo yes || echo no")
        local result = handle:read("*a"):match("^%s*(.-)%s*$")
        handle:close()
        is_dir = (result == "yes")
        
        if not is_dir then
            return false, string.format("Error: source must be a .cz file or directory, got: %s", source_path)
        end
    end

    -- When building a binary, require a main function
    options.require_main = true

    -- Step 1: Compile to .c (calls compile.lua)
    local ok, c_path = compile_module.compile(source_path, options)
    if not ok then
        return false, c_path  -- c_path contains error message
    end

    -- Step 2: Compile C to binary
    local cc_cmd = string.format("cc %s -o %s 2>&1; echo \"EXIT_CODE:$?\"",
        shell_escape(c_path), shell_escape(output_path))
    local cc_output = io.popen(cc_cmd)
    local cc_result = cc_output:read("*a")
    cc_output:close()

    -- Extract exit code from output
    local exit_code = cc_result:match("EXIT_CODE:(%d+)")
    local compilation_output = cc_result:gsub("EXIT_CODE:%d+%s*$", "")

    if exit_code and tonumber(exit_code) ~= 0 then
        return false, "C compilation failed:\n" .. (compilation_output or "")
    end

    return true, output_path
end

return Build
