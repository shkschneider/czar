/*
 * CZar - C semantic authority layer
 * Transpiler runtime module (transpiler/runtime.h)
 *
 * Handles CZar runtime helper function definitions and identifier transformations.
 */

#pragma once

/* Check if identifier is a CZar runtime function and return C equivalent */
const char *transpiler_get_c_function(const char *identifier);

/* Get the runtime helper function definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void);
