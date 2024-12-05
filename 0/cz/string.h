#ifndef CZ_STRING_H_
#define CZ_STRING_H_

// https://github.com/tsoding/skedudle/blob/master/src/s.h
// https://github.com/antirez/sds/

#include <errno.h>
#include <string.h>

typedef char* string;

static inline bool streq(string s1, string s2) {
    if (s1 == NULL && s2 == NULL) return true;
    if (s1 == NULL || s2 == NULL) return false;
    return strlen(s1) == strlen(s2) && memcmp(s1, s2, strlen(s1)) == 0;
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

// https://stackoverflow.com/a/123724
static inline string strtrmc(string s) {
    int l = strlen(s);
    while (isspace(s[l - 1])) --l;
    while (*s && isspace(*s)) ++s, --l;
    return strndup(s, l);
}

static inline string strerr() {
    return strerror(errno);
}

// https://stackoverflow.com/a/24460085
#define printb(x) \
    do { \
        for (int i = sizeof(x) * 8 - 1; i >= 0; i--) { \
            putchar((x & (1 << i)) ? '1' : '0'); \
        } \
        putchar('\n'); \
    } while (0)

#endif
