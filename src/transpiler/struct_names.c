/*
 * CZar - C semantic authority layer
 * Struct names tracking implementation (transpiler/struct_names.c)
 *
 * Tracks defined struct names for transformation.
 */

#include "struct_names.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct StructName {
    char *base_name;      /* e.g., "Point" */
    char *typedef_name;   /* e.g., "Point_t" */
    struct StructName *next;
} StructName;

static StructName *registry = NULL;

void struct_names_add(const char *name) {
    if (!name) return;
    
    /* Check if already registered */
    for (StructName *s = registry; s; s = s->next) {
        if (strcmp(s->base_name, name) == 0) {
            return;
        }
    }
    
    StructName *entry = malloc(sizeof(StructName));
    if (!entry) return;
    
    entry->base_name = strdup(name);
    if (!entry->base_name) {
        free(entry);
        return;
    }
    
    /* Create typedef name: Name_t */
    size_t len = strlen(name);
    entry->typedef_name = malloc(len + 3);
    if (!entry->typedef_name) {
        free(entry->base_name);
        free(entry);
        return;
    }
    snprintf(entry->typedef_name, len + 3, "%s_t", name);
    
    entry->next = registry;
    registry = entry;
}

const char *struct_names_get_typedef(const char *name) {
    if (!name) return NULL;
    
    for (StructName *s = registry; s; s = s->next) {
        if (strcmp(s->base_name, name) == 0) {
            return s->typedef_name;
        }
    }
    
    return NULL;
}

void struct_names_clear(void) {
    while (registry) {
        StructName *next = registry->next;
        free(registry->base_name);
        free(registry->typedef_name);
        free(registry);
        registry = next;
    }
}
