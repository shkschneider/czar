/*
 * libCZar - empowering runtime library
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Log implementation - Structured logging with levels
 */

#include "cz.h"
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

/* Global log level setting */
static cz_log_level_t g_log_level = CZ_LOG_DEBUG;

/* Set minimum log level */
void cz_log_set_level(cz_log_level_t level) {
    g_log_level = level;
}

/* Log a message at the specified level */
void cz_log(cz_log_level_t level, const char *message) {
    if (level < g_log_level) {
        return; /* Suppress messages below threshold */
    }

    const char *level_str;
    FILE *out;

    switch (level) {
        case CZ_LOG_DEBUG:
            level_str = "DEBUG";
            out = stdout;
            break;
        case CZ_LOG_INFO:
            level_str = "INFO";
            out = stdout;
            break;
        case CZ_LOG_WARN:
            level_str = "WARN";
            out = stdout;
            break;
        case CZ_LOG_ERROR:
            level_str = "ERROR";
            out = stderr;
            break;
        default:
            level_str = "UNKNOWN";
            out = stdout;
            break;
    }

    /* Get elapsed time since program start */
    unsigned long long elapsed_ns = cz_monotonic_timer_ns();
    double elapsed_s = elapsed_ns / 1000000000.0;

    fprintf(out, "[CZAR] %.2fs %s %s\n", elapsed_s, level_str, message ? message : "");
    fflush(out);
}
