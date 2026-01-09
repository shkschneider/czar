/*
 * CZar - C semantic authority layer
 * Transpiler unused variable module (transpiler/unused.c)
 *
 * Handles special _ variable to suppress unused warnings.
 */

#include "cz.h"
#include "unused.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ATTRIBUTE_UNUSED "__attribute__((unused))"

/* Counter for generating unique unused variable names */
static int unused_counter = 0;

/* Transform _ identifier to unique unused variable name */
char *transpiler_transform_unused_identifier(void) {
    char buffer[64];
    int written = snprintf(buffer, sizeof(buffer), "_cz_unused_%d "ATTRIBUTE_UNUSED, unused_counter++);

    /* Check if snprintf truncated (should never happen with 64 bytes) */
    if (written < 0 || written >= (int)sizeof(buffer)) {
        return NULL;
    }

    char *result = strdup(buffer);
    if (!result) {
        return NULL;
    }
    return result;
}

/* Reset the unused counter (for each translation unit) */
void transpiler_reset_unused_counter(void) {
    unused_counter = 0;
}
