/*
 * CZar - C semantic authority layer
 * Monotonic clock runtime module header (runtime/monotonic_clock.h)
 *
 * Handles emission of runtime monotonic clock support in generated C code.
 */

#pragma once

#include <stdio.h>

/* Emit Monotonic Clock runtime support to output */
void runtime_emit_monotonic_clock(FILE *output);
