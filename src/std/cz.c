// cz.c - Consolidated raw C builtins and library code for Czar language
// This file contains all core C implementations that are included in generated code.
// It consolidates: print functions, string operations, OS detection, arena allocator,
// and memory tracking helpers.

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>

// ============================================================================
// PRINT FUNCTIONS
// ============================================================================

// Raw print with format string and variadic arguments, without newline
// Called from generated code as _cz_print()
static inline void _cz_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Raw print with format string and variadic arguments, with newline
// Called from generated code as _cz_println()
static inline void _cz_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

// Raw printf with format string and variadic arguments
// Called from generated code as _cz_printf()
static inline void _cz_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// ============================================================================
// STRING FUNCTIONS
// ============================================================================

// String struct definition
// Represents a dynamically-sized byte array suitable for UTF-8 text
typedef struct cz_string {
    char* data;         // Byte array (can contain UTF-8 encoded text)
    int32_t length;     // Number of BYTES (not characters)
    int32_t capacity;   // Allocated capacity in BYTES
} cz_string;

// String helper function: get C-style null-terminated string
static inline char* cz_string_cstr(cz_string* s) {
    return s->data;
}

// String helper function: ensure capacity with dynamic resizing
static inline void cz_string_ensure_capacity(cz_string* s, int32_t required_capacity) {
    if (s->capacity >= required_capacity) return;
    // Grow to next power of 2, minimum 16
    int32_t new_capacity = s->capacity ? s->capacity : 16;
    while (new_capacity < required_capacity) {
        new_capacity *= 2;
    }
    char* new_data = (char*)realloc(s->data, new_capacity);
    if (!new_data) {
        fprintf(stderr, "ERROR: String realloc failed\n");
        exit(1);
    }
    s->data = new_data;
    s->capacity = new_capacity;
}

// String helper function: safe append
static inline void cz_string_append_cstr(cz_string* dest, const char* src, int32_t src_len) {
    int32_t required = dest->length + src_len + 1;
    cz_string_ensure_capacity(dest, required);
    memcpy(dest->data + dest->length, src, src_len);
    dest->length += src_len;
    dest->data[dest->length] = '\0';
}

// String helper function: append another string
static inline void cz_string_append_string(cz_string* dest, cz_string* src) {
    cz_string_append_cstr(dest, src->data, src->length);
}

// String helper function: static concatenate
static inline cz_string* cz_string_concat_static(cz_string* s1, cz_string* s2) {
    int32_t total_len = s1->length + s2->length;
    int32_t capacity = 16;
    while (capacity < total_len + 1) {
        capacity *= 2;
    }

    cz_string* result = (cz_string*)malloc(sizeof(cz_string));
    if (!result) {
        fprintf(stderr, "ERROR: String malloc failed\n");
        exit(1);
    }

    result->data = (char*)malloc(capacity);
    if (!result->data) {
        fprintf(stderr, "ERROR: String data malloc failed\n");
        exit(1);
    }

    result->capacity = capacity;
    result->length = total_len;

    memcpy(result->data, s1->data, s1->length);
    memcpy(result->data + s1->length, s2->data, s2->length);
    result->data[result->length] = '\0';

    return result;
}

// String helper function: safe copy
static inline void cz_string_copy(cz_string* dest, const char* src, int32_t src_len) {
    int32_t required = src_len + 1;
    cz_string_ensure_capacity(dest, required);
    memcpy(dest->data, src, src_len);
    dest->length = src_len;
    dest->data[dest->length] = '\0';
}

// String helper function: substring
static inline cz_string* cz_string_substring(cz_string* s, int32_t start, int32_t end) {
    if (start < 0) start = 0;
    if (end < 0) end = s->length;
    if (start > s->length) start = s->length;
    if (end > s->length) end = s->length;
    if (start > end) start = end;

    int32_t sub_len = end - start;
    int32_t capacity = 16;
    while (capacity < sub_len + 1) {
        capacity *= 2;
    }

    cz_string* result = (cz_string*)malloc(sizeof(cz_string));
    if (!result) {
        fprintf(stderr, "ERROR: String malloc failed\n");
        exit(1);
    }

    result->data = (char*)malloc(capacity);
    if (!result->data) {
        fprintf(stderr, "ERROR: String data malloc failed\n");
        exit(1);
    }

    result->capacity = capacity;
    result->length = sub_len;

    if (sub_len > 0) {
        memcpy(result->data, s->data + start, sub_len);
    }
    result->data[result->length] = '\0';

    return result;
}

// String helper function: find substring (index)
static inline int32_t cz_string_index(cz_string* haystack, cz_string* needle) {
    if (needle->length == 0) return 0;
    if (needle->length > haystack->length) return -1;

    char* pos = strstr(haystack->data, needle->data);
    if (pos == NULL) return -1;

    return (int32_t)(pos - haystack->data);
}

// String helper function: backwards compatibility for find
static inline int32_t cz_string_find(cz_string* haystack, cz_string* needle) {
    return cz_string_index(haystack, needle);
}

// String helper function: find C-string
static inline int32_t cz_string_find_cstr(cz_string* haystack, const char* needle) {
    char* pos = strstr(haystack->data, needle);
    if (pos == NULL) return -1;
    return (int32_t)(pos - haystack->data);
}

// String helper function: contains
static inline int32_t cz_string_contains(cz_string* haystack, cz_string* needle) {
    return cz_string_index(haystack, needle) != -1 ? 1 : 0;
}

// String helper function: cut
static inline cz_string* cz_string_cut(cz_string* s, cz_string* separator) {
    int32_t sep_index = cz_string_index(s, separator);
    if (sep_index == -1) {
        return cz_string_substring(s, 0, s->length);
    }
    return cz_string_substring(s, 0, sep_index);
}

// String helper function: prefix
static inline int32_t cz_string_prefix(cz_string* s, cz_string* prefix) {
    if (prefix->length == 0) return 1;
    if (prefix->length > s->length) return 0;
    return memcmp(s->data, prefix->data, prefix->length) == 0 ? 1 : 0;
}

// String helper function: suffix
static inline int32_t cz_string_suffix(cz_string* s, cz_string* suffix) {
    if (suffix->length == 0) return 1;
    if (suffix->length > s->length) return 0;
    int32_t offset = s->length - suffix->length;
    return memcmp(s->data + offset, suffix->data, suffix->length) == 0 ? 1 : 0;
}

// String helper function: upper
static inline cz_string* cz_string_upper(cz_string* s) {
    for (int32_t i = 0; i < s->length; i++) {
        s->data[i] = (char)toupper((unsigned char)s->data[i]);
    }
    return s;
}

// String helper function: lower
static inline cz_string* cz_string_lower(cz_string* s) {
    for (int32_t i = 0; i < s->length; i++) {
        s->data[i] = (char)tolower((unsigned char)s->data[i]);
    }
    return s;
}

// String helper function: words
static inline cz_string** cz_string_words(cz_string* s, int32_t* out_count) {
    if (s->length == 0) {
        *out_count = 0;
        return NULL;
    }

    int32_t word_count = 0;
    int32_t in_word = 0;

    for (int32_t i = 0; i < s->length; i++) {
        if (isspace((unsigned char)s->data[i])) {
            in_word = 0;
        } else {
            if (!in_word) {
                word_count++;
                in_word = 1;
            }
        }
    }

    if (word_count == 0) {
        *out_count = 0;
        return NULL;
    }

    cz_string** words = (cz_string**)malloc(sizeof(cz_string*) * word_count);
    if (!words) {
        fprintf(stderr, "ERROR: String words malloc failed\n");
        exit(1);
    }

    int32_t word_idx = 0;
    int32_t word_start = -1;
    in_word = 0;

    for (int32_t i = 0; i <= s->length; i++) {
        int32_t is_space = (i == s->length) || isspace((unsigned char)s->data[i]);

        if (!is_space && !in_word) {
            word_start = i;
            in_word = 1;
        } else if ((is_space || i == s->length) && in_word) {
            int32_t word_len = i - word_start;
            int32_t capacity = 16;
            while (capacity < word_len + 1) {
                capacity *= 2;
            }

            words[word_idx] = (cz_string*)malloc(sizeof(cz_string));
            if (!words[word_idx]) {
                fprintf(stderr, "ERROR: String word malloc failed\n");
                exit(1);
            }

            words[word_idx]->data = (char*)malloc(capacity);
            if (!words[word_idx]->data) {
                fprintf(stderr, "ERROR: String word data malloc failed\n");
                exit(1);
            }

            words[word_idx]->capacity = capacity;
            words[word_idx]->length = word_len;

            if (word_len > 0) {
                memcpy(words[word_idx]->data, s->data + word_start, word_len);
            }
            words[word_idx]->data[word_len] = '\0';

            word_idx++;
            in_word = 0;
        }
    }

    *out_count = word_count;
    return words;
}

// String helper function: join array
static inline cz_string* cz_string_join_array(cz_string** strings, int32_t count) {
    if (count == 0) {
        cz_string* result = (cz_string*)malloc(sizeof(cz_string));
        if (!result) {
            fprintf(stderr, "ERROR: String malloc failed\n");
            exit(1);
        }
        result->data = (char*)malloc(16);
        if (!result->data) {
            fprintf(stderr, "ERROR: String data malloc failed\n");
            exit(1);
        }
        result->capacity = 16;
        result->length = 0;
        result->data[0] = '\0';
        return result;
    }

    int32_t total_len = 0;
    for (int32_t i = 0; i < count; i++) {
        total_len += strings[i]->length;
    }

    int32_t capacity = 16;
    while (capacity < total_len + 1) {
        capacity *= 2;
    }

    cz_string* result = (cz_string*)malloc(sizeof(cz_string));
    if (!result) {
        fprintf(stderr, "ERROR: String malloc failed\n");
        exit(1);
    }

    result->data = (char*)malloc(capacity);
    if (!result->data) {
        fprintf(stderr, "ERROR: String data malloc failed\n");
        exit(1);
    }

    result->capacity = capacity;
    result->length = 0;

    for (int32_t i = 0; i < count; i++) {
        memcpy(result->data + result->length, strings[i]->data, strings[i]->length);
        result->length += strings[i]->length;
    }
    result->data[result->length] = '\0';

    return result;
}

// String helper function: left trim
static inline cz_string* cz_string_ltrim(cz_string* s) {
    if (s->length == 0) return s;
    int32_t leading = (int32_t)strspn(s->data, " \t\n\r\v\f");
    if (leading == 0) return s;
    if (leading >= s->length) {
        s->length = 0;
        s->data[0] = '\0';
        return s;
    }
    int32_t new_len = s->length - leading;
    memmove(s->data, s->data + leading, new_len);
    s->length = new_len;
    s->data[s->length] = '\0';
    return s;
}

// String helper function: right trim
static inline cz_string* cz_string_rtrim(cz_string* s) {
    if (s->length == 0) return s;
    int32_t i = s->length - 1;
    while (i >= 0 && isspace((unsigned char)s->data[i])) {
        i--;
    }
    s->length = i + 1;
    s->data[s->length] = '\0';
    return s;
}

// String helper function: trim
static inline cz_string* cz_string_trim(cz_string* s) {
    cz_string_ltrim(s);
    cz_string_rtrim(s);
    return s;
}

// String helper function: split
static inline cz_string** cz_string_split(cz_string* s, char delimiter, int32_t* out_count) {
    if (s->length == 0) {
        *out_count = 0;
        return NULL;
    }

    int32_t count = 1;
    for (int32_t i = 0; i < s->length; i++) {
        if (s->data[i] == delimiter) count++;
    }

    cz_string** parts = (cz_string**)malloc(sizeof(cz_string*) * count);
    if (!parts) {
        fprintf(stderr, "ERROR: String split malloc failed\n");
        exit(1);
    }

    int32_t part_idx = 0;
    int32_t start = 0;

    for (int32_t i = 0; i <= s->length; i++) {
        if (i == s->length || s->data[i] == delimiter) {
            int32_t part_len = i - start;
            int32_t capacity = 16;
            while (capacity < part_len + 1) {
                capacity *= 2;
            }

            parts[part_idx] = (cz_string*)malloc(sizeof(cz_string));
            if (!parts[part_idx]) {
                fprintf(stderr, "ERROR: String part malloc failed\n");
                exit(1);
            }

            parts[part_idx]->data = (char*)malloc(capacity);
            if (!parts[part_idx]->data) {
                fprintf(stderr, "ERROR: String part data malloc failed\n");
                exit(1);
            }

            parts[part_idx]->capacity = capacity;
            parts[part_idx]->length = part_len;

            if (part_len > 0) {
                memcpy(parts[part_idx]->data, s->data + start, part_len);
            }
            parts[part_idx]->data[part_len] = '\0';

            part_idx++;
            start = i + 1;
        }
    }

    *out_count = count;
    return parts;
}

// ============================================================================
// OS DETECTION
// ============================================================================

#ifdef __linux__
    #include <sys/utsname.h>
#endif

#ifdef _WIN32
    #define CZ_OS_WINDOWS 1
    #define CZ_OS_LINUX 0
    #define CZ_OS_MACOS 0
#elif __APPLE__
    #include <TargetConditionals.h>
    #if TARGET_OS_MAC
        #define CZ_OS_MACOS 1
        #define CZ_OS_LINUX 0
        #define CZ_OS_WINDOWS 0
    #endif
#elif __linux__
    #define CZ_OS_LINUX 1
    #define CZ_OS_WINDOWS 0
    #define CZ_OS_MACOS 0
#else
    #define CZ_OS_LINUX 0
    #define CZ_OS_WINDOWS 0
    #define CZ_OS_MACOS 0
#endif

// Undefine potentially conflicting system macros
#ifdef linux
#undef linux
#endif
#ifdef unix
#undef unix
#endif
#ifdef windows
#undef windows
#endif

// OS struct definition
typedef struct {
    const char* name;
    const char* version;
    const char* kernel;
    bool linux;
    bool windows;
    bool macos;
} _cz_os_t;

// Global OS instance
static _cz_os_t __cz_os;
static bool __cz_os_initialized = false;

// Initialize OS detection
static void _cz_os_init() {
    if (__cz_os_initialized) {
        return;
    }
    __cz_os_initialized = true;
    
    #if CZ_OS_WINDOWS
        __cz_os.name = "windows";
        __cz_os.linux = false;
        __cz_os.windows = true;
        __cz_os.macos = false;
        __cz_os.kernel = "windows";
        __cz_os.version = "unknown";
    #elif CZ_OS_MACOS
        __cz_os.name = "macos";
        __cz_os.linux = false;
        __cz_os.windows = false;
        __cz_os.macos = true;
        __cz_os.kernel = "darwin";
        __cz_os.version = "unknown";
    #elif CZ_OS_LINUX
        __cz_os.name = "linux";
        __cz_os.linux = true;
        __cz_os.windows = false;
        __cz_os.macos = false;
        __cz_os.kernel = "linux";
        
        struct utsname buffer;
        if (uname(&buffer) == 0) {
            static char version_buf[256];
            size_t release_len = strlen(buffer.release);
            if (release_len >= sizeof(version_buf)) {
                release_len = sizeof(version_buf) - 1;
            }
            memcpy(version_buf, buffer.release, release_len);
            version_buf[release_len] = '\0';
            __cz_os.version = version_buf;
        } else {
            __cz_os.version = "unknown";
        }
    #else
        __cz_os.name = "unknown";
        __cz_os.linux = false;
        __cz_os.windows = false;
        __cz_os.macos = false;
        __cz_os.kernel = "unknown";
        __cz_os.version = "unknown";
    #endif
}

// Get OS struct
static inline _cz_os_t* _cz_os_get() {
    return &__cz_os;
}

// ============================================================================
// ARENA ALLOCATOR
// ============================================================================

// Forward declare the arena struct
typedef struct cz_alloc_arena cz_alloc_arena;

// Constructor for arena
void _cz_alloc_arena_init(cz_alloc_arena* self) {
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

// Destructor for arena
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

// ============================================================================
// MEMORY TRACKING (for cz.alloc.debug)
// ============================================================================

// Memory tracking globals
static size_t _cz_explicit_alloc_count = 0;
static size_t _cz_explicit_alloc_bytes = 0;
static size_t _cz_implicit_alloc_count = 0;
static size_t _cz_implicit_alloc_bytes = 0;
static size_t _cz_explicit_free_count = 0;
static size_t _cz_implicit_free_count = 0;
static size_t _cz_current_alloc_count = 0;
static size_t _cz_current_alloc_bytes = 0;
static size_t _cz_peak_alloc_count = 0;
static size_t _cz_peak_alloc_bytes = 0;

// Debug allocator with tracking
void* cz_alloc_debug_alloc(size_t size, int is_explicit) {
    void* ptr = malloc(size);
    if (ptr) {
        if (is_explicit) {
            _cz_explicit_alloc_count++;
            _cz_explicit_alloc_bytes += size;
        } else {
            _cz_implicit_alloc_count++;
            _cz_implicit_alloc_bytes += size;
        }
        _cz_current_alloc_count++;
        _cz_current_alloc_bytes += size;
        if (_cz_current_alloc_count > _cz_peak_alloc_count) {
            _cz_peak_alloc_count = _cz_current_alloc_count;
        }
        if (_cz_current_alloc_bytes > _cz_peak_alloc_bytes) {
            _cz_peak_alloc_bytes = _cz_current_alloc_bytes;
        }
    }
    return ptr;
}

// Debug reallocator (simplified tracking)
void* cz_alloc_debug_ralloc(void* ptr, size_t new_size) {
    return realloc(ptr, new_size);
}

// Debug free with tracking
void cz_alloc_debug_free(void* ptr, int is_explicit) {
    if (ptr) {
        if (is_explicit) {
            _cz_explicit_free_count++;
        } else {
            _cz_implicit_free_count++;
        }
        _cz_current_alloc_count--;
    }
    free(ptr);
}

// Print memory statistics
void _cz_print_memory_stats(void) {
    size_t total_alloc_count = _cz_explicit_alloc_count + _cz_implicit_alloc_count;
    size_t total_alloc_bytes = _cz_explicit_alloc_bytes + _cz_implicit_alloc_bytes;
    size_t total_free_count = _cz_explicit_free_count + _cz_implicit_free_count;
    fprintf(stderr, "\n=== Memory Summary (cz.alloc.debug) ===\n");
    fprintf(stderr, "Allocations:\n");
    fprintf(stderr, "  Explicit: %zu (%zu bytes)\n", _cz_explicit_alloc_count, _cz_explicit_alloc_bytes);
    fprintf(stderr, "  Implicit: %zu (%zu bytes)\n", _cz_implicit_alloc_count, _cz_implicit_alloc_bytes);
    fprintf(stderr, "  Total:    %zu (%zu bytes)\n", total_alloc_count, total_alloc_bytes);
    fprintf(stderr, "\n");
    fprintf(stderr, "Frees:\n");
    fprintf(stderr, "  Explicit: %zu\n", _cz_explicit_free_count);
    fprintf(stderr, "  Implicit: %zu\n", _cz_implicit_free_count);
    fprintf(stderr, "  Total:    %zu\n", total_free_count);
    fprintf(stderr, "\n");
    fprintf(stderr, "Peak Usage:\n");
    fprintf(stderr, "  Count: %zu allocations\n", _cz_peak_alloc_count);
    fprintf(stderr, "  Bytes: %zu bytes\n", _cz_peak_alloc_bytes);
    if (total_alloc_count != total_free_count) {
        fprintf(stderr, "\n");
        fprintf(stderr, "WARNING: Memory leak detected! %zu allocations not freed\n",
                total_alloc_count - total_free_count);
    }
    fprintf(stderr, "======================\n");
}
