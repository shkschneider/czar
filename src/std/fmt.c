// fmt.c - Raw C print functions for Czar language
// This file contains low-level print implementations with _cz_fmt_ prefix
// These are the raw primitives called from generated CZ code

#include <stdio.h>
#include <stdarg.h>

// Raw print with format string and variadic arguments, without newline
// Called from generated code as _cz_fmt_print()
static inline void _cz_fmt_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Raw print with format string and variadic arguments, with newline
// Called from generated code as _cz_fmt_println()
static inline void _cz_fmt_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

// Raw printf with format string and variadic arguments
// Called from generated code as _cz_fmt_printf()
static inline void _cz_fmt_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}
