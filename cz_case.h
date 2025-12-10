#ifndef CZ_CASE_H
#define CZ_CASE_H

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "cz_standard.h"
#include "cz_memory.h"
#include "cz_string.h"

// UPPER CASE
string case_upper(string s) {
    for (string p = s; *p; p++) {
        *p = toupper(*p);
    }
    return s;
}

// lower case
string case_lower(string s) {
    for (string p = s; *p; p++) {
        *p = tolower(*p);
    }
    return s;
}

// Title case
string case_title(string s) {
    s = case_lower(s);
    *s = toupper(*s);
    return s;
}

// PascalCase
string case_pascal(string s) { // alloc
    string d = strdup(s);
    string* strings = strdiv(s, " _.-");
    unsigned int p = 0;
    for (unsigned int i = 0; strings[i]; i++) {
        strcpy(&d[p], case_title(strings[i]));
        p += strlen(strings[i]);
    }
    free2(strings);
    return d;
}

// camelCase
string case_camel(string s) { // alloc
    string d = case_pascal(s);
    *d = tolower(*d);
    return d;
}

// snake_case
string case_snake(string s) { // alloc
    string d = strdup(s);
    string* strings = strdiv(s, " _.-");
    unsigned int n;
    for (n = 0; strings[n]; n++) ;
    d = realloc(d, sizeof(char) * (strlen(d) + n) + 1);
    unsigned int p = 0;
    for (unsigned int i = 0; strings[i]; i++) {
        if (i > 0) {
            d[p] = '_';
            p++;
        }
        strcpy(&d[p], case_lower(strings[i]));
        p += strlen(strings[i]);
    }
    d[p] = '\0';
    free2(strings);
    return d;
}

#endif
