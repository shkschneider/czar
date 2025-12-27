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

-- Load stdlib module definitions when imported
-- This function parses stdlib .cz files and merges their definitions into the current context
function Typechecker:load_stdlib_module(module_path)
    -- Handle wildcard imports: cz.fmt.* loads all from cz.fmt
    -- Handle explicit imports: cz.fmt.println loads only println from cz.fmt
    
    local is_wildcard = module_path:match("%*$")
    if is_wildcard then
        -- Remove the .* suffix
        module_path = module_path:gsub("%.[*]$", "")
    end
    
    -- Parse the path to determine if it's an explicit item import
    local parts = {}
    for part in module_path:gmatch("[^.]+") do
        table.insert(parts, part)
    end
    
    -- Map modules to their files
    local module_files = {
        ["cz.os"] = { "src/std/os.cz" },
        ["cz.fmt"] = { "src/std/fmt.cz" },
        -- Note: cz.string not included - String is a builtin type, not a module
        ["cz.math"] = { "src/std/math.cz" },
        ["cz"] = { "src/std/fmt.cz", "src/std/os.cz" },
        ["cz.alloc"] = { 
            "src/std/alloc/ialloc.cz",  -- Load interface first
            "src/std/alloc/arena.cz",
            "src/std/alloc/heap.cz",
            "src/std/alloc/debug.cz"
        },
    }
    
    -- Map explicit item imports to their files
    local item_to_file = {
        ["cz.fmt.print"] = "src/std/fmt.cz",
        ["cz.fmt.printf"] = "src/std/fmt.cz",
        ["cz.fmt.println"] = "src/std/fmt.cz",
        ["cz.alloc.Arena"] = "src/std/alloc/arena.cz",
        ["cz.alloc.Heap"] = "src/std/alloc/heap.cz",
        ["cz.alloc.Debug"] = "src/std/alloc/debug.cz",
        ["cz.alloc.iAlloc"] = "src/std/alloc/ialloc.cz",
        ["cz.os.Os"] = "src/std/os.cz",
    }
    
    local files_to_load = nil
    local base_module = nil
    local item_name = nil
    
    if is_wildcard then
        -- Wildcard import: load all files from the module
        files_to_load = module_files[module_path]
        base_module = module_path
    elseif #parts >= 3 then
        -- Explicit item import: cz.fmt.println
        item_name = parts[#parts]
        table.remove(parts)
        base_module = table.concat(parts, ".")
        
        local full_path = module_path
        local file_path = item_to_file[full_path]
        if file_path then
            files_to_load = { file_path }
        end
    else
        -- Module import without wildcard or item - error
        return
    end
    
    if not files_to_load then
        return
    end
    
    -- Load and parse each file
    local lexer = require("lexer")
    local parser = require("parser")
    
    for _, file_path in ipairs(files_to_load) do
        -- Read the file
        local file = io.open(file_path, "r")
        if file then
            local source = file:read("*all")
            file:close()
            
            -- Parse the file
            local ok, tokens = pcall(lexer, source, file_path)
            if ok then
                local ok2, module_ast = pcall(parser, tokens, source)
                if ok2 then
                    -- Merge structs, interfaces, enums, and functions from the module
                    -- Store them directly in namespace (flat import)
                    -- For explicit imports, only load the requested item
                    -- Also add them to the AST so codegen can see them
                    for _, item in ipairs(module_ast.items) do
                        -- Skip if this is an explicit import and the item doesn't match
                        if item_name and item.name ~= item_name and item.receiver_type ~= item_name then
                            goto continue
                        end
                        
                        if item.kind == "struct" and item.is_public then
                            -- Store directly with simple name: Arena (not alloc.Arena)
                            local struct_name = item.name
                            
                            -- Create a copy to avoid modifying the original
                            local struct_copy = {}
                            for k, v in pairs(item) do
                                struct_copy[k] = v
                            end
                            
                            -- Tag the struct with its module path for C code generation
                            struct_copy.module_path = base_module
                            
                            if not self.structs[struct_name] then
                                self.structs[struct_name] = struct_copy
                                -- Check if already in AST before adding
                                local already_in_ast = false
                                for _, ast_item in ipairs(self.ast.items) do
                                    if ast_item.kind == "struct" and ast_item.name == struct_name then
                                        already_in_ast = true
                                        break
                                    end
                                end
                                if not already_in_ast then
                                    struct_copy.is_imported = true  -- Mark as imported
                                    table.insert(self.ast.items, struct_copy)
                                end
                            end
                            
                            -- For structs that implement interfaces, auto-import those interfaces
                            if item.implements then
                                -- implements can be either a string or a table of strings
                                local iface_list = item.implements
                                if type(iface_list) == "string" then
                                    iface_list = { iface_list }
                                end
                                for _, iface_name in ipairs(iface_list) do
                                    self:load_stdlib_module(base_module .. "." .. iface_name)
                                end
                            end
                        elseif item.kind == "iface" and item.is_public then
                            -- Store directly with simple name: iAlloc (not alloc.iAlloc)
                            local iface_name = item.name
                            if not self.ifaces[iface_name] then
                                self.ifaces[iface_name] = item
                                -- Check if already in AST before adding
                                local already_in_ast = false
                                for _, ast_item in ipairs(self.ast.items) do
                                    if ast_item.kind == "iface" and ast_item.name == iface_name then
                                        already_in_ast = true
                                        break
                                    end
                                end
                                if not already_in_ast then
                                    item.is_imported = true  -- Mark as imported
                                    table.insert(self.ast.items, item)
                                end
                            end
                        elseif item.kind == "enum" and item.is_public then
                            local enum_name = item.name
                            if not self.enums[enum_name] then
                                self.enums[enum_name] = item
                                item.is_imported = true
                                table.insert(self.ast.items, item)
                            end
                        elseif item.kind == "var" and item.is_public then
                            -- Import global variables
                            local var_name = item.name
                            if not self.variables[var_name] then
                                self.variables[var_name] = item
                                item.is_imported = true
                                item.module_path = base_module
                                table.insert(self.ast.items, item)
                            end
                        elseif item.kind == "function" and item.is_public then
                            -- Merge public functions and methods
                            local type_name = "__global__"
                            if item.receiver_type then
                                -- Method on a type: use simple type name
                                type_name = item.receiver_type
                            end
                            
                            if not self.functions[type_name] then
                                self.functions[type_name] = {}
                            end
                            
                            local func_name = item.name
                            if not self.functions[type_name][func_name] then
                                self.functions[type_name][func_name] = {}
                            end
                            
                            table.insert(self.functions[type_name][func_name], item)
                            -- Mark as imported with module path and add to AST for codegen
                            item.is_imported = true
                            item.module_path = base_module
                            table.insert(self.ast.items, item)
                        end
                        
                        ::continue::
                    end
                end
            end
        end
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
            
            -- Wildcard imports (ending in *) are always considered used
            -- since items are imported directly into namespace
            local is_wildcard = module_path:match("%*$")
            
            table.insert(self.imports, {
                path = module_path,
                alias = alias,
                used = is_wildcard or false,  -- Mark wildcard imports as used
                line = import.line,
                col = import.col
            })
            
            -- Register cz module builtins if importing from cz
            if import.path[1] == "cz" then
                self:register_cz_builtins()
            end
            
            -- Load stdlib module definitions if this is a stdlib import
            self:load_stdlib_module(module_path)
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
