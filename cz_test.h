#ifndef CZ_TEST_H
#define CZ_TEST_H

#include <assert.h>
#include <stdio.h>
#include <string.h>

#define CZ_TEST_SPRINTF(buffer, any) \
    sprintf(buffer, _Generic((any), \
                          char: "%c", \
                   signed char: "%hhd", \
                 unsigned char: "%hhu", \
                  signed short: "%hd", \
                unsigned short: "%hu", \
                    signed int: "%d", \
                  unsigned int: "%u", \
                      long int: "%ld", \
             unsigned long int: "%lu", \
                 long long int: "%lld", \
        unsigned long long int: "%llu", \
                         _Bool: "%d", \
                         float: "%g", \
                        double: "%g", \
                   long double: "%Lg", \
               _Complex double: "%g + %gi", \
                        char *: "%s", \
                        void *: "%p", \
             char[sizeof(any)]: "%s", \
                       default: "<unknown>" \
    ), any);

char cz_test_str1[512];
char cz_test_str2[512];

#define TEST(expected, actual) \
    CZ_TEST_SPRINTF(cz_test_str1, expected); \
    CZ_TEST_SPRINTF(cz_test_str2, actual); \
    if (strcmp(cz_test_str1, cz_test_str2) != 0) { \
        fprintf(stderr, "%s:%d %s != %s\n", __FILE__, __LINE__, cz_test_str1, cz_test_str2); \
        fprintf(stderr, "\texpected @ %p: %s\n", (void *)expected, cz_test_str1); \
        fprintf(stderr, "\tactual   @ %p: %s\n", (void *)actual, cz_test_str2); \
        abort(); \
    }


#define ASSERT(result, message) \
    static_assert(result, message);

#endif
