// default.c - Simple malloc/free wrapper
// C functions for cz.alloc.default module

#include <stdlib.h>

// Allocate memory
void* cz_alloc_default_alloc(size_t size) {
    return malloc(size);
}

// Reallocate memory
void* cz_alloc_default_ralloc(void* ptr, size_t new_size) {
    return realloc(ptr, new_size);
}

// Free memory
void cz_alloc_default_free(void* ptr) {
    free(ptr);
}
