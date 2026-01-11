/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 */

#pragma once

#define _POSIX_C_SOURCE 200809L
#include <string.h>

#if defined(_MSC_VER) && !defined(strdup)
    /* Map calls to strdup(...) to MSVC's _strdup(...) */
    #define strdup _strdup
#endif

/* Global context for error/warning reporting */
extern const char *g_filename;
extern const char *g_source;
