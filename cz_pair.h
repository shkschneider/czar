#ifndef CZ_PAIR_H
#define CZ_PAIR_H

#include <stdlib.h>

typedef struct pair_s {
    void* key;
    void* value;
} Pair;

Pair* pair_new() { // alloc
    Pair* p = malloc(sizeof(Pair));
    p->key = NULL;
    p->value = NULL;
    return p;
}

void pair_clear(Pair* pair) {
    assert(pair);
    Pair* p = pair;
    while (p != NULL) {
        TODO();
    }
}

#endif
