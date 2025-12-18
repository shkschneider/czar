-- Builtins module for Czar language
-- This module contains all builtin functions and features that can be extended
-- Users can modify this table to add/remove builtins

local Builtins = {}

-- Builtin function calls
-- These are functions that get special code generation treatment
Builtins.calls = {
    print_i32 = function(args)
        return string.format('printf("%%d\\n", %s)', args[1])
    end,
    
    -- Print string with automatic newline
    println = function(args)
        return string.format('printf("%%s\\n", %s)', args[1])
    end,
    
    -- Print string without newline (works like printf with format string)
    print = function(args)
        if #args == 1 then
            return string.format('printf("%%s", %s)', args[1])
        else
            -- Multiple arguments: treat like printf
            return string.format('printf(%s)', table.concat(args, ", "))
        end
    end,
    
    -- Direct printf binding with format string and variadic arguments
    printf = function(args)
        -- Simply pass all arguments to printf
        return string.format('printf(%s)', table.concat(args, ", "))
    end,
}

-- Builtin features/keywords
-- These are language features that have special parsing/codegen behavior
-- This is for documentation purposes - they are implemented in parser/codegen
Builtins.features = {
    -- Type introspection
    type = {
        description = "Returns the type name of an expression as a string",
        syntax = "type expr",
        example = 'type x  // Returns "i32" if x is i32',
        kind = "type_of"
    },
    
    sizeof = {
        description = "Returns the size in bytes of an expression's type",
        syntax = "sizeof expr",
        example = "sizeof x  // Returns 4 for i32",
        kind = "sizeof"
    },
    
    -- Type checking and casting
    is = {
        description = "Compile-time type checking",
        syntax = "expr is Type",
        example = "x is i32  // Returns true/false at compile time",
        kind = "is_check"
    },
    
    as = {
        description = "Unsafe type cast",
        syntax = "expr as<Type>",
        example = "x as<i64>",
        kind = "unsafe_cast"
    },
    
    ["as?"] = {
        description = "Safe type cast with fallback",
        syntax = "expr as?<Type>(fallback)",
        example = "x as?<i64>(0)",
        kind = "safe_cast"
    },
    
    -- Memory operations
    clone = {
        description = "Clone an expression to heap",
        syntax = "clone expr or clone<Type> expr",
        example = "clone mystruct",
        kind = "clone"
    },
    
    new = {
        description = "Allocate on heap",
        syntax = "new Type { fields... } or new [elements...]",
        example = "new Point { x: 10, y: 20 }",
        kind = "new_heap"
    },
    
    free = {
        description = "Explicitly free heap memory",
        syntax = "free ptr",
        example = "free myptr",
        kind = "free"
    },
}

-- Add a new builtin function
function Builtins.add_call(name, codegen_func)
    Builtins.calls[name] = codegen_func
end

-- Remove a builtin function
function Builtins.remove_call(name)
    Builtins.calls[name] = nil
end

-- Get all builtin function names
function Builtins.list_calls()
    local names = {}
    for name, _ in pairs(Builtins.calls) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Get all builtin feature names
function Builtins.list_features()
    local names = {}
    for name, _ in pairs(Builtins.features) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return Builtins
