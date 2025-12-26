#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool cz_debug_flag = false;

// Raw C implementation from string.c
// cz_string.c - Safe string implementation for Czar language
// This file contains all string helper functions that are memory-safe and bounds-checked.
// Generated code will include this file to provide string functionality.
//
// UTF-8 SUPPORT:
// The cz_string type treats strings as byte arrays, not character arrays.
// This design naturally supports UTF-8 encoding, where multi-byte characters
// are stored as sequences of bytes.
//
// - `length` field represents the number of BYTES, not the number of characters
// - `data` field is a byte array that can contain UTF-8 encoded text
// - Operations like substring(), index(), find(), etc. work on BYTE offsets
// - This means a UTF-8 character may span multiple bytes (1-4 bytes per character)
//
// IMPORTANT NOTES:
// - upper() and lower() only work correctly for ASCII characters (bytes 0-127)
//   Bytes 128-255 in UTF-8 are part of multi-byte sequences, and attempting
//   case conversion on them individually would corrupt the UTF-8 encoding.
//   Multi-byte UTF-8 characters will not be converted and are preserved as-is.
// - All string operations preserve UTF-8 byte sequences correctly as long as
//   you work on character boundaries (don't split multi-byte characters)
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
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
// String helper function: safe append (dynamically resizes, bounds-checked)
// This is the instance method version: string:append(str)
// NOTE: Appends BYTES, not characters. Works correctly with UTF-8 as it
// preserves all byte sequences without interpretation.
static inline void cz_string_append_cstr(cz_string* dest, const char* src, int32_t src_len) {
    int32_t required = dest->length + src_len + 1; // +1 for null terminator
    cz_string_ensure_capacity(dest, required);
    // Safe copy: we know we have enough space
    memcpy(dest->data + dest->length, src, src_len);
    dest->length += src_len;
    dest->data[dest->length] = '\0';
}
// String helper function: append another string (instance method)
static inline void cz_string_append_string(cz_string* dest, cz_string* src) {
    cz_string_append_cstr(dest, src->data, src->length);
}
// String helper function: static concatenate - returns a new string
// This is the static method version: string.concat(s1, s2)
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
// String helper function: safe copy (bounds-checked, no buffer overrun)
static inline void cz_string_copy(cz_string* dest, const char* src, int32_t src_len) {
    int32_t required = src_len + 1; // +1 for null terminator
    cz_string_ensure_capacity(dest, required);
    memcpy(dest->data, src, src_len);
    dest->length = src_len;
    dest->data[dest->length] = '\0';
}
// String helper function: substring - extract a portion of the string
// Returns a new heap-allocated string
// NOTE: Works on BYTE offsets, not character offsets.
// For UTF-8 strings, ensure start and end are on character boundaries to avoid
// splitting multi-byte characters. This function will correctly copy UTF-8 byte
// sequences as long as the offsets are valid.
static inline cz_string* cz_string_substring(cz_string* s, int32_t start, int32_t end) {
    // Handle negative indices
    if (start < 0) start = 0;
    if (end < 0) end = s->length;
    // Clamp to valid range
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
// String helper function: find substring using safe strstr()
// Returns index of first occurrence, or -1 if not found
// Renamed to cz_string_index to match the new API
// NOTE: Returns BYTE offset, not character offset. Works correctly with UTF-8
// strings as it performs byte-by-byte comparison.
static inline int32_t cz_string_index(cz_string* haystack, cz_string* needle) {
    if (needle->length == 0) return 0;
    if (needle->length > haystack->length) return -1;
    char* pos = strstr(haystack->data, needle->data);
    if (pos == NULL) return -1;
    return (int32_t)(pos - haystack->data);
}
// String helper function: keep old name for backwards compatibility
static inline int32_t cz_string_find(cz_string* haystack, cz_string* needle) {
    return cz_string_index(haystack, needle);
}
// String helper function: find C-string using safe strstr()
static inline int32_t cz_string_find_cstr(cz_string* haystack, const char* needle) {
    char* pos = strstr(haystack->data, needle);
    if (pos == NULL) return -1;
    return (int32_t)(pos - haystack->data);
}
// String helper function: contains - check if substring exists
// Returns 1 (true) if needle is found, 0 (false) otherwise
static inline int32_t cz_string_contains(cz_string* haystack, cz_string* needle) {
    return cz_string_index(haystack, needle) != -1 ? 1 : 0;
}
// String helper function: cut - extract substring from 0 to first separator occurrence
// Returns a new heap-allocated string
static inline cz_string* cz_string_cut(cz_string* s, cz_string* separator) {
    int32_t sep_index = cz_string_index(s, separator);
    if (sep_index == -1) {
        // Separator not found, return copy of entire string
        return cz_string_substring(s, 0, s->length);
    }
    // Return substring from 0 to separator position
    return cz_string_substring(s, 0, sep_index);
}
// String helper function: prefix - check if string starts with prefix
// Returns 1 (true) if string starts with prefix, 0 (false) otherwise
static inline int32_t cz_string_prefix(cz_string* s, cz_string* prefix) {
    if (prefix->length == 0) return 1;
    if (prefix->length > s->length) return 0;
    return memcmp(s->data, prefix->data, prefix->length) == 0 ? 1 : 0;
}
// String helper function: suffix - check if string ends with suffix
// Returns 1 (true) if string ends with suffix, 0 (false) otherwise
static inline int32_t cz_string_suffix(cz_string* s, cz_string* suffix) {
    if (suffix->length == 0) return 1;
    if (suffix->length > s->length) return 0;
    int32_t offset = s->length - suffix->length;
    return memcmp(s->data + offset, suffix->data, suffix->length) == 0 ? 1 : 0;
}
// String helper function: upper - convert string to uppercase
// Modifies the string in place, returns the string
// NOTE: This function only works correctly for ASCII characters (bytes 0-127).
// Multi-byte UTF-8 characters (bytes 128-255) are part of multi-byte sequences,
// and attempting case conversion on them would corrupt the UTF-8 encoding.
// Non-ASCII characters are preserved as-is. For proper UTF-8 case conversion,
// a Unicode library would be needed.
static inline cz_string* cz_string_upper(cz_string* s) {
    for (int32_t i = 0; i < s->length; i++) {
        s->data[i] = (char)toupper((unsigned char)s->data[i]);
    }
    return s;
}
// String helper function: lower - convert string to lowercase
// Modifies the string in place, returns the string
// NOTE: This function only works correctly for ASCII characters (bytes 0-127).
// Multi-byte UTF-8 characters (bytes 128-255) are part of multi-byte sequences,
// and attempting case conversion on them would corrupt the UTF-8 encoding.
// Non-ASCII characters are preserved as-is. For proper UTF-8 case conversion,
// a Unicode library would be needed.
static inline cz_string* cz_string_lower(cz_string* s) {
    for (int32_t i = 0; i < s->length; i++) {
        s->data[i] = (char)tolower((unsigned char)s->data[i]);
    }
    return s;
}
// String helper function: words - split string by whitespace
// Returns a dynamically allocated array of strings
// The count is stored in the out_count parameter
// NOTE: This function is implemented but not yet exposed to the language
// because it requires support for returning arrays from methods.
static inline cz_string** cz_string_words(cz_string* s, int32_t* out_count) {
    if (s->length == 0) {
        *out_count = 0;
        return NULL;
    }
    // Count words by counting transitions from whitespace to non-whitespace
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
    // Allocate array of string pointers
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
            // Start of a new word
            word_start = i;
            in_word = 1;
        } else if ((is_space || i == s->length) && in_word) {
            // End of a word
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
// String helper function: join - static method to concatenate multiple strings
// Takes an array of strings and concatenates them
// NOTE: This function is implemented but not yet exposed to the language
// because it requires support for variadic static methods or array parameters.
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
    // Calculate total length
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
    // Copy all strings
    for (int32_t i = 0; i < count; i++) {
        memcpy(result->data + result->length, strings[i]->data, strings[i]->length);
        result->length += strings[i]->length;
    }
    result->data[result->length] = '\0';
    return result;
}
// String helper function: left trim whitespace
// Modifies the string in place, returns the string
static inline cz_string* cz_string_ltrim(cz_string* s) {
    if (s->length == 0) return s;
    // Find first non-whitespace using strspn (safe)
    int32_t leading = (int32_t)strspn(s->data, " \t\n\r\v\f");
    if (leading == 0) return s;
    if (leading >= s->length) {
        // All whitespace
        s->length = 0;
        s->data[0] = '\0';
        return s;
    }
    // Move data to the beginning
    int32_t new_len = s->length - leading;
    memmove(s->data, s->data + leading, new_len);
    s->length = new_len;
    s->data[s->length] = '\0';
    return s;
}
// String helper function: right trim whitespace
// Modifies the string in place, returns the string
static inline cz_string* cz_string_rtrim(cz_string* s) {
    if (s->length == 0) return s;
    // Find trailing whitespace from the end
    int32_t i = s->length - 1;
    while (i >= 0 && isspace((unsigned char)s->data[i])) {
        i--;
    }
    s->length = i + 1;
    s->data[s->length] = '\0';
    return s;
}
// String helper function: trim whitespace from both ends
// Modifies the string in place, returns the string
static inline cz_string* cz_string_trim(cz_string* s) {
    cz_string_ltrim(s);
    cz_string_rtrim(s);
    return s;
}
// String helper function: split string by delimiter
// Returns a dynamically allocated array of strings
// The count is stored in the out_count parameter
static inline cz_string** cz_string_split(cz_string* s, char delimiter, int32_t* out_count) {
    if (s->length == 0) {
        *out_count = 0;
        return NULL;
    }
    // Count occurrences of delimiter using strchr (safe)
    int32_t count = 1;  // At least one part
    for (int32_t i = 0; i < s->length; i++) {
        if (s->data[i] == delimiter) count++;
    }
    // Allocate array of string pointers
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

// Raw C implementation from fmt.c
// cz_print.c - Raw C print functions for Czar language
// This file contains low-level print implementations with _cz_ prefix
// These are the raw primitives called from generated CZ code
#include <stdio.h>
#include <stdarg.h>
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

// Raw C implementation from os.c
// OS detection struct for the cz module
// This provides runtime OS information
#ifndef CZ_OS_H
#define CZ_OS_H
#include <stdbool.h>
#include <string.h>
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
// OS struct definition - C type with cz_ prefix
typedef struct {
    const char* name;      // "linux", "windows", "macos", etc.
    const char* version;   // kernel version string only
    const char* kernel;    // kernel name lowercased ("linux", "darwin", "windows", etc.)
    bool linux;            // true if running on Linux
    bool windows;          // true if running on Windows
    bool macos;            // true if running on macOS
} cz_os;
// Global OS instance
static cz_os __cz_os;
static bool __cz_os_initialized = false;
// Initialize OS detection - called once on first access
// Internal function with _cz_ prefix
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
        // On Windows, we could use GetVersionEx but it's deprecated
        // For simplicity, we'll just use a generic version string
        __cz_os.version = "unknown";
    #elif CZ_OS_MACOS
        __cz_os.name = "macos";
        __cz_os.linux = false;
        __cz_os.windows = false;
        __cz_os.macos = true;
        __cz_os.kernel = "darwin";
        // On macOS, we could use uname or sysctl
        __cz_os.version = "unknown";
    #elif CZ_OS_LINUX
        __cz_os.name = "linux";
        __cz_os.linux = true;
        __cz_os.windows = false;
        __cz_os.macos = false;
        __cz_os.kernel = "linux";
        
        // Try to get kernel version using uname
        struct utsname buffer;
        if (uname(&buffer) == 0) {
            // Allocate static buffer for version string
            static char version_buf[256];
            // Safely copy release version (just the version, not the sysname)
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
// Get OS struct - returns pointer to OS data
// Raw C function with _cz_ prefix, called from generated code
// NOTE: _cz_os_init() must be called via #init macro before accessing this
static inline cz_os* _cz_os_get() {
    return &__cz_os;
}
#endif // CZ_OS_H

// Raw C implementation from arena.c
// cz_alloc_arena.c - Arena allocator implementation
// Functions prefixed with _ to be called from generated arena methods
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
// The CzAllocArena struct will be defined by generated code
// This typedef creates an alias cz_alloc_arena for compatibility
typedef struct CzAllocArena cz_alloc_arena;
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

// Forward declarations
int32_t main();

int32_t main()
{
    _cz_println("Hello, World!");
    _cz_println("Welcome to Czar!");
    return 0;
}

