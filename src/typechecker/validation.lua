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

    -- Validate main function signature
    local main_func = global_functions["main"]
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

-- Validate module name follows directory structure rules
function Validation.validate_module_name(typechecker)
    if not typechecker.module_name or not typechecker.source_path then
        return
    end
    
    -- Extract directory structure from source path
    -- e.g., "tests/ok/app/geometry/point.cz" -> ["tests", "ok", "app", "geometry"]
    local path_parts = {}
    for part in typechecker.source_path:gmatch("[^/]+") do
        table.insert(path_parts, part)
    end
    
    -- Remove the filename (last part)
    table.remove(path_parts)
    
    -- Get module name parts
    local module_parts = {}
    for part in typechecker.module_name:gmatch("[^.]+") do
        table.insert(module_parts, part)
    end
    
    -- Exception: "main" module can be declared in any directory as an entry point
    local is_main_module = (#module_parts == 1 and module_parts[1] == "main")
    
    -- For multi-part module names, or single-part non-main modules in subdirectories:
    -- Module name must end with the directory name
    if #path_parts > 0 and not is_main_module then
        local dir_name = path_parts[#path_parts]
        
        -- Module name must end with the directory name
        -- e.g., module "app.geometry" in directory "geometry" is valid
        -- e.g., module "app" in directory "app" is valid
        -- e.g., module "examples" in directory "ok" is invalid
        -- e.g., module "app.math" in directory "geometry" is invalid
        if #module_parts > 0 and module_parts[#module_parts] ~= dir_name then
            local msg = string.format(
                "Module name '%s' must end with directory name '%s' (expected: '...%s'). Only 'main' module can be declared as entry point in any folder.",
                typechecker.module_name, dir_name, dir_name
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, 0,
                Errors.ErrorType.INVALID_MODULE_NAME, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
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
