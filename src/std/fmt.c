// fmt.c - Format and print functions
// Part of the Czar standard library

#include <stdio.h>
#include <stdarg.h>

// Print formatted string without newline
static inline void cz_fmt_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Print formatted string with newline
static inline void cz_fmt_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

// Print formatted string (alias for print)
static inline void cz_fmt_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}
