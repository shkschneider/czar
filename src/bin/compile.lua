-- compile module: generates C code from .cz source file
-- Contains all transpilation logic (lexer, parser, typechecker, lowering, analysis, codegen)
-- This is the main compilation step that produces .c files
--
-- Returns:
--   success, result, exit_code
--   - success (boolean): true if compilation succeeded, false otherwise
--   - result (string): output file path on success, error message on failure
--   - exit_code (number): 0 on success, phase-specific error code on failure:
--       1 = lexer error
--       2 = parser error  
--       3 = typechecker error
--       4 = lowering error
--       5 = analysis error
--       6 = codegen error
--       7 = file write error

local lexer = require("lexer")
local parser = require("parser")
local typechecker = require("typechecker")
local lowering = require("lowering")
local analysis = require("analysis")
local codegen = require("codegen")

local Compile = {}
Compile.__index = Compile

local function read_file(path)
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function write_file(content, output_path)
    local handle, err = io.open(output_path, "w")
    if not handle then
        return false, string.format("Failed to create '%s': %s", output_path, err or "unknown error")
    end
    handle:write(content)
    handle:close()
    return true, nil
end

-- Check if path is a directory
local function is_directory(path)
    local handle = io.popen("test -d " .. path:gsub("'", "'\\''") .. " && echo yes || echo no")
    local result = handle:read("*a"):match("^%s*(.-)%s*$")
    handle:close()
    return result == "yes"
end

-- Get all .cz files from a directory (non-recursive)
local function get_cz_files_in_dir(dir)
    local files = {}
    local handle = io.popen("find " .. dir:gsub("'", "'\\''") .. " -maxdepth 1 -type f -name '*.cz' 2>/dev/null | sort")
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

-- Merge multiple ASTs into one
-- This combines items and imports from all files
local function merge_asts(asts, main_file)
    if #asts == 0 then
        return nil, "No ASTs to merge"
    end
    
    if #asts == 1 then
        return asts[1]
    end
    
    -- Use the first AST as the base
    local merged = {
        kind = "program",
        items = {},
        imports = {},
        module = asts[1].module,  -- Use module from first file if any
    }
    
    -- Collect all imports and items
    for _, ast in ipairs(asts) do
        -- Merge imports
        for _, import in ipairs(ast.imports or {}) do
            table.insert(merged.imports, import)
        end
        
        -- Merge items (functions, structs, enums, etc.)
        for _, item in ipairs(ast.items or {}) do
            table.insert(merged.items, item)
        end
    end
    
    return merged
end

-- Compile a single file or directory to C code
function Compile.compile(source_path, options)
    options = options or {}
    
    -- Check if source_path is a directory
    if is_directory(source_path) then
        -- Multi-file compilation
        local cz_files = get_cz_files_in_dir(source_path)
        
        if #cz_files == 0 then
            return false, string.format("Error: no .cz files found in directory: %s", source_path), 1
        end
        
        -- Find main.cz as the primary file
        local main_file = nil
        for _, file in ipairs(cz_files) do
            if file:match("main%.cz$") then
                main_file = file
                break
            end
        end
        
        if not main_file then
            -- Use first file if no main.cz found
            main_file = cz_files[1]
        end
        
        -- Parse all files
        local asts = {}
        for _, file in ipairs(cz_files) do
            local source, err = read_file(file)
            if not source then
                return false, string.format("Failed to read '%s': %s", file, err or "unknown error"), 1
            end
            
            -- Lex
            local ok, tokens = pcall(lexer, source)
            if not ok then
                local clean_error = tokens:gsub("^%[string [^%]]+%]:%d+: ", "")
                local line_match = clean_error:match("at (%d+)")
                if line_match then
                    return false, string.format("ERROR at %s:%s lexer-error\n\t%s", file, line_match, clean_error), 1
                else
                    return false, string.format("ERROR at %s lexer-error\n\t%s", file, clean_error), 1
                end
            end
            
            -- Parse
            local ok, ast = pcall(parser, tokens, source)
            if not ok then
                local clean_error = ast:gsub("^%[string [^%]]+%]:%d+: ", "")
                local line_match = clean_error:match("at (%d+)")
                if line_match then
                    return false, string.format("ERROR at %s:%s parser-error\n\t%s", file, line_match, clean_error), 2
                else
                    return false, string.format("ERROR at %s parser-error\n\t%s", file, clean_error), 2
                end
            end
            
            table.insert(asts, ast)
        end
        
        -- Merge ASTs
        local merged_ast, err = merge_asts(asts, main_file)
        if not merged_ast then
            return false, string.format("Error merging ASTs: %s", err), 2
        end
        
        -- Use main file for naming
        local filename = main_file:match("([^/]+)$") or "main.cz"
        options.source_file = filename
        options.source_path = main_file
        
        -- Continue with typechecking, lowering, analysis, codegen using merged AST
        local ok, typed_ast = pcall(typechecker, merged_ast, options)
        if not ok then
            local clean_error = typed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            return false, clean_error, 3
        end
        
        local ok, lowered_ast = pcall(lowering, typed_ast, options)
        if not ok then
            local clean_error = lowered_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            return false, string.format("ERROR lowering-error\n\t%s", clean_error), 4
        end
        
        local ok, analyzed_ast = pcall(analysis, lowered_ast, options)
        if not ok then
            local clean_error = analyzed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            return false, string.format("ERROR analysis-error\n\t%s", clean_error), 5
        end
        
        local ok, c_source = pcall(codegen, analyzed_ast, options)
        if not ok then
            local clean_error = c_source:gsub("^%[string [^%]]+%]:%d+: ", "")
            return false, string.format("ERROR codegen-error\n\t%s", clean_error), 6
        end
        
        -- Determine output path - use main file name
        local output_path = main_file:gsub("%.cz$", ".c")
        
        -- Write C file
        local ok, err = write_file(c_source, output_path)
        if not ok then
            return false, err, 7
        end
        
        return true, output_path, 0
    else
        -- Single file compilation (original behavior)
        -- Validate that the source file has a .cz extension
        if not source_path:match("%.cz$") then
            return false, string.format("Error: source file must have .cz extension, got: %s", source_path), 1
        end

        -- Extract just the filename (not the full path) for #FILE
        local filename = source_path:match("([^/]+)$") or source_path
        options.source_file = filename
        options.source_path = source_path  -- Full path for reading source lines
        
        -- Read source file
        local source, err = read_file(source_path)
        if not source then
            return false, string.format("Failed to read '%s': %s", source_path, err or "unknown error"), 1
        end

        -- Lex
        local ok, tokens = pcall(lexer, source)
        if not ok then
            local clean_error = tokens:gsub("^%[string [^%]]+%]:%d+: ", "")
            -- Extract line number if present in lexer error
            local line_match = clean_error:match("at (%d+)")
            if line_match then
                return false, string.format("ERROR at %s:%s lexer-error\n\t%s", source_path, line_match, clean_error), 1
            else
                return false, string.format("ERROR at %s lexer-error\n\t%s", source_path, clean_error), 1
            end
        end

        -- Parse (pass source for #unsafe blocks)
        local ok, ast = pcall(parser, tokens, source)
        if not ok then
            local clean_error = ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            -- Extract line number if present in error
            local line_match = clean_error:match("at (%d+)")
            if line_match then
                return false, string.format("ERROR at %s:%s parser-error\n\t%s", source_path, line_match, clean_error), 2
            else
                return false, string.format("ERROR at %s parser-error\n\t%s", source_path, clean_error), 2
            end
        end

        -- Type check
        local ok, typed_ast = pcall(typechecker, ast, options)
        if not ok then
            local clean_error = typed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            return false, clean_error, 3
        end

        -- Lowering
        local ok, lowered_ast = pcall(lowering, typed_ast, options)
        if not ok then
            local clean_error = lowered_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            -- Extract line number if present
            local line_match = clean_error:match("at (%d+)")
            if line_match then
                return false, string.format("ERROR at %s:%s lowering-error\n\t%s", source_path, line_match, clean_error), 4
            else
                return false, string.format("ERROR at %s lowering-error\n\t%s", source_path, clean_error), 4
            end
        end

        -- Analysis
        local ok, analyzed_ast = pcall(analysis, lowered_ast, options)
        if not ok then
            local clean_error = analyzed_ast:gsub("^%[string [^%]]+%]:%d+: ", "")
            -- Extract line number if present
            local line_match = clean_error:match("at (%d+)")
            if line_match then
                return false, string.format("ERROR at %s:%s analysis-error\n\t%s", source_path, line_match, clean_error), 5
            else
                return false, string.format("ERROR at %s analysis-error\n\t%s", source_path, clean_error), 5
            end
        end

        -- Generate C code
        local ok, c_source = pcall(codegen, analyzed_ast, options)
        if not ok then
            local clean_error = c_source:gsub("^%[string [^%]]+%]:%d+: ", "")
            -- Extract line number if present in error
            local line_match = clean_error:match("line (%d+)")
            if line_match then
                return false, string.format("ERROR at %s:%s codegen-error\n\t%s", source_path, line_match, clean_error), 6
            else
                return false, string.format("ERROR at %s codegen-error\n\t%s", source_path, clean_error), 6
            end
        end

        -- Determine output path (.cz -> .c)
        local output_path = source_path:gsub("%.cz$", ".c")

        -- Write C file
        local ok, err = write_file(c_source, output_path)
        if not ok then
            return false, err, 7
        end

        return true, output_path, 0
    end
end

return Compile
