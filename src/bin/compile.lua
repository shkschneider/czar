-- compile module: generates both C and assembly from .cz source file
-- This depends on both c and s modules

local c_module = require("c")
local s_module = require("s")

local Compile = {}
Compile.__index = Compile

function Compile.compile(source_path, options)
    options = options or {}
    
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- Generate .c file
    local ok, c_path = c_module.cz_to_c(source_path, options)
    if not ok then
        return false, c_path  -- c_path contains error message
    end

    -- Generate .s file from .c file
    local ok, s_path = s_module.c_to_s(c_path)
    if not ok then
        return false, s_path  -- s_path contains error message
    end

    return true, { c_path = c_path, s_path = s_path }
end

return Compile
