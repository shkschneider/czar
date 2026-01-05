/*
 * CZar - C semantic authority layer
 */

#pragma once

#define _POSIX_C_SOURCE 200809L
#include <string.h>

#if defined(_MSC_VER) && !defined(strdup)
    /* Map calls to strdup(...) to MSVC's _strdup(...) */
    #define strdup _strdup
#endif
