/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Registers all CZar transpiler features with the registry.
 */

#include "features.h"
#include "src/deprecated.h"
#include "src/validation.h"
#include "src/casts.h"
#include "src/enums.h"
#include "src/functions.h"
#include "src/structs.h"
#include "src/methods.h"
#include "src/autodereference.h"
#include "src/unreachable.h"
#include "src/todo.h"
#include "src/fixme.h"
#include "src/arguments.h"
#include "src/mutability.h"
#include "src/defer.h"
#include "src/types.h"
#include "src/constants.h"
#include "src/unused.h"

/* Wrapper functions to adapt existing functions to feature interface */

/* Validation wrappers */
static void validate_general(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_validate(ast, filename, source);
}

static void validate_casts(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_validate_casts(ast, filename, source);
}

static void validate_enums(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_validate_enums(ast, filename, source);
}

static void validate_functions(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_validate_functions(ast, filename, source);
}

/* Transform wrappers */
static void transform_deprecated(ASTNode_t *ast, const char *filename, const char *source) {
    (void)filename;
    (void)source;
    transpiler_transform_deprecated(ast);
}

static void transform_functions(ASTNode_t *ast, const char *filename, const char *source) {
    (void)filename;
    (void)source;
    transpiler_transform_functions(ast);
    transpiler_add_warn_unused_result(ast);
    transpiler_add_pure(ast);
}

static void transform_structs(ASTNode_t *ast, const char *filename, const char *source) {
    (void)filename;
    (void)source;
    transpiler_transform_structs(ast);
    transpiler_transform_struct_init(ast);
}

static void transform_methods(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_transform_methods(ast, filename, source);
}

static void transform_struct_names(ASTNode_t *ast, const char *filename, const char *source) {
    (void)source;
    transpiler_replace_struct_names(ast, filename);
}

static void transform_autodereference(ASTNode_t *ast, const char *filename, const char *source) {
    (void)filename;
    (void)source;
    transpiler_transform_autodereference(ast);
}

static void transform_enums(ASTNode_t *ast, const char *filename, const char *source) {
    (void)source;
    transpiler_transform_enums(ast, filename);
}

static void transform_unreachable(ASTNode_t *ast, const char *filename, const char *source) {
    (void)source;
    transpiler_expand_unreachable(ast, filename);
}

static void transform_todo(ASTNode_t *ast, const char *filename, const char *source) {
    (void)source;
    transpiler_expand_todo(ast, filename);
}

static void transform_fixme(ASTNode_t *ast, const char *filename, const char *source) {
    (void)source;
    transpiler_expand_fixme(ast, filename);
}

static void transform_arguments(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_transform_named_arguments(ast, filename, source);
}

static void transform_mutability(ASTNode_t *ast, const char *filename, const char *source) {
    transpiler_transform_mutability(ast, filename, source);
}

static void transform_defer(ASTNode_t *ast, const char *filename, const char *source) {
    (void)filename;
    (void)source;
    transpiler_transform_defer(ast);
}

static void transform_types_and_constants(ASTNode_t *ast, const char *filename, const char *source) {
    (void)ast;
    (void)filename;
    (void)source;
    /* This is handled by transform_node in transpiler.c */
    /* Types and constants are transformed inline */
}

/* Emit wrappers */
static void emit_defer_functions(FILE *output) {
    transpiler_emit_defer_functions(output);
}

/* Feature definitions */

static Feature feature_deprecated = {
    .name = "deprecated",
    .description = "Transform #deprecated directives to __attribute__((deprecated))",
    .enabled = true,
    .validate = NULL,
    .transform = transform_deprecated,
    .emit = NULL,
    .dependencies = NULL
};

static Feature feature_validation = {
    .name = "validation",
    .description = "Validate AST for CZar semantic rules",
    .enabled = true,
    .validate = validate_general,
    .transform = NULL,
    .emit = NULL,
    .dependencies = NULL
};

static const char *casts_deps[] = { "types_constants", NULL };
static Feature feature_casts = {
    .name = "casts",
    .description = "Validate and transform cast expressions",
    .enabled = true,
    .validate = validate_casts,
    .transform = NULL,  /* Transform is called separately after types_constants */
    .emit = NULL,
    .dependencies = casts_deps
};

static const char *enum_deps[] = { NULL };
static Feature feature_enums = {
    .name = "enums",
    .description = "Validate enum declarations and switch exhaustiveness",
    .enabled = true,
    .validate = validate_enums,
    .transform = transform_enums,
    .emit = NULL,
    .dependencies = enum_deps
};

static Feature feature_functions = {
    .name = "functions",
    .description = "Validate and transform function declarations",
    .enabled = true,
    .validate = validate_functions,
    .transform = transform_functions,
    .emit = NULL,
    .dependencies = NULL
};

static Feature feature_structs = {
    .name = "structs",
    .description = "Transform named structs to typedef structs",
    .enabled = true,
    .validate = NULL,
    .transform = transform_structs,
    .emit = NULL,
    .dependencies = NULL
};

static const char *methods_deps[] = { "structs", NULL };
static Feature feature_methods = {
    .name = "methods",
    .description = "Transform struct methods",
    .enabled = true,
    .validate = NULL,
    .transform = transform_methods,
    .emit = NULL,
    .dependencies = methods_deps
};

static const char *struct_names_deps[] = { "methods", NULL };
static Feature feature_struct_names = {
    .name = "struct_names",
    .description = "Replace struct names with _t variants",
    .enabled = true,
    .validate = NULL,
    .transform = transform_struct_names,
    .emit = NULL,
    .dependencies = struct_names_deps
};

static const char *autodereference_deps[] = { "struct_names", NULL };
static Feature feature_autodereference = {
    .name = "autodereference",
    .description = "Transform member access operators (. to -> for pointers)",
    .enabled = true,
    .validate = NULL,
    .transform = transform_autodereference,
    .emit = NULL,
    .dependencies = autodereference_deps
};

static Feature feature_unreachable = {
    .name = "unreachable",
    .description = "Expand unreachable() runtime function calls",
    .enabled = true,
    .validate = NULL,
    .transform = transform_unreachable,
    .emit = NULL,
    .dependencies = NULL
};

static Feature feature_todo = {
    .name = "todo",
    .description = "Expand todo() runtime function calls",
    .enabled = true,
    .validate = NULL,
    .transform = transform_todo,
    .emit = NULL,
    .dependencies = NULL
};

static Feature feature_fixme = {
    .name = "fixme",
    .description = "Expand fixme() runtime function calls",
    .enabled = true,
    .validate = NULL,
    .transform = transform_fixme,
    .emit = NULL,
    .dependencies = NULL
};

static Feature feature_arguments = {
    .name = "arguments",
    .description = "Transform named arguments (strip labels)",
    .enabled = true,
    .validate = NULL,
    .transform = transform_arguments,
    .emit = NULL,
    .dependencies = NULL
};

static const char *mutability_deps[] = { "arguments", NULL };
static Feature feature_mutability = {
    .name = "mutability",
    .description = "Transform mutability (mut keyword and const insertion)",
    .enabled = true,
    .validate = NULL,
    .transform = transform_mutability,
    .emit = NULL,
    .dependencies = mutability_deps
};

static const char *defer_deps[] = { "mutability", NULL };
static Feature feature_defer = {
    .name = "defer",
    .description = "Transform defer statements to cleanup attribute pattern",
    .enabled = true,
    .validate = NULL,
    .transform = transform_defer,
    .emit = emit_defer_functions,
    .dependencies = defer_deps
};

static Feature feature_types_constants = {
    .name = "types_constants",
    .description = "Transform CZar types and constants to C types and constants",
    .enabled = true,
    .validate = NULL,
    .transform = transform_types_and_constants,
    .emit = NULL,
    .dependencies = NULL
};

/* Register all built-in features with the registry */
void register_all_features(FeatureRegistry *registry) {
    if (!registry) {
        return;
    }

    /* Register features in the order they should be executed */
    /* Validation phase features */
    feature_registry_register(registry, &feature_validation);
    feature_registry_register(registry, &feature_casts);
    feature_registry_register(registry, &feature_enums);
    feature_registry_register(registry, &feature_functions);

    /* Transform phase features (order matters!) */
    feature_registry_register(registry, &feature_deprecated);
    feature_registry_register(registry, &feature_structs);
    feature_registry_register(registry, &feature_methods);
    feature_registry_register(registry, &feature_struct_names);
    feature_registry_register(registry, &feature_autodereference);
    feature_registry_register(registry, &feature_unreachable);
    feature_registry_register(registry, &feature_todo);
    feature_registry_register(registry, &feature_fixme);
    feature_registry_register(registry, &feature_arguments);
    feature_registry_register(registry, &feature_mutability);
    feature_registry_register(registry, &feature_defer);
    feature_registry_register(registry, &feature_types_constants);

    /* Note: functions transform is registered but includes multiple operations */
    /* casts validation and transform are already registered */
    /* enums validation and transform are already registered */
}
