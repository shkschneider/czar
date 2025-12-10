local lexer = require("lexer")
local parser = require("parser")
local codegen = require("codegen")

local function usage()
    io.stderr:write("Usage: lua main.lua <source.cz>\n")
end

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end

    local content = handle:read("*a")
    handle:close()
    return content
end

local function format_token(tok)
    local value = tok.value
    if value == "" then
        value = "(empty)"
    end
    return string.format("%-8s %-12s @ %d:%d", tok.type, value, tok.line, tok.col)
end

local function indent_lines(level)
    return string.rep("  ", level)
end

local function dump(value, level)
    level = level or 0
    local prefix = indent_lines(level)
    local t = type(value)
    if t == "table" then
        local parts = {"{\n"}
        for k, v in pairs(value) do
            table.insert(parts, string.format("%s  %s = %s\n", prefix, tostring(k), dump(v, level + 1)))
        end
        table.insert(parts, prefix .. "}")
        return table.concat(parts)
    elseif t == "string" then
        return string.format("\"%s\"", value)
    else
        return tostring(value)
    end
end

local function main()
    if not arg or #arg < 1 then
        usage()
        os.exit(1)
    end

    local path = arg[1]
    local source, err = read_file(path)
    if not source then
        io.stderr:write(string.format("Failed to read '%s': %s\n", path, err or "unknown error"))
        os.exit(1)
    end

    local tokens = lexer(source)
    -- print("Tokens:")
    -- for _, tok in ipairs(tokens) do
    --     print(format_token(tok))
    -- end

    local ast = parser(tokens)
    -- print("\nAST:")
    -- print(dump(ast))

    local c_source = codegen(ast)
    -- print("\nGenerated C:\n")
    print(c_source)
end

main()
