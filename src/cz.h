/*
 * CZar - C semantic authority layer
 * Runtime header (cz.h)
 *
 * Provides runtime macros and debugging utilities:
 * - Source location macros (FILE, LINE, FUNC)
 * - Assertion and debugging utilities (cz_assert, todo, fixme, cz_unreachable)
 */

#ifndef CZ_H
#define CZ_H

#include <stdio.h>
#include <stdlib.h>

/* ========================================================================
 * Runtime Macros
 * ======================================================================== */

/* Source location macros */
#define FILE __FILE__
#define LINE __LINE__
#define FUNC __func__

/* ========================================================================
 * Assertion and Debugging Utilities
 * ======================================================================== */

/*
 * cz_assert - Runtime assertion with source location
 * 
 * Checks a condition at runtime and aborts with diagnostic information
 * if the condition is false.
 */
#define cz_assert(condition) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "%s:%d: %s: Assertion failed: %s\n", \
                    __FILE__, __LINE__, __func__, #condition); \
            abort(); \
        } \
    } while (0)

/*
 * todo - Mark unimplemented code paths
 * 
 * Indicates that a code path is not yet implemented. Will abort
 * if executed at runtime with a diagnostic message.
 */
#define todo(msg) \
    do { \
        fprintf(stderr, "%s:%d: %s: TODO: %s\n", \
                __FILE__, __LINE__, __func__, msg); \
        abort(); \
    } while (0)

/*
 * fixme - Mark code that needs attention
 * 
 * Indicates that a code path has known issues or technical debt.
 * Will abort if executed at runtime with a diagnostic message.
 */
#define fixme(msg) \
    do { \
        fprintf(stderr, "%s:%d: %s: FIXME: %s\n", \
                __FILE__, __LINE__, __func__, msg); \
        abort(); \
    } while (0)

/*
 * cz_unreachable - Mark logically unreachable code
 * 
 * Indicates that a code path should never be executed under correct
 * program logic. Will abort if reached with a diagnostic message.
 */
#define cz_unreachable(msg) \
    do { \
        fprintf(stderr, "%s:%d: %s: Unreachable code reached: %s\n", \
                __FILE__, __LINE__, __func__, msg); \
        abort(); \
    } while (0)

#endif /* CZ_H */
