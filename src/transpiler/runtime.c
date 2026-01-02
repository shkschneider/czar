/*
 * CZar - C semantic authority layer
 * Transpiler runtime module (transpiler/runtime.c)
 *
 * Handles CZar runtime helper function definitions for transpilation.
 */

#include "runtime.h"

/* Runtime helper function definitions to be injected into transpiled code */
static const char *runtime_functions =
"/* CZar runtime functions - injected by transpiler */\n"
"#include <stdio.h>\n"
"#include <stdlib.h>\n"
"\n"
"static inline void _cz_assert(int condition, const char* file, int line, const char* func, const char* cond_str) {\n"
"    if (!condition) {\n"
"        fprintf(stderr, \"%s:%d %s() Assertion failed: %s\\n\", file, line, func, cond_str);\n"
"        abort();\n"
"    }\n"
"}\n"
"#define cz_assert(cond) _cz_assert((cond), __FILE__, __LINE__, __func__, #cond)\n"
"\n"
"static inline void _cz_todo(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d %s() TODO: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_todo(msg) _cz_todo((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"static inline void _cz_fixme(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d %s() FIXME: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_fixme(msg) _cz_fixme((msg), __FILE__, __LINE__, __func__)\n"
"\n"
"static inline void _cz_unreachable_impl(const char* msg, const char* file, int line, const char* func) {\n"
"    fprintf(stderr, \"%s:%d %s() Unreachable code reached: %s\\n\", file, line, func, msg);\n"
"    abort();\n"
"}\n"
"#define cz_unreachable(msg) _cz_unreachable((msg), __FILE__, __LINE__, __func__)\n"
"/* End of CZar runtime functions */\n"
"\n";

/* Get the runtime helper function definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void) {
    return runtime_functions;
}
