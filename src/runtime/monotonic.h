/*
 * CZar - C semantic authority layer
 * Monotonic clock runtime module header (runtime/monotonic_clock.h)
 *
 * Handles emission of runtime monotonic clock support in generated C code.
 */

#pragma once

#include <stdio.h>

/* Emit Monotonic Clock/Timer runtime support to output */
void runtime_emit_monotonic(FILE *output);

unsigned long long cz_monotonic_clock_ns(void);
unsigned long long cz_monotonic_timer_ns(void);
void cz_nanosleep(void);
