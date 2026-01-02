/*
 * CZar - C semantic authority layer
 * Runtime header (cz.h)
 * 
 * This umbrella header provides the core CZar runtime facilities:
 * - Fixed-width type aliases (cz_u8, cz_i32, etc.)
 * - Numeric limit constants (CZ_U8_MAX, CZ_I32_MIN, etc.)
 * - Runtime macros (FILE, LINE, FUNC)
 * - Assertion and debugging utilities
 */

#ifndef CZ_H
#define CZ_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

/* ========================================================================
 * Type Aliases - Lowered to prefixed C types
 * ======================================================================== */

/* Unsigned integer types */
typedef uint8_t  cz_u8;
typedef uint16_t cz_u16;
typedef uint32_t cz_u32;
typedef uint64_t cz_u64;

/* Signed integer types */
typedef int8_t  cz_i8;
typedef int16_t cz_i16;
typedef int32_t cz_i32;
typedef int64_t cz_i64;

/* Floating point types */
typedef float  cz_f32;
typedef double cz_f64;

/* Architecture-dependent size types */
typedef size_t   cz_usize;
typedef ptrdiff_t cz_isize;

/* ========================================================================
 * Numeric Limit Constants
 * ======================================================================== */

/* Unsigned integer limits */
#define CZ_U8_MIN  ((cz_u8)0)
#define CZ_U8_MAX  ((cz_u8)UINT8_MAX)
#define CZ_U16_MIN ((cz_u16)0)
#define CZ_U16_MAX ((cz_u16)UINT16_MAX)
#define CZ_U32_MIN ((cz_u32)0)
#define CZ_U32_MAX ((cz_u32)UINT32_MAX)
#define CZ_U64_MIN ((cz_u64)0)
#define CZ_U64_MAX ((cz_u64)UINT64_MAX)

/* Signed integer limits */
#define CZ_I8_MIN  ((cz_i8)INT8_MIN)
#define CZ_I8_MAX  ((cz_i8)INT8_MAX)
#define CZ_I16_MIN ((cz_i16)INT16_MIN)
#define CZ_I16_MAX ((cz_i16)INT16_MAX)
#define CZ_I32_MIN ((cz_i32)INT32_MIN)
#define CZ_I32_MAX ((cz_i32)INT32_MAX)
#define CZ_I64_MIN ((cz_i64)INT64_MIN)
#define CZ_I64_MAX ((cz_i64)INT64_MAX)

/* Architecture-dependent size limits */
#define CZ_USIZE_MIN ((cz_usize)0)
#define CZ_USIZE_MAX ((cz_usize)SIZE_MAX)
#define CZ_ISIZE_MIN ((cz_isize)PTRDIFF_MIN)
#define CZ_ISIZE_MAX ((cz_isize)PTRDIFF_MAX)

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
