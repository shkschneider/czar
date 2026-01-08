/*
 * CZar - C semantic authority layer
 * Transpiler types module (transpiler/types.c)
 *
 * Handles CZar type to C type transformations.
 */

#include "cz.h"
#include "types.h"
#include <string.h>
#include <stddef.h>

/* CZar type mapping structure */
typedef struct {
    const char *czar_name;
    const char *c_name;
} TypeMapping;

/* CZar type to C type mappings */
static const TypeMapping type_mappings[] = {
    {"bool", "bool"},

    /* Unsigned integer types */
    {"u8", "uint8_t"},
    {"u16", "uint16_t"},
    {"u32", "uint32_t"},
    {"u64", "uint64_t"},

    /* Signed integer types */
    {"i8", "int8_t"},
    {"i16", "int16_t"},
    {"i32", "int32_t"},
    {"i64", "int64_t"},

    /* Floating point types */
    {"f32", "float"},
    {"f64", "double"},

    /* Architecture-dependent size types */
    {"usize", "size_t"},
    {"isize", "ptrdiff_t"},

    {NULL, NULL} /* Sentinel */
};

/* Check if identifier is a CZar type and return C equivalent */
const char *transpiler_get_c_type(const char *identifier) {
    for (int i = 0; type_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, type_mappings[i].czar_name) == 0) {
            return type_mappings[i].c_name;
        }
    }
    return NULL;
}
