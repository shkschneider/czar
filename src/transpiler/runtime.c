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
"/* Compatibility for noreturn attribute */\n"
"#if defined(__GNUC__) || defined(__clang__)\n"
"#define CZ_NORETURN __attribute__((noreturn))\n"
"#elif defined(_MSC_VER)\n"
"#define CZ_NORETURN __declspec(noreturn)\n"
"#elif __STDC_VERSION__ >= 201112L\n"
"#define CZ_NORETURN _Noreturn\n"
"#else\n"
"#define CZ_NORETURN\n"
"#endif\n"
"\n"
"static inline void _cz_assert(int condition, const char* file, int line, const char* func, const char* cond_str) {\n"
"    if (!condition) {\n"
"        fprintf(stderr, \"%s:%d: %s: Assertion failed: %s\\n\", file, line, func, cond_str);\n"
"        abort();\n"
"    }\n"
"}\n"
"#define cz_assert(cond) _cz_assert((cond), __FILE__, __LINE__, __func__, #cond)\n"
"\n"
"CZ_NORETURN static inline void _cz_todo(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: TODO: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_todo(msg) _cz_todo((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"CZ_NORETURN static inline void _cz_fixme(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: FIXME: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_fixme(msg) _cz_fixme((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"CZ_NORETURN static inline void _cz_unreachable(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d: %s: Unreachable code reached: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_unreachable(msg) _cz_unreachable((msg), __FILE__, __LINE__, __func__)\n"
"/* End of CZar runtime functions */\n"
"\n";

/* Get the runtime helper function definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void) {
    return runtime_functions;
}
