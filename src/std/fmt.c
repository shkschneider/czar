// fmt.c - Format and print functions
// Part of the Czar standard library

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>

// Print formatted string without newline
static inline void _cz_fmt_print(const int8_t* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf((const char*)fmt, args);
    va_end(args);
}

// Print formatted string with newline
static inline void _cz_fmt_println(const int8_t* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf((const char*)fmt, args);
    va_end(args);
    printf("\n");
}

// Print formatted string (alias for print)
static inline void _cz_fmt_printf(const int8_t* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf((const char*)fmt, args);
    va_end(args);
}
