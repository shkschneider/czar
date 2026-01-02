/*
 * CZar - C semantic authority layer
 * Transpiler functions module (transpiler/functions.c)
 *
 * Handles CZar function to C function transformations.
 */

#include "functions.h"
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
