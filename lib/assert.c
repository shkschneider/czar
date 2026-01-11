/*
 * CZar Runtime Library
 * Assert implementation
 */

#include "cz.h"
#include <stdio.h>
#include <stdlib.h>

void cz_assert_fail(const char *condition, const char *file, int line) {
    fprintf(stderr, "[CZAR] ASSERTION failed at %s:%d: %s\n", file, line, condition);
    abort();
}
