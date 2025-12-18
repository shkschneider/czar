-- Typechecker statement checking
-- Handles type checking of statements

local Errors = require("errors")
local Resolver = require("typechecker.resolver")
local Inference = require("typechecker.inference")
local Mutability = require("typechecker.mutability")
local Scopes = require("typechecker.scopes")

local Statements = {}

-- Type check a block of statements
function Statements.check_block(typechecker, block)
    local statements = block.statements or block
    for _, stmt in ipairs(statements) do
        Statements.check_statement(typechecker, stmt)
    end
end

-- Type check a single statement
function Statements.check_statement(typechecker, stmt)
    if stmt.kind == "var_decl" then
        Statements.check_var_decl(typechecker, stmt)
    elseif stmt.kind == "assign" then
        Statements.check_assign(typechecker, stmt)
    elseif stmt.kind == "if" then
        Statements.check_if(typechecker, stmt)
    elseif stmt.kind == "while" then
        Statements.check_while(typechecker, stmt)
    elseif stmt.kind == "for" then
        Statements.check_for(typechecker, stmt)
    elseif stmt.kind == "repeat" then
        Statements.check_repeat(typechecker, stmt)
    elseif stmt.kind == "break" then
        Statements.check_break(typechecker, stmt)
    elseif stmt.kind == "continue" then
        Statements.check_continue(typechecker, stmt)
    elseif stmt.kind == "return" then
        Statements.check_return(typechecker, stmt)
    elseif stmt.kind == "expr_stmt" then
        -- Check if the expression is an assignment
        if stmt.expression and stmt.expression.kind == "assign" then
            Statements.check_assign(typechecker, stmt.expression)
        else
            Inference.infer_type(typechecker, stmt.expr or stmt.expression)
        end
    elseif stmt.kind == "free" then
        Inference.infer_type(typechecker, stmt.expr)
    end
end

-- Type check a variable declaration
function Statements.check_var_decl(typechecker, stmt)
    local var_type = stmt.type
    local is_mutable = stmt.mutable or false

    -- Check if trying to declare a mutable slice (not allowed)
    if var_type.kind == "slice" and is_mutable then
        local line = stmt.line or 0
        local msg = "Slices cannot be declared as mutable"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end

    -- Handle implicit array size (Type[*])
    if var_type.kind == "array" and var_type.size == "*" then
        if not stmt.init then
            local line = stmt.line or 0
            local msg = "Arrays with implicit size must have an initializer"
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        else
            local init_type = Inference.infer_type(typechecker, stmt.init)

            -- Check that initializer is an array literal or array
            if init_type and init_type.kind == "array" then
                -- Infer the size from the initializer
                var_type.size = init_type.size
                stmt.type = var_type

                -- Check element type compatibility
                if not Inference.types_compatible(var_type.element_type, init_type.element_type, typechecker) then
                    local line = stmt.line or 0
                    local msg = string.format(
                        "Array element type mismatch: expected %s, got %s",
                        Inference.type_to_string(var_type.element_type),
                        Inference.type_to_string(init_type.element_type)
                    )
                    local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                        Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                    typechecker:add_error(formatted_error)
                end
            else
                local line = stmt.line or 0
                local msg = "Implicit array size requires array literal or array initializer"
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
        end
    elseif stmt.init then
        -- Type check the initializer if present (for non-implicit arrays)
        local init_type = Inference.infer_type(typechecker, stmt.init)

        -- Check type compatibility
        if not Inference.types_compatible(var_type, init_type, typechecker) then
            -- Types don't match exactly - check if implicit cast is safe
            local can_implicit_cast = false
            
            -- Helper: Check if cast is a safe widening cast or literal-to-type
            local function is_safe_implicit_cast(from_type, to_type, init_expr)
                if not from_type or not to_type then
                    return false
                end
                
                -- Both must be named types (primitive types)
                if from_type.kind ~= "named_type" or to_type.kind ~= "named_type" then
                    return false
                end
                
                local from_name = from_type.name
                local to_name = to_type.name
                
                -- Define type sizes and signedness
                local type_info = {
                    i8 = {size = 8, signed = true},
                    i16 = {size = 16, signed = true},
                    i32 = {size = 32, signed = true},
                    i64 = {size = 64, signed = true},
                    u8 = {size = 8, signed = false},
                    u16 = {size = 16, signed = false},
                    u32 = {size = 32, signed = false},
                    u64 = {size = 64, signed = false},
                    f32 = {size = 32, signed = true, float = true},
                    f64 = {size = 64, signed = true, float = true},
                }
                
                local from_info = type_info[from_name]
                local to_info = type_info[to_name]
                
                if not from_info or not to_info then
                    return false
                end
                
                -- If init is a literal integer and target is any integer type, allow it
                -- This allows: u8 x = 10, i32 y = 42, etc.
                if init_expr and init_expr.kind == "int" and not to_info.float then
                    -- Check if the literal value fits in the target type
                    local value = init_expr.value
                    if to_info.signed then
                        -- Signed types: check range
                        local max = 2^(to_info.size - 1) - 1
                        local min = -(2^(to_info.size - 1))
                        if value >= min and value <= max then
                            return true
                        end
                    else
                        -- Unsigned types: check non-negative and fits
                        local max = 2^to_info.size - 1
                        if value >= 0 and value <= max then
                            return true
                        end
                    end
                end
                
                -- Otherwise, safe if same signedness and target is larger or equal
                return from_info.signed == to_info.signed and to_info.size >= from_info.size
            end
            
            can_implicit_cast = is_safe_implicit_cast(init_type, var_type, stmt.init)
            
            if can_implicit_cast then
                -- Wrap initializer in implicit cast node
                stmt.init = {
                    kind = "implicit_cast",
                    target_type = var_type,
                    expr = stmt.init,
                    line = stmt.line
                }
                -- Update the inferred type
                init_type = var_type
            else
                -- Error: incompatible types
                local line = stmt.line or 0
                local msg = string.format(
                    "Type mismatch in variable '%s': expected %s, got %s",
                    stmt.name,
                    Inference.type_to_string(var_type),
                    Inference.type_to_string(init_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
        end

        -- Annotate the initializer with its type
        stmt.init.inferred_type = init_type
    end

    -- Add variable to scope
    Scopes.add_var(typechecker, stmt.name, var_type, is_mutable)

    -- Annotate the statement with type information
    stmt.resolved_type = var_type
end

-- Type check an assignment
function Statements.check_assign(typechecker, stmt)
    -- Check if target is mutable
    if not Mutability.check_mutable_target(typechecker, stmt.target) then
        -- Mutability check failed, don't continue with type checking
        return
    end

    -- Type check both sides
    local target_type = Inference.infer_type(typechecker, stmt.target)
    local value_type = Inference.infer_type(typechecker, stmt.value)

    -- Check type compatibility
    if not Inference.types_compatible(target_type, value_type, typechecker) then
        local line = stmt.line or (stmt.target and stmt.target.line) or 0
        local msg = string.format(
            "Type mismatch in assignment: expected %s, got %s",
            Inference.type_to_string(target_type),
            Inference.type_to_string(value_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end

    -- Check const-correctness: cannot assign immutable value to mutable target
    -- This prevents discarding const qualifiers in generated C code
    if stmt.value.kind == "identifier" then
        local value_var_info = Resolver.resolve_name(typechecker, stmt.value.name)
        if value_var_info and not value_var_info.mutable then
            -- Value is immutable (const in C)
            -- Check if target needs a mutable value
            local target_needs_mut = false

            if stmt.target.kind == "identifier" then
                local target_var_info = Resolver.resolve_name(typechecker, stmt.target.name)
                target_needs_mut = target_var_info and target_var_info.mutable
            elseif stmt.target.kind == "field" and stmt.target.object.kind == "identifier" then
                local obj_var_info = Resolver.resolve_name(typechecker, stmt.target.object.name)
                -- Field assignment to mutable object means we need non-const value
                target_needs_mut = obj_var_info and obj_var_info.mutable
            end

            if target_needs_mut and value_type and value_type.kind == "nullable" then
                local line = stmt.line or stmt.value.line or 0
                local msg = string.format(
                    "Cannot assign immutable pointer '%s' to mutable location. The value has const qualifier. Use 'mut %s' if you need to reassign it.",
                    stmt.value.name,
                    stmt.value.name
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.CONST_QUALIFIER_DISCARDED, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            end
        end
    end
end

-- Type check an if statement
function Statements.check_if(typechecker, stmt)
    -- Type check condition
    local cond_type = Inference.infer_type(typechecker, stmt.condition)

    -- Condition should be bool
    if not Inference.is_bool_type(cond_type) then
        local line = stmt.line or (stmt.condition and stmt.condition.line) or 0
        local msg = string.format(
            "Condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg)
        typechecker:add_error(formatted_error)
    end

    -- Type check branches
    Scopes.push_scope(typechecker)
    Statements.check_block(typechecker, stmt.then_block)
    Scopes.pop_scope(typechecker)

    -- Handle elseif branches
    if stmt.elseif_branches then
        for _, branch in ipairs(stmt.elseif_branches) do
            local branch_cond_type = Inference.infer_type(typechecker, branch.condition)
            if not Inference.is_bool_type(branch_cond_type) then
                local line = branch.line or (branch.condition and branch.condition.line) or 0
                local msg = string.format(
                    "Elseif condition must be bool, got %s",
                    Inference.type_to_string(branch_cond_type)
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg)
                typechecker:add_error(formatted_error)
            end
            Scopes.push_scope(typechecker)
            Statements.check_block(typechecker, branch.block)
            Scopes.pop_scope(typechecker)
        end
    end

    if stmt.else_block then
        Scopes.push_scope(typechecker)
        Statements.check_block(typechecker, stmt.else_block)
        Scopes.pop_scope(typechecker)
    end
end

-- Type check a while statement
function Statements.check_while(typechecker, stmt)
    -- Type check condition
    local cond_type = Inference.infer_type(typechecker, stmt.condition)

    -- Condition should be bool
    if not Inference.is_bool_type(cond_type) then
        local line = stmt.line or (stmt.condition and stmt.condition.line) or 0
        local msg = string.format(
            "While condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg)
        typechecker:add_error(formatted_error)
    end

    -- Type check body (increment loop depth for break/continue)
    typechecker.loop_depth = typechecker.loop_depth + 1
    Scopes.push_scope(typechecker)
    Statements.check_block(typechecker, stmt.body)
    Scopes.pop_scope(typechecker)
    typechecker.loop_depth = typechecker.loop_depth - 1
end

-- Type check a for statement
function Statements.check_for(typechecker, stmt)
    local Utils = require("typechecker.utils")
    
    -- Type check the collection
    local collection_type = Inference.infer_type(typechecker, stmt.collection)

    if not collection_type then
        return
    end

    -- Collection must be an array, slice, or varargs
    if collection_type.kind ~= "array" and collection_type.kind ~= "slice" and collection_type.kind ~= "varargs" then
        local line = stmt.line or (stmt.collection and stmt.collection.line) or 0
        local msg = string.format(
            "For loop collection must be an array, slice, or varargs, got '%s'",
            Utils.type_to_string(collection_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
        return
    end

    -- Check if trying to iterate with mut item on immutable collection
    if stmt.item_mutable and not stmt.item_is_underscore then
        -- Get the collection mutability
        local collection_is_mutable = false
        if stmt.collection.kind == "identifier" then
            local var_info = Scopes.get_var_info(typechecker, stmt.collection.name)
            if var_info then
                collection_is_mutable = var_info.mutable
            end
        end

        -- If collection is not mutable, item cannot be mut
        if not collection_is_mutable then
            local line = stmt.line or 0
            local msg = string.format(
                "Cannot declare mutable item '%s' when iterating over immutable collection",
                stmt.item_name
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end

        -- Slices and varargs are always read-only
        if collection_type.kind == "slice" or collection_type.kind == "varargs" then
            local line = stmt.line or 0
            local msg = string.format(
                "Cannot declare mutable item '%s' when iterating over %s (slices and varargs are read-only)",
                stmt.item_name,
                collection_type.kind
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end
    end

    -- Type check body in new scope (increment loop depth for break/continue)
    typechecker.loop_depth = typechecker.loop_depth + 1
    Scopes.push_scope(typechecker)

    -- Add index variable to scope (always i32)
    if not stmt.index_is_underscore and stmt.index_name then
        Scopes.add_var(typechecker, stmt.index_name, { kind = "named_type", name = "i32" }, false)
    end

    -- Add item variable to scope with element type
    if not stmt.item_is_underscore and stmt.item_name then
        local element_type = collection_type.element_type
        if stmt.item_mutable then
            -- Mutable item: pointer to element
            local pointer_type = { kind = "nullable", to = element_type }
            Scopes.add_var(typechecker, stmt.item_name, pointer_type, true)
        else
            -- Immutable item: value copy
            Scopes.add_var(typechecker, stmt.item_name, element_type, false)
        end
    end

    Statements.check_block(typechecker, stmt.body)
    Scopes.pop_scope(typechecker)
    typechecker.loop_depth = typechecker.loop_depth - 1
end

-- Type check a repeat statement
function Statements.check_repeat(typechecker, stmt)
    -- Type check count expression
    local count_type = Inference.infer_type(typechecker, stmt.count)

    -- Count must be an integer type (i8, i16, i32, i64, u8, u16, u32, u64)
    local is_int_type = count_type and
                        count_type.kind == "named_type" and
                        count_type.name:match("^[iu]%d+$") ~= nil

    if not is_int_type then
        local line = stmt.line or (stmt.count and stmt.count.line) or 0
        local msg = string.format(
            "Repeat count must be an integer type, got %s",
            Inference.type_to_string(count_type)
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end

    -- Type check body (increment loop depth for break/continue)
    typechecker.loop_depth = typechecker.loop_depth + 1
    Scopes.push_scope(typechecker)
    Statements.check_block(typechecker, stmt.body)
    Scopes.pop_scope(typechecker)
    typechecker.loop_depth = typechecker.loop_depth - 1
end

-- Type check a break statement
function Statements.check_break(typechecker, stmt)
    local level = stmt.level or 1  -- Default to 1 if not specified

    if typechecker.loop_depth == 0 then
        local line = stmt.line or 0
        local msg = "Break statement must be inside a loop"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    elseif level > typechecker.loop_depth then
        local line = stmt.line or 0
        local msg = string.format(
            "Break level %d exceeds loop depth %d",
            level, typechecker.loop_depth
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    elseif level < 1 then
        local line = stmt.line or 0
        local msg = string.format(
            "Break level must be at least 1, got %d",
            level
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
end

-- Type check a continue statement
function Statements.check_continue(typechecker, stmt)
    local level = stmt.level or 1  -- Default to 1 if not specified

    if typechecker.loop_depth == 0 then
        local line = stmt.line or 0
        local msg = "Continue statement must be inside a loop"
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    elseif level > typechecker.loop_depth then
        local line = stmt.line or 0
        local msg = string.format(
            "Continue level %d exceeds loop depth %d",
            level, typechecker.loop_depth
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    elseif level < 1 then
        local line = stmt.line or 0
        local msg = string.format(
            "Continue level must be at least 1, got %d",
            level
        )
        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, typechecker.source_path)
        typechecker:add_error(formatted_error)
    end
end

-- Type check a return statement
function Statements.check_return(typechecker, stmt)
    if stmt.value then
        -- Check if we're in a void function
        if typechecker.current_function and
           typechecker.current_function.return_type.kind == "named_type" and
           typechecker.current_function.return_type.name == "void" then
            local line = stmt.line or 0
            local msg = string.format(
                "Function '%s' has void return type but is returning a value",
                typechecker.current_function.name
            )
            local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                Errors.ErrorType.VOID_FUNCTION_RETURNS_VALUE, msg, typechecker.source_path)
            typechecker:add_error(formatted_error)
        end

        local return_type = Inference.infer_type(typechecker, stmt.value)

        -- Note: In the new pointer model, all types are implicitly pass-by-reference
        -- The check for returning stack variables is no longer needed here
        -- as the type system now handles this through nullable vs non-nullable types
    end
end

return Statements
