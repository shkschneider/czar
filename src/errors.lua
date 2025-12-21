-- Error reporting utilities
-- Provides consistent error message formatting across all compiler phases

local Errors = {}

-- Error identifiers for different types of errors
Errors.ErrorType = {
    -- Lexer errors
    LEXER_FAILED = "LEXER_FAILED",

    -- Parser errors
    PARSER_FAILED = "PARSER_FAILED",
    UNEXPECTED_TOKEN = "UNEXPECTED_TOKEN",
    EXPECTED_TOKEN = "EXPECTED_TOKEN",

    -- Type checking errors
    TYPE_CHECKING_FAILED = "TYPE_CHECKING_FAILED",
    TYPE_MISMATCH = "TYPE_MISMATCH",
    UNDECLARED_IDENTIFIER = "UNDECLARED_IDENTIFIER",
    FIELD_NOT_FOUND = "FIELD_NOT_FOUND",
    UNDEFINED_FUNCTION = "UNDEFINED_FUNCTION",
    UNDEFINED_STRUCT = "UNDEFINED_STRUCT",
    DUPLICATE_ALIAS = "DUPLICATE_ALIAS",
    DUPLICATE_STRUCT = "DUPLICATE_STRUCT",
    DUPLICATE_ENUM = "DUPLICATE_ENUM",
    DUPLICATE_FUNCTION = "DUPLICATE_FUNCTION",
    DUPLICATE_FIELD = "DUPLICATE_FIELD",
    DUPLICATE_PARAMETER = "DUPLICATE_PARAMETER",
    DUPLICATE_VARIABLE = "DUPLICATE_VARIABLE",
    INVALID_MODULE_NAME = "INVALID_MODULE_NAME",
    PRIVATE_ACCESS = "PRIVATE_ACCESS",
    MODULE_PRIVATE_ACCESS = "MODULE_PRIVATE_ACCESS",
    MISSING_METHOD = "MISSING_METHOD",
    MISSING_FIELD = "MISSING_FIELD",
    MISMATCHED_SIGNATURE = "MISMATCHED_SIGNATURE",
    INVALID_INTERFACE_CAST = "INVALID_INTERFACE_CAST",

    -- Pointer arithmetic errors
    POINTER_ARITHMETIC_FORBIDDEN = "POINTER_ARITHMETIC_FORBIDDEN",

    -- Nullable safety errors
    UNSAFE_NULLABLE_ASSIGNMENT = "UNSAFE_NULLABLE_ASSIGNMENT",
    UNSAFE_NULLABLE_ACCESS = "UNSAFE_NULLABLE_ACCESS",

    -- Array bounds errors
    ARRAY_INDEX_OUT_OF_BOUNDS = "ARRAY_INDEX_OUT_OF_BOUNDS",

    -- Arithmetic errors
    DIVISION_BY_ZERO = "DIVISION_BY_ZERO",

    -- Function return errors
    MISSING_RETURN = "MISSING_RETURN",
    VOID_FUNCTION_RETURNS_VALUE = "VOID_FUNCTION_RETURNS_VALUE",
    MISSING_MAIN_FUNCTION = "MISSING_MAIN_FUNCTION",
    INVALID_MAIN_SIGNATURE = "INVALID_MAIN_SIGNATURE",

    -- Memory safety errors
    LIFETIME_ANALYSIS_FAILED = "LIFETIME_ANALYSIS_FAILED",
    USE_AFTER_FREE = "USE_AFTER_FREE",
    RETURN_STACK_REFERENCE = "RETURN_STACK_REFERENCE",

    -- Mutability errors
    MUTABILITY_VIOLATION = "MUTABILITY_VIOLATION",
    CONST_QUALIFIER_DISCARDED = "CONST_QUALIFIER_DISCARDED",
    IMMUTABLE_VARIABLE = "IMMUTABLE_VARIABLE",

    -- Lowering errors
    LOWERING_FAILED = "LOWERING_FAILED",

    -- Code generation errors
    CODEGEN_FAILED = "CODEGEN_FAILED",
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

-- Convert error ID from SCREAMING_SNAKE_CASE to lowercase-hyphenated format
local function format_error_id(error_id)
    if not error_id then
        return "unknown-error"
    end
    -- Convert SCREAMING_SNAKE_CASE to lowercase-hyphenated
    return error_id:lower():gsub("_", "-")
end

-- Format a single error message with multi-line format
-- severity: "ERROR" or "WARNING"
-- filename: source filename (e.g., "program.cz")
-- line: line number (optional, can be nil or 0)
-- error_id: error identifier from ErrorType
-- message: human-readable error message
-- source_path: optional full path to source file for reading line content
-- function_name: optional function name for context
function Errors.format(severity, filename, line, error_id, message, source_path, function_name)
    severity = severity or "ERROR"
    filename = filename or "<unknown>"
    error_id = error_id or "UNKNOWN_ERROR"

    -- If line is 0 or nil, we don't have good line info, so don't display it
    -- This is better than showing line 0
    local display_line = line
    if not line or line == 0 then
        display_line = nil
    end

    -- Convert error ID to lowercase-hyphenated format
    local formatted_error_id = format_error_id(error_id)

    -- Build error message in unified format: "TYPE in function() at filename:line error-code"
    local prefix = severity
    if function_name then
        prefix = prefix .. string.format(" in %s()", function_name)
    end
    prefix = prefix .. " at " .. filename
    if display_line then
        prefix = prefix .. ":" .. display_line
    end
    prefix = prefix .. " " .. formatted_error_id

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

-- Format multiple errors with a phase header
-- phase: name of the compiler phase (e.g., "Type checking", "Analysis")
-- errors: array of formatted error messages
function Errors.format_phase_errors(phase, errors)
    if #errors == 0 then
        return nil
    end

    local lines = {}
    for _, err in ipairs(errors) do
        table.insert(lines, err)
    end

    return table.concat(lines, "\n")
end

-- Clear the source file cache (useful for testing or long-running processes)
function Errors.clear_cache()
    source_cache = {}
end

return Errors
