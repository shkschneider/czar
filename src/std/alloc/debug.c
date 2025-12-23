// debug.c - Debug allocator with tracking
// C functions for cz.alloc.debug module

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

// Tracking variables
static size_t _czar_explicit_alloc_count = 0;
static size_t _czar_explicit_alloc_bytes = 0;
static size_t _czar_implicit_alloc_count = 0;
static size_t _czar_implicit_alloc_bytes = 0;
static size_t _czar_explicit_free_count = 0;
static size_t _czar_implicit_free_count = 0;
static size_t _czar_current_alloc_count = 0;
static size_t _czar_current_alloc_bytes = 0;
static size_t _czar_peak_alloc_count = 0;
static size_t _czar_peak_alloc_bytes = 0;

// Allocate memory with tracking
void* cz_alloc_debug_alloc(size_t size, int is_explicit) {
    void* ptr = malloc(size);
    if (ptr) {
        if (is_explicit) {
            _czar_explicit_alloc_count++;
            _czar_explicit_alloc_bytes += size;
        } else {
            _czar_implicit_alloc_count++;
            _czar_implicit_alloc_bytes += size;
        }
        _czar_current_alloc_count++;
        _czar_current_alloc_bytes += size;
        if (_czar_current_alloc_count > _czar_peak_alloc_count) {
            _czar_peak_alloc_count = _czar_current_alloc_count;
        }
        if (_czar_current_alloc_bytes > _czar_peak_alloc_bytes) {
            _czar_peak_alloc_bytes = _czar_current_alloc_bytes;
        }
    }
    return ptr;
}

// Reallocate memory
void* cz_alloc_debug_ralloc(void* ptr, size_t new_size) {
    // Note: tracking for ralloc is simplified - doesn't track size changes
    return realloc(ptr, new_size);
}

// Free memory with tracking
void cz_alloc_debug_free(void* ptr, int is_explicit) {
    if (ptr) {
        if (is_explicit) {
            _czar_explicit_free_count++;
        } else {
            _czar_implicit_free_count++;
        }
        _czar_current_alloc_count--;
        // Note: we can't track bytes freed without storing allocation sizes
        free(ptr);
    }
}

// Print allocation statistics
void cz_alloc_debug_print_stats() {
    fprintf(stderr, "\n=== Memory Allocation Statistics ===\n");
    fprintf(stderr, "Explicit allocations: %zu (%zu bytes)\n", 
            _czar_explicit_alloc_count, _czar_explicit_alloc_bytes);
    fprintf(stderr, "Implicit allocations: %zu (%zu bytes)\n", 
            _czar_implicit_alloc_count, _czar_implicit_alloc_bytes);
    fprintf(stderr, "Total allocations: %zu (%zu bytes)\n",
            _czar_explicit_alloc_count + _czar_implicit_alloc_count,
            _czar_explicit_alloc_bytes + _czar_implicit_alloc_bytes);
    fprintf(stderr, "Explicit frees: %zu\n", _czar_explicit_free_count);
    fprintf(stderr, "Implicit frees: %zu\n", _czar_implicit_free_count);
    fprintf(stderr, "Current allocations: %zu (%zu bytes)\n",
            _czar_current_alloc_count, _czar_current_alloc_bytes);
    fprintf(stderr, "Peak allocations: %zu (%zu bytes)\n",
            _czar_peak_alloc_count, _czar_peak_alloc_bytes);
    fprintf(stderr, "====================================\n\n");
}
