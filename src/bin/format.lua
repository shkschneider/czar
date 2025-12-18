-- format module: code formatter for .cz files

local Format = {}
Format.__index = Format

-- Split line into tokens for easier processing
local function tokenize_line(line)
    local tokens = {}
    local i = 1
    local in_string = false
    local in_char = false
    local string_delim = nil
    local current_token = ""
    local token_type = "other"
    
    while i <= #line do
        local char = line:sub(i, i)
        local next_char = i < #line and line:sub(i + 1, i + 1) or ""
        
        -- Handle escape sequences
        if (in_string or in_char) and char == '\\' and i < #line then
            current_token = current_token .. char .. next_char
            i = i + 2
            goto continue
        end
        
        -- Handle strings
        if char == '"' and not in_char then
            if in_string then
                current_token = current_token .. char
                table.insert(tokens, {type = "string", value = current_token})
                current_token = ""
                in_string = false
            else
                if current_token ~= "" then
                    table.insert(tokens, {type = token_type, value = current_token})
                end
                current_token = char
                in_string = true
            end
            i = i + 1
            goto continue
        end
        
        -- Handle char literals
        if char == "'" and not in_string then
            if in_char then
                current_token = current_token .. char
                table.insert(tokens, {type = "char", value = current_token})
                current_token = ""
                in_char = false
            else
                if current_token ~= "" then
                    table.insert(tokens, {type = token_type, value = current_token})
                end
                current_token = char
                in_char = true
            end
            i = i + 1
            goto continue
        end
        
        if in_string or in_char then
            current_token = current_token .. char
            i = i + 1
            goto continue
        end
        
        -- Handle comments
        if char == '/' and next_char == '/' then
            if current_token ~= "" then
                table.insert(tokens, {type = token_type, value = current_token})
            end
            table.insert(tokens, {type = "comment", value = line:sub(i)})
            break
        end
        
        -- Handle whitespace
        if char:match("%s") then
            if current_token ~= "" then
                table.insert(tokens, {type = token_type, value = current_token})
                current_token = ""
            end
            i = i + 1
            goto continue
        end
        
        -- Handle special characters
        if char:match("[%(%){%}%[%],;:]") then
            if current_token ~= "" then
                table.insert(tokens, {type = token_type, value = current_token})
                current_token = ""
            end
            table.insert(tokens, {type = "punct", value = char})
            i = i + 1
            goto continue
        end
        
        -- Handle operators (including multi-char)
        local two_char = line:sub(i, i + 1)
        if two_char:match("^[=!<>]=") or two_char:match("^[&|%+%-*/%%]=") or 
           two_char == "<<" or two_char == ">>" or two_char == "&&" or two_char == "||" or two_char == "->" then
            if current_token ~= "" then
                table.insert(tokens, {type = token_type, value = current_token})
                current_token = ""
            end
            table.insert(tokens, {type = "op", value = two_char})
            i = i + 2
            goto continue
        end
        
        if char:match("[%+%-*/%%=<>&|!]") then
            if current_token ~= "" then
                table.insert(tokens, {type = token_type, value = current_token})
                current_token = ""
            end
            table.insert(tokens, {type = "op", value = char})
            i = i + 1
            goto continue
        end
        
        -- Regular character (identifier, number, etc.)
        current_token = current_token .. char
        i = i + 1
        
        ::continue::
    end
    
    if current_token ~= "" then
        table.insert(tokens, {type = token_type, value = current_token})
    end
    
    return tokens
end

-- Format a line based on tokens
local function format_line_tokens(tokens)
    local result = ""
    local i = 1
    
    while i <= #tokens do
        local token = tokens[i]
        local prev = i > 1 and tokens[i - 1] or nil
        local next = i < #tokens and tokens[i + 1] or nil
        
        if token.type == "string" or token.type == "char" then
            result = result .. token.value
        elseif token.type == "comment" then
            -- Add space before comment if not already there
            if prev and not result:match(" $") then
                result = result .. "  "
            end
            result = result .. token.value
        elseif token.type == "punct" then
            if token.value == "(" then
                -- No space before (
                result = result .. token.value
                -- No space after ( unless at end
            elseif token.value == ")" then
                -- No space before )
                result = result .. token.value
                -- Space after ) if followed by { or type/identifier
                if next then
                    if next.type == "punct" and next.value == "{" then
                        result = result .. " "
                    elseif next.type == "other" then
                        result = result .. " "
                    end
                end
            elseif token.value == "{" then
                -- Space before { (unless first token or already has space)
                if prev and not result:match(" $") then
                    result = result .. " "
                end
                result = result .. token.value
                -- No space after { at end of line
            elseif token.value == "}" then
                -- No space before }
                result = result .. token.value
                -- Space after } if not at end
                if next and next.type ~= "punct" or (next and next.value == "{") then
                    result = result .. " "
                end
            elseif token.value == "[" then
                -- Check if this is array type (prev token is type name)
                if prev and prev.type == "other" and prev.value:match("^[%w_]+$") then
                    -- Array type like "i32[]" - no space before
                    result = result .. token.value
                else
                    -- Array literal - space before only if not already there
                    if prev and not result:match(" $") then
                        result = result .. " "
                    end
                    result = result .. token.value
                end
            elseif token.value == "]" then
                result = result .. token.value
                -- Space after ] in array type declaration
                if next and next.type == "other" then
                    result = result .. " "
                elseif next and next.type == "punct" and (next.value == "," or next.value == ")") then
                    -- No space before comma or )
                else
                    -- Space after ] in other contexts
                    if next then
                        result = result .. " "
                    end
                end
            elseif token.value == "," then
                result = result .. token.value
                -- Space after comma
                if next then
                    result = result .. " "
                end
            elseif token.value == ";" then
                result = result .. token.value
                -- Space after semicolon if not at end
                if next then
                    result = result .. " "
                end
            elseif token.value == ":" then
                result = result .. token.value
                -- Space after colon only for named parameters (when inside function calls)
                -- No space for method names (when between two identifiers with no prior ( or ,)
                local prev2 = i > 2 and tokens[i - 2] or nil
                local is_method = false
                
                if prev and prev.type == "other" and next and next.type == "other" then
                    -- Check if this is a method declaration (fn Type:method)
                    if not prev2 or (prev2.type == "other" and prev2.value == "fn") then
                        is_method = true
                    end
                end
                
                if not is_method and next then
                    result = result .. " "
                end
            end
        elseif token.type == "op" then
            -- Check if - or + is unary
            local is_unary = false
            if (token.value == "-" or token.value == "+") and next and next.type == "other" then
                -- Check if previous token indicates this is unary
                if not prev or 
                   (prev.type == "punct" and (prev.value == "(" or prev.value == "," or prev.value == "{" or prev.value == "[")) or
                   (prev.type == "op") or
                   (prev.type == "other" and (prev.value == "return" or prev.value == "if" or prev.value == "while")) then
                    is_unary = true
                end
            end
            
            if is_unary then
                -- Unary operator - space before if after keyword
                if prev and prev.type == "other" and (prev.value == "return" or prev.value == "if" or prev.value == "while") then
                    result = result .. " "
                end
                result = result .. token.value
            -- Check if * is pointer type or multiplication
            elseif token.value == "*" and next and next.type == "other" and 
               prev and prev.type == "other" then
                -- Need to determine if this is "Type* var" or "a * b"
                -- Pointer types typically follow type names (i32, string, etc.)
                -- and are followed by variable names, and appear after ) or , or at start of statement
                local is_pointer = false
                
                -- Look further back to see context
                local prev2 = i > 2 and tokens[i - 2] or nil
                if prev2 and prev2.type == "punct" and (prev2.value == "(" or prev2.value == ",") then
                    -- Pattern: "fn foo(Type* var" or "fn foo(Type x, Type* y"
                    is_pointer = true
                elseif not prev2 then
                    -- Pattern at start: "Type* var"
                    is_pointer = true
                end
                
                if is_pointer then
                    -- Pointer type: Type* var
                    result = result .. token.value .. " "
                else
                    -- Regular operator - spaces around
                    if prev then
                        result = result .. " "
                    end
                    result = result .. token.value
                    if next then
                        result = result .. " "
                    end
                end
            else
                -- Regular operator - spaces around
                if prev and not is_unary then
                    result = result .. " "
                end
                result = result .. token.value
                if next then
                    result = result .. " "
                end
            end
        else
            -- Other token (identifier, keyword, number)
            -- Space before if previous was identifier/keyword and this is too
            if prev and prev.type == "other" then
                result = result .. " "
            end
            result = result .. token.value
        end
        
        i = i + 1
    end
    
    return result
end

-- Get indentation level for a line
local function get_indent_level(line, prev_level)
    local level = prev_level or 0
    local trimmed = line:match("^%s*(.-)%s*$")
    
    -- If line starts with }, decrease indent
    if trimmed:match("^}") then
        level = math.max(0, level - 1)
    end
    
    -- Count braces
    local opens = 0
    local closes = 0
    local in_string = false
    local in_char = false
    
    for i = 1, #trimmed do
        local char = trimmed:sub(i, i)
        local prev_char = i > 1 and trimmed:sub(i - 1, i - 1) or ""
        
        if char == '"' and prev_char ~= '\\' and not in_char then
            in_string = not in_string
        elseif char == "'" and prev_char ~= '\\' and not in_string then
            in_char = not in_char
        elseif not in_string and not in_char then
            if char == '{' then
                opens = opens + 1
            elseif char == '}' then
                closes = closes + 1
            end
        end
    end
    
    local next_level = level + opens - closes
    if trimmed:match("^}") then
        next_level = next_level + 1
    end
    
    return level, math.max(0, next_level)
end

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
    
    -- Format each line
    local formatted_lines = {}
    local indent_level = 0
    
    for _, line in ipairs(lines) do
        -- Trim trailing whitespace
        line = line:gsub("%s+$", "")
        
        -- Skip completely empty lines
        if line:match("^%s*$") then
            table.insert(formatted_lines, "")
        else
            -- Tokenize and format
            local tokens = tokenize_line(line)
            local formatted = format_line_tokens(tokens)
            
            -- Get indent level
            local current_level, next_level = get_indent_level(formatted, indent_level)
            
            -- Remove existing indentation
            formatted = formatted:gsub("^%s+", "")
            
            -- Apply new indentation (4 spaces per level)
            local indent = string.rep("    ", current_level)
            formatted = indent .. formatted
            
            table.insert(formatted_lines, formatted)
            indent_level = next_level
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
