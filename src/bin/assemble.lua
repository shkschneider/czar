-- Assemble module: generates assembly code from .cz or .c source file
-- Wraps the C compilation process to output assembly instead of binary

local generate = require("generate")

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function write_file(content, output_path)
    local handle, err = io.open(output_path, "w")
    if not handle then
        return false, string.format("Failed to create '%s': %s", output_path, err or "unknown error")
    end
    handle:write(content)
    handle:close()
    return true, nil
end

local function assemble_to_asm(source_path)
    -- Determine if source is .cz or .c
    local c_source
    local c_file_path
    local cleanup_c = false

    if source_path:match("%.cz$") then
        -- Generate C code from .cz file
        local c_code, err = generate.generate_c(source_path)
        if not c_code then
            return nil, err
        end
        c_source = c_code

        -- Write to temporary C file (named after source file)
        c_file_path = generate.make_temp_path(source_path, ".c")
        local ok, err = write_file(c_source, c_file_path)
        if not ok then
            return nil, err
        end
        cleanup_c = true
    elseif source_path:match("%.c$") then
        -- Read C file
        local content, err = read_file(source_path)
        if not content then
            return nil, string.format("Failed to read '%s': %s", source_path, err or "unknown error")
        end
        c_source = content
        c_file_path = source_path
    else
        return nil, string.format("Source file must have .c or .cz extension, got: %s", source_path)
    end

    -- Compile C to assembly using cc -S
    local asm_temp = generate.make_temp_path(source_path, ".s")
    local cmd = string.format("cc -S -o %s %s 2>&1", asm_temp, c_file_path)
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    local success = handle:close()

    -- Clean up temporary C file if we created one
    if cleanup_c then
        os.remove(c_file_path)
    end

    if not success then
        return nil, string.format("Assembly generation failed:\n%s", output)
    end

    -- Read the assembly file
    local asm_content, err = read_file(asm_temp)
    os.remove(asm_temp)

    if not asm_content then
        return nil, string.format("Failed to read assembly output: %s", err or "unknown error")
    end

    return asm_content, nil
end

return {
    assemble_to_asm = assemble_to_asm,
    write_file = write_file,
    read_file = read_file
}
