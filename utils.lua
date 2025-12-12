-- Utility module: shared helper functions

local function shell_escape(str)
    -- Escape shell metacharacters by wrapping in single quotes
    -- and escaping any single quotes in the string
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

return {
    shell_escape = shell_escape
}
