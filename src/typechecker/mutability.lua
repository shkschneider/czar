-- Mutability checking utilities
-- Enforces mutability rules: writes only to mut bindings, parameter mutability, etc.

local Resolver = require("typechecker.resolver")

local Mutability = {}

-- Check if a target expression is mutable
function Mutability.check_mutable_target(typechecker, target)
    if target.kind == "identifier" then
        local var_info = Resolver.resolve_name(typechecker, target.name)
        if not var_info then
            -- Don't report error here - let the expression type checker handle it
            return false
        end
        
        if not var_info.mutable then
            typechecker:add_error(string.format(
                "Cannot assign to immutable variable '%s'",
                target.name
            ))
            return false
        end
        
        return true
    elseif target.kind == "field" then
        -- Field mutability depends on whether we're accessing through a nullable reference or value
        if target.object.kind == "identifier" then
            local var_info = Resolver.resolve_name(typechecker, target.object.name)
            if not var_info then
                -- Don't report error here - let the expression type checker handle it
                return false
            end
            
            -- If the variable is a nullable reference type, check if it's mutable
            if var_info.type and var_info.type.kind == "nullable" then
                -- For nullable references: need the variable to be marked as mutable to modify through it
                -- This enforces: Vec2? p = const (cannot modify), mut Vec2? p = mutable
                if not var_info.mutable then
                    local type_name = "Type"
                    if var_info.type.to and var_info.type.to.name then
                        type_name = var_info.type.to.name
                    end
                    typechecker:add_error(string.format(
                        "Cannot assign to field '%s' through immutable reference '%s'. Use 'mut %s?' to allow modification.",
                        target.field,
                        target.object.name,
                        type_name
                    ))
                    return false
                end
                return true
            end
            
            -- If it's a value type, the variable itself must be mutable
            if not var_info.mutable then
                typechecker:add_error(string.format(
                    "Cannot assign to field '%s' of immutable variable '%s'",
                    target.field,
                    target.object.name
                ))
                return false
            end
            
            return true
        end
        
        -- Recursively check nested field accesses
        return Mutability.check_mutable_target(typechecker, target.object)
    elseif target.kind == "index" then
        -- Array/slice indexing: check if the array itself is mutable
        -- For index expressions, we need to check the base array
        if target.array.kind == "identifier" then
            local var_info = Resolver.resolve_name(typechecker, target.array.name)
            if not var_info then
                -- Don't report error here - let the expression type checker handle it
                return false
            end
            
            -- Check if the array/slice variable is mutable
            if not var_info.mutable then
                local Errors = require("errors")
                local line = target.line or target.array.line or 0
                local formatted_error = Errors.format(
                    "ERROR",
                    typechecker.source_file,
                    line,
                    Errors.ErrorType.IMMUTABLE_VARIABLE,
                    string.format("Cannot modify element of immutable array/slice '%s'. Use 'mut' to allow modification.", target.array.name),
                    typechecker.source_path
                )
                typechecker:add_error(formatted_error)
                return false
            end
            
            return true
        end
        
        -- Recursively check nested index accesses
        return Mutability.check_mutable_target(typechecker, target.array)
    end
    
    -- Other targets (e.g., dereferences) - for now, allow them
    return true
end

return Mutability
