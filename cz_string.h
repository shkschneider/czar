#ifndef CZ_STRING_H
#define CZ_STRING_H

// https://github.com/tsoding/skedudle/blob/master/src/s.h
// https://github.com/antirez/sds/

#include <ctype.h>
#include <errno.h>
#include <string.h>

typedef char* string;

static inline string str(const char* str) { // alloc
    return strdup(str);
}

static inline bool streq(string s1, string s2) {
    if (s1 == NULL && s2 == NULL) return true;
    if (s1 == NULL || s2 == NULL) return false;
    return strlen(s1) == strlen(s2) && memcmp(s1, s2, strlen(s1)) == 0;
}

static inline bool strsmth(string s) {
    return s != NULL && strlen(s) > 0;
}

static inline bool strpre(string s, string pre) {
    if (s == NULL && pre == NULL) return true;
    if (s == NULL && pre != NULL) return false;
    if (s != NULL && pre == NULL) return true;
    return strncmp(pre, s, strlen(pre)) == 0;
}

static inline bool strsuf(string s, string suf) {
    if (s == NULL && suf == NULL) return true;
    if (s == NULL && suf != NULL) return false;
    if (s != NULL && suf == NULL) return true;
    size_t l1 = strlen(s);
    size_t l2 = strlen(suf);
    return (l1 >= l2) && (!memcmp(s + l1 - l2, suf, l2));
}

// https://stackoverflow.com/a/123724
static inline string strtrmc(string s) { // alloc
    int l = strlen(s);
    while (isspace(s[l - 1])) --l;
    while (*s && isspace(*s)) ++s, --l;
    return strndup(s, l);
}

string* strdiv(string s, string c) { // alloc
    string* strings = malloc(sizeof(string) * strlen(s));
    string d = strdup(s);
    string p = strtok(d, c);
    unsigned int i;
    for (i = 0; p != NULL; i++) {
        strings[i] = strdup(p);
        p = strtok(NULL, c);
    }
    strings[i] = NULL;
    free(d);
    return strings;
}

string strrpl(string s, unsigned char from, unsigned char to) {
    for (unsigned int i = 0; i < strlen(s); i++) {
        if (s[i] == from) {
            s[i] = to;
        }
    }
    return s;
}

string strdrp(string s, unsigned char c) { // alloc
    string d = strdup(s);
    string result = d;
    // Remove leading instances of c
    while (*d == c && *d != '\0') {
        d++;
    }
    // Shift the string to the beginning
    if (d != result) {
        memmove(result, d, strlen(d) + 1);
    }
    // Remove all other instances of c
    size_t write_pos = 0;
    for (size_t read_pos = 0; result[read_pos] != '\0'; read_pos++) {
        if (result[read_pos] != c) {
            result[write_pos++] = result[read_pos];
        }
    }
    result[write_pos] = '\0';
    return result;
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
