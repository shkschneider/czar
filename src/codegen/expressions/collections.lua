-- Collection expression generation
-- Handles: new_heap, new_array, new_map, array_literal, slice, new_pair, pair_literal, map_literal, new_string, string_literal

local Collections = {}

local function ctx() return _G.Codegen end

local function join(list, sep)
    return table.concat(list, sep or "")
end

-- Constants
local MAP_MIN_CAPACITY = 16  -- Minimum capacity for newly allocated maps

-- Generate new heap-allocated struct
function Collections.gen_new_heap(expr, gen_expr_fn)
    -- new Type { fields... }
    -- Allocate on heap and initialize fields
    -- Note: Automatic scope-based cleanup implemented - freed at scope exit
    
    -- Special handling for String struct with string literal
    if expr.type_name == "String" and expr.is_string_literal then
        local str_value = expr.string_value or ""
        local str_len = #str_value
        
        -- Generate code: malloc + initialize
        local statements = {}
        table.insert(statements, string.format("cz_string* _str = %s", 
            ctx():alloc_call("sizeof(cz_string)", true)))
        -- Allocate capacity with room to grow (next power of 2, minimum 16)
        local capacity = math.max(16, math.ceil((str_len + 1) / 16) * 16)
        table.insert(statements, string.format("_str->data = %s",
            ctx():alloc_call(tostring(capacity), false)))
        table.insert(statements, string.format("_str->length = %d", str_len))
        table.insert(statements, string.format("_str->capacity = %d", capacity))
        -- Copy the string data
        if str_len > 0 then
            table.insert(statements, string.format("memcpy(_str->data, \"%s\", %d)", str_value, str_len))
        end
        table.insert(statements, "_str->data[_str->length] = '\\0'")
        table.insert(statements, "_str")
        
        return string.format("({ %s; })", join(statements, "; "))
    end
    
    -- Map Czar type name to C type name
    local c_type_name = expr.type_name
    if expr.type_name == "String" then
        c_type_name = "cz_string"
    elseif expr.type_name == "Os" then
        c_type_name = "cz_os"
    elseif expr.type_name == "Arena" then
        c_type_name = "cz_alloc_arena"
    elseif expr.type_name == "Heap" then
        c_type_name = "cz_alloc_heap"
    elseif expr.type_name == "Debug" then
        c_type_name = "cz_alloc_debug"
    elseif expr.type_name == "CzAllocArena" then
        c_type_name = "cz_alloc_arena"
    elseif expr.type_name:match("%.") then
        -- Qualified name (e.g., alloc.Arena)
        local parts = {}
        for part in expr.type_name:gmatch("[^.]+") do
            table.insert(parts, part:lower())
        end
        c_type_name = "cz_" .. table.concat(parts, "_")
    end
    
    local parts = {}
    for _, f in ipairs(expr.fields) do
        table.insert(parts, string.format(".%s = %s", f.name, gen_expr_fn(f.value)))
    end
    
    -- Zero-initialize first, then set fields
    local initializer
    if #parts == 0 then
        initializer = string.format("(%s){ 0 }", c_type_name)
    else
        -- Use designated initializers which automatically zero-initialize unspecified fields
        initializer = string.format("(%s){ %s }", c_type_name, join(parts, ", "))
    end
    
    -- Generate: ({ Type* _ptr = malloc(sizeof(Type)); *_ptr = (Type){ fields... }; _ptr; })
    -- Explicit allocation with 'new' keyword
    return string.format("({ %s* _ptr = %s; *_ptr = %s; _ptr; })",
        c_type_name, ctx():alloc_call("sizeof(" .. c_type_name .. ")", true), initializer)
end

-- Generate new heap-allocated array
function Collections.gen_new_array(expr, gen_expr_fn)
    -- new [elements...] - heap-allocated array
    -- Generate: ({ Type* _ptr = malloc(sizeof(Type) * N); _ptr[0] = elem1; _ptr[1] = elem2; ...; _ptr; })
    local element_parts = {}
    for i, elem in ipairs(expr.elements) do
        table.insert(element_parts, gen_expr_fn(elem))
    end
    
    -- Get element type from inferred type
    local element_type = expr.inferred_type and expr.inferred_type.element_type
    if not element_type then
        error("new_array expression missing inferred type")
    end
    local element_type_str = ctx():c_type(element_type)
    local array_size = #expr.elements
    
    -- Build the expression statement block
    local statements = {}
    table.insert(statements, string.format("%s* _ptr = %s", 
        element_type_str, 
        ctx():alloc_call(string.format("sizeof(%s) * %d", element_type_str, array_size), true)))
    
    for i, elem_expr in ipairs(element_parts) do
        table.insert(statements, string.format("_ptr[%d] = %s", i-1, elem_expr))
    end
    
    table.insert(statements, "_ptr")
    
    return string.format("({ %s; })", join(statements, "; "))
end

-- Generate new heap-allocated map
function Collections.gen_new_map(expr, gen_expr_fn)
    -- new map[K]V { key: value, ... } - heap-allocated map
    -- Generate a simple linear search implementation for now
    local key_type = expr.key_type
    local value_type = expr.value_type
    local key_type_str = ctx():c_type(key_type)
    local value_type_str = ctx():c_type(value_type)
    
    -- Generate map struct type name
    local map_type_name = "cz_map_" .. key_type_str:gsub("%*", "ptr") .. "_" .. value_type_str:gsub("%*", "ptr")
    
    -- Register map type for later struct generation
    if not ctx().map_types then
        ctx().map_types = {}
    end
    local map_key = key_type_str .. "_" .. value_type_str
    if not ctx().map_types[map_key] then
        ctx().map_types[map_key] = {
            map_type_name = map_type_name,
            key_type = key_type,
            value_type = value_type,
            key_type_str = key_type_str,
            value_type_str = value_type_str
        }
    end
    
    -- Build initialization code
    local statements = {}
    local capacity = math.max(MAP_MIN_CAPACITY, #expr.entries * 2)
    table.insert(statements, string.format("%s* _map = %s", 
        map_type_name, 
        ctx():alloc_call(string.format("sizeof(%s)", map_type_name), true)))
    table.insert(statements, string.format("_map->capacity = %d", capacity))
    table.insert(statements, string.format("_map->size = %d", #expr.entries))
    table.insert(statements, string.format("_map->keys = %s", 
        ctx():alloc_call(string.format("sizeof(%s) * %d", key_type_str, capacity), true)))
    table.insert(statements, string.format("_map->values = %s", 
        ctx():alloc_call(string.format("sizeof(%s) * %d", value_type_str, capacity), true)))
    
    -- Initialize entries
    for i, entry in ipairs(expr.entries) do
        local key_expr = gen_expr_fn(entry.key)
        local value_expr = gen_expr_fn(entry.value)
        table.insert(statements, string.format("_map->keys[%d] = %s", i-1, key_expr))
        table.insert(statements, string.format("_map->values[%d] = %s", i-1, value_expr))
    end
    
    table.insert(statements, "_map")
    
    return string.format("({ %s; })", join(statements, "; "))
end

-- Generate array literal
function Collections.gen_array_literal(expr, gen_expr_fn)
    -- Array literal: { expr1, expr2, ... }
    local parts = {}
    for _, elem in ipairs(expr.elements) do
        table.insert(parts, gen_expr_fn(elem))
    end
    return string.format("{ %s }", join(parts, ", "))
end

-- Generate slice expression
function Collections.gen_slice(expr, gen_expr_fn)
    -- Slice: arr[start:end]
    -- In C, this is a pointer to the start element
    -- We'll generate: &arr[start]
    local array_expr = gen_expr_fn(expr.array)
    local start_expr = gen_expr_fn(expr.start)
    return string.format("&%s[%s]", array_expr, start_expr)
end

-- Generate new heap-allocated pair
function Collections.gen_new_pair(expr, gen_expr_fn)
    -- new pair { left, right } - heap-allocated pair
    local left_type = expr.left_type
    local right_type = expr.right_type
    local left_type_str = ctx():c_type(left_type)
    local right_type_str = ctx():c_type(right_type)
    
    -- Generate pair struct type name
    local pair_type_name = "cz_pair_" .. left_type_str:gsub("%*", "ptr") .. "_" .. right_type_str:gsub("%*", "ptr")
    
    -- Register pair type for later struct generation
    if not ctx().pair_types then
        ctx().pair_types = {}
    end
    local pair_key = left_type_str .. "_" .. right_type_str
    if not ctx().pair_types[pair_key] then
        ctx().pair_types[pair_key] = {
            pair_type_name = pair_type_name,
            left_type = left_type,
            right_type = right_type,
        }
    end
    
    -- Generate code: malloc + initialize
    local left_expr = gen_expr_fn(expr.left)
    local right_expr = gen_expr_fn(expr.right)
    
    local statements = {}
    table.insert(statements, string.format("%s* _pair = %s", 
        pair_type_name,
        ctx():alloc_call(string.format("sizeof(%s)", pair_type_name), true)))
    table.insert(statements, string.format("_pair->left = %s", left_expr))
    table.insert(statements, string.format("_pair->right = %s", right_expr))
    table.insert(statements, "_pair")
    
    return string.format("({ %s; })", join(statements, "; "))
end

-- Generate stack-allocated pair literal
function Collections.gen_pair_literal(expr, gen_expr_fn)
    -- pair { left, right } - stack-allocated pair
    local left_type = expr.left_type
    local right_type = expr.right_type
    local left_type_str = ctx():c_type(left_type)
    local right_type_str = ctx():c_type(right_type)
    
    -- Generate pair struct type name
    local pair_type_name = "cz_pair_" .. left_type_str:gsub("%*", "ptr") .. "_" .. right_type_str:gsub("%*", "ptr")
    
    -- Register pair type for later struct generation
    if not ctx().pair_types then
        ctx().pair_types = {}
    end
    local pair_key = left_type_str .. "_" .. right_type_str
    if not ctx().pair_types[pair_key] then
        ctx().pair_types[pair_key] = {
            pair_type_name = pair_type_name,
            left_type = left_type,
            right_type = right_type,
        }
    end
    
    -- Generate code: compound literal
    local left_expr = gen_expr_fn(expr.left)
    local right_expr = gen_expr_fn(expr.right)
    
    return string.format("(%s){ .left = %s, .right = %s }", pair_type_name, left_expr, right_expr)
end

-- Generate stack-allocated map literal
function Collections.gen_map_literal(expr, gen_expr_fn)
    -- map { key: value, ... } - stack-allocated map (similar to new_map but without malloc)
    local key_type = expr.key_type
    local value_type = expr.value_type
    local key_type_str = ctx():c_type(key_type)
    local value_type_str = ctx():c_type(value_type)
    
    -- Generate map struct type name
    local map_type_name = "cz_map_" .. key_type_str:gsub("%*", "ptr") .. "_" .. value_type_str:gsub("%*", "ptr")
    
    -- Register map type for later struct generation
    if not ctx().map_types then
        ctx().map_types = {}
    end
    local map_key = key_type_str .. "_" .. value_type_str
    if not ctx().map_types[map_key] then
        ctx().map_types[map_key] = {
            map_type_name = map_type_name,
            key_type = key_type,
            value_type = value_type,
        }
    end
    
    -- Generate arrays for keys and values
    local key_parts = {}
    local value_parts = {}
    for _, entry in ipairs(expr.entries) do
        table.insert(key_parts, gen_expr_fn(entry.key))
        table.insert(value_parts, gen_expr_fn(entry.value))
    end
    
    local size = #expr.entries
    return string.format("(%s){ .size = %d, .keys = { %s }, .values = { %s } }",
        map_type_name, size, join(key_parts, ", "), join(value_parts, ", "))
end

-- Generate new heap-allocated string
function Collections.gen_new_string(expr)
    -- new string "text" - heap-allocated string
    local str_value = expr.value
    local str_len = #str_value
    
    -- Generate code: malloc + initialize
    local statements = {}
    table.insert(statements, string.format("cz_string* _str = %s", 
        ctx():alloc_call("sizeof(cz_string)", true)))
    -- Allocate capacity with room to grow (next power of 2, minimum 16)
    local capacity = math.max(16, math.ceil((str_len + 1) / 16) * 16)
    table.insert(statements, string.format("_str->data = %s",
        ctx():alloc_call(tostring(capacity), false)))
    table.insert(statements, string.format("_str->length = %d", str_len))
    table.insert(statements, string.format("_str->capacity = %d", capacity))
    -- Copy the string data
    table.insert(statements, string.format("memcpy(_str->data, \"%s\", %d)", str_value, str_len))
    table.insert(statements, "_str->data[_str->length] = '\\0'")
    table.insert(statements, "_str")
    
    return string.format("({ %s; })", join(statements, "; "))
end

-- Generate stack-allocated string literal
function Collections.gen_string_literal(expr)
    -- string "text" - stack-allocated string
    local str_value = expr.value
    local str_len = #str_value
    
    -- For stack allocation, we need to create a compound literal with inline data
    -- We'll allocate capacity with room to grow (next power of 2, minimum 16)
    local capacity = math.max(16, math.ceil((str_len + 1) / 16) * 16)
    
    -- Generate code: compound literal with malloc for data
    local statements = {}
    table.insert(statements, string.format("char* _data = %s",
        ctx():alloc_call(tostring(capacity), false)))
    table.insert(statements, string.format("memcpy(_data, \"%s\", %d)", str_value, str_len))
    table.insert(statements, "_data[" .. str_len .. "] = '\\0'")
    table.insert(statements, string.format("(cz_string){ .data = _data, .length = %d, .capacity = %d }", str_len, capacity))
    
    return string.format("({ %s; })", join(statements, "; "))
end

return Collections
