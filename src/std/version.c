// version.c - Semantic versioning support for Czar language
// Part of the Czar standard library

#include <stdint.h>

// Semantic version struct
typedef struct Version {
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} Version;
