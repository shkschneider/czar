/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles CZar constant to C constant transformations.
 */

#pragma once

/* Check if identifier is a CZar constant and return C equivalent */
const char *transpiler_get_c_constant(const char *identifier);
