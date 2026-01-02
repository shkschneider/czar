/*
 * CZar - C semantic authority layer
 * Transpiler types module (transpiler/types.h)
 *
 * Handles CZar type to C type transformations.
 */

#ifndef TRANSPILER_TYPES_H
#define TRANSPILER_TYPES_H

/* Check if identifier is a CZar type and return C equivalent */
const char *transpiler_get_c_type(const char *identifier);

#endif /* TRANSPILER_TYPES_H */
