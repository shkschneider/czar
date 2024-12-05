#ifndef CZ_TYPES_H_
#define CZ_TYPES_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#define any void
#define SIZE(x) (size_t)sizeof(x)

typedef _Bool bit;
typedef char byte;

typedef int8_t i8; // char
typedef int16_t i16; // short int
typedef int32_t i32; // long int
typedef int64_t i64; // long long

typedef uint8_t u8; // char
typedef uint16_t u16; // short int
typedef uint32_t u32; // long int
typedef uint64_t u64; // long long

typedef uint32_t f32; // float
typedef uint64_t f64; // double

typedef long double f128;

#endif
