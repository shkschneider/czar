-- Call type inference
-- Handles function calls, method calls, and static method calls

local Resolver = require("typechecker.resolver")
local Errors = require("errors")

local Calls = {}

-- Forward declarations - will be set from init.lua
Calls.infer_type = nil
Calls.get_base_type_name = nil

-- Helper: Convert a field access expression to a dotted path string
-- Example: cz.fmt becomes "cz.fmt"
local function field_access_to_path(expr)
    if expr.kind == "identifier" then
        return expr.name
    elseif expr.kind == "field" then
        local base_path = field_access_to_path(expr.object)
        if base_path then
            return base_path .. "." .. expr.field
        end
    end
    return nil
end

-- Helper: Check if an expression represents an imported module
-- Returns the module path if it matches, nil otherwise
local function get_module_path_if_imported(typechecker, expr)
    local path = field_access_to_path(expr)
    if not path then
        return nil
    end
    
    -- Check if this path matches an imported module
    for _, import in ipairs(typechecker.imports) do
        if import.path == path then
            import.used = true
            return path
        end
    end
    
    return nil
end

-- Infer the type of a function call
function Calls.infer_call_type(typechecker, expr)
    if expr.callee.kind == "identifier" then
        local func_name = expr.callee.name
        
        -- Infer argument types for overload resolution
        local arg_types = {}
        for _, arg in ipairs(expr.args) do
            local arg_type = Calls.infer_type(typechecker, arg)
            table.insert(arg_types, arg_type)
        end
        
        local func_def = Resolver.resolve_function(typechecker, "__global__", func_name, arg_types)

        if func_def then
            -- Store the resolved overload in the expression for codegen
            expr.resolved_function = func_def
            
            -- Check caller-controlled mutability
            for i, arg in ipairs(expr.args) do
                if i <= #func_def.params then
                    local param = func_def.params[i]
                    local caller_allows_mut = (arg.kind == "mut_arg" and arg.allows_mutation)

                    -- If callee wants mut but caller doesn't give it, error
                    if param.mutable and param.type.kind == "nullable" and not caller_allows_mut then
                        local line = expr.line or 0
                        local msg = string.format(
                            "Function '%s' parameter %d requires mutable pointer (mut %s*), but caller passes immutable. Use 'mut' at call site.",
                            func_name, i, param.type.to.name or "Type"
                        )
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.MUTABILITY_VIOLATION, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    end
                end
            end

            expr.inferred_type = func_def.return_type
            return func_def.return_type
        else
            local line = expr.line or (expr.callee and expr.callee.line) or 0
            local msg = string.format("Undefined function: %s", func_name)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    elseif expr.callee.kind == "method_ref" then
        -- Handle method reference calls (e.g., obj:method())
        local obj_type = Calls.infer_type(typechecker, expr.callee.object)
        if not obj_type then
            return nil
        end
        
        -- Special handling for string methods with : syntax
        if obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string") then
            local method = expr.callee.method
            if method == "append" then
                local return_type = { kind = "named_type", name = "void" }
                expr.inferred_type = return_type
                return return_type
            elseif method == "substring" then
                local return_type = { kind = "nullable", to = { kind = "string" } }
                expr.inferred_type = return_type
                return return_type
            elseif method == "find" or method == "index" then
                local return_type = { kind = "named_type", name = "i32" }
                expr.inferred_type = return_type
                return return_type
            elseif method == "contains" then
                local return_type = { kind = "named_type", name = "i32" }
                expr.inferred_type = return_type
                return return_type
            elseif method == "cut" then
                local return_type = { kind = "nullable", to = { kind = "string" } }
                expr.inferred_type = return_type
                return return_type
            elseif method == "prefix" or method == "suffix" then
                local return_type = { kind = "named_type", name = "i32" }
                expr.inferred_type = return_type
                return return_type
            elseif method == "upper" or method == "lower" then
                local return_type = { kind = "nullable", to = { kind = "string" } }
                expr.inferred_type = return_type
                return return_type
            elseif method == "trim" or method == "ltrim" or method == "rtrim" then
                local return_type = { kind = "nullable", to = { kind = "string" } }
                expr.inferred_type = return_type
                return return_type
            elseif method == "cstr" then
                local return_type = { kind = "nullable", to = { kind = "named_type", name = "i8" } }
                expr.inferred_type = return_type
                return return_type
            end
        end

        local type_name = Calls.get_base_type_name(obj_type)
        local method_def = Resolver.resolve_function(typechecker, type_name, expr.callee.method)

        if method_def then
            -- Check if method is private (prv keyword)
            if method_def.is_private then
                -- Private method can only be called from within methods of the same struct
                local is_internal_call = false
                if typechecker.current_function and typechecker.current_function.receiver_type then
                    if typechecker.current_function.receiver_type == type_name then
                        is_internal_call = true
                    end
                end
                
                if not is_internal_call then
                    local line = expr.line or (expr.callee and expr.callee.object and expr.callee.object.line) or 0
                    local msg = string.format(
                        "Cannot call private method '%s()' in '%s'",
                        expr.callee.method, type_name
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.PRIVATE_ACCESS, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                    return nil
                end
            end
            
            expr.inferred_type = method_def.return_type
            return method_def.return_type
        else
            local line = expr.line or (expr.callee and expr.callee.object and expr.callee.object.line) or 0
            local msg = string.format(
                "Method '%s' not found on type '%s'",
                expr.callee.method, type_name or "unknown"
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    elseif expr.callee.kind == "field" then
        -- Handle field-based method calls (e.g., obj.method())
        local obj_type = Calls.infer_type(typechecker, expr.callee.object)
        if not obj_type then
            return nil
        end
        
        -- Check if this is a method call on a module (e.g., fmt.println())
        if obj_type.kind == "module" then
            -- Transform to static method call
            expr.kind = "static_method_call"
            expr.type_name = obj_type.path
            expr.method = expr.callee.field
            -- Copy args if needed (they should already be in expr.args)
            return Calls.infer_static_method_call_type(typechecker, expr)
        end
        
        -- Special handling for string.cstr() method
        if obj_type.kind == "string" and expr.callee.field == "cstr" then
            -- cstr() returns char* (pointer to i8)
            local return_type = { kind = "nullable", to = { kind = "named_type", name = "i8" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string*.cstr() method
        if obj_type.kind == "nullable" and obj_type.to.kind == "string" and expr.callee.field == "cstr" then
            -- cstr() returns char* (pointer to i8)
            local return_type = { kind = "nullable", to = { kind = "named_type", name = "i8" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:append(str) method
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and expr.callee.field == "append" then
            -- append() modifies in place, returns void (but we'll return the string pointer for chaining)
            local return_type = { kind = "named_type", name = "void" }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:substring(start, end) method
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and expr.callee.field == "substring" then
            -- substring() returns a new heap-allocated string*
            local return_type = { kind = "nullable", to = { kind = "string" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:find(needle) or string:index(needle) method
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and (expr.callee.field == "find" or expr.callee.field == "index") then
            -- find/index() returns i32 (index or -1)
            local return_type = { kind = "named_type", name = "i32" }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:contains(needle) method
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and expr.callee.field == "contains" then
            -- contains() returns i32 (bool: 1 or 0)
            local return_type = { kind = "named_type", name = "i32" }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:cut(separator) method
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and expr.callee.field == "cut" then
            -- cut() returns a new heap-allocated string*
            local return_type = { kind = "nullable", to = { kind = "string" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:prefix(str) and string:suffix(str) methods
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and (expr.callee.field == "prefix" or expr.callee.field == "suffix") then
            -- prefix/suffix() returns i32 (bool: 1 or 0)
            local return_type = { kind = "named_type", name = "i32" }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:upper() and string:lower() methods
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and (expr.callee.field == "upper" or expr.callee.field == "lower") then
            -- upper/lower() modifies in place, returns string* (for chaining)
            local return_type = { kind = "nullable", to = { kind = "string" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Special handling for string:trim/ltrim/rtrim() methods
        if (obj_type.kind == "string" or (obj_type.kind == "nullable" and obj_type.to.kind == "string")) and 
           (expr.callee.field == "trim" or expr.callee.field == "ltrim" or expr.callee.field == "rtrim") then
            -- trim() modifies in place, returns string* (for chaining)
            local return_type = { kind = "nullable", to = { kind = "string" } }
            expr.inferred_type = return_type
            return return_type
        end
        
        -- Try to resolve as a method on the type
        local type_name = Calls.get_base_type_name(obj_type)
        local method_def = Resolver.resolve_function(typechecker, type_name, expr.callee.field)
        
        if method_def then
            -- Check if method is private (prv keyword)
            if method_def.is_private then
                -- Private method can only be called from within methods of the same struct
                local is_internal_call = false
                if typechecker.current_function and typechecker.current_function.receiver_type then
                    if typechecker.current_function.receiver_type == type_name then
                        is_internal_call = true
                    end
                end
                
                if not is_internal_call then
                    local line = expr.line or (expr.callee and expr.callee.object and expr.callee.object.line) or 0
                    local msg = string.format(
                        "Cannot call private method '%s()' in '%s'",
                        expr.callee.field, type_name
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.PRIVATE_ACCESS, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                    return nil
                end
            end
            
            expr.inferred_type = method_def.return_type
            return method_def.return_type
        else
            local line = expr.line or (expr.callee and expr.callee.object and expr.callee.object.line) or 0
            local msg = string.format(
                "Method '%s' not found on type '%s'",
                expr.callee.field, type_name or "unknown"
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    return nil
end

-- Infer the type of a method call
function Calls.infer_method_call_type(typechecker, expr)
    -- Check if this is a method call on an imported module alias
    -- For example: fmt.println() where fmt is an alias for cz.fmt
    if expr.object.kind == "identifier" then
        local obj_name = expr.object.name
        for _, import in ipairs(typechecker.imports) do
            if import.alias == obj_name then
                -- This is a static method call on a module
                import.used = true
                expr.kind = "static_method_call"
                expr.type_name = import.path
                return Calls.infer_static_method_call_type(typechecker, expr)
            end
        end
    end
    
    -- If object already has a module type, handle it
    local obj_type = Calls.infer_type(typechecker, expr.object)
    if obj_type and obj_type.kind == "module" then
        -- This is a method call on a module
        expr.kind = "static_method_call"
        expr.type_name = obj_type.path
        return Calls.infer_static_method_call_type(typechecker, expr)
    end
    
    if not obj_type then
        return nil
    end

    local type_name = Calls.get_base_type_name(obj_type)
    local method_def = Resolver.resolve_function(typechecker, type_name, expr.method)

    if method_def then
        -- Check if method is private (prv keyword)
        if method_def.is_private then
            -- Private method can only be called from within methods of the same struct
            local is_internal_call = false
            if typechecker.current_function and typechecker.current_function.receiver_type then
                if typechecker.current_function.receiver_type == type_name then
                    is_internal_call = true
                end
            end
            
            if not is_internal_call then
                local line = expr.line or (expr.object and expr.object.line) or 0
                local msg = string.format(
                    "Cannot call private method '%s()' in '%s'",
                    expr.method, type_name
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.PRIVATE_ACCESS, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
        end
        
        expr.inferred_type = method_def.return_type
        return method_def.return_type
    else
        local line = expr.line or (expr.object and expr.object.line) or 0
        local msg = string.format(
            "Method '%s' not found on type '%s'",
            expr.method, type_name or "unknown"
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.UNDEFINED_FUNCTION, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return nil
    end
end

-- Infer the type of a static method call
function Calls.infer_static_method_call_type(typechecker, expr)
    -- Special handling for C module functions (C interop)
    if expr.type_name == "C" then
        -- Check if any C headers are imported
        if #typechecker.c_imports == 0 then
            local Errors = require("errors")
            local msg = string.format("C module must be imported to use C.%s(). Use 'import C : header.h' where header.h contains the function you want to call.", expr.method)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- For C interop, we trust the user knows what they're doing
        -- We assume C functions return void unless we have more type info
        -- In the future, we could parse headers or maintain a database
        local return_type = { kind = "named_type", name = "void" }
        expr.inferred_type = return_type
        return return_type
    end
    
    -- Generic handling for stdlib modules (cz.fmt, cz.os, etc.)
    if expr.type_name:match("^cz%.") then
        -- Check if this specific module is imported
        local module_imported = false
        local module_alias = nil
        for _, import in ipairs(typechecker.imports) do
            if import.path == expr.type_name then
                module_imported = true
                module_alias = import.alias
                import.used = true
                break
            end
        end
        
        if not module_imported then
            local Errors = require("errors")
            local alias_hint = expr.type_name:match("%.([^.]+)$") or expr.type_name
            local msg = string.format("Module '%s' must be imported to use %s.%s() (use: #import %s)", 
                expr.type_name, alias_hint, expr.method, expr.type_name)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- Handle specific module functions
        if expr.type_name == "cz.fmt" then
            -- Return type for fmt module functions
            if expr.method == "print" or expr.method == "println" or expr.method == "printf" then
                local void_type = { kind = "named_type", name = "void" }
                expr.inferred_type = void_type
                return void_type
            else
                local Errors = require("errors")
                local msg = string.format("Unknown function '%s.%s()'", module_alias or "fmt", expr.method)
                local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                    Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
                return nil
            end
        end
        
        -- For other cz.* modules, we can add handling here as needed
        -- For now, return void as a default
        local void_type = { kind = "named_type", name = "void" }
        expr.inferred_type = void_type
        return void_type
    end
    
    -- Legacy handling for old cz module (deprecated - use cz.fmt instead)
    if expr.type_name == "cz" then
        -- Check if cz module is imported
        local cz_imported = false
        for _, import in ipairs(typechecker.imports) do
            if import.path == "cz" or import.alias == "cz" then
                cz_imported = true
                import.used = true -- Mark as used
                break
            end
        end
        
        if not cz_imported then
            local Errors = require("errors")
            local msg = string.format("Module 'cz' must be imported to use cz.%s()", expr.method)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
        
        -- Return type for cz module functions
        if expr.method == "print" or expr.method == "println" or expr.method == "printf" then
            local void_type = { kind = "named_type", name = "void" }
            expr.inferred_type = void_type
            return void_type
        else
            local Errors = require("errors")
            local msg = string.format("Unknown function 'cz.%s()'", expr.method)
            local formatted_error = Errors.format("ERROR", typechecker.source_file, expr.line or 0,
                Errors.ErrorType.UNDECLARED_IDENTIFIER, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
            return nil
        end
    end

    local method_def = Resolver.resolve_function(typechecker, expr.type_name, expr.method)

    if method_def then
        expr.inferred_type = method_def.return_type
        return method_def.return_type
    else
        typechecker:add_error(string.format(
            "Static method '%s' not found on type '%s'",
            expr.method, expr.type_name
        ))
        return nil
    end
end

return Calls
