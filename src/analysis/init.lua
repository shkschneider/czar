-- Escape analysis and lifetime checking
-- This runs after lowering and before codegen
-- It analyzes which allocations escape and determines allocation strategy (stack vs heap)

local Errors = require("errors")

local Analysis = {}
Analysis.__index = Analysis

function Analysis.new(lowered_ast, options)
    options = options or {}
    local self = {
        ast = lowered_ast,
        freed_vars = {},     -- Track variables that have been freed in current scope
        scope_stack = {},    -- Stack of scopes for tracking freed variables
        errors = {},         -- Collected analysis errors
        source_file = options.source_file or "<unknown>",  -- Source filename for error messages
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

-- Analyze a function for use-after-free
function Analysis:analyze_function(func)
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
                "Use-after-free detected: Variable '%s' is used after being freed. " ..
                "This is a memory safety violation.",
                expr.name
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line, 
                Errors.ErrorType.USE_AFTER_FREE, msg)
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
    elseif expr.kind == "method_ref" then
        self:analyze_expression(expr.object, declaring_var)
    elseif expr.kind == "method_call" then
        self:analyze_expression(expr.object, declaring_var)
        for _, arg in ipairs(expr.args) do
            self:analyze_expression(arg, declaring_var)
        end
    elseif expr.kind == "cast" or expr.kind == "clone" then
        self:analyze_expression(expr.expr, declaring_var)
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
