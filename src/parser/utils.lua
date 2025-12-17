-- Parser utilities
-- Common helper functions used throughout the parser

local Utils = {}

function Utils.token_label(tok)
    if not tok then return "<eof>" end
    return string.format("%s('%s') at %d:%d", tok.type, tok.value, tok.line, tok.col)
end

return Utils
