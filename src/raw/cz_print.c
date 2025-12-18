// cz_print.c - Print functions for Czar language
// This file contains print, println, and printf implementations
// Generated code will include this file to provide printing functionality.

#include <stdio.h>
#include <stdarg.h>

// Print string without newline
// Usage: cz_print("Hello World")
static inline void cz_print(const char* str) {
    printf("%s", str);
}

// Print string with newline
// Usage: cz_println("Hello World")
static inline void cz_println(const char* str) {
    printf("%s\n", str);
}

// Printf with format string and variadic arguments
// Usage: cz_printf("Value: %d", 42)
static inline void cz_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}
