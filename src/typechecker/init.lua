-- Typechecker: Main entry point for type checking pass
-- This module performs type checking after AST construction and before lowering
-- It resolves names, infers types, checks type compatibility, and enforces mutability rules

local Resolver = require("typechecker.resolver")
local Inference = require("typechecker.inference")
local Mutability = require("typechecker.mutability")
local Errors = require("errors")
local Scopes = require("typechecker.scopes")
local Utils = require("typechecker.utils")
local Declarations = require("typechecker.declarations")
local Functions = require("typechecker.functions")
local Statements = require("typechecker.statements")
local Validation = require("typechecker.validation")

local Typechecker = {}
Typechecker.__index = Typechecker

function Typechecker.new(ast, options)
    options = options or {}
    local self = {
        ast = ast,
        structs = {},      -- struct_name -> struct_def
        enums = {},        -- enum_name -> enum_def
        functions = {},    -- type_name -> { method_name -> func_def } or "__global__" -> { func_name -> func_def }
        scope_stack = {},  -- stack of scopes for variable lookups
        errors = {},       -- collected type errors
        type_aliases = {   -- type_name -> target_type_string
            ["String"] = "char*"  -- Built-in alias
        },
        function_aliases = {}, -- function_name -> target_function_string (e.g., "print" -> "cz.print")
        source_file = options.source_file or "<unknown>",  -- Source filename for error messages
        source_path = options.source_path or options.source_file or "<unknown>",  -- Full path for reading source
        loop_depth = 0,    -- Track if we're inside a loop for break/continue validation
        require_main = options.require_main or false,  -- Whether to enforce presence of main function
        module_name = nil, -- Current module name
        imports = {},      -- Imported modules: { module_path, alias, used }
        c_imports = {},    -- C header files imported via import C : header.h
    }
    setmetatable(self, Typechecker)

    -- Register builtin functions
    self:register_builtins()

    return self
end

-- Register builtin functions that have special codegen treatment
function Typechecker:register_builtins()
    -- Create __global__ function table if it doesn't exist
    if not self.functions["__global__"] then
        self.functions["__global__"] = {}
    end

    -- Note: print, println, and printf have been moved to the cz module
    -- Users must: import cz, then use cz.print(), cz.println(), cz.printf()
    -- They are NOT available as global functions

    -- Register print_i32 for compatibility (legacy builtin)
    self.functions["__global__"]["print_i32"] = {
        {
            name = "print_i32",
            params = {
                {
                    name = "value",
                    type = { kind = "named_type", name = "i32" },
                    mutable = false
                }
            },
            return_type = { kind = "named_type", name = "void" },
            is_builtin = true
        }
    }
end

-- Main entry point: type check the entire AST
function Typechecker:check()
    -- Process module declaration and validate module naming rules
    if self.ast.module then
        self.module_name = table.concat(self.ast.module.path, ".")
        Validation.validate_module_name(self)
    end
    
    -- Process imports
    for _, import in ipairs(self.ast.imports or {}) do
        if import.kind == "c_import" then
            -- C import: import C : header.h, ...
            for _, header in ipairs(import.headers) do
                table.insert(self.c_imports, {
                    header = header,
                    line = import.line,
                    col = import.col
                })
            end
        else
            -- Regular module import
            local module_path = table.concat(import.path, ".")
            local alias = import.alias or import.path[#import.path]
            table.insert(self.imports, {
                path = module_path,
                alias = alias,
                used = false,
                line = import.line,
                col = import.col
            })
        end
    end
    
    -- Pass 1: Collect all top-level declarations (structs, functions)
    Declarations.collect_declarations(self)
    
    -- Pass 1.5: Replace function aliases in the AST (must happen before type checking)
    self:replace_function_aliases()

    -- Pass 2: Type check all functions
    Functions.check_all_functions(self)

    -- Pass 3: Validate main function if required for binary output
    if self.require_main then
        Validation.validate_main_function(self)
    end
    
    -- Pass 4: Check for unused imports
    Validation.check_unused_imports(self)

    -- Report any errors
    if #self.errors > 0 then
        local error_msg = Errors.format_phase_errors("Type checking", self.errors)
        error(error_msg)
    end

    -- Return the annotated AST
    return self.ast
end

-- Type check an expression and return its type
function Typechecker:check_expression(expr)
    return Inference.infer_type(self, expr)
end

-- Add error to error list
-- Now implements fail-fast behavior: immediately throws the error instead of collecting
function Typechecker:add_error(msg)
    -- Immediately throw the error to stop compilation on first error
    error(msg)
end

-- Get variable information (delegate to Scopes module)
function Typechecker:get_var_info(name)
    return Scopes.get_var_info(self, name)
end

-- Add variable to scope (delegate to Scopes module)
function Typechecker:add_var(name, type_node, is_mutable)
    return Scopes.add_var(self, name, type_node, is_mutable)
end

-- Push scope (delegate to Scopes module)
function Typechecker:push_scope()
    return Scopes.push_scope(self)
end

-- Pop scope (delegate to Scopes module)
function Typechecker:pop_scope()
    return Scopes.pop_scope(self)
end

-- Replace function aliases in expressions throughout the AST
-- This must happen before type checking to ensure pub/prv checks work correctly
function Typechecker:replace_function_aliases()
    -- Helper function to recursively replace aliases in an expression
    local function replace_in_expr(expr)
        if not expr then return end
        
        -- Replace identifier if it's an alias
        if expr.kind == "identifier" then
            local alias_target = self.function_aliases[expr.name]
            if alias_target then
                -- Transform "aliasName" into qualified access like "cz.print"
                -- Parse the target to create appropriate expression
                local parts = {}
                for part in alias_target:gmatch("[^.]+") do
                    table.insert(parts, part)
                end
                
                if #parts >= 2 then
                    -- Multi-part name like "cz.print" - keep as identifier for now
                    -- When it's called, it will be transformed to static_method_call by caller
                    -- For now, just replace with a field access
                    expr.kind = "field"
                    expr.object = { kind = "identifier", name = parts[1], line = expr.line, col = expr.col }
                    expr.field = parts[2]
                elseif #parts == 1 then
                    -- Simple rename
                    expr.name = parts[1]
                end
            end
        -- Replace aliased function in call expressions
        elseif expr.kind == "call" then
            -- Special handling: if callee is an identifier that's an alias,
            -- transform it before processing the call
            if expr.callee.kind == "identifier" then
                local alias_target = self.function_aliases[expr.callee.name]
                if alias_target then
                    -- Parse the target
                    local parts = {}
                    for part in alias_target:gmatch("[^.]+") do
                        table.insert(parts, part)
                    end
                    
                    if #parts == 2 then
                        -- Transform to static_method_call like "cz.print(...)"
                        -- Only 2-level module.function is supported in the language
                        expr.kind = "static_method_call"
                        expr.type_name = parts[1]
                        expr.method = parts[2]
                        -- Keep args as they are
                        -- Remove callee field since static_method_call doesn't use it
                        expr.callee = nil
                    elseif #parts == 1 then
                        -- Simple function rename
                        expr.callee.name = parts[1]
                    else
                        -- More than 2 parts - not supported, keep as-is and let type checker error
                        -- This maintains current language semantics
                    end
                end
            else
                -- Process callee expression
                replace_in_expr(expr.callee)
            end
            
            -- Process arguments
            for _, arg in ipairs(expr.args or {}) do
                replace_in_expr(arg)
            end
        -- Recursively process other expression types
        elseif expr.kind == "field" or expr.kind == "safe_field" then
            replace_in_expr(expr.object)
        elseif expr.kind == "index" then
            replace_in_expr(expr.object)
            replace_in_expr(expr.index)
        elseif expr.kind == "binary" then
            replace_in_expr(expr.left)
            replace_in_expr(expr.right)
        elseif expr.kind == "unary" then
            replace_in_expr(expr.operand)
        elseif expr.kind == "cast" then
            replace_in_expr(expr.expr)
        elseif expr.kind == "assignment" then
            replace_in_expr(expr.target)
            replace_in_expr(expr.value)
        elseif expr.kind == "array_literal" then
            for _, elem in ipairs(expr.elements or {}) do
                replace_in_expr(elem)
            end
        elseif expr.kind == "map_literal" then
            for _, entry in ipairs(expr.entries or {}) do
                replace_in_expr(entry.key)
                replace_in_expr(entry.value)
            end
        elseif expr.kind == "pair_literal" then
            replace_in_expr(expr.first)
            replace_in_expr(expr.second)
        elseif expr.kind == "interpolated_string" then
            for _, part in ipairs(expr.parts or {}) do
                if part.kind == "expr" then
                    replace_in_expr(part.expr)
                end
            end
        elseif expr.kind == "static_method_call" then
            -- Process arguments in static method calls
            for _, arg in ipairs(expr.args or {}) do
                replace_in_expr(arg)
            end
        end
    end
    
    -- Helper function to recursively replace aliases in a statement
    local function replace_in_stmt(stmt)
        if not stmt then return end
        
        if stmt.kind == "var_decl" then
            replace_in_expr(stmt.init)
        elseif stmt.kind == "expr_stmt" then
            replace_in_expr(stmt.expression)
        elseif stmt.kind == "return" then
            replace_in_expr(stmt.value)
        elseif stmt.kind == "if" then
            replace_in_expr(stmt.condition)
            for _, s in ipairs(stmt.then_block or {}) do
                replace_in_stmt(s)
            end
            for _, elif in ipairs(stmt.elseif_blocks or {}) do
                replace_in_expr(elif.condition)
                for _, s in ipairs(elif.block or {}) do
                    replace_in_stmt(s)
                end
            end
            for _, s in ipairs(stmt.else_block or {}) do
                replace_in_stmt(s)
            end
        elseif stmt.kind == "while" then
            replace_in_expr(stmt.condition)
            for _, s in ipairs(stmt.block or {}) do
                replace_in_stmt(s)
            end
        elseif stmt.kind == "for" then
            replace_in_expr(stmt.iterable)
            for _, s in ipairs(stmt.block or {}) do
                replace_in_stmt(s)
            end
        elseif stmt.kind == "assert_stmt" then
            replace_in_expr(stmt.condition)
        elseif stmt.kind == "log_stmt" then
            replace_in_expr(stmt.message)
        end
    end
    
    -- Replace aliases in all function bodies
    -- This is a single pass through the AST items (O(n) where n = number of items)
    -- For each function, we traverse its body statements (O(m) where m = statements per function)
    -- Total complexity: O(n * m) which is effectively O(total_ast_nodes)
    for _, item in ipairs(self.ast.items or {}) do
        if item.kind == "function" then
            local body_statements = (item.body and item.body.statements) or {}
            for _, stmt in ipairs(body_statements) do
                replace_in_stmt(stmt)
            end
        end
    end
end

-- Helper: Convert type to string for error messages (delegate to Utils)
function Typechecker:type_to_string(type_node)
    return Utils.type_to_string(type_node)
end

-- Module entry point
return function(ast, options)
    local checker = Typechecker.new(ast, options)
    return checker:check()
end
