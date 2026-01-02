/*
 * CZar - C semantic authority layer
 * Transpiler functions module (transpiler/functions.h)
 *
 * Handles CZar function to C function transformations.
 */

#ifndef TRANSPILER_FUNCTIONS_H
#define TRANSPILER_FUNCTIONS_H

/* Check if identifier is a CZar function and return C equivalent */
const char *transpiler_get_c_function(const char *identifier);

#endif /* TRANSPILER_FUNCTIONS_H */
