-- Name resolution utilities for type checker
-- Handles resolving identifiers to their declarations

local Resolver = {}

-- Helper: Convert type to string for signature matching
local function type_to_signature_string(type_node)
    if not type_node then
        return "unknown"
    end
    
    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "nullable" then
        return type_to_signature_string(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        return type_to_signature_string(type_node.element_type) .. "[" .. (type_node.size or "*") .. "]"
    elseif type_node.kind == "slice" then
        return type_to_signature_string(type_node.element_type) .. "[:]"
    elseif type_node.kind == "varargs" then
        return type_to_signature_string(type_node.element_type) .. "..."
    end
    
    return "unknown"
end

-- Resolve a name in the current scope stack
function Resolver.resolve_name(typechecker, name)
    return typechecker:get_var_info(name)
end

-- Resolve a struct type
function Resolver.resolve_struct(typechecker, type_name)
    return typechecker.structs[type_name]
end

-- Resolve a function or method
-- Returns the best matching overload based on signature
function Resolver.resolve_function(typechecker, type_name, func_name, arg_types)
    local type_funcs = typechecker.functions[type_name]
    if not type_funcs then
        return nil
    end
    
    local overloads = type_funcs[func_name]
    if not overloads then
        return nil
    end
    
    -- If no arg_types provided, return first overload (backward compatibility)
    if not arg_types then
        if type(overloads) == "table" and #overloads > 0 then
            return overloads[1]
        end
        return overloads
    end
    
    -- Find matching overload based on argument types
    for _, overload in ipairs(overloads) do
        local matches = true
        if #overload.params ~= #arg_types then
            matches = false
        else
            for i = 1, #arg_types do
                local param_type = overload.params[i].type
                local arg_type = arg_types[i]
                
                -- Simple type matching (can be enhanced later)
                local param_type_str = type_to_signature_string(param_type)
                local arg_type_str = type_to_signature_string(arg_type)
                
                if param_type_str ~= arg_type_str then
                    matches = false
                    break
                end
            end
        end
        
        if matches then
            return overload
        end
    end
    
    -- No exact match found - if there's only one overload, return it anyway
    -- (for non-overloaded functions, type checking will catch mismatches)
    if #overloads == 1 then
        return overloads[1]
    end
    
    return nil
end

return Resolver
