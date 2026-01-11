/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Implements the feature registry system for managing transpiler features.
 */

#include "registry.h"
#include <stdlib.h>
#include <string.h>

/* Initialize the feature registry */
void feature_registry_init(FeatureRegistry *registry) {
    registry->features = NULL;
    registry->count = 0;
    registry->capacity = 0;
}

/* Register a feature with the registry */
void feature_registry_register(FeatureRegistry *registry, Feature *feature) {
    if (!registry || !feature) {
        return;
    }

    /* Grow array if needed */
    if (registry->count >= registry->capacity) {
        size_t new_capacity = registry->capacity == 0 ? 8 : registry->capacity * 2;
        Feature **new_features = realloc(registry->features, new_capacity * sizeof(Feature *));
        if (!new_features) {
            return; /* Memory allocation failed */
        }
        registry->features = new_features;
        registry->capacity = new_capacity;
    }

    registry->features[registry->count++] = feature;
}

/* Get a feature by name */
Feature *feature_registry_get(FeatureRegistry *registry, const char *name) {
    if (!registry || !name) {
        return NULL;
    }

    for (size_t i = 0; i < registry->count; i++) {
        if (registry->features[i] && strcmp(registry->features[i]->name, name) == 0) {
            return registry->features[i];
        }
    }

    return NULL;
}

/* Enable or disable a feature */
void feature_registry_set_enabled(FeatureRegistry *registry, const char *name, bool enabled) {
    Feature *feature = feature_registry_get(registry, name);
    if (feature) {
        feature->enabled = enabled;
    }
}

/* Check if all dependencies are satisfied and run first */
static bool check_dependencies(FeatureRegistry *registry, Feature *feature, bool *visited, size_t feature_idx) {
    if (!feature->dependencies) {
        return true; /* No dependencies */
    }

    /* Check for circular dependencies */
    if (visited[feature_idx]) {
        return false; /* Circular dependency detected */
    }

    visited[feature_idx] = true;

    for (size_t i = 0; feature->dependencies[i] != NULL; i++) {
        Feature *dep = feature_registry_get(registry, feature->dependencies[i]);
        if (!dep) {
            return false; /* Dependency not found */
        }

        /* Find dependency index */
        size_t dep_idx = 0;
        for (dep_idx = 0; dep_idx < registry->count; dep_idx++) {
            if (registry->features[dep_idx] == dep) {
                break;
            }
        }

        if (dep_idx < registry->count) {
            if (!check_dependencies(registry, dep, visited, dep_idx)) {
                return false;
            }
        }
    }

    visited[feature_idx] = false;
    return true;
}

/* Execute all enabled features in the validation phase */
void feature_registry_validate(FeatureRegistry *registry, ASTNode_t *ast, const char *filename, const char *source) {
    if (!registry || !ast) {
        return;
    }

    bool *visited = calloc(registry->count, sizeof(bool));
    if (!visited) {
        return;
    }

    for (size_t i = 0; i < registry->count; i++) {
        Feature *feature = registry->features[i];
        if (feature && feature->enabled && feature->validate) {
            /* Check dependencies */
            if (check_dependencies(registry, feature, visited, i)) {
                feature->validate(ast, filename, source);
            }
        }
    }

    free(visited);
}

/* Execute all enabled features in the transformation phase */
void feature_registry_transform(FeatureRegistry *registry, ASTNode_t *ast, const char *filename, const char *source) {
    if (!registry || !ast) {
        return;
    }

    bool *visited = calloc(registry->count, sizeof(bool));
    if (!visited) {
        return;
    }

    for (size_t i = 0; i < registry->count; i++) {
        Feature *feature = registry->features[i];
        if (feature && feature->enabled && feature->transform) {
            /* Check dependencies */
            if (check_dependencies(registry, feature, visited, i)) {
                feature->transform(ast, filename, source);
            }
        }
    }

    free(visited);
}

/* Execute all enabled features in the emission phase */
void feature_registry_emit(FeatureRegistry *registry, FILE *output) {
    if (!registry || !output) {
        return;
    }

    for (size_t i = 0; i < registry->count; i++) {
        Feature *feature = registry->features[i];
        if (feature && feature->enabled && feature->emit) {
            feature->emit(output);
        }
    }
}

/* Free the feature registry */
void feature_registry_free(FeatureRegistry *registry) {
    if (!registry) {
        return;
    }

    free(registry->features);
    registry->features = NULL;
    registry->count = 0;
    registry->capacity = 0;
}
