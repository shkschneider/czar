#ifndef CZ_MISC_H
#define CZ_MISC_H

#define UNUSED(x) ((void)x)

static inline void NOTHING(void) {}

#include <stdio.h>
#include <stdlib.h>
static inline void TODO() {
    fprintf(stderr, "NOT IMPLEMENTED!\n");
    abort();
}

// __FILE__
// __LINE__
#ifndef __FUNC__
#define __FUNC__ __func__
#endif

#endif
