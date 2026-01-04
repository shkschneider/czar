/*
 * CZar - C semantic authority layer
 * Print transpiler module header (runtime/print.h)
 *
 * Handles emission of runtime print support in generated C code.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Emit Print runtime support to output */
void runtime_emit_print(FILE *output);
