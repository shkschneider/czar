/*
 * CZar - C semantic authority layer
 * Centralized Unsafe Definitions (unsafe.h)
 */

#pragma once

/*
 * unsafe_to_safe_mappings.c
 *
 * A compact mapping of commonly "unsafe" C APIs to safer alternatives,
 * represented as a const array of structs (const char *unsafe, const char *safe).
 *
 * This is just data (plus a tiny print helper). Use as a reference in docs,
 * lint messages, or to populate a checklist.
 *
 * Compile with: clang -std=c11 -Wall -Wextra unsafe_to_safe_mappings.c -o map
 */

#include <stdio.h>

typedef struct {
    const char *unsafe;
    const char *safe;
    const bool error;
} cz_unsafe_t;

static const cz_unsafe_t cz_unsafe[] = {
    // no bounds checking, removed from the standard (C11)
    { "gets", "fgets() / getline()", true },
    // format-string vulnerabilities
    { "scanf", "fgets() / getline()", false },
    // no length checks → buffer overflow
    { "strcpy", "snprintf() / strlcpy()", false },
    { "strcat", "snprintf() / strlcat()", false },
    { "sprintf", "snprintf()", false },
    // race conditions, predictable names
    { "tmpnam", "mkstemp()", true },
    { "tempnam", "mkstemp()", true },
    { "mktemp", "mkstemp()", true },
    // shell interpretation can lead to command injection when inputs are untrusted
    { "system", "fork() + exec()", false },
    { "popen", "fork() + exec()", false },
    // poor quality and confusing semantics
    { "rand", "getrandom()", true },
    { "srand", "getrandom()", true },
    { "rand_r", "getrandom()", true },
    // subtle buffer sizing problems and deprecated
    { "readdir_r", "readdir()", true },
    // deprecated
    { "gethostbyname", "getaddrinfo()", true },
    { "gethostbyaddr", "getnameinfo()", true },
    /* sentinel */
    { NULL, NULL, false }
};
