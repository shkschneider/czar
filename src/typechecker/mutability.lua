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
        -- In the implicit pointer model, field mutability comes from the variable
        if target.object.kind == "identifier" then
            local var_info = Resolver.resolve_name(typechecker, target.object.name)
            if not var_info then
                -- Don't report error here - let the expression type checker handle it
                return false
            end
            
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
