-- Typechecker: Main entry point for type checking pass
-- This module performs type checking after AST construction and before lowering
-- It resolves names, infers types, checks type compatibility, and enforces mutability rules

local Resolver = require("typechecker.resolver")
local Inference = require("typechecker.inference")
local Mutability = require("typechecker.mutability")

local Typechecker = {}
Typechecker.__index = Typechecker

function Typechecker.new(ast)
    local self = {
        ast = ast,
        structs = {},      -- struct_name -> struct_def
        functions = {},    -- type_name -> { method_name -> func_def } or "__global__" -> { func_name -> func_def }
        scope_stack = {},  -- stack of scopes for variable lookups
        errors = {},       -- collected type errors
    }
    return setmetatable(self, Typechecker)
end

-- Main entry point: type check the entire AST
function Typechecker:check()
    -- Pass 1: Collect all top-level declarations (structs, functions)
    self:collect_declarations()
    
    -- Pass 2: Type check all functions
    self:check_all_functions()
    
    -- Report any errors
    if #self.errors > 0 then
        local error_msg = "Type checking failed:\n" .. table.concat(self.errors, "\n")
        error(error_msg)
    end
    
    -- Return the annotated AST
    return self.ast
end

-- Collect all top-level declarations
function Typechecker:collect_declarations()
    for _, item in ipairs(self.ast.items) do
        if item.kind == "struct" then
            self.structs[item.name] = item
        elseif item.kind == "function" then
            -- Determine if this is a method or a global function
            local type_name = "__global__"
            -- Check for receiver_type field (used by parser for methods)
            if item.receiver_type then
                type_name = item.receiver_type
            elseif item.receiver then
                type_name = item.receiver.type.name
            end
            
            if not self.functions[type_name] then
                self.functions[type_name] = {}
            end
            self.functions[type_name][item.name] = item
        elseif item.kind == "directive" then
            -- Store directives but don't type check them
        end
    end
end

-- Type check all functions
function Typechecker:check_all_functions()
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            self:check_function(item)
        end
    end
end

-- Type check a single function
function Typechecker:check_function(func)
    -- Create a new scope for this function
    self:push_scope()
    
    -- Add receiver (self) to scope if this is a method
    if func.receiver then
        local receiver_type = func.receiver.type
        local is_mutable = func.receiver.mutable
        self:add_var("self", receiver_type, is_mutable)
    end
    
    -- Add parameters to scope
    for _, param in ipairs(func.params) do
        local param_type = param.type
        -- Check if mutability is in param.mutable or in the type itself (for pointers)
        local is_mutable = param.mutable
        if not is_mutable and param_type and param_type.kind == "pointer" then
            -- For pointer types, check is_mut flag in the type
            is_mutable = param_type.is_mut
        end
        self:add_var(param.name, param_type, is_mutable)
    end
    
    -- Type check the function body
    self:check_block(func.body)
    
    -- Pop the function scope
    self:pop_scope()
end

-- Type check a block of statements
function Typechecker:check_block(block)
    local statements = block.statements or block
    for _, stmt in ipairs(statements) do
        self:check_statement(stmt)
    end
end

-- Type check a single statement
function Typechecker:check_statement(stmt)
    if stmt.kind == "var_decl" then
        self:check_var_decl(stmt)
    elseif stmt.kind == "assign" then
        self:check_assign(stmt)
    elseif stmt.kind == "if" then
        self:check_if(stmt)
    elseif stmt.kind == "while" then
        self:check_while(stmt)
    elseif stmt.kind == "return" then
        self:check_return(stmt)
    elseif stmt.kind == "expr_stmt" then
        -- Check if the expression is an assignment
        if stmt.expression and stmt.expression.kind == "assign" then
            self:check_assign(stmt.expression)
        else
            self:check_expression(stmt.expr or stmt.expression)
        end
    elseif stmt.kind == "when" then
        self:check_when(stmt)
    elseif stmt.kind == "free" then
        self:check_expression(stmt.expr)
    end
end

-- Type check a variable declaration
function Typechecker:check_var_decl(stmt)
    local var_type = stmt.type
    local is_mutable = stmt.mutable or false
    
    -- Type check the initializer if present
    if stmt.init then
        local init_type = self:check_expression(stmt.init)
        
        -- Check type compatibility
        if not Inference.types_compatible(var_type, init_type) then
            self:add_error(string.format(
                "Type mismatch in variable '%s': expected %s, got %s",
                stmt.name,
                Inference.type_to_string(var_type),
                Inference.type_to_string(init_type)
            ))
        end
        
        -- Annotate the initializer with its type
        stmt.init.inferred_type = init_type
    end
    
    -- Add variable to scope
    self:add_var(stmt.name, var_type, is_mutable)
    
    -- Annotate the statement with type information
    stmt.resolved_type = var_type
end

-- Type check an assignment
function Typechecker:check_assign(stmt)
    -- Check if target is mutable
    if not Mutability.check_mutable_target(self, stmt.target) then
        -- Mutability check failed, don't continue with type checking
        return
    end
    
    -- Type check both sides
    local target_type = self:check_expression(stmt.target)
    local value_type = self:check_expression(stmt.value)
    
    -- Check type compatibility
    if not Inference.types_compatible(target_type, value_type) then
        self:add_error(string.format(
            "Type mismatch in assignment: expected %s, got %s",
            Inference.type_to_string(target_type),
            Inference.type_to_string(value_type)
        ))
    end
end

-- Type check an if statement
function Typechecker:check_if(stmt)
    -- Type check condition
    local cond_type = self:check_expression(stmt.condition)
    
    -- Condition should be bool
    if not Inference.is_bool_type(cond_type) then
        self:add_error(string.format(
            "Condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        ))
    end
    
    -- Type check branches
    self:push_scope()
    self:check_block(stmt.then_block)
    self:pop_scope()
    
    -- Handle elseif branches
    if stmt.elseif_branches then
        for _, branch in ipairs(stmt.elseif_branches) do
            local branch_cond_type = self:check_expression(branch.condition)
            if not Inference.is_bool_type(branch_cond_type) then
                self:add_error(string.format(
                    "Elseif condition must be bool, got %s",
                    Inference.type_to_string(branch_cond_type)
                ))
            end
            self:push_scope()
            self:check_block(branch.block)
            self:pop_scope()
        end
    end
    
    if stmt.else_block then
        self:push_scope()
        self:check_block(stmt.else_block)
        self:pop_scope()
    end
end

-- Type check a while statement
function Typechecker:check_while(stmt)
    -- Type check condition
    local cond_type = self:check_expression(stmt.condition)
    
    -- Condition should be bool
    if not Inference.is_bool_type(cond_type) then
        self:add_error(string.format(
            "While condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        ))
    end
    
    -- Type check body
    self:push_scope()
    self:check_block(stmt.body)
    self:pop_scope()
end

-- Type check a when statement
function Typechecker:check_when(stmt)
    -- Type check the subject
    local subject_type = self:check_expression(stmt.subject)
    
    -- Type check each arm
    if stmt.arms then
        for _, arm in ipairs(stmt.arms) do
            self:push_scope()
            
            -- Add variable binding if present
            if arm.var_name then
                self:add_var(arm.var_name, subject_type, false)
            end
            
            -- Check the arm condition if present
            if arm.condition then
                self:check_expression(arm.condition)
            end
            
            -- Check the arm body (which might be called 'block' or 'body')
            local arm_block = arm.block or arm.body
            if arm_block then
                self:check_block(arm_block)
            end
            self:pop_scope()
        end
    end
end

-- Type check a return statement
function Typechecker:check_return(stmt)
    if stmt.value then
        self:check_expression(stmt.value)
    end
end

-- Type check an expression and return its type
function Typechecker:check_expression(expr)
    return Inference.infer_type(self, expr)
end

-- Scope management
function Typechecker:push_scope()
    table.insert(self.scope_stack, {})
end

function Typechecker:pop_scope()
    table.remove(self.scope_stack)
end

function Typechecker:add_var(name, type_node, is_mutable)
    local scope = self.scope_stack[#self.scope_stack]
    scope[name] = {
        type = type_node,
        mutable = is_mutable or false
    }
end

function Typechecker:get_var_info(name)
    for i = #self.scope_stack, 1, -1 do
        local var_info = self.scope_stack[i][name]
        if var_info then
            return var_info
        end
    end
    return nil
end

-- Error reporting
function Typechecker:add_error(msg)
    table.insert(self.errors, msg)
end

-- Module entry point
return function(ast)
    local checker = Typechecker.new(ast)
    return checker:check()
end
