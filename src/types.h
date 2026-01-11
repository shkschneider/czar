/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles CZar type to C type transformations.
 */

#pragma once

/* Check if identifier is a CZar type and return C equivalent */
const char *transpiler_get_c_type(const char *identifier);
