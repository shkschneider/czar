/*
 * CZar - C semantic authority layer
 * Type system header (cz_types.h)
 * 
 * Provides fixed-width type aliases and numeric limit constants:
 * - Type aliases (cz_u8, cz_i32, cz_f32, etc.)
 * - Numeric limit constants (CZ_U8_MAX, CZ_I32_MIN, etc.)
 */

#ifndef CZ_TYPES_H
#define CZ_TYPES_H

#include <stdint.h>
#include <stddef.h>

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

#endif /* CZ_TYPES_H */
