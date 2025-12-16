-- format module: code formatter for .cz files
-- TODO: Not implemented yet

local Format = {}
Format.__index = Format

function Format.format(source_path)
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- TODO: Implement formatting
    return false, "Error: format command not implemented yet"
end

return Format
