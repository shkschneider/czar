/*
 * CZar Runtime Library - Header
 * Include this in all generated .cz.c files
 */

#pragma once

/* Enable POSIX features */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

/* Standard library includes */
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stdarg.h>
#include <string.h>

/* Platform detection for monotonic clock */
#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

#if defined(_MSC_VER) && !defined(strdup)
    /* Map calls to strdup(...) to MSVC's _strdup(...) */
    #define strdup _strdup
#endif

/* CZar Assert Macro */
#define cz_assert(cond) do {\
  if (!(cond)) {\
    fprintf(stderr, "[CZAR] ASSERTION failed at %s:%d: %s\n", __FILE__, __LINE__, #cond);\
    abort();\
  }\
} while (0)

/* CZar Monotonic Clock Functions */
unsigned long long cz_monotonic_clock_ns(void);
void cz_nanosleep(unsigned long long nanoseconds);
unsigned long long cz_monotonic_timer_ns(void);

/* CZar Log Runtime */
typedef enum {
    CZ_LOG_VERBOSE = 0,
    CZ_LOG_DEBUG = 1,
    CZ_LOG_INFO = 2,
    CZ_LOG_WARN = 3,
    CZ_LOG_ERROR = 4,
    CZ_LOG_FATAL = 5
} CzLogLevel;

void cz_log(CzLogLevel level, const char *file, int line, const char *func, const char *fmt, ...);

/* Log macros */
#ifdef __GNUC__
#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, __func__, __VA_ARGS__)
#else
#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, NULL, __VA_ARGS__)
#endif

typedef struct { int _unused; } Log;

/* CZar Format Runtime */
char* cz_format_string(const char* fmt, ...);
