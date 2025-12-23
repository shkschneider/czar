-- Code generator orchestration module
-- This is the main entry point for code generation (loaded as src/codegen/init.lua)
-- It coordinates all the specialized modules using module-level globals for simplicity

local Macros = require("src.macros")

-- Module-level globals shared across all codegen modules
local Codegen = {
    -- Load all modules for cross-module access
    Types = require("codegen.types"),
    Memory = require("codegen.memory"),
    Functions = require("codegen.functions"),
    Statements = require("codegen.statements"),
    Expressions = require("codegen.expressions"),
}
Codegen.__index = Codegen

local function join(list, sep)
    return table.concat(list, sep or "")
end

-- Cache for parsed stdlib files to avoid redundant parsing
local stdlib_file_cache = {}
local stdlib_ast_cache = {}

-- Parse a specific stdlib .cz file to collect #init blocks
-- This function is used during code generation to extract #init blocks
-- from imported stdlib modules, enabling automatic initialization
local function parse_stdlib_file(file_path)
    -- Check cache first to avoid redundant parsing
    if stdlib_file_cache[file_path] then
        return stdlib_file_cache[file_path]
    end

    local init_macros = {}

    -- Read the file
    local file = io.open(file_path, "r")
    if not file then
        stdlib_file_cache[file_path] = init_macros
        return init_macros
    end

    local source = file:read("*all")
    file:close()

    -- Parse using the already-loaded lexer and parser
    local lexer = require("lexer")
    local parser = require("parser")

    local tokens = lexer(source, file_path)
    local ast = parser(tokens, source)  -- Pass source as second parameter

    -- Collect #init macros from this file
    for _, item in ipairs(ast.items) do
        if item.kind == "init_macro" then
            table.insert(init_macros, item)
        end
    end

    -- Cache the result
    stdlib_file_cache[file_path] = init_macros
    return init_macros
end

-- Parse and fully process a stdlib .cz file to get its full AST
-- This is used to compile stdlib modules and include their functions
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

    -- Parse using the already-loaded lexer and parser
    local lexer = require("lexer")
    local parser = require("parser")

    local tokens = lexer(source, file_path)
    local ast = parser(tokens, source)

    -- Cache the result
    stdlib_ast_cache[file_path] = ast
    return ast
end

-- Map module imports to their .cz file paths
local function get_stdlib_file_path(import_path)
    local module_to_file = {
        -- string module defines the string struct type
        ["cz.string"] = "src/std/string.cz",
        -- fmt module provides formatted print functions
        ["cz.fmt"] = "src/std/fmt.cz",
        -- os module provides OS interface functions
        ["cz.os"] = "src/std/os.cz",
        -- arena allocator module
        ["cz.alloc.arena"] = "src/std/alloc/arena.cz",
        -- default allocator module
        ["cz.alloc.default"] = "src/std/alloc/default.cz",
        -- debug allocator module
        ["cz.alloc.debug"] = "src/std/alloc/debug.cz",
    }

    return module_to_file[import_path]
end

function Codegen.new(ast, options)
    options = options or {}
    local self = {
        ast = ast,
        structs = {},
        enums = {},
        ifaces = {},  -- Add interfaces support
        functions = {},
        out = {},
        scope_stack = {},
        heap_vars_stack = {},
        deferred_stack = {},  -- Stack of deferred statements per scope
        debug = options.debug or false,
        source_file = options.source_file or "unknown",
        source_path = options.source_path or options.source_file or "unknown",
        current_function = nil,
        custom_allocator_interface = nil,  -- Interface for custom allocator (#alloc)
        repeat_counter = 0,  -- Counter for generating unique repeat loop variables
        loop_label_counter = 0,  -- Counter for generating unique loop labels
        loop_stack = {},  -- Stack of loop info for multi-level break/continue
        c_imports = {},  -- C header files imported via import C : header.h
        init_macros = {},  -- #init macros to run during initialization,
        stdlib_init_blocks = {},  -- #init blocks from imported stdlib modules
    }
    return setmetatable(self, Codegen)
end

function Codegen:emit(line)
    table.insert(self.out, line)
end

-- Delegate to modules (they use _G.codegen_ctx directly)
function Codegen:alloc_call(size_expr, is_explicit)
    return Codegen.Memory.alloc_call(size_expr, is_explicit)
end

-- Keep old name for backward compatibility
Codegen.malloc_call = Codegen.alloc_call

function Codegen:free_call(ptr_expr, is_explicit)
    return Codegen.Memory.free_call(ptr_expr, is_explicit)
end

function Codegen:push_scope()
    Codegen.Memory.push_scope()
end

function Codegen:pop_scope()
    -- Check for unused variables before popping
    Codegen.Memory.check_unused_vars()
    Codegen.Memory.pop_scope()
end

function Codegen:add_var(name, type_node, mutable, needs_free, is_reference)
    Codegen.Memory.add_var(name, type_node, mutable, needs_free, is_reference)
end

function Codegen:mark_freed(name)
    Codegen.Memory.mark_freed(name)
end

function Codegen:add_deferred(stmt_code)
    Codegen.Memory.add_deferred(stmt_code)
end

function Codegen:get_scope_cleanup()
    return Codegen.Memory.get_scope_cleanup()
end

function Codegen:get_all_scope_cleanup()
    return Codegen.Memory.get_all_scope_cleanup()
end

function Codegen:get_var_type(name)
    return Codegen.Memory.get_var_type(name)
end

function Codegen:get_var_info(name)
    return Codegen.Memory.get_var_info(name)
end

function Codegen:mark_var_used(name)
    return Codegen.Memory.mark_var_used(name)
end

function Codegen:check_unused_vars()
    return Codegen.Memory.check_unused_vars()
end

function Codegen:is_pointer_type(type_node)
    return Codegen.Types.is_pointer_type(type_node)
end

function Codegen:c_type(type_node)
    return Codegen.Types.c_type(type_node)
end

function Codegen:c_type_in_struct(type_node, struct_name)
    return Codegen.Types.c_type_in_struct(type_node, struct_name)
end

function Codegen:get_expr_type(expr, depth)
    return Codegen.Types.get_expr_type(expr, depth)
end

function Codegen:type_name(type_node)
    return Codegen.Types.type_name(type_node)
end

function Codegen:is_struct_type(type_node)
    return Codegen.Types.is_struct_type(type_node)
end

function Codegen:is_pointer_var(name)
    return Codegen.Types.is_pointer_var(name)
end

function Codegen:infer_type(expr)
    return Codegen.Types.infer_type(expr)
end

function Codegen:types_match(type1, type2)
    return Codegen.Types.types_match(type1, type2)
end

function Codegen:type_name_string(type_node)
    return Codegen.Types.type_name_string(type_node)
end

function Codegen:sizeof_expr(type_node)
    return Codegen.Types.sizeof_expr(type_node)
end

function Codegen:resolve_arguments(func_name, args, params)
    return Codegen.Functions.resolve_arguments(func_name, args, params)
end

function Codegen:collect_structs_and_functions()
    Codegen.Functions.collect_structs_and_functions()
end

function Codegen:has_constructor(struct_name)
    return Codegen.Functions.has_constructor(struct_name)
end

function Codegen:has_destructor(struct_name)
    return Codegen.Functions.has_destructor(struct_name)
end

function Codegen:gen_constructor_call(struct_name, var_name)
    return Codegen.Functions.gen_constructor_call(struct_name, var_name)
end

function Codegen:gen_destructor_call(struct_name, var_name)
    return Codegen.Functions.gen_destructor_call(struct_name, var_name)
end

function Codegen:gen_params(params)
    return Codegen.Functions.gen_params(params)
end

function Codegen:gen_struct(item)
    Codegen.Functions.gen_struct(item)
end

function Codegen:gen_enum(item)
    Codegen.Functions.gen_enum(item)
end

function Codegen:gen_function(fn)
    Codegen.Functions.gen_function(fn)
end

function Codegen:gen_wrapper(has_main)
    Codegen.Functions.gen_wrapper(has_main)
end

function Codegen:gen_block(block)
    Codegen.Statements.gen_block(block)
end

function Codegen:gen_statement(stmt)
    return Codegen.Statements.gen_statement(stmt)
end

function Codegen:gen_expr(expr)
    return Codegen.Expressions.gen_expr(expr)
end

function Codegen:generate()
    -- First, collect C imports and stdlib imports from AST
    -- This needs to happen before collect_structs_and_functions so that
    -- stdlib functions are available during collection
    self.stdlib_imports = {}  -- Track stdlib imports like "cz.os", "cz.alloc", etc.
    self.stdlib_init_blocks = {}  -- Track #init blocks from imported stdlib modules
    self.stdlib_asts = {}  -- Track full ASTs of imported stdlib modules
    
    -- ALWAYS load string.cz since string is a global built-in type
    local string_ast = parse_stdlib_ast("src/std/string.cz")
    if not string_ast then
        error("FATAL: Failed to load src/std/string.cz - string is a required built-in type")
    end
    self.stdlib_asts["__builtin__string"] = string_ast
    
    for _, import in ipairs(self.ast.imports or {}) do
        if import.kind == "c_import" then
            for _, header in ipairs(import.headers) do
                table.insert(self.c_imports, header)
            end
        elseif import.kind == "import" then
            -- Track stdlib imports
            -- import.path is a table of parts, e.g., {"cz", "os"} or {"cz", "alloc"}
            local import_path = table.concat(import.path, ".")

            -- Only handle specific cz.* imports (not just "cz")
            if import_path:match("^cz%.") then
                self.stdlib_imports[import_path] = true

                -- Parse the stdlib file to extract #init blocks AND full AST
                local file_path = get_stdlib_file_path(import_path)
                if file_path then
                    local init_blocks = parse_stdlib_file(file_path)
                    if #init_blocks > 0 then
                        self.stdlib_init_blocks[import_path] = init_blocks
                    end
                    
                    -- Also parse full AST for function compilation
                    local stdlib_ast = parse_stdlib_ast(file_path)
                    if stdlib_ast then
                        self.stdlib_asts[import_path] = stdlib_ast
                    end
                end
            end
        end
    end

    -- Now collect structs and functions from main AST
    self:collect_structs_and_functions()
    
    -- Also collect structs and functions from stdlib ASTs
    for import_path, stdlib_ast in pairs(self.stdlib_asts) do
        -- Collect functions from stdlib module and register them under the module name
        for _, item in ipairs(stdlib_ast.items or {}) do
            if item.kind == "struct" then
                -- Skip re-registering string struct (already registered as global built-in)
                if item.name ~= "string" and not self.structs[item.name] then
                    self.structs[item.name] = item
                end
            elseif item.kind == "enum" then
                self.enums[item.name] = item
            elseif item.kind == "iface" then
                self.ifaces[item.name] = item
            elseif item.kind == "function" then
                -- Register function under the module name (e.g., "cz.fmt")
                if not self.functions[import_path] then
                    self.functions[import_path] = {}
                end
                if not self.functions[import_path][item.name] then
                    self.functions[import_path][item.name] = {}
                end
                
                -- Set c_name for stdlib functions (cz_module_function format)
                -- e.g., cz.fmt.printf -> cz_fmt_printf (use only last part of module)
                if not item.c_name then
                    local module_last = import_path:match("[^.]+$")  -- cz.fmt -> fmt
                    item.c_name = "cz_" .. module_last .. "_" .. item.name
                end
                
                table.insert(self.functions[import_path][item.name], item)
            end
        end
    end

    -- Process allocator macros (#alloc)
    -- Delegate to Macros module
    Macros.process_top_level(self, self.ast)

    -- Set default allocator based on debug mode if not already overridden
    if not self.custom_allocator_interface then
        if self.debug then
            self.custom_allocator_interface = "cz.alloc.debug"
        else
            self.custom_allocator_interface = "cz.alloc.default"
        end
    end

    self:emit("#include <stdint.h>")
    self:emit("#include <stdbool.h>")
    self:emit("#include <stdio.h>")
    self:emit("#include <stdlib.h>")
    self:emit("#include <string.h>")

    -- Emit C imports from import C : header.h
    for _, header in ipairs(self.c_imports) do
        self:emit(string.format("#include <%s>", header))
    end

    self:emit("")

    -- Global flag for runtime #DEBUG() support
    self:emit(string.format("static bool czar_debug_flag = %s;", self.debug and "true" or "false"))
    self:emit("")

    -- Generate memory tracking helpers only for cz.alloc.debug
    if self.custom_allocator_interface == "cz.alloc.debug" then
        Codegen.Memory.gen_memory_tracking_helpers()
    end

    for _, item in ipairs(self.ast.items) do
        if item.kind == "struct" then
            self:gen_struct(item)
        elseif item.kind == "enum" then
            self:gen_enum(item)
        end
    end

    local has_main = false

    -- Mark functions in AST as overloaded based on self.functions
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            local type_name = "__global__"
            if item.receiver_type then
                type_name = item.receiver_type
            end

            if self.functions[type_name] and self.functions[type_name][item.name] then
                local overloads = self.functions[type_name][item.name]
                if type(overloads) == "table" and #overloads > 1 then
                    item.is_overloaded = true
                else
                    item.is_overloaded = false
                end
            end
            
            -- Now set c_name for overloaded/generic functions (after is_overloaded is set)
            if not item.receiver_type and (item.is_overloaded or item.is_generic_instance) then
                local Functions = require("codegen.functions")
                item.c_name = Functions.generate_c_name(item.name, item.params, item.is_overloaded, item.generic_concrete_type)
            end
        end
    end
    
    -- Also mark stdlib functions as overloaded
    for import_path, stdlib_ast in pairs(self.stdlib_asts) do
        for _, item in ipairs(stdlib_ast.items) do
            if item.kind == "function" then
                -- For stdlib functions, they're registered under the module name
                if self.functions[import_path] and self.functions[import_path][item.name] then
                    local overloads = self.functions[import_path][item.name]
                    if type(overloads) == "table" and #overloads > 1 then
                        item.is_overloaded = true
                    else
                        item.is_overloaded = false
                    end
                end
                
                -- Now set c_name for overloaded/generic functions (after is_overloaded is set)
                if not item.receiver_type and (item.is_overloaded or item.is_generic_instance) then
                    local Functions = require("codegen.functions")
                    item.c_name = Functions.generate_c_name(item.name, item.params, item.is_overloaded, item.generic_concrete_type)
                end
            end
        end
    end

    -- First pass: collect all map types by generating functions into a temporary buffer
    local saved_out = self.out
    self.out = {}
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            if item.name == "main" then has_main = true end
            self:gen_function(item)
        end
    end
    
    -- Also generate functions from stdlib modules
    for import_path, stdlib_ast in pairs(self.stdlib_asts) do
        for _, item in ipairs(stdlib_ast.items) do
            if item.kind == "function" then
                self:gen_function(item)
            end
        end
    end
    
    local function_code = self.out
    self.out = saved_out

    -- Generate map struct definitions if any maps were discovered
    if self.map_types then
        for _, map_info in pairs(self.map_types) do
            self:emit(string.format("typedef struct %s {", map_info.map_type_name))
            self:emit(string.format("    %s* keys;", map_info.key_type_str))
            self:emit(string.format("    %s* values;", map_info.value_type_str))
            self:emit("    int32_t size;")
            self:emit("    int32_t capacity;")
            self:emit(string.format("} %s;", map_info.map_type_name))
            self:emit("")
        end
    end

    -- Generate pair struct definitions if any pairs were discovered
    if self.pair_types then
        for _, pair_info in pairs(self.pair_types) do
            local left_type_str = self:c_type(pair_info.left_type)
            local right_type_str = self:c_type(pair_info.right_type)
            self:emit(string.format("typedef struct %s {", pair_info.pair_type_name))
            self:emit(string.format("    %s left;", left_type_str))
            self:emit(string.format("    %s right;", right_type_str))
            self:emit(string.format("} %s;", pair_info.pair_type_name))
            self:emit("")
        end
    end

    -- Always include raw C implementations from src/std/ directory
    -- These are internal C library files that the generated code relies on
    local raw_c_files = {
        "src/std/string.c",
        "src/std/fmt.c",
        "src/std/os.c",
        "src/std/alloc/arena.c",
        "src/std/alloc/default.c",
        "src/std/alloc/debug.c",
    }

    for _, raw_file_path in ipairs(raw_c_files) do
        local file = io.open(raw_file_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            -- Extract just the filename for the comment
            local filename = raw_file_path:match("([^/]+)$")
            self:emit("// Raw C implementation from " .. filename)
            for line in content:gmatch("[^\r\n]+") do
                self:emit(line)
            end
            self:emit("")
        else
            error("Failed to open raw C file: " .. raw_file_path)
        end
    end

    -- Generate forward declarations for all functions to avoid C ordering issues
    self:emit("// Forward declarations")
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            Codegen.Functions.gen_function_declaration(item)
        end
    end
    
    -- Also forward declare stdlib functions
    for import_path, stdlib_ast in pairs(self.stdlib_asts) do
        for _, item in ipairs(stdlib_ast.items) do
            if item.kind == "function" then
                Codegen.Functions.gen_function_declaration(item)
            end
        end
    end
    self:emit("")

    -- Now emit the function code
    for _, line in ipairs(function_code) do
        self:emit(line)
    end

    self:gen_wrapper(has_main)

    local result = join(self.out, "\n") .. "\n"

    -- Safety check: warn about unsafe C functions in generated code
    local unsafe_functions = {
        -- Unsafe string operations (no bounds checking)
        "strcpy", "strcat", "strncpy", "strncat",
        "gets", "sprintf", "vsprintf",

        -- Unsafe string conversion functions (no error handling, undefined behavior on overflow)
        "atoi", "atof", "atol", "atoll",

        -- Unsafe formatted I/O (buffer overflow risks)
        "scanf", "sscanf", "vscanf", "vsscanf",

        -- Other commonly unsafe functions
        "strtok",   -- Not thread-safe, modifies input
        "tmpnam",   -- Race condition vulnerability
        "getenv",   -- Returns pointer to internal data
    }

    local safer_alternatives = {
        strcpy = "snprintf, memcpy with length check",
        strcat = "snprintf, strncat with proper length calculation",
        strncpy = "memcpy with explicit null termination",
        strncat = "snprintf or manual bounds checking",
        gets = "fgets with size limit",
        sprintf = "snprintf with buffer size",
        vsprintf = "vsnprintf with buffer size",
        atoi = "strtol with error checking",
        atof = "strtod with error checking",
        atol = "strtol with error checking",
        atoll = "strtoll with error checking",
        scanf = "fgets + sscanf or custom parsing",
        sscanf = "manual parsing with bounds checks",
        strtok = "strtok_r (reentrant) or manual parsing",
        tmpnam = "mkstemp",
        getenv = "secure_getenv or careful handling",
    }

    for _, unsafe_func in ipairs(unsafe_functions) do
        -- Match function calls: funcname( with possible whitespace
        if result:match(unsafe_func .. "%s*%(") then
            local Warnings = require("src.warnings")
            local alternative = safer_alternatives[unsafe_func] or "safer alternatives"
            print(Warnings.format("WARNING", self.source_file, 0, "unsafe-c-function",
                string.format("Generated code contains unsafe C function '%s'. " ..
                    "Consider using: %s",
                    unsafe_func, alternative), self.source_path))
        end
    end

    return result
end

return function(ast, options)
    _G.Codegen = Codegen.new(ast, options)
    return _G.Codegen:generate()
end
