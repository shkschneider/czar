#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool czar_debug_flag = false;

// Raw C implementation from cz_string.c
// czar_string.c - Safe string implementation for Czar language
// This file contains all string helper functions that are memory-safe and bounds-checked.
// Generated code will include this file to provide string functionality.
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
// String struct definition
typedef struct czar_string {
    char* data;
    int32_t length;
    int32_t capacity;
} czar_string;
// String helper function: get C-style null-terminated string
static inline char* czar_string_cstr(czar_string* s) {
    return s->data;
}
// String helper function: ensure capacity with dynamic resizing
static inline void czar_string_ensure_capacity(czar_string* s, int32_t required_capacity) {
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
static inline void czar_string_append_cstr(czar_string* dest, const char* src, int32_t src_len) {
    int32_t required = dest->length + src_len + 1; // +1 for null terminator
    czar_string_ensure_capacity(dest, required);
    // Safe copy: we know we have enough space
    memcpy(dest->data + dest->length, src, src_len);
    dest->length += src_len;
    dest->data[dest->length] = '\0';
}
// String helper function: append another string (instance method)
static inline void czar_string_append_string(czar_string* dest, czar_string* src) {
    czar_string_append_cstr(dest, src->data, src->length);
}
// String helper function: static concatenate - returns a new string
// This is the static method version: string.concat(s1, s2)
static inline czar_string* czar_string_concat_static(czar_string* s1, czar_string* s2) {
    int32_t total_len = s1->length + s2->length;
    int32_t capacity = 16;
    while (capacity < total_len + 1) {
        capacity *= 2;
    }
    
    czar_string* result = (czar_string*)malloc(sizeof(czar_string));
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
static inline void czar_string_copy(czar_string* dest, const char* src, int32_t src_len) {
    int32_t required = src_len + 1; // +1 for null terminator
    czar_string_ensure_capacity(dest, required);
    memcpy(dest->data, src, src_len);
    dest->length = src_len;
    dest->data[dest->length] = '\0';
}
// String helper function: substring - extract a portion of the string
// Returns a new heap-allocated string
static inline czar_string* czar_string_substring(czar_string* s, int32_t start, int32_t end) {
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
    
    czar_string* result = (czar_string*)malloc(sizeof(czar_string));
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
// Renamed to czar_string_index to match the new API
static inline int32_t czar_string_index(czar_string* haystack, czar_string* needle) {
    if (needle->length == 0) return 0;
    if (needle->length > haystack->length) return -1;
    
    char* pos = strstr(haystack->data, needle->data);
    if (pos == NULL) return -1;
    
    return (int32_t)(pos - haystack->data);
}
// String helper function: keep old name for backwards compatibility
static inline int32_t czar_string_find(czar_string* haystack, czar_string* needle) {
    return czar_string_index(haystack, needle);
}
// String helper function: find C-string using safe strstr()
static inline int32_t czar_string_find_cstr(czar_string* haystack, const char* needle) {
    char* pos = strstr(haystack->data, needle);
    if (pos == NULL) return -1;
    
    return (int32_t)(pos - haystack->data);
}
// String helper function: contains - check if substring exists
// Returns 1 (true) if needle is found, 0 (false) otherwise
static inline int32_t czar_string_contains(czar_string* haystack, czar_string* needle) {
    return czar_string_index(haystack, needle) != -1 ? 1 : 0;
}
// String helper function: cut - extract substring from 0 to first separator occurrence
// Returns a new heap-allocated string
static inline czar_string* czar_string_cut(czar_string* s, czar_string* separator) {
    int32_t sep_index = czar_string_index(s, separator);
    
    if (sep_index == -1) {
        // Separator not found, return copy of entire string
        return czar_string_substring(s, 0, s->length);
    }
    
    // Return substring from 0 to separator position
    return czar_string_substring(s, 0, sep_index);
}
// String helper function: prefix - check if string starts with prefix
// Returns 1 (true) if string starts with prefix, 0 (false) otherwise
static inline int32_t czar_string_prefix(czar_string* s, czar_string* prefix) {
    if (prefix->length == 0) return 1;
    if (prefix->length > s->length) return 0;
    
    return memcmp(s->data, prefix->data, prefix->length) == 0 ? 1 : 0;
}
// String helper function: suffix - check if string ends with suffix
// Returns 1 (true) if string ends with suffix, 0 (false) otherwise
static inline int32_t czar_string_suffix(czar_string* s, czar_string* suffix) {
    if (suffix->length == 0) return 1;
    if (suffix->length > s->length) return 0;
    
    int32_t offset = s->length - suffix->length;
    return memcmp(s->data + offset, suffix->data, suffix->length) == 0 ? 1 : 0;
}
// String helper function: upper - convert string to uppercase
// Modifies the string in place, returns the string
static inline czar_string* czar_string_upper(czar_string* s) {
    for (int32_t i = 0; i < s->length; i++) {
        s->data[i] = (char)toupper((unsigned char)s->data[i]);
    }
    return s;
}
// String helper function: lower - convert string to lowercase
// Modifies the string in place, returns the string
static inline czar_string* czar_string_lower(czar_string* s) {
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
static inline czar_string** czar_string_words(czar_string* s, int32_t* out_count) {
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
    czar_string** words = (czar_string**)malloc(sizeof(czar_string*) * word_count);
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
            
            words[word_idx] = (czar_string*)malloc(sizeof(czar_string));
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
static inline czar_string* czar_string_join_array(czar_string** strings, int32_t count) {
    if (count == 0) {
        czar_string* result = (czar_string*)malloc(sizeof(czar_string));
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
    
    czar_string* result = (czar_string*)malloc(sizeof(czar_string));
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
static inline czar_string* czar_string_ltrim(czar_string* s) {
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
static inline czar_string* czar_string_rtrim(czar_string* s) {
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
static inline czar_string* czar_string_trim(czar_string* s) {
    czar_string_ltrim(s);
    czar_string_rtrim(s);
    return s;
}
// String helper function: split string by delimiter
// Returns a dynamically allocated array of strings
// The count is stored in the out_count parameter
static inline czar_string** czar_string_split(czar_string* s, char delimiter, int32_t* out_count) {
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
    czar_string** parts = (czar_string**)malloc(sizeof(czar_string*) * count);
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
            
            parts[part_idx] = (czar_string*)malloc(sizeof(czar_string));
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

// Raw C implementation from cz_print.c
// cz_print.c - Print functions for Czar language
// This file contains print, println, and printf implementations
// Generated code will include this file to provide printing functionality.
#include <stdio.h>
#include <stdarg.h>
// Print with format string and variadic arguments, without newline
// Usage: cz_print("Hello %s", "World")
static inline void cz_print(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}
// Print with format string and variadic arguments, with newline
// Usage: cz_println("Hello %s", "World")
static inline void cz_println(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}
// Printf with format string and variadic arguments
// Usage: cz_printf("Value: %d", 42)
static inline void cz_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

// Forward declarations
int32_t main_main();

int32_t main_main()
{
    const int64_t n = ((int64_t)((((((9 * 9) * 9) * 9) * 9) * 9) * 9));
    int32_t i = 3;
    int32_t t1 = 0;
    int32_t t2 = 1;
    int32_t nextTerm = (t1 + t2);
    printf("Fibonacci Series: %d, %d, ", (void*[]){t1, t2}, 2);
    while ((i <= n)) {
        printf("%dm ", (void*[]){nextTerm}, 1);
        (t1 = t2);
        (t2 = nextTerm);
        (nextTerm = (t1 + t2));
        i++;
    _loop_continue_1: ;
    }
    _loop_break_1: ;
    return 0;
}

int main(void) { return main_main(); }
