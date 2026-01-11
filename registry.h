/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Provides a standardized interface for CZar transpiler features.
 * Each feature can provide validation and/or transformation functions.
 */

#pragma once

#include "parser.h"
#include <stdio.h>
#include <stdbool.h>

/* Forward declaration - removed to avoid C99 typedef redefinition error */
/* The full Transpiler_t definition is in transpiler.h */

/* Feature phase - determines when the feature runs */
typedef enum {
    FEATURE_PHASE_VALIDATE,      /* Validation phase - check AST for errors */
    FEATURE_PHASE_TRANSFORM,     /* Transform phase - modify AST */
    FEATURE_PHASE_EMIT,          /* Emit phase - output code */
} FeaturePhase;

/* Feature function signature for validation */
typedef void (*FeatureValidateFunc)(ASTNode_t *ast, const char *filename, const char *source);

/* Feature function signature for transformation */
typedef void (*FeatureTransformFunc)(ASTNode_t *ast, const char *filename, const char *source);

/* Feature function signature for emission */
typedef void (*FeatureEmitFunc)(FILE *output);

/* Feature descriptor - describes a CZar feature */
typedef struct {
    const char *name;                    /* Feature name (e.g., "mutability", "enums") */
    const char *description;             /* Short description of the feature */
    bool enabled;                        /* Whether this feature is enabled */

    /* Validation function (optional) */
    FeatureValidateFunc validate;

    /* Transformation function (optional) */
    FeatureTransformFunc transform;

    /* Emission function (optional) */
    FeatureEmitFunc emit;

    /* Dependencies - NULL-terminated array of feature names that must run before this one */
    const char **dependencies;
} Feature;

/* Feature registry - manages all features */
typedef struct {
    Feature **features;      /* Array of feature pointers */
    size_t count;            /* Number of registered features */
    size_t capacity;         /* Capacity of features array */
} FeatureRegistry;

/* Initialize the feature registry */
void feature_registry_init(FeatureRegistry *registry);

/* Register a feature with the registry */
void feature_registry_register(FeatureRegistry *registry, Feature *feature);

/* Get a feature by name */
Feature *feature_registry_get(FeatureRegistry *registry, const char *name);

/* Enable or disable a feature */
void feature_registry_set_enabled(FeatureRegistry *registry, const char *name, bool enabled);

/* Execute all enabled features in the validation phase */
void feature_registry_validate(FeatureRegistry *registry, ASTNode_t *ast, const char *filename, const char *source);

/* Execute all enabled features in the transformation phase */
void feature_registry_transform(FeatureRegistry *registry, ASTNode_t *ast, const char *filename, const char *source);

/* Execute all enabled features in the emission phase */
void feature_registry_emit(FeatureRegistry *registry, FILE *output);

/* Free the feature registry */
void feature_registry_free(FeatureRegistry *registry);
