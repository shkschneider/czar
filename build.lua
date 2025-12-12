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

return {
    compile_c_to_binary = compile_c_to_binary
}
