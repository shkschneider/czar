-- asm module: generates assembly from .c source file
-- Contains all assembly generation logic

local Asm = {}
Asm.__index = Asm

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

function Asm.c_to_asm(source_path)
    -- Validate that the source file has a .c extension
    if not source_path:match("%.c$") then
        return false, string.format("Error: source file must have .c extension, got: %s", source_path)
    end

    -- Check that the C file exists
    local content, err = read_file(source_path)
    if not content then
        return false, string.format("Failed to read '%s': %s", source_path, err or "unknown error")
    end

    -- Determine output path (.c -> .s)
    local output_path = source_path:gsub("%.c$", ".s")

    -- Compile C to assembly using cc -S
    local cmd = string.format("cc -S -o %s %s 2>&1", shell_escape(output_path), shell_escape(source_path))
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    local success = handle:close()

    if not success then
        return false, string.format("Assembly generation failed:\n%s", output)
    end

    return true, output_path
end

return Asm
