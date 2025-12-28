// cz_print.h - Raw C print functions for Czar language
// This file contains low-level print implementations with _cz_ prefix
// These are the raw primitives called from generated CZ code

#ifndef CZ_FMT_H
#define CZ_FMT_H

#include <stdio.h>
#include <stdarg.h>

// Raw print with format string and variadic arguments, without newline
// Called from generated code as _cz_print()
static inline void _cz_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Raw print with format string and variadic arguments, with newline
// Called from generated code as _cz_println()
static inline void _cz_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

// Raw printf with format string and variadic arguments
// Called from generated code as _cz_printf()
static inline void _cz_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

#endif // CZ_FMT_H
