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
        ifaces = {},       -- iface_name -> iface_def (new)
        functions = {},    -- type_name -> { method_name -> func_def } or "__global__" -> { func_name -> func_def }
        scope_stack = {},  -- stack of scopes for variable lookups
        errors = {},       -- collected type errors
        source_file = options.source_file or "<unknown>",  -- Source filename for error messages
        source_path = options.source_path or options.source_file or "<unknown>",  -- Full path for reading source
        loop_depth = 0,    -- Track if we're inside a loop for break/continue validation
        require_main = options.require_main or false,  -- Whether to enforce presence of main function
        module_name = nil, -- Current module name
        imports = {},      -- Imported modules: { module_path, alias, used }
        c_imports = {},    -- C header files imported via #import C : header.h
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
    
    -- Built-in structs from cz module (String, Os) are no longer automatically available
    -- They must be explicitly imported via #import cz or #import cz.string, etc.
    -- This function is kept for future builtin registrations if needed
end

-- Register cz module builtins when cz module is imported
function Typechecker:register_cz_builtins()
    -- Register built-in structs from cz module (String, Os)
    -- These are only available when cz module is imported
    -- They map to cz_string and cz_os in generated C code
    if not self.structs["String"] then
        self.structs["String"] = {
            kind = "struct",
            name = "String",
            fields = {
                { name = "data", type = { kind = "named_type", name = "cstr" }, visibility = "prv" },
                { name = "length", type = { kind = "named_type", name = "i32" } },
                { name = "capacity", type = { kind = "named_type", name = "i32" } },
            },
            line = 0,
            builtin = true,
            is_public = true,
            module = "cz"
        }
    end
    
    if not self.structs["Os"] then
        self.structs["Os"] = {
            kind = "struct",
            name = "Os",
            fields = {
                { name = "name", type = { kind = "named_type", name = "String" } },
                { name = "version", type = { kind = "named_type", name = "String" } },
                { name = "kernel", type = { kind = "named_type", name = "String" } },
                { name = "linux", type = { kind = "named_type", name = "bool" } },
                { name = "windows", type = { kind = "named_type", name = "bool" } },
                { name = "macos", type = { kind = "named_type", name = "bool" } },
            },
            line = 0,
            builtin = true,
            is_public = true,
            module = "cz"
        }
    end
end

-- Main entry point: type check the entire AST
function Typechecker:check()
    -- Determine module name: either from #module declaration or inferred from path
    if self.ast.module then
        -- Explicit #module declaration
        self.module_name = table.concat(self.ast.module.path, ".")
        -- Validate that #module can only be an ancestor of the file's location
        Validation.validate_module_declaration(self)
    else
        -- Infer module name from directory structure
        self.module_name = Validation.infer_module_name(self)
    end

    -- If this file is part of the cz module, register cz builtins
    if self.module_name == "cz" then
        self:register_cz_builtins()
    end

    -- Process imports
    for _, import in ipairs(self.ast.imports or {}) do
        if import.kind == "c_import" then
            -- C import: #import C : header.h ...
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
            
            -- Register cz module builtins if importing from cz
            if import.path[1] == "cz" then
                self:register_cz_builtins()
            end
        end
    end

    -- Pass 1: Collect all top-level declarations (structs, functions)
    Declarations.collect_declarations(self)

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

-- Helper: Convert type to string for error messages (delegate to Utils)
function Typechecker:type_to_string(type_node)
    return Utils.type_to_string(type_node)
end

-- Module entry point
return function(ast, options)
    local checker = Typechecker.new(ast, options)
    return checker:check()
end
