-- asm module: generates assembly from .cz or .c source file
-- Contains all assembly generation logic
-- Accepts .cz files (will compile to .c first) or .c files directly

local compile_module = require("compile")

local Asm = {}
Asm.__index = Asm

local function shell_escape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

function Asm.generate_asm(source_path, options)
    options = options or {}
    local c_file_path
    local cleanup_c = false

    -- If input is .cz, compile it to .c first
    if source_path:match("%.cz$") then
        local ok, c_path = compile_module.compile(source_path, options)
        if not ok then
            return false, c_path  -- c_path contains error message
        end
        c_file_path = c_path
    elseif source_path:match("%.c$") then
        -- It's already a .c file
        c_file_path = source_path
    else
        return false, string.format("Error: source file must have .cz or .c extension, got: %s", source_path)
    end

    -- Determine output path (.c -> .s, or .cz -> .s)
    local output_path
    if source_path:match("%.cz$") then
        output_path = source_path:gsub("%.cz$", ".s")
    else
        output_path = source_path:gsub("%.c$", ".s")
    end

    -- Compile C to assembly using cc -S
    local cmd = string.format("cc -S -o %s %s 2>&1", shell_escape(output_path), shell_escape(c_file_path))
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    local success = handle:close()

    if not success then
        return false, string.format("Assembly generation failed:\n%s", output)
    end

    return true, output_path
end

return Asm
