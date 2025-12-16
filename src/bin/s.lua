-- s module: generates assembly from .c source file
-- This is a thin wrapper around the assemble module

local assemble = require("assemble")

local S = {}
S.__index = S

function S.c_to_s(source_path)
    -- Validate that the source file has a .c extension
    if not source_path:match("%.c$") then
        return false, string.format("Error: source file must have .c extension, got: %s", source_path)
    end

    -- Generate assembly code
    local asm_source, err = assemble.assemble_to_asm(source_path)
    if not asm_source then
        return false, err
    end

    -- Determine output path (.c -> .s)
    local output_path = source_path:gsub("%.c$", ".s")

    -- Write assembly file
    local ok, err = assemble.write_file(asm_source, output_path)
    if not ok then
        return false, err
    end

    return true, output_path
end

return S
