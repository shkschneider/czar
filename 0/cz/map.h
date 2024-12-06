#ifndef CZ_MAP_H
#define CZ_MAP_H

#include <stdlib.h>
#include <stdint.h>
#include "cz/array.h"

typedef struct map_s {
    void* key;
    void* value;
    struct map_s* next;
} Map;

Map* map_new() { // alloc
    Map* m = malloc(sizeof(Map));
    m->key = NULL;
    m->value = NULL;
    m->next = NULL;
    return m;
}

void map_put(Map* map, void* key, void* value) { // alloc
    assert(map);
    if (map->key == NULL) {
        map->key = key;
        map->value = value;
        return;
    }
    Map* m = map;
    while (m->next != NULL) {
        m = m->next;
    }
    Map* e = malloc(sizeof(Map));
    e->key = key;
    e->value = value;
    e->next = NULL;
    m->next = e;
}

void* map_get(Map* map, void* key) {
    assert(map);
    Map* m = map;
    while (m != NULL) {
        if (m->key == key) {
            return m->value;
        }
        m = m->next;
    }
    return NULL;
}

void map_delete(Map* map, void* key) {
    assert(map);
    Map* m = map;
    Map* p = NULL;
    while (m != NULL) {
        if (m->key == key) {
            if (p != NULL) {
                p->next = m->next;
            }
            free(m);
        }
        p = m;
        m = m->next;
    }
}

void map_clear(Map* map) {
    assert(map);
    Map* m = map;
    while (m != NULL) {
        TODO();
        m = m->next;
    }
}

void map_keys(Map* map) {
    assert(map);
    TODO();
}

void map_values(Map* map) {
    assert(map);
    TODO();
}

size_t map_size(Map* map) {
    assert(map);
    size_t i = 0;
    for (Map *m = map; m != NULL; m = m->next) {
        i++;
    }
    return i;
}

#define map_foreach(map, entry) \
    for (entry = map; entry != NULL; entry = entry->next)

#endif
