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

#define _FILE_ strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__
#define _LINE_ __LINE__
#define _FUNC_ __func__

#endif
