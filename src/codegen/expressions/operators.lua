-- Operator and cast expression generation
-- Handles: unsafe_cast, safe_cast, clone, binary, unary, is_check, type_of, sizeof, null_check, assign, compound_assign

local Operators = {}

local function ctx() return _G.Codegen end

-- Generate unsafe cast expression
function Operators.gen_unsafe_cast(expr, gen_expr_fn)
    -- Unsafe cast: <Type> expr !!
    -- Only emit warning for explicit unsafe casts (with !!)
    local Warnings = require("warnings")
    local target_type_str = ctx():c_type(expr.target_type)
    local source_type = ctx():infer_type(expr.expr)
    local source_type_str = source_type and ctx():type_name_string(source_type) or "unknown"
    
    -- Helper: Check if cast is a safe widening cast
    local function is_safe_widening_cast(from_type, to_type)
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
        }
        
        local from_info = type_info[from_name]
        local to_info = type_info[to_name]
        
        if not from_info or not to_info then
            return false
        end
        
        -- Safe if same signedness and target is larger or equal
        return from_info.signed == to_info.signed and to_info.size >= from_info.size
    end
    
    -- Only emit warning for explicit unsafe casts (with !!)
    if not is_safe_widening_cast(source_type, expr.target_type) and expr.explicit_unsafe then
        Warnings.emit(
            ctx().source_file,
            expr.line,
            Warnings.WarningType.UNSAFE_CAST,
            string.format("Explicit unsafe cast from '%s' to '%s' (!!)", 
                source_type_str, target_type_str),
            ctx().source_path,
            ctx().current_function
        )
    end
    
    local expr_str = gen_expr_fn(expr.expr)
    
    -- Handle pointer casting
    if expr.target_type.kind == "pointer" then
        target_type_str = ctx():c_type(expr.target_type.to) .. "*"
    end

    return string.format("((%s)%s)", target_type_str, expr_str)
end

-- Generate safe cast expression
function Operators.gen_safe_cast(expr, gen_expr_fn)
    -- Safe cast: <Type> expr ?? fallback
    -- Cast both expr and fallback to target type
    local target_type_str = ctx():c_type(expr.target_type)
    local expr_str = gen_expr_fn(expr.expr)
    local fallback_str = gen_expr_fn(expr.fallback)
    
    -- Handle pointer casting
    if expr.target_type.kind == "pointer" then
        target_type_str = ctx():c_type(expr.target_type.to) .. "*"
    end

    -- Cast the expression, fallback is implicitly cast to target type
    -- For now, just use the cast. Future: add runtime validation and use fallback on failure
    return string.format("((%s)%s)", target_type_str, expr_str)
end

-- Generate clone expression
function Operators.gen_clone(expr, gen_expr_fn)
    -- clone(expr) or clone<Type>(expr)
    -- Allocate on heap and copy the value
    local expr_str = gen_expr_fn(expr.expr)
    local source_type = nil
    local target_type = nil

    -- Determine source type from expression
    if expr.expr.kind == "identifier" then
        source_type = ctx():get_var_type(expr.expr.name)
    end

    -- If target type specified, use it; otherwise use source type
    if expr.target_type then
        target_type = expr.target_type
    else
        target_type = source_type
    end

    if not target_type then
        error("Cannot determine type for clone operation")
    end

    -- In implicit pointer model, struct variables are pointers
    -- We need to dereference them to clone the value
    local actual_type = target_type
    local needs_deref = false

    if target_type.kind == "pointer" then
        -- Source is a pointer, need to dereference it
        actual_type = target_type.to
        needs_deref = true
    end

    local target_type_str = ctx():c_type(actual_type)
    local source_expr = needs_deref and ("*" .. expr_str) or expr_str

    -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = *source_ptr; _ptr; })
    if expr.target_type and source_type then
        -- With cast (implicit allocation - clone)
        return string.format("({ %s* _ptr = %s; *_ptr = (%s)%s; _ptr; })",
            target_type_str, ctx():malloc_call("sizeof(" .. target_type_str .. ")", false), target_type_str, source_expr)
    else
        -- Without cast (implicit allocation - clone)
        return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
            target_type_str, ctx():malloc_call("sizeof(" .. target_type_str .. ")", false), source_expr)
    end
end

-- Generate binary operation
function Operators.gen_binary(expr, gen_expr_fn)
    -- Handle special operators
    if expr.op == "or" then
        local left = gen_expr_fn(expr.left)
        local right = gen_expr_fn(expr.right)
        -- 'or' is used for both logical OR and null coalescing
        -- For null coalescing, we use a statement expression with a temporary
        return string.format("({ __auto_type _tmp = %s; _tmp ? _tmp : (%s); })", left, right)
    elseif expr.op == "and" then
        -- 'and' is logical AND
        return string.format("(%s && %s)", gen_expr_fn(expr.left), gen_expr_fn(expr.right))
    else
        return string.format("(%s %s %s)", gen_expr_fn(expr.left), expr.op, gen_expr_fn(expr.right))
    end
end

-- Generate type check (is keyword)
function Operators.gen_is_check(expr)
    -- Handle 'is' keyword for type checking
    -- This is a compile-time check that always returns true or false
    local expr_type = ctx():infer_type(expr.expr)
    if not expr_type then
        error("Cannot infer type for 'is' check expression")
    end
    local target_type = expr.type
    local matches = ctx():types_match(expr_type, target_type)
    return matches and "true" or "false"
end

-- Generate type_of expression
function Operators.gen_type_of(expr)
    -- Handle 'type' built-in that returns a const string
    local expr_type = ctx():infer_type(expr.expr)
    if not expr_type then
        error("Cannot infer type for 'type' built-in expression")
    end
    local type_name = ctx():type_name_string(expr_type)
    return string.format("\"%s\"", type_name)
end

-- Generate sizeof expression
function Operators.gen_sizeof(expr)
    -- Handle 'sizeof' built-in that returns the size in bytes
    local expr_type = ctx():infer_type(expr.expr)
    if not expr_type then
        error("Cannot infer type for 'sizeof' expression")
    end
    return ctx():sizeof_expr(expr_type)
end

-- Generate unary operation
function Operators.gen_unary(expr, gen_expr_fn)
    if expr.op == "not" then
        return string.format("(!%s)", gen_expr_fn(expr.operand))
    else
        return string.format("(%s%s)", expr.op, gen_expr_fn(expr.operand))
    end
end

-- Generate null check operator
function Operators.gen_null_check(expr, gen_expr_fn)
    -- Null check operator: expr!!
    local operand = gen_expr_fn(expr.operand)
    -- Generate: assert-like behavior
    return string.format("({ __auto_type _tmp = %s; if (!_tmp) { fprintf(stderr, \"null check failed\\n\"); abort(); } _tmp; })", operand)
end

-- Generate assignment expression
function Operators.gen_assign(expr, gen_expr_fn)
    -- Check if target is an immutable variable
    if expr.target.kind == "identifier" then
        local var_type = ctx():get_var_type(expr.target.name)
        if var_type then
            -- Check if variable is immutable (we need to track this)
            local var_info = ctx():get_var_info(expr.target.name)
            if var_info and not var_info.mutable then
                error(string.format("Cannot assign to immutable variable '%s'", expr.target.name))
            end
            
            -- Warning: reassigning a pointer to another address
            if var_type.kind == "pointer" then
                local Warnings = require("warnings")
                Warnings.emit(
                    ctx().source_file,
                    expr.line,
                    Warnings.WarningType.POINTER_REASSIGNMENT,
                    string.format("Reassigning pointer '%s' to another address (potential dangling pointer risk)", expr.target.name),
                    ctx().source_path,
                    ctx().current_function
                )
            end
        end
    elseif expr.target.kind == "field" then
        -- Check if target object variable is mutable
        if expr.target.object.kind == "identifier" then
            local var_info = ctx():get_var_info(expr.target.object.name)
            if var_info then
                local var_type = ctx():get_var_type(expr.target.object.name)
                -- For pointers: need the variable to be mutable to modify through it
                if var_type and var_type.kind == "pointer" then
                    if not var_info.mutable then
                        error(string.format("Cannot assign to field '%s' through immutable pointer '%s'", expr.target.field, expr.target.object.name))
                    end
                elseif not var_info.mutable then
                    -- Value type and not mutable - error
                    error(string.format("Cannot assign to field '%s' of immutable variable '%s'", expr.target.field, expr.target.object.name))
                end
            end
        end
    end

    local target_expr = gen_expr_fn(expr.target)
    local value_expr = gen_expr_fn(expr.value)

    -- In explicit pointer model, no automatic conversions
    return string.format("(%s = %s)", target_expr, value_expr)
end

-- Generate compound assignment
function Operators.gen_compound_assign(expr, gen_expr_fn)
    -- Compound assignment: x += y becomes x = x + y
    return string.format("(%s = %s %s %s)", gen_expr_fn(expr.target), gen_expr_fn(expr.target), expr.operator, gen_expr_fn(expr.value))
end

return Operators
