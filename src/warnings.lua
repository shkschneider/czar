-- Warning reporting utilities
-- Provides consistent warning message formatting across all compiler phases

local Warnings = {}

-- Warning identifiers for different types of warnings
Warnings.WarningType = {
    -- Unused variable warnings
    UNUSED_VARIABLE = "UNUSED_VARIABLE",
    UNUSED_PARAMETER = "UNUSED_PARAMETER",
    UNUSED_IMPORT = "UNUSED_IMPORT",
    
    -- Type safety warnings
    UNSAFE_CAST = "UNSAFE_CAST",
    
    -- Pointer warnings
    POINTER_REASSIGNMENT = "POINTER_REASSIGNMENT",
    
    -- Enum warnings
    ENUM_VALUE_NOT_UPPERCASE = "ENUM_VALUE_NOT_UPPERCASE",
    
    -- Stack warnings
    STACK_WARNING = "STACK_WARNING",
}

-- Cache for source file contents
local source_cache = {}

-- Read a source file and cache it
local function read_source_file(filename)
    if source_cache[filename] then
        return source_cache[filename]
    end

    local handle, err = io.open(filename, "r")
    if not handle then
        return nil
    end

    local lines = {}
    for line in handle:lines() do
        table.insert(lines, line)
    end
    handle:close()

    source_cache[filename] = lines
    return lines
end

-- Convert warning ID from SCREAMING_SNAKE_CASE to lowercase-hyphenated format
local function format_warning_id(warning_id)
    if not warning_id then
        return "unknown-warning"
    end
    -- Convert SCREAMING_SNAKE_CASE to lowercase-hyphenated
    return warning_id:lower():gsub("_", "-")
end

-- Format a single warning message with multi-line format
-- filename: source filename (e.g., "program.cz")
-- line: line number (optional, can be nil or 0)
-- warning_id: warning identifier from WarningType
-- message: human-readable warning message
-- source_path: optional full path to source file for reading line content
-- function_name: optional function name for context
function Warnings.format(filename, line, warning_id, message, source_path, function_name)
    filename = filename or "<unknown>"
    warning_id = warning_id or "UNKNOWN_WARNING"

    -- If line is 0 or nil, we don't have good line info, so don't display it
    local display_line = line
    if not line or line == 0 then
        display_line = nil
    end

    -- Convert warning ID to lowercase-hyphenated format
    local formatted_warning_id = format_warning_id(warning_id)

    -- Build warning message in standard format: "WARNING in function() at filename:line warning-type"
    local prefix = "WARNING "
    if function_name then
        prefix = prefix .. string.format("in %s() ", function_name)
    end
    prefix = prefix .. "at "
    
    if display_line then
        prefix = prefix .. string.format("%s:%d", filename, display_line)
    else
        prefix = prefix .. filename
    end
    
    prefix = prefix .. " " .. formatted_warning_id

    -- Build warning message parts
    local parts = {}
    table.insert(parts, prefix)
    table.insert(parts, "\t" .. message)

    -- Try to add the source line if we have a valid line number
    if display_line and source_path then
        local source_lines = read_source_file(source_path)
        if source_lines and source_lines[display_line] then
            local source_line = source_lines[display_line]
            -- Trim leading whitespace but preserve indentation for display
            table.insert(parts, "\t> " .. source_line:gsub("^%s+", ""))
        end
    end

    return table.concat(parts, "\n")
end

-- Format multiple warnings
-- warnings: array of formatted warning messages
function Warnings.format_multiple(warnings)
    if #warnings == 0 then
        return nil
    end

    return table.concat(warnings, "\n")
end

-- Emit a warning to stderr
-- This is the primary way to report warnings during compilation
function Warnings.emit(filename, line, warning_id, message, source_path, function_name)
    local formatted = Warnings.format(filename, line, warning_id, message, source_path, function_name)
    io.stderr:write(formatted .. "\n")
end

-- Clear the source file cache (useful for testing or long-running processes)
function Warnings.clear_cache()
    source_cache = {}
end

return Warnings
