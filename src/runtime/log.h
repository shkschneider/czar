/*
 * CZar - C semantic authority layer
 * Log transpiler module header (transpiler/log.h)
 *
 * Handles emission of runtime logging support in generated C code.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Emit Log runtime support to output */
void runtime_emit_log(FILE *output, int debug_mode);
