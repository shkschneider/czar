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

-- Map module imports to their .cz file paths (same as in codegen)
local function get_stdlib_file_path(import_path)
    local module_to_file = {
        -- string module defines the string struct type
        ["cz.string"] = "src/std/string.cz",
        -- fmt module provides formatted print functions
        ["cz.fmt"] = "src/std/fmt.cz",
        -- os module provides OS interface functions
        ["cz.os"] = "src/std/os.cz",
    }

    return module_to_file[import_path]
end

-- Cache for parsed stdlib ASTs
local stdlib_ast_cache = {}

-- Parse stdlib .cz file to get its full AST (same as in codegen)
local function parse_stdlib_ast(file_path)
    -- Check cache first
    if stdlib_ast_cache[file_path] then
        return stdlib_ast_cache[file_path]
    end

    -- Read the file
    local file = io.open(file_path, "r")
    if not file then
        return nil
    end

    local source = file:read("*all")
    file:close()

    -- Parse using the lexer and parser
    local lexer = require("lexer")
    local parser = require("parser")

    local tokens = lexer(source, file_path)
    local ast = parser(tokens, source)

    -- Cache the result
    stdlib_ast_cache[file_path] = ast
    return ast
end

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
        end
    end
    
    -- Pass 1: Collect all top-level declarations (structs, functions)
    Declarations.collect_declarations(self)
    
    -- Also collect declarations from imported stdlib modules
    for _, import in ipairs(self.imports) do
        -- Only process cz.* stdlib imports
        if import.path:match("^cz%.") then
            local file_path = get_stdlib_file_path(import.path)
            if file_path then
                local stdlib_ast = parse_stdlib_ast(file_path)
                if stdlib_ast then
                    -- Collect functions from stdlib and register under module name
                    for _, item in ipairs(stdlib_ast.items or {}) do
                        if item.kind == "struct" then
                            -- Could register structs if needed
                            self.structs[item.name] = item
                        elseif item.kind == "enum" then
                            self.enums[item.name] = item
                        elseif item.kind == "iface" then
                            self.ifaces[item.name] = item
                        elseif item.kind == "function" then
                            -- Register function under the module name (e.g., "cz.fmt")
                            if not self.functions[import.path] then
                                self.functions[import.path] = {}
                            end
                            if not self.functions[import.path][item.name] then
                                self.functions[import.path][item.name] = {}
                            end
                            
                            -- Set c_name for stdlib functions (cz_module_function format)
                            -- e.g., cz.fmt.printf -> cz_fmt_printf (use only last part of module)
                            if not item.c_name then
                                local module_last = import.path:match("[^.]+$")  -- cz.fmt -> fmt
                                item.c_name = "cz_" .. module_last .. "_" .. item.name
                            end
                            
                            table.insert(self.functions[import.path][item.name], item)
                        end
                    end
                end
            end
        end
    end

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
