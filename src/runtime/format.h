/*
 * CZar - C semantic authority layer
 * Format transpiler module header (runtime/format.h)
 *
 * Handles emission of runtime print support in generated C code.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Emit Format runtime support to output */
void runtime_emit_format(FILE *output);
