-- Name resolution utilities for type checker
-- Handles resolving identifiers to their declarations

local Resolver = {}

-- Resolve a name in the current scope stack
function Resolver.resolve_name(typechecker, name)
    return typechecker:get_var_info(name)
end

-- Resolve a struct type
function Resolver.resolve_struct(typechecker, type_name)
    return typechecker.structs[type_name]
end

-- Resolve a function or method
function Resolver.resolve_function(typechecker, type_name, func_name)
    local type_funcs = typechecker.functions[type_name]
    if type_funcs then
        return type_funcs[func_name]
    end
    return nil
end

return Resolver
