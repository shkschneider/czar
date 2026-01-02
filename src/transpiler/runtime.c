/*
 * CZar - C semantic authority layer
 * Transpiler runtime module (transpiler/runtime.c)
 *
 * Handles CZar runtime helper function definitions and identifier transformations.
 */

#include "runtime.h"
#include <string.h>
#include <stddef.h>

/* CZar function mapping structure */
typedef struct {
    const char *czar_name;
    const char *c_name;
} FunctionMapping;

/* CZar function to C function mappings */
static const FunctionMapping function_mappings[] = {
    {"ASSERT", "cz_assert"},
    {"TODO", "cz_todo"},
    {"FIXME", "cz_fixme"},
    {"UNREACHABLE", "cz_unreachable"},
    {NULL, NULL} /* Sentinel */
};

/* Check if identifier is a CZar function and return C equivalent */
const char *transpiler_get_c_function(const char *identifier) {
    for (int i = 0; function_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, function_mappings[i].czar_name) == 0) {
            return function_mappings[i].c_name;
        }
    }
    return NULL;
}

/* Runtime helper function definitions to be injected into transpiled code */
static const char *runtime_functions = 
"/* CZar runtime functions - injected by transpiler */\n"
"#include <stdio.h>\n"
"#include <stdlib.h>\n"
"\n"
"static inline void _cz_assert_impl(int condition, const char* file, int line, const char* func, const char* cond_str) {\n"
"    if (!condition) {\n"
"        fprintf(stderr, \"%s:%d: %s: Assertion failed: %s\\n\", file, line, func, cond_str);\n"
"        abort();\n"
"    }\n"
"}\n"
"#define cz_assert(cond) _cz_assert_impl((cond), __FILE__, __LINE__, __func__, #cond)\n"
"\n"
"static inline void _cz_todo_impl(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: TODO: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_todo(msg) _cz_todo_impl((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"static inline void _cz_fixme_impl(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: FIXME: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_fixme(msg) _cz_fixme_impl((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"static inline void _cz_unreachable_impl(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: Unreachable code reached: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_unreachable(msg) _cz_unreachable_impl((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"/* Safe cast macros with range checking */\n"
"#define CZ_SAFE_CAST_u8(val, fallback) (((val) > 255) ? (fallback) : (uint8_t)(val))\n"
"#define CZ_SAFE_CAST_u16(val, fallback) (((val) > 65535) ? (fallback) : (uint16_t)(val))\n"
"#define CZ_SAFE_CAST_u32(val, fallback) (((val) > 4294967295U) ? (fallback) : (uint32_t)(val))\n"
"#define CZ_SAFE_CAST_u64(val, fallback) (uint64_t)(val)\n"
"#define CZ_SAFE_CAST_i8(val, fallback) (((val) < -128 || (val) > 127) ? (fallback) : (int8_t)(val))\n"
"#define CZ_SAFE_CAST_i16(val, fallback) (((val) < -32768 || (val) > 32767) ? (fallback) : (int16_t)(val))\n"
"#define CZ_SAFE_CAST_i32(val, fallback) (((val) < (-2147483647-1) || (val) > 2147483647) ? (fallback) : (int32_t)(val))\n"
"#define CZ_SAFE_CAST_i64(val, fallback) (int64_t)(val)\n"
"/* Also define for transformed C types */\n"
"#define CZ_SAFE_CAST_uint8_t CZ_SAFE_CAST_u8\n"
"#define CZ_SAFE_CAST_uint16_t CZ_SAFE_CAST_u16\n"
"#define CZ_SAFE_CAST_uint32_t CZ_SAFE_CAST_u32\n"
"#define CZ_SAFE_CAST_uint64_t CZ_SAFE_CAST_u64\n"
"#define CZ_SAFE_CAST_int8_t CZ_SAFE_CAST_i8\n"
"#define CZ_SAFE_CAST_int16_t CZ_SAFE_CAST_i16\n"
"#define CZ_SAFE_CAST_int32_t CZ_SAFE_CAST_i32\n"
"#define CZ_SAFE_CAST_int64_t CZ_SAFE_CAST_i64\n"
"/* End of CZar runtime functions */\n"
"\n";

/* Get the runtime helper function definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void) {
    return runtime_functions;
}
