// string.c - String type C implementation
// Part of the Czar standard library

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

// Note: string struct is defined in the generated code, not here

// Append a C string to this string
void _cz_string_append_cstr(string* self, const int8_t* cstr, int32_t len) {
    if (!self || !cstr || len <= 0) return;
    
    int32_t new_len = self->length + len;
    
    // Resize if needed
    if (new_len + 1 > self->capacity) {
        int32_t new_capacity = self->capacity;
        while (new_capacity < new_len + 1) {
            new_capacity *= 2;
        }
        int8_t* new_data = (int8_t*)realloc(self->data, new_capacity);
        if (!new_data) {
            return; // Out of memory
        }
        self->data = new_data;
        self->capacity = new_capacity;
    }
    
    // Append the data
    memcpy(self->data + self->length, cstr, len);
    self->length = new_len;
    self->data[self->length] = '\0';
}

// Append another string to this string
void _cz_string_append_string(string* self, const string* other) {
    if (!self || !other) return;
    _cz_string_append_cstr(self, other->data, other->length);
}

// Concatenate two strings into a new string (static method)
string* _cz_string_concat_static(const string* s1, const string* s2) {
    if (!s1 || !s2) return NULL;
    
    int32_t new_len = s1->length + s2->length;
    int32_t new_capacity = 16;
    while (new_capacity < new_len + 1) {
        new_capacity *= 2;
    }
    
    string* result = (string*)malloc(sizeof(string));
    if (!result) return NULL;
    
    result->data = (int8_t*)malloc(new_capacity);
    if (!result->data) {
        free(result);
        return NULL;
    }
    
    result->capacity = new_capacity;
    result->length = new_len;
    
    memcpy(result->data, s1->data, s1->length);
    memcpy(result->data + s1->length, s2->data, s2->length);
    result->data[result->length] = '\0';
    
    return result;
}

// Copy a C string into this string
void _cz_string_copy(string* self, const int8_t* cstr, int32_t len) {
    if (!self || !cstr) return;
    
    // Resize if needed
    if (len + 1 > self->capacity) {
        int32_t new_capacity = 16;
        while (new_capacity < len + 1) {
            new_capacity *= 2;
        }
        int8_t* new_data = (int8_t*)realloc(self->data, new_capacity);
        if (!new_data) return;
        self->data = new_data;
        self->capacity = new_capacity;
    }
    
    memcpy(self->data, cstr, len);
    self->length = len;
    self->data[self->length] = '\0';
}

// Extract a substring (byte range)
string* _cz_string_substring(const string* self, int32_t start, int32_t end) {
    if (!self || start < 0 || end < start || end > self->length) return NULL;
    
    int32_t len = end - start;
    int32_t capacity = 16;
    while (capacity < len + 1) {
        capacity *= 2;
    }
    
    string* result = (string*)malloc(sizeof(string));
    if (!result) return NULL;
    
    result->data = (int8_t*)malloc(capacity);
    if (!result->data) {
        free(result);
        return NULL;
    }
    
    result->capacity = capacity;
    result->length = len;
    memcpy(result->data, self->data + start, len);
    result->data[len] = '\0';
    
    return result;
}

// Find index of substring (returns byte offset)
int32_t _cz_string_find(const string* self, const string* needle) {
    if (!self || !needle || needle->length == 0) return -1;
    if (needle->length > self->length) return -1;
    
    for (int32_t i = 0; i <= self->length - needle->length; i++) {
        if (memcmp(self->data + i, needle->data, needle->length) == 0) {
            return i;
        }
    }
    
    return -1;
}

// Alias for find()
int32_t _cz_string_index(const string* self, const string* needle) {
    return _cz_string_find(self, needle);
}

// Check if string contains substring
int32_t _cz_string_contains(const string* self, const string* needle) {
    return _cz_string_find(self, needle) != -1 ? 1 : 0;
}

// Convert to uppercase (ASCII only)
string* _cz_string_upper(const string* self) {
    if (!self) return NULL;
    
    string* result = (string*)malloc(sizeof(string));
    if (!result) return NULL;
    
    result->data = (int8_t*)malloc(self->capacity);
    if (!result->data) {
        free(result);
        return NULL;
    }
    
    result->capacity = self->capacity;
    result->length = self->length;
    
    for (int32_t i = 0; i < self->length; i++) {
        result->data[i] = (int8_t)toupper((unsigned char)self->data[i]);
    }
    result->data[result->length] = '\0';
    
    return result;
}

// Convert to lowercase (ASCII only)
string* _cz_string_lower(const string* self) {
    if (!self) return NULL;
    
    string* result = (string*)malloc(sizeof(string));
    if (!result) return NULL;
    
    result->data = (int8_t*)malloc(self->capacity);
    if (!result->data) {
        free(result);
        return NULL;
    }
    
    result->capacity = self->capacity;
    result->length = self->length;
    
    for (int32_t i = 0; i < self->length; i++) {
        result->data[i] = (int8_t)tolower((unsigned char)self->data[i]);
    }
    result->data[result->length] = '\0';
    
    return result;
}

// Split string by separator (returns first part)
string* _cz_string_cut(const string* self, const string* separator) {
    if (!self || !separator) return NULL;
    
    int32_t pos = _cz_string_find(self, separator);
    if (pos == -1) {
        // Separator not found, return full string
        return _cz_string_substring(self, 0, self->length);
    }
    
    return _cz_string_substring(self, 0, pos);
}

// Check if string starts with prefix
int32_t _cz_string_prefix(const string* self, const string* prefix) {
    if (!self || !prefix) return 0;
    if (prefix->length > self->length) return 0;
    
    return memcmp(self->data, prefix->data, prefix->length) == 0 ? 1 : 0;
}

// Check if string ends with suffix
int32_t _cz_string_suffix(const string* self, const string* suffix) {
    if (!self || !suffix) return 0;
    if (suffix->length > self->length) return 0;
    
    int32_t offset = self->length - suffix->length;
    return memcmp(self->data + offset, suffix->data, suffix->length) == 0 ? 1 : 0;
}
