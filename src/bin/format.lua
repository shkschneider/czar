-- format module: code formatter for .cz files

local Format = {}
Format.__index = Format

-- Main formatting function
function Format.format(source_path)
    -- Validate that the source file has a .cz extension
    if not source_path:match("%.cz$") then
        return false, string.format("Error: source file must have .cz extension, got: %s", source_path)
    end

    -- Read the file
    local file, err = io.open(source_path, "r")
    if not file then
        return false, string.format("Error: cannot open file: %s", err)
    end

    local content = file:read("*a")
    file:close()

    -- Split into lines
    local lines = {}
    for line in content:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Remove trailing empty line if it exists
    if #lines > 0 and lines[#lines] == "" then
        table.remove(lines)
    end

    local formatted_lines = {}
    for _, line in ipairs(lines) do
        -- Trim trailing whitespace
        line = line:gsub("%s+$", "")

        -- Skip completely empty lines
        if line:match("^%s*$") then
            table.insert(formatted_lines, "")
        else
            -- TODO read all tokens
            -- TODO keep track of indent level
            -- TODO go through all tokens
            -- TODO add spaces around each token -> Vec2 p = < Vec2 > new Vec2 { }
            -- TODO then we'll remove unnecessary spaces after -> Vec2 p = <Vec2> new Vec2 {}
            table.insert(formatted_lines, line)
        end
    end

    -- Join lines and ensure final newline
    local formatted = table.concat(formatted_lines, "\n")
    if not formatted:match("\n$") then
        formatted = formatted .. "\n"
    end

    -- Write back to file
    file, err = io.open(source_path, "w")
    if not file then
        return false, string.format("Error: cannot write file: %s", err)
    end

    file:write(formatted)
    file:close()

    return true
end

return Format
