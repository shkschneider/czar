#ifndef CZ_STRING_H_
#define CZ_STRING_H_

// https://github.com/tsoding/skedudle/blob/master/src/s.h
// https://github.com/antirez/sds/

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

typedef char* string;

static inline string string_of(const char *cstr) {
    char *s = malloc(sizeof(char) * strlen(cstr));
    memcpy(s, cstr, strlen(cstr));
    return s;
}

static inline bool string_is_empty(string str) {
    return strlen(str) == 0;
}

static inline int string_equal(string a, string b) {
    if (strlen(a) != strlen(b)) {
        return 0;
    }
    return memcmp(a, b, strlen(a)) == 0;
}


static inline bool string_has_prefix(string str, string prefix) {
    return strncmp(prefix, str, strlen(prefix)) == 0;
}

static inline bool string_has_suffix(string str, string suffix) {
    size_t l1 = strlen(str);
    size_t l2 = strlen(suffix);
    return (l1 >= l2) && (!memcmp(str + l1 - l2, suffix, l2));
}

#endif
