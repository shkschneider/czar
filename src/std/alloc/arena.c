// cz_alloc_arena.c - Arena allocator implementation
// Functions prefixed with _ to be called from generated arena methods

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

// The Arena struct from cz.alloc will be defined by generated code as cz_alloc_arena
// This typedef creates compatibility alias for backwards compatibility
typedef struct cz_alloc_arena cz_alloc_arena;

// Constructor for any arena struct
void _cz_alloc_arena_init(cz_alloc_arena* self) {
    // Arena struct layout: uint64_t size, void* buffer, uint64_t offset
    uint64_t* size_ptr = (uint64_t*)self;
    void** buffer_ptr = (void**)((char*)self + sizeof(uint64_t));
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));

    *buffer_ptr = malloc(*size_ptr);
    if (!*buffer_ptr) {
        fprintf(stderr, "FATAL: Failed to allocate arena of size %lu\n", *size_ptr);
        abort();
    }
    *offset_ptr = 0;
}

// Destructor for any arena struct
void _cz_alloc_arena_fini(cz_alloc_arena* self) {
    uint64_t* size_ptr = (uint64_t*)self;
    void** buffer_ptr = (void**)((char*)self + sizeof(uint64_t));
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));

    if (*buffer_ptr) {
        free(*buffer_ptr);
        *buffer_ptr = NULL;
        *size_ptr = 0;
        *offset_ptr = 0;
    }
}

// Arena alloc implementation
void* _alloc(cz_alloc_arena* self, uint64_t size) {
    uint64_t* size_ptr = (uint64_t*)self;
    void** buffer_ptr = (void**)((char*)self + sizeof(uint64_t));
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));

    uint64_t aligned_size = (size + 7) & ~7;

    if (*offset_ptr + aligned_size > *size_ptr) {
        fprintf(stderr, "FATAL: Arena out of memory. Requested %lu bytes, but only %lu bytes available.\n",
                size, *size_ptr - *offset_ptr);
        abort();
    }

    void* ptr = (char*)*buffer_ptr + *offset_ptr;
    *offset_ptr += aligned_size;
    return ptr;
}

// Arena ralloc implementation
void* _ralloc(cz_alloc_arena* self, const void* ptr, uint64_t new_size) {
    if (!ptr) {
        return _alloc(self, new_size);
    }

    uint64_t* size_ptr = (uint64_t*)self;
    void** buffer_ptr = (void**)((char*)self + sizeof(uint64_t));
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));

    uint64_t aligned_new_size = (new_size + 7) & ~7;

    char* last_alloc = (char*)*buffer_ptr + *offset_ptr;
    char* ptr_char = (char*)ptr;

    if (ptr_char < last_alloc && last_alloc - ptr_char < 1024) {
        uint64_t current_size = last_alloc - ptr_char;

        if (aligned_new_size <= current_size) {
            *offset_ptr = (ptr_char - (char*)*buffer_ptr) + aligned_new_size;
            return (void*)ptr;
        } else {
            uint64_t additional = aligned_new_size - current_size;
            if (*offset_ptr + additional <= *size_ptr) {
                *offset_ptr += additional;
                return (void*)ptr;
            }
        }
    }

    void* new_ptr = _alloc(self, new_size);
    memcpy(new_ptr, ptr, new_size);
    return new_ptr;
}

// Arena clear implementation
void _clear(cz_alloc_arena* self) {
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));
    *offset_ptr = 0;
}
