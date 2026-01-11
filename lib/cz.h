/*
 * CZar Runtime Library
 * Main header file for CZar runtime features
 */

#pragma once

/* Platform detection - must be first */
#ifdef _WIN32
    #define CZ_PLATFORM_WINDOWS
#else
    #define CZ_PLATFORM_POSIX
    #ifndef _POSIX_C_SOURCE
        #define _POSIX_C_SOURCE 200809L
    #endif
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* ============================================================================
 * Assert - Runtime assertions with detailed error messages
 * ============================================================================ */

/* Assert that a condition is true, abort with message if false */
#define cz_assert(cond) do { \
    if (!(cond)) { \
        cz_assert_fail(#cond, __FILE__, __LINE__); \
    } \
} while (0)

void cz_assert_fail(const char *condition, const char *file, int line);


/* ============================================================================
 * Format - Type-safe string formatting with mustache-like templates
 * ============================================================================ */

/* Type enum for any_t */
typedef enum {
    CZ_ANY_INT,
    CZ_ANY_UINT,
    CZ_ANY_LONG,
    CZ_ANY_ULONG,
    CZ_ANY_SIZE,
    CZ_ANY_DOUBLE,
    CZ_ANY_CHAR,
    CZ_ANY_CSTR,
    CZ_ANY_PTR
} cz_any_type_t;

/* Type-safe value container */
typedef struct {
    cz_any_type_t type;
    union {
        long i;
        unsigned long u;
        double d;
        char c;
        const char *s;
        const void *p;
    } v;
} cz_any_t;

/* Internal format implementation */
char* cz_format_impl(const char *fmt, int argc, cz_any_t *argv);

/* Helper constructors for any_t */
static inline cz_any_t cz_any_int(int val) {
    cz_any_t a; a.type = CZ_ANY_INT; a.v.i = val; return a;
}
static inline cz_any_t cz_any_uint(unsigned int val) {
    cz_any_t a; a.type = CZ_ANY_UINT; a.v.u = val; return a;
}
static inline cz_any_t cz_any_long(long val) {
    cz_any_t a; a.type = CZ_ANY_LONG; a.v.i = val; return a;
}
static inline cz_any_t cz_any_ulong(unsigned long val) {
    cz_any_t a; a.type = CZ_ANY_ULONG; a.v.u = val; return a;
}
static inline cz_any_t cz_any_size(size_t val) {
    cz_any_t a; a.type = CZ_ANY_SIZE; a.v.u = val; return a;
}
static inline cz_any_t cz_any_double(double val) {
    cz_any_t a; a.type = CZ_ANY_DOUBLE; a.v.d = val; return a;
}
static inline cz_any_t cz_any_char(char val) {
    cz_any_t a; a.type = CZ_ANY_CHAR; a.v.c = val; return a;
}
static inline cz_any_t cz_any_cstr(const char *val) {
    cz_any_t a; a.type = CZ_ANY_CSTR; a.v.s = val; return a;
}
static inline cz_any_t cz_any_ptr(const void *val) {
    cz_any_t a; a.type = CZ_ANY_PTR; a.v.p = val; return a;
}

/* Type detection macro using C11 _Generic */
#define CZ_TO_ANY(x) _Generic((x), \
    int: cz_any_int, \
    unsigned int: cz_any_uint, \
    long: cz_any_long, \
    unsigned long: cz_any_ulong, \
    float: cz_any_double, \
    double: cz_any_double, \
    char: cz_any_char, \
    char*: cz_any_cstr, \
    const char*: cz_any_cstr, \
    default: cz_any_ptr \
)(x)

/* Format macro implementations for different argument counts */
#define cz_format_1(fmt) cz_format_impl(fmt, 0, NULL)
#define cz_format_2(fmt, a1) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1)}; \
    cz_format_impl(fmt, 1, _args); \
})
#define cz_format_3(fmt, a1, a2) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2)}; \
    cz_format_impl(fmt, 2, _args); \
})
#define cz_format_4(fmt, a1, a2, a3) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3)}; \
    cz_format_impl(fmt, 3, _args); \
})
#define cz_format_5(fmt, a1, a2, a3, a4) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4)}; \
    cz_format_impl(fmt, 4, _args); \
})
#define cz_format_6(fmt, a1, a2, a3, a4, a5) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5)}; \
    cz_format_impl(fmt, 5, _args); \
})
#define cz_format_7(fmt, a1, a2, a3, a4, a5, a6) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6)}; \
    cz_format_impl(fmt, 6, _args); \
})
#define cz_format_8(fmt, a1, a2, a3, a4, a5, a6, a7) ({ \
    cz_any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6), CZ_TO_ANY(a7)}; \
    cz_format_impl(fmt, 7, _args); \
})

/* Argument counting and dispatch */
#define CZ_ARG_COUNT(...) CZ_ARG_COUNT_IMPL(__VA_ARGS__, 8, 7, 6, 5, 4, 3, 2, 1)
#define CZ_ARG_COUNT_IMPL(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N
#define CZ_CONCAT(a, b) CZ_CONCAT_IMPL(a, b)
#define CZ_CONCAT_IMPL(a, b) a##b
#define cz_format(...) CZ_CONCAT(cz_format_, CZ_ARG_COUNT(__VA_ARGS__))(__VA_ARGS__)


/* ============================================================================
 * Log - Structured logging with levels
 * ============================================================================ */

typedef enum {
    CZ_LOG_DEBUG,
    CZ_LOG_INFO,
    CZ_LOG_WARN,
    CZ_LOG_ERROR
} cz_log_level_t;

/* Set minimum log level (messages below this level are suppressed) */
void cz_log_set_level(cz_log_level_t level);

/* Log a message at the specified level */
void cz_log(cz_log_level_t level, const char *message);

/* Convenience macros */
#define cz_log_debug(msg) cz_log(CZ_LOG_DEBUG, msg)
#define cz_log_info(msg) cz_log(CZ_LOG_INFO, msg)
#define cz_log_warn(msg) cz_log(CZ_LOG_WARN, msg)
#define cz_log_error(msg) cz_log(CZ_LOG_ERROR, msg)


/* ============================================================================
 * Monotonic Clock - High-resolution time measurement
 * ============================================================================ */

/* Get current time in nanoseconds from monotonic clock */
unsigned long long cz_monotonic_clock_ns(void);

/* Get nanoseconds since program start */
unsigned long long cz_monotonic_timer_ns(void);

/* Sleep for specified nanoseconds */
void cz_nanosleep(unsigned long long nanoseconds);
