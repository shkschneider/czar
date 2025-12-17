-- Typechecker declaration collection
-- Handles collection of top-level declarations (structs, enums, functions)

local Errors = require("errors")

local Declarations = {}

-- Collect all top-level declarations
function Declarations.collect_declarations(typechecker)
    for _, item in ipairs(typechecker.ast.items) do
        if item.kind == "struct" then
            -- Check for duplicate struct definition
            if typechecker.structs[item.name] then
                local line = item.line or 0
                local prev_line = typechecker.structs[item.name].line or 0
                local msg = string.format(
                    "Duplicate struct definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_STRUCT, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
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
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        field_names[field.name] = true
                    end
                end
                typechecker.structs[item.name] = item
            end
        elseif item.kind == "enum" then
            -- Check for duplicate enum definition
            if typechecker.enums[item.name] then
                local line = item.line or 0
                local prev_line = typechecker.enums[item.name].line or 0
                local msg = string.format(
                    "Duplicate enum definition '%s' (previously defined at line %d)",
                    item.name, prev_line
                )
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_ENUM, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
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
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_FIELD, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        value_names[value.name] = true
                    end
                end
                typechecker.enums[item.name] = item
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

            if not typechecker.functions[type_name] then
                typechecker.functions[type_name] = {}
            end

            -- Check for duplicate function/method definition
            if typechecker.functions[type_name][item.name] then
                local line = item.line or 0
                local prev_line = typechecker.functions[type_name][item.name].line or 0
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
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_FUNCTION, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
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
                        local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                            Errors.ErrorType.DUPLICATE_PARAMETER, msg, typechecker.source_path)
                        typechecker:add_error(formatted_error)
                    else
                        param_names[param.name] = true
                    end
                end
                typechecker.functions[type_name][item.name] = item
            end
        elseif item.kind == "alias_macro" then
            -- Store type aliases
            if typechecker.type_aliases[item.alias_name] then
                local line = item.line or 0
                local msg = string.format("duplicate #alias for '%s'", item.alias_name)
                local formatted_error = Errors.format("ERROR", typechecker.source_file, line,
                    Errors.ErrorType.DUPLICATE_ALIAS, msg, typechecker.source_path)
                typechecker:add_error(formatted_error)
            else
                typechecker.type_aliases[item.alias_name] = item.target_type_str
            end
        elseif item.kind == "allocator_macro" then
            -- Store other macros but don't type check them
        end
    end
end

return Declarations
