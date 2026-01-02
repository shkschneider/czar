/*
 * CZar - C semantic authority layer
 * Transpiler runtime module (transpiler/runtime.c)
 *
 * Handles CZar runtime macro definitions for transpilation.
 */

#include "runtime.h"

/* Runtime macro definitions to be injected into transpiled code */
static const char *runtime_macros = 
"/* CZar runtime macros - injected by transpiler */\n"
"#include <stdio.h>\n"
"#include <stdlib.h>\n"
"\n"
"#define cz_assert(condition) \\\n"
"    do { \\\n"
"        if (!(condition)) { \\\n"
"            fprintf(stderr, \"%s:%d: %s: Assertion failed: %s\\n\", \\\n"
"                    __FILE__, __LINE__, __func__, #condition); \\\n"
"            abort(); \\\n"
"        } \\\n"
"    } while (0)\n"
"\n"
"#define cz_todo(msg) \\\n"
"    do { \\\n"
"        fprintf(stderr, \"%s:%d: %s: TODO: %s\\n\", \\\n"
"                __FILE__, __LINE__, __func__, msg); \\\n"
"        abort(); \\\n"
"    } while (0)\n"
"\n"
"#define cz_fixme(msg) \\\n"
"    do { \\\n"
"        fprintf(stderr, \"%s:%d: %s: FIXME: %s\\n\", \\\n"
"                __FILE__, __LINE__, __func__, msg); \\\n"
"        abort(); \\\n"
"    } while (0)\n"
"\n"
"#define cz_unreachable(msg) \\\n"
"    do { \\\n"
"        fprintf(stderr, \"%s:%d: %s: Unreachable code reached: %s\\n\", \\\n"
"                __FILE__, __LINE__, __func__, msg); \\\n"
"        abort(); \\\n"
"    } while (0)\n"
"/* End of CZar runtime macros */\n"
"\n";

/* Get the runtime macro definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void) {
    return runtime_macros;
}
