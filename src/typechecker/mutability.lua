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
        -- Field mutability depends on whether we're accessing through a pointer or value
        if target.object.kind == "identifier" then
            local var_info = Resolver.resolve_name(typechecker, target.object.name)
            if not var_info then
                -- Don't report error here - let the expression type checker handle it
                return false
            end
            
            -- If the variable is a pointer type, we can always modify through it
            -- (the pointed-to memory, not the pointer itself)
            if var_info.type and var_info.type.kind == "pointer" then
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
    end
    
    -- Other targets (e.g., dereferences) - for now, allow them
    return true
end

return Mutability
