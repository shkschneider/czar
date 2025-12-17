-- Typechecker: Main entry point for type checking pass
-- This module performs type checking after AST construction and before lowering
-- It resolves names, infers types, checks type compatibility, and enforces mutability rules

local Resolver = require("typechecker.resolver")
local Inference = require("typechecker.inference")
local Mutability = require("typechecker.mutability")
local Errors = require("errors")

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
        source_file = options.source_file or "<unknown>",  -- Source filename for error messages
        source_path = options.source_path or options.source_file or "<unknown>",  -- Full path for reading source
        loop_depth = 0,    -- Track if we're inside a loop for break/continue validation
        require_main = options.require_main or false,  -- Whether to enforce presence of main function
        module_name = nil, -- Current module name
        imports = {},      -- Imported modules: { module_path, alias, used }
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

    -- Register println: takes a string, returns void
    self.functions["__global__"]["println"] = {
        name = "println",
        params = {
            {
                name = "str",
                type = { kind = "pointer", to = { kind = "named_type", name = "char" } },
                mutable = false
            }
        },
        return_type = { kind = "named_type", name = "void" },
        is_builtin = true
    }

    -- Register print: takes a string, returns void
    self.functions["__global__"]["print"] = {
        name = "print",
        params = {
            {
                name = "str",
                type = { kind = "pointer", to = { kind = "named_type", name = "char" } },
                mutable = false
            }
        },
        return_type = { kind = "named_type", name = "void" },
        is_builtin = true
    }

    -- Register printf: takes a format string and variadic arguments, returns void
    -- Note: Uses 'any' type for varargs since C printf accepts multiple types (i32, f32, char*, etc.)
    -- Type safety is enforced by the format string at runtime in C
    self.functions["__global__"]["printf"] = {
        name = "printf",
        params = {
            {
                name = "format",
                type = { kind = "pointer", to = { kind = "named_type", name = "char" } },
                mutable = false
            },
            {
                name = "args",
                type = { kind = "varargs", element_type = { kind = "named_type", name = "any" } },
                mutable = false
            }
        },
        return_type = { kind = "named_type", name = "void" },
        is_builtin = true
    }

    -- Register print_i32 for compatibility
    self.functions["__global__"]["print_i32"] = {
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
end

-- Main entry point: type check the entire AST
function Typechecker:check()
    -- Process module declaration and validate module naming rules
    if self.ast.module then
        self.module_name = table.concat(self.ast.module.path, ".")
        self:validate_module_name()
    end
    
    -- Process imports
    for _, import in ipairs(self.ast.imports or {}) do
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
    
    -- Pass 1: Collect all top-level declarations (structs, functions)
    self:collect_declarations()

    -- Pass 2: Type check all functions
    self:check_all_functions()

    -- Pass 3: Validate main function if required for binary output
    if self.require_main then
        self:validate_main_function()
    end
    
    -- Pass 4: Check for unused imports
    self:check_unused_imports()

    -- Report any errors
    if #self.errors > 0 then
        local error_msg = Errors.format_phase_errors("Type checking", self.errors)
        error(error_msg)
    end

    -- Return the annotated AST
    return self.ast
end

-- Collect all top-level declarations
function Typechecker:collect_declarations()
    for _, item in ipairs(self.ast.items) do
        if item.kind == "struct" then
            -- Check for duplicate struct definition
            if self.structs[item.name] then
                local line = item.line or 0
                local prev_line = self.structs[item.name].line or 0
                local msg = string.format(
                    "Duplicate struct definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.DUPLICATE_STRUCT, msg, self.source_path)
                self:add_error(formatted_error)
            else
                -- Check for duplicate field names within the struct
                local field_names = {}
                for _, field in ipairs(item.fields) do
                    if field_names[field.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate field '%s' in struct '%s'",
                            field.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", self.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, self.source_path)
                        self:add_error(formatted_error)
                    else
                        field_names[field.name] = true
                    end
                end
                self.structs[item.name] = item
            end
        elseif item.kind == "enum" then
            -- Check for duplicate enum definition
            if self.enums[item.name] then
                local line = item.line or 0
                local prev_line = self.enums[item.name].line or 0
                local msg = string.format(
                    "Duplicate enum definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.DUPLICATE_ENUM, msg, self.source_path)
                self:add_error(formatted_error)
            else
                -- Check for duplicate value names within the enum
                local value_names = {}
                for _, value in ipairs(item.values) do
                    if value_names[value.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate value '%s' in enum '%s'",
                            value.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", self.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, self.source_path)
                        self:add_error(formatted_error)
                    else
                        value_names[value.name] = true
                    end
                end
                self.enums[item.name] = item
            end
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

            -- Check for duplicate function/method definition
            if self.functions[type_name][item.name] then
                local line = item.line or 0
                local prev_line = self.functions[type_name][item.name].line or 0
                local msg
                if type_name == "__global__" then
                    msg = string.format(
                        "Duplicate function definition '%s' (previously defined at line %d)",
                        item.name, prev_line
                    )
                else
                    msg = string.format(
                        "Duplicate method definition '%s::%s' (previously defined at line %d)",
                        type_name, item.name, prev_line
                    )
                end
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.DUPLICATE_FUNCTION, msg, self.source_path)
                self:add_error(formatted_error)
            else
                -- Check for duplicate parameter names within the function
                -- Allow multiple '_' parameters (convention for unused/ignored parameters)
                local param_names = {}
                for _, param in ipairs(item.params) do
                    if param.name ~= "_" and param_names[param.name] then
                        local line = item.line or 0
                        local msg = string.format(
                            "Duplicate parameter '%s' in function '%s'",
                            param.name, item.name
                        )
                        local formatted_error = Errors.format("ERROR", self.source_file, line,
                            Errors.ErrorType.DUPLICATE_PARAMETER, msg, self.source_path)
                        self:add_error(formatted_error)
                    else
                        param_names[param.name] = true
                    end
                end
                self.functions[type_name][item.name] = item
            end
        elseif item.kind == "alias_macro" then
            -- Store type aliases
            if self.type_aliases[item.alias_name] then
                local line = item.line or 0
                local msg = string.format("duplicate #alias for '%s'", item.alias_name)
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.DUPLICATE_ALIAS, msg, self.source_path)
                self:add_error(formatted_error)
            else
                self.type_aliases[item.alias_name] = item.target_type_str
            end
        elseif item.kind == "allocator_macro" then
            -- Store other macros but don't type check them
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
    -- Store current function for return statement checking
    self.current_function = func

    -- Create a new scope for this function
    self:push_scope()

    -- Add receiver (self) to scope if this is a method
    if func.receiver then
        local receiver_type = func.receiver.type
        local is_mutable = func.receiver.mutable
        self:add_var("self", receiver_type, is_mutable)
    end

    -- Add parameters to scope and validate varargs
    local has_varargs = false
    for i, param in ipairs(func.params) do
        local param_type = param.type
        -- In explicit pointer model, check mutable field directly
        local is_mutable = param.mutable or false

        -- Check for varargs
        if param_type.kind == "varargs" then
            has_varargs = true
            -- Varargs cannot be mutable
            if is_mutable then
                local line = func.line or 0
                local msg = string.format("varargs parameter '%s' cannot be mutable (varargs are read-only like slices)", param.name)
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
                self:add_error(formatted_error)
            end
            -- Varargs must be the last parameter (already checked in parser, but double-check)
            if i ~= #func.params then
                local line = func.line or 0
                local msg = string.format("varargs parameter '%s' must be the last parameter", param.name)
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
                self:add_error(formatted_error)
            end
        end

        self:add_var(param.name, param_type, is_mutable)
    end

    -- Type check the function body
    self:check_block(func.body)

    -- Check if non-void function has return statement
    if func.return_type.kind ~= "named_type" or func.return_type.name ~= "void" then
        local has_return = self:block_has_return(func.body)
        if not has_return then
            local line = func.line or 0
            local msg = string.format(
                "Function '%s' with return type '%s' must return a value in all code paths",
                func.name,
                self:type_to_string(func.return_type)
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.MISSING_RETURN, msg, self.source_path)
            self:add_error(formatted_error)
        end
    end

    -- Pop the function scope
    self:pop_scope()

    -- Clear current function
    self.current_function = nil
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
    elseif stmt.kind == "for" then
        self:check_for(stmt)
    elseif stmt.kind == "repeat" then
        self:check_repeat(stmt)
    elseif stmt.kind == "break" then
        self:check_break(stmt)
    elseif stmt.kind == "continue" then
        self:check_continue(stmt)
    elseif stmt.kind == "return" then
        self:check_return(stmt)
    elseif stmt.kind == "expr_stmt" then
        -- Check if the expression is an assignment
        if stmt.expression and stmt.expression.kind == "assign" then
            self:check_assign(stmt.expression)
        else
            self:check_expression(stmt.expr or stmt.expression)
        end
    elseif stmt.kind == "free" then
        self:check_expression(stmt.expr)
    end
end

-- Type check a variable declaration
function Typechecker:check_var_decl(stmt)
    local var_type = stmt.type
    local is_mutable = stmt.mutable or false

    -- Check if trying to declare a mutable slice (not allowed)
    if var_type.kind == "slice" and is_mutable then
        local line = stmt.line or 0
        local msg = "Slices cannot be declared as mutable"
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    end

    -- Handle implicit array size (Type[*])
    if var_type.kind == "array" and var_type.size == "*" then
        if not stmt.init then
            local line = stmt.line or 0
            local msg = "Arrays with implicit size must have an initializer"
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
            self:add_error(formatted_error)
        else
            local init_type = self:check_expression(stmt.init)

            -- Check that initializer is an array literal or array
            if init_type and init_type.kind == "array" then
                -- Infer the size from the initializer
                var_type.size = init_type.size
                stmt.type = var_type

                -- Check element type compatibility
                if not Inference.types_compatible(var_type.element_type, init_type.element_type, self) then
                    local line = stmt.line or 0
                    local msg = string.format(
                        "Array element type mismatch: expected %s, got %s",
                        Inference.type_to_string(var_type.element_type),
                        Inference.type_to_string(init_type.element_type)
                    )
                    local formatted_error = Errors.format("ERROR", self.source_file, line,
                        Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
                    self:add_error(formatted_error)
                end
            else
                local line = stmt.line or 0
                local msg = "Implicit array size requires array literal or array initializer"
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
                self:add_error(formatted_error)
            end
        end
    elseif stmt.init then
        -- Type check the initializer if present (for non-implicit arrays)
        local init_type = self:check_expression(stmt.init)

        -- Check type compatibility
        if not Inference.types_compatible(var_type, init_type, self) then
            local line = stmt.line or 0
            local msg = string.format(
                "Type mismatch in variable '%s': expected %s, got %s",
                stmt.name,
                Inference.type_to_string(var_type),
                Inference.type_to_string(init_type)
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
            self:add_error(formatted_error)
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
    if not Inference.types_compatible(target_type, value_type, self) then
        local line = stmt.line or (stmt.target and stmt.target.line) or 0
        local msg = string.format(
            "Type mismatch in assignment: expected %s, got %s",
            Inference.type_to_string(target_type),
            Inference.type_to_string(value_type)
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    end

    -- Check const-correctness: cannot assign immutable value to mutable target
    -- This prevents discarding const qualifiers in generated C code
    if stmt.value.kind == "identifier" then
        local value_var_info = Resolver.resolve_name(self, stmt.value.name)
        if value_var_info and not value_var_info.mutable then
            -- Value is immutable (const in C)
            -- Check if target needs a mutable value
            local target_needs_mut = false

            if stmt.target.kind == "identifier" then
                local target_var_info = Resolver.resolve_name(self, stmt.target.name)
                target_needs_mut = target_var_info and target_var_info.mutable
            elseif stmt.target.kind == "field" and stmt.target.object.kind == "identifier" then
                local obj_var_info = Resolver.resolve_name(self, stmt.target.object.name)
                -- Field assignment to mutable object means we need non-const value
                target_needs_mut = obj_var_info and obj_var_info.mutable
            end

            if target_needs_mut and value_type and value_type.kind == "pointer" then
                local line = stmt.line or stmt.value.line or 0
                local msg = string.format(
                    "Cannot assign immutable pointer '%s' to mutable location. The value has const qualifier. Use 'mut %s' if you need to reassign it.",
                    stmt.value.name,
                    stmt.value.name
                )
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.CONST_QUALIFIER_DISCARDED, msg, self.source_path)
                self:add_error(formatted_error)
            end
        end
    end
end

-- Type check an if statement
function Typechecker:check_if(stmt)
    -- Type check condition
    local cond_type = self:check_expression(stmt.condition)

    -- Condition should be bool
    if not Inference.is_bool_type(cond_type) then
        local line = stmt.line or (stmt.condition and stmt.condition.line) or 0
        local msg = string.format(
            "Condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg)
        self:add_error(formatted_error)
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
                local line = branch.line or (branch.condition and branch.condition.line) or 0
                local msg = string.format(
                    "Elseif condition must be bool, got %s",
                    Inference.type_to_string(branch_cond_type)
                )
                local formatted_error = Errors.format("ERROR", self.source_file, line,
                    Errors.ErrorType.TYPE_MISMATCH, msg)
                self:add_error(formatted_error)
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
        local line = stmt.line or (stmt.condition and stmt.condition.line) or 0
        local msg = string.format(
            "While condition must be bool, got %s",
            Inference.type_to_string(cond_type)
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg)
        self:add_error(formatted_error)
    end

    -- Type check body (increment loop depth for break/continue)
    self.loop_depth = self.loop_depth + 1
    self:push_scope()
    self:check_block(stmt.body)
    self:pop_scope()
    self.loop_depth = self.loop_depth - 1
end

-- Type check a for statement
function Typechecker:check_for(stmt)
    -- Type check the collection
    local collection_type = self:check_expression(stmt.collection)

    if not collection_type then
        return
    end

    -- Collection must be an array, slice, or varargs
    if collection_type.kind ~= "array" and collection_type.kind ~= "slice" and collection_type.kind ~= "varargs" then
        local line = stmt.line or (stmt.collection and stmt.collection.line) or 0
        local msg = string.format(
            "For loop collection must be an array, slice, or varargs, got '%s'",
            self:type_to_string(collection_type)
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
        return
    end

    -- Check if trying to iterate with mut item on immutable collection
    if stmt.item_mutable and not stmt.item_is_underscore then
        -- Get the collection mutability
        local collection_is_mutable = false
        if stmt.collection.kind == "identifier" then
            local var_info = self:get_var_info(stmt.collection.name)
            if var_info then
                collection_is_mutable = var_info.mutable
            end
        end

        -- If collection is not mutable, item cannot be mut
        if not collection_is_mutable then
            local line = stmt.line or 0
            local msg = string.format(
                "Cannot declare mutable item '%s' when iterating over immutable collection",
                stmt.item_name
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
            self:add_error(formatted_error)
        end

        -- Slices and varargs are always read-only
        if collection_type.kind == "slice" or collection_type.kind == "varargs" then
            local line = stmt.line or 0
            local msg = string.format(
                "Cannot declare mutable item '%s' when iterating over %s (slices and varargs are read-only)",
                stmt.item_name,
                collection_type.kind
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
            self:add_error(formatted_error)
        end
    end

    -- Type check body in new scope (increment loop depth for break/continue)
    self.loop_depth = self.loop_depth + 1
    self:push_scope()

    -- Add index variable to scope (always i32)
    if not stmt.index_is_underscore and stmt.index_name then
        self:add_var(stmt.index_name, { kind = "named_type", name = "i32" }, false)
    end

    -- Add item variable to scope with element type
    if not stmt.item_is_underscore and stmt.item_name then
        local element_type = collection_type.element_type
        if stmt.item_mutable then
            -- Mutable item: pointer to element
            local pointer_type = { kind = "pointer", to = element_type }
            self:add_var(stmt.item_name, pointer_type, true)
        else
            -- Immutable item: value copy
            self:add_var(stmt.item_name, element_type, false)
        end
    end

    self:check_block(stmt.body)
    self:pop_scope()
    self.loop_depth = self.loop_depth - 1
end

-- Type check a repeat statement
function Typechecker:check_repeat(stmt)
    -- Type check count expression
    local count_type = self:check_expression(stmt.count)

    -- Count must be an integer type (i8, i16, i32, i64, u8, u16, u32, u64)
    local is_int_type = count_type and
                        count_type.kind == "named_type" and
                        count_type.name:match("^[iu]%d+$") ~= nil

    if not is_int_type then
        local line = stmt.line or (stmt.count and stmt.count.line) or 0
        local msg = string.format(
            "Repeat count must be an integer type, got %s",
            Inference.type_to_string(count_type)
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    end

    -- Type check body (increment loop depth for break/continue)
    self.loop_depth = self.loop_depth + 1
    self:push_scope()
    self:check_block(stmt.body)
    self:pop_scope()
    self.loop_depth = self.loop_depth - 1
end

-- Type check a break statement
function Typechecker:check_break(stmt)
    local level = stmt.level or 1  -- Default to 1 if not specified

    if self.loop_depth == 0 then
        local line = stmt.line or 0
        local msg = "Break statement must be inside a loop"
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    elseif level > self.loop_depth then
        local line = stmt.line or 0
        local msg = string.format(
            "Break level %d exceeds loop depth %d",
            level, self.loop_depth
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    elseif level < 1 then
        local line = stmt.line or 0
        local msg = string.format(
            "Break level must be at least 1, got %d",
            level
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    end
end

-- Type check a continue statement
function Typechecker:check_continue(stmt)
    local level = stmt.level or 1  -- Default to 1 if not specified

    if self.loop_depth == 0 then
        local line = stmt.line or 0
        local msg = "Continue statement must be inside a loop"
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    elseif level > self.loop_depth then
        local line = stmt.line or 0
        local msg = string.format(
            "Continue level %d exceeds loop depth %d",
            level, self.loop_depth
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    elseif level < 1 then
        local line = stmt.line or 0
        local msg = string.format(
            "Continue level must be at least 1, got %d",
            level
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.TYPE_MISMATCH, msg, self.source_path)
        self:add_error(formatted_error)
    end
end

-- Type check a return statement
function Typechecker:check_return(stmt)
    if stmt.value then
        -- Check if we're in a void function
        if self.current_function and
           self.current_function.return_type.kind == "named_type" and
           self.current_function.return_type.name == "void" then
            local line = stmt.line or 0
            local msg = string.format(
                "Function '%s' has void return type but is returning a value",
                self.current_function.name
            )
            local formatted_error = Errors.format("ERROR", self.source_file, line,
                Errors.ErrorType.VOID_FUNCTION_RETURNS_VALUE, msg, self.source_path)
            self:add_error(formatted_error)
        end

        local return_type = self:check_expression(stmt.value)

        -- Check for returning address to stack variable
        if stmt.value.kind == "unary" and stmt.value.op == "&" then
            -- User is returning &variable
            local operand = stmt.value.operand
            if operand.kind == "identifier" then
                local var_info = Resolver.resolve_name(self, operand.name)
                if var_info then
                    local var_type = var_info.type
                    -- Check if this is a stack-allocated variable (not a pointer)
                    if var_type and var_type.kind ~= "pointer" then
                        local line = stmt.line or stmt.value.line or 0
                        local msg = string.format(
                            "Cannot return address of stack variable '%s'. The variable will be destroyed when the function returns. Use 'return clone %s' to return a heap-allocated copy.",
                            operand.name,
                            operand.name
                        )
                        local formatted_error = Errors.format("ERROR", self.source_file, line,
                            Errors.ErrorType.RETURN_STACK_REFERENCE, msg)
                        self:add_error(formatted_error)
                    end
                end
            end
        end

        -- Note: 'return clone stack_var' is safe because clone allocates on heap
        -- and returns a pointer to the heap-allocated copy
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

-- Helper: Check if a block has a return statement in all paths
function Typechecker:block_has_return(block)
    local statements = block.statements or block

    for _, stmt in ipairs(statements) do
        if stmt.kind == "return" then
            return true
        elseif stmt.kind == "if" then
            -- For if statements, all branches must have returns
            local then_has_return = self:block_has_return(stmt.then_block)

            -- Check all elseif branches
            local all_elseif_have_return = true
            if stmt.elseif_branches then
                for _, branch in ipairs(stmt.elseif_branches) do
                    if not self:block_has_return(branch.block) then
                        all_elseif_have_return = false
                        break
                    end
                end
            end

            -- Check else branch
            local else_has_return = stmt.else_block and self:block_has_return(stmt.else_block) or false

            -- Only return true if we have an else and all branches return
            if stmt.else_block and then_has_return and all_elseif_have_return and else_has_return then
                return true
            end
        end
        -- Note: we don't check while loops as they might not execute
    end

    return false
end

-- Helper: Convert type to string for error messages
function Typechecker:type_to_string(type_node)
    if not type_node then
        return "unknown"
    end

    if type_node.kind == "named_type" then
        return type_node.name
    elseif type_node.kind == "pointer" then
        return self:type_to_string(type_node.to) .. "*"
    elseif type_node.kind == "array" then
        return self:type_to_string(type_node.element_type) .. "[" .. (type_node.size or "*") .. "]"
    elseif type_node.kind == "slice" then
        return self:type_to_string(type_node.element_type) .. "[:]"
    elseif type_node.kind == "varargs" then
        return self:type_to_string(type_node.element_type) .. "..."
    end

    return "unknown"
end

-- Validate that a main function exists with the correct signature
function Typechecker:validate_main_function()
    -- Check if main function exists in global functions
    local global_functions = self.functions["__global__"]
    if not global_functions or not global_functions["main"] then
        local msg = "Missing 'main' function. When building a binary, a 'main' function with signature 'fn main() i32' is required"
        local formatted_error = Errors.format("ERROR", self.source_file, 0,
            Errors.ErrorType.MISSING_MAIN_FUNCTION, msg, self.source_path)
        self:add_error(formatted_error)
        return
    end

    -- Validate main function signature
    local main_func = global_functions["main"]

    -- Check return type (must be i32)
    local return_type = main_func.return_type
    local is_valid_return = return_type and
                           return_type.kind == "named_type" and
                           return_type.name == "i32"

    if not is_valid_return then
        local line = main_func.line or 0
        local actual_return = return_type and self:type_to_string(return_type) or "unknown"
        local msg = string.format(
            "Invalid 'main' function signature: return type must be i32, got %s. Expected signature: 'fn main() i32'",
            actual_return
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.INVALID_MAIN_SIGNATURE, msg, self.source_path)
        self:add_error(formatted_error)
    end

    -- Check parameters (must have no parameters)
    if main_func.params and #main_func.params > 0 then
        local line = main_func.line or 0
        local msg = string.format(
            "Invalid 'main' function signature: must have no parameters, got %d parameter(s). Expected signature: 'fn main() i32'",
            #main_func.params
        )
        local formatted_error = Errors.format("ERROR", self.source_file, line,
            Errors.ErrorType.INVALID_MAIN_SIGNATURE, msg, self.source_path)
        self:add_error(formatted_error)
    end
end

-- Validate module name follows directory structure rules
function Typechecker:validate_module_name()
    if not self.module_name or not self.source_path then
        return
    end
    
    -- Extract directory structure from source path
    -- e.g., "tests/ok/app/geometry/point.cz" -> ["tests", "ok", "app", "geometry"]
    local path_parts = {}
    for part in self.source_path:gmatch("[^/]+") do
        table.insert(path_parts, part)
    end
    
    -- Remove the filename (last part)
    table.remove(path_parts)
    
    -- Get module name parts
    local module_parts = {}
    for part in self.module_name:gmatch("[^.]+") do
        table.insert(module_parts, part)
    end
    
    -- Exception: "main" module can be declared in any directory as an entry point
    local is_main_module = (#module_parts == 1 and module_parts[1] == "main")
    
    -- For multi-part module names, or single-part non-main modules in subdirectories:
    -- Module name must end with the directory name
    if #path_parts > 0 and not is_main_module then
        local dir_name = path_parts[#path_parts]
        
        -- Module name must end with the directory name
        -- e.g., module "app.geometry" in directory "geometry" is valid
        -- e.g., module "app" in directory "app" is valid
        -- e.g., module "examples" in directory "ok" is invalid
        -- e.g., module "app.math" in directory "geometry" is invalid
        if #module_parts > 0 and module_parts[#module_parts] ~= dir_name then
            local msg = string.format(
                "Module name '%s' must end with directory name '%s' (expected: '...%s'). Only 'main' module can be declared as entry point in any folder.",
                self.module_name, dir_name, dir_name
            )
            local formatted_error = Errors.format("ERROR", self.source_file, 0,
                Errors.ErrorType.INVALID_MODULE_NAME, msg, self.source_path)
            self:add_error(formatted_error)
        end
    end
end

-- Check for unused imports and generate warnings
function Typechecker:check_unused_imports()
    local Warnings = require("warnings")
    
    -- Helper to extract the last component of a module path (e.g., "cz.io" -> "io")
    local function get_default_alias(module_path)
        return module_path:match("[^.]+$")
    end
    
    for _, import in ipairs(self.imports) do
        if not import.used then
            local msg = string.format("Unused import '%s'", import.path)
            -- Only mention alias if it differs from the default
            if import.alias and import.alias ~= get_default_alias(import.path) then
                msg = string.format("Unused import '%s' (aliased as '%s')", import.path, import.alias)
            end
            
            Warnings.emit(self.source_file, import.line or 0,
                Warnings.WarningType.UNUSED_IMPORT, msg, self.source_path)
        end
    end
end

-- Module entry point
return function(ast, options)
    local checker = Typechecker.new(ast, options)
    return checker:check()
end
