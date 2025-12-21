-- Typechecker validation functions
-- Handles validation of module names, main function, and imports

local Errors = require("errors")

local Validation = {}

-- Validate that a main function exists with the correct signature
function Validation.validate_main_function(typechecker)
    -- Check if main function exists in global functions
    local global_functions = typechecker.functions["__global__"]
    if not global_functions or not global_functions["main"] then
        local msg = "Missing 'main' function. When building a binary, a 'main' function with signature 'fn main() i32' is required"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, 0,
            Errors.ErrorType.MISSING_MAIN_FUNCTION, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return
    end

    -- Get the main function (handle overload array)
    local main_overloads = global_functions["main"]
    local main_func = nil
    if type(main_overloads) == "table" and #main_overloads > 0 then
        main_func = main_overloads[1]
    else
        main_func = main_overloads
    end
    
    -- Validate main function signature
    local Utils = require("typechecker.utils")

    -- Check return type (must be i32)
    local return_type = main_func.return_type
    local is_valid_return = return_type and
                           return_type.kind == "named_type" and
                           return_type.name == "i32"

    if not is_valid_return then
        local line = main_func.line or 0
        local actual_return = return_type and Utils.type_to_string(return_type) or "unknown"
        local msg = string.format(
            "Invalid 'main' function signature: return type must be i32, got %s. Expected signature: 'fn main() i32'",
            actual_return
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.INVALID_MAIN_SIGNATURE, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end

    -- Check parameters (must have no parameters)
    if main_func.params and #main_func.params > 0 then
        local line = main_func.line or 0
        local msg = string.format(
            "Invalid 'main' function signature: must have no parameters, got %d parameter(s). Expected signature: 'fn main() i32'",
            #main_func.params
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.INVALID_MAIN_SIGNATURE, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
end

-- Infer module name from directory structure
-- Returns the module name based on the file's path, or nil for top-level files
function Validation.infer_module_name(typechecker)
    if not typechecker.source_path then
        return nil
    end
    
    -- Extract directory structure from source path
    -- e.g., "mod1/file1.cz" -> ["mod1"]
    -- e.g., "mod2/submod1/test1.cz" -> ["mod2", "submod1"]
    local path_parts = {}
    for part in typechecker.source_path:gmatch("[^/]+") do
        table.insert(path_parts, part)
    end
    
    -- Remove the filename (last part)
    table.remove(path_parts)
    
    -- If no directory parts, this is a top-level file (no module)
    if #path_parts == 0 then
        return nil
    end
    
    -- Join directory parts with dots to create module name
    -- e.g., ["mod2", "submod1"] -> "mod2.submod1"
    return table.concat(path_parts, ".")
end

-- Validate that explicit #module declaration is valid
-- Rules: 
-- 1. Module names must be single words (no dots)
-- 2. #module can only be declared as an ancestor directory name
function Validation.validate_module_declaration(typechecker)
    if not typechecker.module_name or not typechecker.source_path then
        return
    end
    
    -- Module names must be single words (no dots allowed)
    if typechecker.module_name:find("%.") then
        local msg = string.format(
            "Module name '%s' is invalid. Module names must be single words (no dots). Use #module to specify an ancestor directory name.",
            typechecker.module_name
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, 0,
            Errors.ErrorType.INVALID_MODULE_NAME, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return
    end
    
    -- Extract directory structure from source path
    local path_parts = {}
    for part in typechecker.source_path:gmatch("[^/]+") do
        table.insert(path_parts, part)
    end
    
    -- Remove the filename (last part)
    table.remove(path_parts)
    
    -- Special case: "main" module can be declared anywhere (top-level entry point)
    if typechecker.module_name == "main" then
        return
    end
    
    -- If there's no directory (top-level file), any module declaration is invalid
    -- unless it's "main"
    if #path_parts == 0 then
        local msg = string.format(
            "Top-level files cannot declare module '%s'. Only 'main' module can be declared at top level.",
            typechecker.module_name
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, 0,
            Errors.ErrorType.INVALID_MODULE_NAME, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return
    end
    
    -- Validate that #module is one of the ancestor directory names
    -- e.g., for file "mod2/submod1/test1.cz", valid modules are: "mod2"
    -- The module must match one of the directories in the path
    local is_ancestor = false
    for _, dir in ipairs(path_parts) do
        if dir == typechecker.module_name then
            is_ancestor = true
            break
        end
    end
    
    if not is_ancestor then
        local msg = string.format(
            "Module '%s' cannot be declared in '%s'. Files can only declare modules that match ancestor directory names.",
            typechecker.module_name, 
            table.concat(path_parts, "/")
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, 0,
            Errors.ErrorType.INVALID_MODULE_NAME, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
end

-- Check for unused imports and generate warnings
function Validation.check_unused_imports(typechecker)
    local Warnings = require("warnings")
    
    -- Helper to extract the last component of a module path (e.g., "cz.io" -> "io")
    local function get_default_alias(module_path)
        return module_path:match("[^.]+$")
    end
    
    for _, import in ipairs(typechecker.imports) do
        if not import.used then
            local msg = string.format("Unused import '%s'", import.path)
            -- Only mention alias if it differs from the default
            if import.alias and import.alias ~= get_default_alias(import.path) then
                msg = string.format("Unused import '%s' (aliased as '%s')", import.path, import.alias)
            end
            
            Warnings.emit(typechecker.source_file, import.line or 0,
                Warnings.WarningType.UNUSED_IMPORT, msg, typechecker.source_path)
        end
    end
end

return Validation
