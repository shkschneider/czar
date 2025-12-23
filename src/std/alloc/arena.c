// arena.c - Arena allocator implementation
// C functions for cz.alloc.arena module

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

// Forward declare the arena struct (defined in arena.cz)
typedef struct cz_Arena cz_Arena;

// Constructor - initialize arena with given size
void cz_alloc_arena_init(cz_Arena* self) {
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

// Destructor - free arena memory
void cz_alloc_arena_fini(cz_Arena* self) {
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

// Allocate memory from arena
void* cz_alloc_arena_alloc(cz_Arena* self, uint64_t size) {
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

// Reset arena offset to reuse buffer
void cz_alloc_arena_reset(cz_Arena* self) {
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));
    *offset_ptr = 0;
}

// Get remaining capacity
uint64_t cz_alloc_arena_remaining(cz_Arena* self) {
    uint64_t* size_ptr = (uint64_t*)self;
    uint64_t* offset_ptr = (uint64_t*)((char*)self + sizeof(uint64_t) + sizeof(void*));
    return *size_ptr - *offset_ptr;
}
