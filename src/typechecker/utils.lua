-- Typechecker utilities
-- Common helper functions used throughout the typechecker

local Utils = {}

-- Helper: Check if a block has a return statement in all paths
function Utils.block_has_return(typechecker, block)
    local statements = block.statements or block

    for _, stmt in ipairs(statements) do
        if stmt.kind == "return" then
            return true
        elseif stmt.kind == "if" then
            -- For if statements, all branches must have returns
            local then_has_return = Utils.block_has_return(typechecker, stmt.then_block)

            -- Check all elseif branches
            local all_elseif_have_return = true
            if stmt.elseif_branches then
                for _, branch in ipairs(stmt.elseif_branches) do
                    if not Utils.block_has_return(typechecker, branch.block) then
                        all_elseif_have_return = false
                        break
                    end
                end
            end

            -- Check else branch
            local else_has_return = stmt.else_block and Utils.block_has_return(typechecker, stmt.else_block) or false

            -- Only return true if we have an else and all branches return
            if stmt.else_block and then_has_return and all_elseif_have_return and else_has_return then
                return true
            end
        end
        -- Note: we don't check while loops as they might not execute
    end

    return false
end

-- Helper: Convert type to string for error messages
function Utils.type_to_string(type_node)
    if not type_node then
        return "unknown"
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "nullable" then
        return Utils.type_to_string(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        return Utils.type_to_string(type_node.element_type) .. "[" .. (type_node.size or "*") .. "]"
    elseif type_node.kind == "slice" then
        return Utils.type_to_string(type_node.element_type) .. "[:]"
    elseif type_node.kind == "varargs" then
        return Utils.type_to_string(type_node.element_type) .. "..."
    end

    return "unknown"
end

return Utils
