/*
 * CZar - C semantic authority layer
 * Transpiler unused variable module (transpiler/unused.c)
 *
 * Handles special _ variable to suppress unused warnings.
 */

#define _POSIX_C_SOURCE 200809L

#include "unused.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Counter for generating unique unused variable names */
static int unused_counter = 0;

/* Transform _ identifier to unique unused variable name */
char *transpiler_transform_unused_identifier(void) {
    char buffer[64];
    int written = snprintf(buffer, sizeof(buffer), "_unused_%d __attribute__((unused))", unused_counter++);
    
    /* Check if snprintf truncated (should never happen with 64 bytes) */
    if (written < 0 || written >= (int)sizeof(buffer)) {
        return NULL;
    }
    
    return strdup(buffer);
}

/* Reset the unused counter (for each translation unit) */
void transpiler_reset_unused_counter(void) {
    unused_counter = 0;
}
