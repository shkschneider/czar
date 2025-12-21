-- Typechecker scope management utilities
-- Handles variable scopes and name lookups

local Scopes = {}

-- Push a new scope onto the stack
function Scopes.push_scope(typechecker)
    table.insert(typechecker.scope_stack, {})
end

-- Pop the current scope from the stack
function Scopes.pop_scope(typechecker)
    table.remove(typechecker.scope_stack)
end

-- Add a variable to the current scope
-- Returns true if successful, false if duplicate
function Scopes.add_var(typechecker, name, type_node, is_mutable)
    local scope = typechecker.scope_stack[#typechecker.scope_stack]
    
    -- Check if variable already exists in current scope
    if scope[name] then
        return false
    end
    
    scope[name] = {
        type = type_node,
        mutable = is_mutable or false
    }
    return true
end

-- Get variable information from scopes (searches from innermost to outermost)
function Scopes.get_var_info(typechecker, name)
    for i = #typechecker.scope_stack, 1, -1 do
        local var_info = typechecker.scope_stack[i][name]
        if var_info then
            return var_info
        end
    end
    return nil
end

return Scopes
