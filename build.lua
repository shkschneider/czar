-- Build module: compiles C files to binary

local function shell_escape(str)
    -- Escape shell metacharacters by wrapping in single quotes
    -- and escaping any single quotes in the string
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

local function compile_c_to_binary(c_file_path, output_path)
    -- Compile C to binary with escaped paths, capture exit code properly
    local cc_cmd = string.format("cc %s -o %s 2>&1; echo \"EXIT_CODE:$?\"", 
        shell_escape(c_file_path), shell_escape(output_path))
    local cc_output = io.popen(cc_cmd)
    local cc_result = cc_output:read("*a")
    cc_output:close()
    
    -- Extract exit code from output
    local exit_code = cc_result:match("EXIT_CODE:(%d+)")
    local compilation_output = cc_result:gsub("EXIT_CODE:%d+%s*$", "")

    if exit_code and tonumber(exit_code) ~= 0 then
        return false, "C compilation failed:\n" .. (compilation_output or "")
    end

    return true, nil
end

local function run_binary(binary_path)
    -- Run the binary and capture exit code
    local run_cmd = shell_escape("./" .. binary_path)
    local ret = os.execute(run_cmd)
    
    -- In LuaJIT, os.execute returns the raw system return value
    -- The exit code is in the high byte (shifted left by 8), so we need to shift right by 8
    -- This is done via division by 256, which is equivalent to right-shifting by 8 bits
    -- Example: if program exits with code 42, os.execute returns 42 << 8 = 10752
    --          and we extract 42 via 10752 / 256 = 42
    if type(ret) == "number" then
        -- LuaJIT/Lua 5.1 behavior: return value contains exit code shifted left by 8
        local exit_code = math.floor(ret / 256)
        return exit_code
    else
        -- Lua 5.2+ behavior: returns (true/nil, "exit", code)
        local ok, _, code = ret
        if ok then
            return code or 0
        else
            return code or 1
        end
    end
end

return {
    compile_c_to_binary = compile_c_to_binary,
    run_binary = run_binary
}
