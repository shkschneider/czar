// cz_print.c - Raw C print functions for Czar language
// This file contains low-level print implementations with cz_ prefix
// These are the raw primitives called from generated CZ code

#include <stdio.h>
#include <stdarg.h>

// Raw print with format string and variadic arguments, without newline
// Called from generated code as cz_print()
static inline void cz_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Raw print with format string and variadic arguments, with newline
// Called from generated code as cz_println()
static inline void cz_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

// Raw printf with format string and variadic arguments
// Called from generated code as cz_printf()
static inline void cz_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}
