/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles CZar constant to C constant transformations.
 */

#include "cz.h"
#include "constants.h"
#include <string.h>
#include <stddef.h>

/* CZar constant mapping structure */
typedef struct {
    const char *czar_name;
    const char *c_name;
} ConstantMapping;

/* CZar constant to C constant mappings */
static const ConstantMapping constant_mappings[] = {
    /* Unsigned integer constants */
    {"U8_MIN", "0"},
    {"U8_MAX", "UINT8_MAX"},
    {"U16_MIN", "0"},
    {"U16_MAX", "UINT16_MAX"},
    {"U32_MIN", "0"},
    {"U32_MAX", "UINT32_MAX"},
    {"U64_MIN", "0"},
    {"U64_MAX", "UINT64_MAX"},

    /* Signed integer constants */
    {"I8_MIN", "INT8_MIN"},
    {"I8_MAX", "INT8_MAX"},
    {"I16_MIN", "INT16_MIN"},
    {"I16_MAX", "INT16_MAX"},
    {"I32_MIN", "INT32_MIN"},
    {"I32_MAX", "INT32_MAX"},
    {"I64_MIN", "INT64_MIN"},
    {"I64_MAX", "INT64_MAX"},

    /* Size type constants */
    {"USIZE_MIN", "0"},
    {"USIZE_MAX", "SIZE_MAX"},
    {"ISIZE_MIN", "PTRDIFF_MIN"},
    {"ISIZE_MAX", "PTRDIFF_MAX"},

    {NULL, NULL} /* Sentinel */
};

/* Check if identifier is a CZar constant and return C equivalent */
const char *transpiler_get_c_constant(const char *identifier) {
    for (int i = 0; constant_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, constant_mappings[i].czar_name) == 0) {
            return constant_mappings[i].c_name;
        }
    }
    return NULL;
}
