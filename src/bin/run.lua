-- Run module: builds and runs binary from .cz source file
-- Depends on build module (calls build.lua first, then runs and cleans up)

local build_module = require("build")

local Run = {}
Run.__index = Run

local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

function Run.run(source_path, options)
    options = options or {}
    
    -- Allow both .cz files and directories
    -- Validate that the source is either a .cz file or a directory
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

    -- When running a binary, require a main function
    options.require_main = true

    -- Step 1: Build binary (calls build.lua which calls compile.lua)
    local output_path = "a.out"
    local ok, result = build_module.build(source_path, output_path, options)
    if not ok then
        return false, result  -- result contains error message
    end

    -- Step 2: Run the binary and capture exit code
    local run_cmd = shell_escape("./" .. output_path)
    local ret = os.execute(run_cmd)

    local exit_code
    if type(ret) == "number" then
        -- LuaJIT/Lua 5.1 behavior: return value contains exit code shifted left by 8
        exit_code = math.floor(ret / 256)
    else
        -- Lua 5.2+ behavior: returns (true/nil, "exit", code)
        local ok, _, code = ret
        exit_code = code or (ok and 0 or 1)
    end

    -- Step 3: Clean up binary
    os.remove(output_path)

    return true, exit_code
end

return Run
