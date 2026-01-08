/*
 * CZar - C semantic authority layer
 * Transpiler constants module (transpiler/constants.h)
 *
 * Handles CZar constant to C constant transformations.
 */

#pragma once

/* Check if identifier is a CZar constant and return C equivalent */
const char *transpiler_get_c_constant(const char *identifier);
