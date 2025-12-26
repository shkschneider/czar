-- Parser utility functions
-- Shared utilities to avoid circular dependencies between parser modules

local Utils = {}

-- Format a token into a human-readable label for error messages
-- @param tok: token table with type, value, line, and col fields (or nil for EOF)
-- @return string: formatted token label
function Utils.token_label(tok)
    if not tok then return "<eof>" end
    return string.format("%s('%s') at %d:%d", tok.type, tok.value, tok.line, tok.col)
end

return Utils
