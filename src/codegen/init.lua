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

function Codegen.new(ast, options)
    options = options or {}
    local self = {
        ast = ast,
        structs = {},
        enums = {},
        functions = {},
        out = {},
        scope_stack = {},
        heap_vars_stack = {},
        debug = options.debug or false,
        source_file = options.source_file or "unknown",
        source_path = options.source_path or options.source_file or "unknown",
        current_function = nil,
        custom_malloc = nil,
        custom_free = nil,
        type_aliases = {
            -- Built-in alias for String -> char*
            ["String"] = "char*"
        },
    }
    return setmetatable(self, Codegen)
end

function Codegen:emit(line)
    table.insert(self.out, line)
end

-- Delegate to modules (they use _G.codegen_ctx directly)
function Codegen:malloc_call(size_expr, is_explicit)
    return Codegen.Memory.malloc_call(size_expr, is_explicit)
end

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

function Codegen:add_var(name, type_node, mutable, needs_free)
    Codegen.Memory.add_var(name, type_node, mutable, needs_free)
end

function Codegen:mark_freed(name)
    Codegen.Memory.mark_freed(name)
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
    self:collect_structs_and_functions()
    
    -- Process allocator macros (#malloc, #free) and type aliases (#alias)
    -- Delegate to Macros module
    Macros.process_top_level(self, self.ast)
    
    -- In debug mode, automatically use cz_malloc/cz_free if not already overridden
    if self.debug then
        if not self.custom_malloc then
            self.custom_malloc = "cz_malloc"
        end
        if not self.custom_free then
            self.custom_free = "cz_free"
        end
    end
    
    self:emit("#include <stdint.h>")
    self:emit("#include <stdbool.h>")
    self:emit("#include <stdio.h>")
    self:emit("#include <stdlib.h>")
    self:emit("#include <string.h>")
    self:emit("")
    
    -- Global flag for runtime #DEBUG() support
    self:emit(string.format("static bool czar_debug_flag = %s;", self.debug and "true" or "false"))
    self:emit("")

    if self.debug then
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
    -- First pass: collect all map types by generating functions into a temporary buffer
    local saved_out = self.out
    self.out = {}
    for _, item in ipairs(self.ast.items) do
        if item.kind == "function" then
            if item.name == "main" then has_main = true end
            self:gen_function(item)
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
    
    -- Generate string struct definition if any strings were discovered
    if self.has_string_type then
        self:emit("typedef struct czar_string {")
        self:emit("    char* data;")
        self:emit("    int32_t length;")
        self:emit("    int32_t capacity;")
        self:emit("} czar_string;")
        self:emit("")
        
        -- Generate string helper functions
        self:emit("// String helper function: get C-style null-terminated string")
        self:emit("static inline char* czar_string_cstr(czar_string* s) {")
        self:emit("    return s->data;")
        self:emit("}")
        self:emit("")
    end
    
    -- Now emit the function code
    for _, line in ipairs(function_code) do
        self:emit(line)
    end

    self:gen_wrapper(has_main)

    local result = join(self.out, "\n") .. "\n"
    return result
end

return function(ast, options)
    _G.Codegen = Codegen.new(ast, options)
    return _G.Codegen:generate()
end
