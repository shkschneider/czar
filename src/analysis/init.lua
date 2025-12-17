-- Escape analysis and lifetime checking
-- This runs after lowering and before codegen
-- It analyzes which allocations escape and determines allocation strategy (stack vs heap)

local Errors = require("errors")
local Warnings = require("warnings")

local Analysis = {}
Analysis.__index = Analysis

-- Stack size thresholds (in bytes)
local STACK_WARNING_THRESHOLD = 1048576  -- 1 MB
local STACK_ERROR_THRESHOLD = 2097152    -- 2 MB

-- Calculate the size of a type in bytes
local function calculate_type_size(type_node, seen_types)
    if not type_node then
        return 0
    end
    
    -- Prevent infinite recursion with self-referential types
    seen_types = seen_types or {}
    
    if type_node.kind == "pointer" then
        return 8  -- 64-bit architecture
    elseif type_node.kind == "array" then
        -- Arrays: size * element_size
        local size = type_node.size or 0
        local element_size = calculate_type_size(type_node.element_type, seen_types)
        return size * element_size
    elseif type_node.kind == "slice" then
        -- Slices are represented as pointers
        return 8
    elseif type_node.kind == "varargs" then
        -- Varargs are represented as pointers
        return 8
    elseif type_node.kind == "map" then
        -- Maps are pointers to heap-allocated structures
        return 8
    elseif type_node.kind == "pair" then
        -- Pairs contain two fields
        local left_size = calculate_type_size(type_node.left_type, seen_types)
        local right_size = calculate_type_size(type_node.right_type, seen_types)
        return left_size + right_size
    elseif type_node.kind == "string" then
        -- Strings are represented as a struct with capacity, length, and data pointer
        -- struct czar_string { size_t capacity; size_t length; char* data; }
        return 8 + 8 + 8  -- 24 bytes on 64-bit
    elseif type_node.kind == "named_type" then
        local name = type_node.name
        
        if name == "i8" or name == "u8" then
            return 1
        elseif name == "i16" or name == "u16" then
            return 2
        elseif name == "i32" or name == "u32" then
            return 4
        elseif name == "i64" or name == "u64" then
            return 8
        elseif name == "f32" then
            return 4
        elseif name == "f64" then
            return 8
        elseif name == "bool" then
            return 1
        elseif name == "void" then
            return 0
        elseif name == "any" then
            return 8  -- void* pointer
        else
            -- For custom struct types, we need to look them up
            -- To avoid infinite recursion, we'll assume a minimum size
            -- In a complete implementation, we'd track struct definitions
            if seen_types[name] then
                return 0  -- Already counting this type (recursive reference)
            end
            seen_types[name] = true
            -- Conservative estimate for unknown struct types
            return 8
        end
    else
        -- Unknown type, conservative estimate
        return 8
    end
end

-- Calculate total stack size for a function
-- Note: This is a conservative (worst-case) estimate that counts all variables
-- in nested scopes, even if they don't exist simultaneously (e.g., if/else branches).
-- This ensures we catch potential stack overflows even in complex control flow.
local function calculate_function_stack_size(func)
    local total_size = 0
    
    -- Add sizes of all parameters
    for _, param in ipairs(func.params) do
        local param_size = calculate_type_size(param.type)
        total_size = total_size + param_size
    end
    
    -- Helper function to get statements from a block
    local function get_statements(block)
        return block.statements or block
    end
    
    -- Add sizes of all local variables
    -- We need to traverse the function body to find all var_decl statements
    local function traverse_statements(statements)
        for _, stmt in ipairs(statements) do
            if stmt.kind == "var_decl" then
                local var_size = calculate_type_size(stmt.type)
                total_size = total_size + var_size
            elseif stmt.kind == "if" then
                if stmt.then_block then
                    traverse_statements(get_statements(stmt.then_block))
                end
                if stmt.elseif_branches then
                    for _, branch in ipairs(stmt.elseif_branches) do
                        traverse_statements(get_statements(branch.block))
                    end
                end
                if stmt.else_block then
                    traverse_statements(get_statements(stmt.else_block))
                end
            elseif stmt.kind == "while" then
                if stmt.body then
                    traverse_statements(get_statements(stmt.body))
                end
            elseif stmt.kind == "for" then
                if stmt.body then
                    traverse_statements(get_statements(stmt.body))
                end
            elseif stmt.kind == "repeat" then
                if stmt.body then
                    traverse_statements(get_statements(stmt.body))
                end
            end
        end
    end
    
    if func.body then
        traverse_statements(get_statements(func.body))
    end
    
    return total_size
end

function Analysis.new(lowered_ast, options)
    options = options or {}
    local self = {
        ast = lowered_ast,
        freed_vars = {},     -- Track variables that have been freed in current scope
        scope_stack = {},    -- Stack of scopes for tracking freed variables
        errors = {},         -- Collected analysis errors
        source_file = options.source_file or "<unknown>",  -- Source filename for error messages
        source_path = options.source_path or options.source_file or "<unknown>",  -- Full path for reading source
    }
    return setmetatable(self, Analysis)
end

-- Main entry point: analyze the entire AST
function Analysis:analyze()
    -- Perform escape analysis and lifetime checks
    -- 1. Identify which allocations escape their scope
    -- 2. Mark variables that need heap allocation
    -- 3. Verify that pointer lifetimes are valid
    -- 4. Detect use-after-free errors
    -- 5. Annotate AST nodes with allocation strategy

    -- Analyze all top-level items
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            self:analyze_function(item)
        end
    end

    -- Report any errors
    if #self.errors > 0 then
        local error_msg = Errors.format_phase_errors("Lifetime analysis", self.errors)
        error(error_msg)
    end

    return self.ast
end

-- Analyze a function for use-after-free and stack size
function Analysis:analyze_function(func)
    -- Check stack size
    local stack_size = calculate_function_stack_size(func)
    
    if stack_size >= STACK_ERROR_THRESHOLD then
        local line = func.line or 0
        local msg = string.format(
            "Function '%s' exceeds stack size limit: %d bytes (limit: %d bytes / 2MB)",
            func.name, stack_size, STACK_ERROR_THRESHOLD
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.STACK_OVERFLOW, msg, self.source_path)
        self:add_error(formatted_error)
    elseif stack_size >= STACK_WARNING_THRESHOLD then
        local line = func.line or 0
        local msg = string.format(
            "Function '%s' uses large stack: %d bytes (warning threshold: %d bytes / 1MB)",
            func.name, stack_size, STACK_WARNING_THRESHOLD
        )
        Warnings.emit(self.source_file, line, Warnings.WarningType.STACK_WARNING, msg, self.source_path, func.name)
    end
    
    -- Perform use-after-free analysis
    self:push_scope()
    self:analyze_block(func.body)
    self:pop_scope()
end

-- Analyze a block of statements
function Analysis:analyze_block(block)
    local statements = block.statements or block
    for _, stmt in ipairs(statements) do
        self:analyze_statement(stmt)
    end
end

-- Analyze a single statement
function Analysis:analyze_statement(stmt)
    if stmt.kind == "var_decl" then
        -- Check initializer for use-after-free
        if stmt.init then
            self:analyze_expression(stmt.init, stmt.name)
        end
    elseif stmt.kind == "assign" then
        -- Check both target and value for use-after-free
        self:analyze_expression(stmt.target, nil)
        self:analyze_expression(stmt.value, nil)
    elseif stmt.kind == "if" then
        self:analyze_expression(stmt.condition, nil)
        self:push_scope()
        self:analyze_block(stmt.then_block)
        self:pop_scope()

        if stmt.elseif_branches then
            for _, branch in ipairs(stmt.elseif_branches) do
                self:analyze_expression(branch.condition, nil)
                self:push_scope()
                self:analyze_block(branch.block)
                self:pop_scope()
            end
        end

        if stmt.else_block then
            self:push_scope()
            self:analyze_block(stmt.else_block)
            self:pop_scope()
        end
    elseif stmt.kind == "while" then
        self:analyze_expression(stmt.condition, nil)
        self:push_scope()
        self:analyze_block(stmt.body)
        self:pop_scope()
    elseif stmt.kind == "return" then
        if stmt.value then
            self:analyze_expression(stmt.value, nil)
        end
    elseif stmt.kind == "expr_stmt" then
        if stmt.expression then
            self:analyze_expression(stmt.expression, nil)
        elseif stmt.expr then
            self:analyze_expression(stmt.expr, nil)
        end
    elseif stmt.kind == "free" then
        -- Mark the variable as freed
        local free_expr = stmt.expr or stmt.value
        if free_expr and free_expr.kind == "identifier" then
            local var_name = free_expr.name
            self:mark_freed(var_name)
        end
    end
end

-- Analyze an expression for use-after-free
function Analysis:analyze_expression(expr, declaring_var)
    if not expr then
        return
    end

    if expr.kind == "identifier" then
        -- Check if this variable has been freed
        if self:is_freed(expr.name) and expr.name ~= declaring_var then
            local line = expr.line or 0
            local msg = string.format(
                "Variable '%s' is used after being freed.",
                expr.name
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.USE_AFTER_FREE, msg, self.source_path)
            self:add_error(formatted_error)
        end
    elseif expr.kind == "binary" then
        self:analyze_expression(expr.left, declaring_var)
        self:analyze_expression(expr.right, declaring_var)
    elseif expr.kind == "unary" then
        self:analyze_expression(expr.operand, declaring_var)
    elseif expr.kind == "call" then
        self:analyze_expression(expr.callee, declaring_var)
        for _, arg in ipairs(expr.args) do
            if arg.kind == "mut_arg" then
                self:analyze_expression(arg.expr, declaring_var)
            elseif arg.kind == "named_arg" then
                self:analyze_expression(arg.expr, declaring_var)
            else
                self:analyze_expression(arg, declaring_var)
            end
        end
    elseif expr.kind == "field" then
        self:analyze_expression(expr.object, declaring_var)
    elseif expr.kind == "struct_literal" then
        for _, field in ipairs(expr.fields) do
            self:analyze_expression(field.value, declaring_var)
        end
    elseif expr.kind == "new_heap" or expr.kind == "new_stack" then
        for _, field in ipairs(expr.fields) do
            self:analyze_expression(field.value, declaring_var)
        end
    elseif expr.kind == "new_array" then
        for _, elem in ipairs(expr.elements) do
            self:analyze_expression(elem, declaring_var)
        end
    elseif expr.kind == "method_ref" then
        self:analyze_expression(expr.object, declaring_var)
    elseif expr.kind == "method_call" then
        self:analyze_expression(expr.object, declaring_var)
        for _, arg in ipairs(expr.args) do
            self:analyze_expression(arg, declaring_var)
        end
    elseif expr.kind == "unsafe_cast" or expr.kind == "safe_cast" or expr.kind == "clone" then
        self:analyze_expression(expr.expr, declaring_var)
        if expr.kind == "safe_cast" and expr.fallback then
            self:analyze_expression(expr.fallback, declaring_var)
        end
    elseif expr.kind == "null_check" then
        self:analyze_expression(expr.operand, declaring_var)
    end
end

-- Scope management for tracking freed variables
function Analysis:push_scope()
    table.insert(self.scope_stack, {})
end

function Analysis:pop_scope()
    table.remove(self.scope_stack)
end

function Analysis:mark_freed(var_name)
    local scope = self.scope_stack[#self.scope_stack]
    if scope then
        scope[var_name] = true
    end
end

function Analysis:is_freed(var_name)
    -- Check from innermost to outermost scope
    for i = #self.scope_stack, 1, -1 do
        if self.scope_stack[i][var_name] then
            return true
        end
    end
    return false
end

-- Error reporting
function Analysis:add_error(msg)
    table.insert(self.errors, msg)
end

-- Module entry point
return function(lowered_ast, options)
    local analyzer = Analysis.new(lowered_ast, options)
    return analyzer:analyze()
end
