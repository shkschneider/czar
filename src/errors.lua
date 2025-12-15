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
    
    -- Pointer arithmetic errors
    POINTER_ARITHMETIC_FORBIDDEN = "POINTER_ARITHMETIC_FORBIDDEN",
    
    -- Array bounds errors
    ARRAY_INDEX_OUT_OF_BOUNDS = "ARRAY_INDEX_OUT_OF_BOUNDS",
    
    -- Memory safety errors
    LIFETIME_ANALYSIS_FAILED = "LIFETIME_ANALYSIS_FAILED",
    USE_AFTER_FREE = "USE_AFTER_FREE",
    RETURN_STACK_REFERENCE = "RETURN_STACK_REFERENCE",
    
    -- Mutability errors
    MUTABILITY_VIOLATION = "MUTABILITY_VIOLATION",
    CONST_QUALIFIER_DISCARDED = "CONST_QUALIFIER_DISCARDED",
    
    -- Lowering errors
    LOWERING_FAILED = "LOWERING_FAILED",
    
    -- Code generation errors
    CODEGEN_FAILED = "CODEGEN_FAILED",
}

-- Format a single error message
-- severity: "ERROR" or "WARNING"
-- filename: source filename (e.g., "program.cz")
-- line: line number (optional, can be nil)
-- error_id: error identifier from ErrorType
-- message: human-readable error message
function Errors.format(severity, filename, line, error_id, message)
    severity = severity or "ERROR"
    filename = filename or "<unknown>"
    error_id = error_id or "UNKNOWN_ERROR"
    
    local location
    if line then
        location = string.format("%s:%d", filename, line)
    else
        location = filename
    end
    
    return string.format("%s %s %s %s", severity, location, error_id, message)
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

return Errors
