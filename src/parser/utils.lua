-- Parser utilities
local Utils = {}

-- Get a human-readable label for a token
function Utils.token_label(tok)
    if not tok then
        return "EOF"
    end
    if tok.type == "IDENT" then
        return string.format("identifier '%s'", tok.value)
    elseif tok.type == "NUMBER" then
        return string.format("number '%s'", tok.value)
    elseif tok.type == "STRING" then
        return string.format("string '%s'", tok.value)
    else
        return tok.type
    end
end

return Utils
