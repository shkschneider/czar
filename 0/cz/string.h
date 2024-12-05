#ifndef CZ_STRING_H_
#define CZ_STRING_H_

// https://github.com/tsoding/skedudle/blob/master/src/s.h
// https://github.com/antirez/sds/

#include <string.h>

typedef char* string;

static inline bool streq(string a, string b) {
    if (a == NULL && b == NULL) return true;
    if (a == NULL || b == NULL) return false;
    return strlen(a) == strlen(b) && memcmp(a, b, strlen(a)) == 0;
}

static inline bool strsmth(string s) {
    return s != NULL && strlen(s) > 0;
}

static inline bool strpre(string s, string pre) {
    if (s == NULL && pre != NULL) return false;
    if (s != NULL && pre == NULL) return true;
    return strncmp(pre, s, strlen(pre)) == 0;
}

static inline bool strsuf(string s, string suf) {
    if (s == NULL && suf != NULL) return false;
    if (s != NULL && suf == NULL) return true;
    size_t l1 = strlen(s);
    size_t l2 = strlen(suf);
    return (l1 >= l2) && (!memcmp(s + l1 - l2, suf, l2));
}

#endif
