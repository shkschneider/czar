-- c module: generates C code from .cz source file
-- This is a thin wrapper around the generate module

local generate = require("generate")

local C = {}
C.__index = C

function C.cz_to_c(source_path, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- Generate C code
    local c_source, err = generate.generate_c(source_path, options)
    if not c_source then
        return false, err
    end

    -- Determine output path (.cz -> .c)
    local output_path = source_path:gsub("%.cz$", ".c")

    -- Write C file
    local ok, err = generate.write_c_file(c_source, output_path)
    if not ok then
        return false, err
    end

    return true, output_path
end

return C
