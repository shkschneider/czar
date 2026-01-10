# CZar Feature Registry System

The CZar transpiler uses a modular feature registry system that allows features to be easily managed, enabled/disabled, and ordered.

## Architecture

### Feature Interface (`src/feature.h`)

Each CZar feature can provide three types of functions:
- **Validation**: Check AST for semantic errors
- **Transformation**: Modify the AST
- **Emission**: Output additional code (e.g., helper functions)

### Feature Descriptor

```c
typedef struct {
    const char *name;                    /* Feature name */
    const char *description;             /* Short description */
    bool enabled;                        /* Whether feature is enabled */
    FeatureValidateFunc validate;        /* Validation function (optional) */
    FeatureTransformFunc transform;      /* Transformation function (optional) */
    FeatureEmitFunc emit;                /* Emission function (optional) */
    const char **dependencies;           /* Dependencies (NULL-terminated) */
} Feature;
```

## Registered Features

### Validation Phase
1. **validation** - General AST validation
2. **casts** - Cast expression validation
3. **enums** - Enum and switch exhaustiveness validation
4. **functions** - Function declaration validation

### Transformation Phase (in execution order)
1. **deprecated** - Transform `#deprecated` directives
2. **functions** - Transform function declarations
3. **structs** - Transform named structs to typedef structs
4. **methods** - Transform struct methods
5. **struct_names** - Replace struct names with `_t` variants
6. **autodereference** - Transform `.` to `->` for pointers
7. **enums** - Transform enum switch statements
8. **unreachable** - Expand `unreachable()` calls
9. **todo** - Expand `todo()` calls
10. **fixme** - Expand `fixme()` calls
11. **arguments** - Transform named arguments
12. **mutability** - Transform `mut` keyword and add `const`
13. **defer** - Transform `defer` statements
14. **types_constants** - Transform CZar types and constants

### Emission Phase
1. **defer** - Emit defer cleanup functions

## Adding a New Feature

To add a new feature:

1. **Create the feature module** in `src/`:
   ```c
   // src/myfeature.h
   void transpiler_transform_myfeature(ASTNode *ast, const char *filename, const char *source);
   ```

2. **Add wrapper function** in `src/features.c`:
   ```c
   static void transform_myfeature(ASTNode *ast, const char *filename, const char *source) {
       transpiler_transform_myfeature(ast, filename, source);
   }
   ```

3. **Define the feature descriptor**:
   ```c
   static const char *myfeature_deps[] = { "some_dependency", NULL };
   static Feature feature_myfeature = {
       .name = "myfeature",
       .description = "Transform my feature",
       .enabled = true,
       .validate = NULL,
       .transform = transform_myfeature,
       .emit = NULL,
       .dependencies = myfeature_deps
   };
   ```

4. **Register the feature** in `register_all_features()`:
   ```c
   feature_registry_register(registry, &feature_myfeature);
   ```

## Enabling/Disabling Features

Features can be enabled or disabled programmatically:

```c
Transpiler transpiler;
transpiler_init(&transpiler, ast, filename, source);

// Disable a feature
feature_registry_set_enabled(&transpiler.registry, "defer", false);

// Transform without the disabled feature
transpiler_transform(&transpiler);
```

## Feature Dependencies

Features can declare dependencies on other features. The registry ensures dependencies are satisfied before execution. For example:

- `methods` depends on `structs`
- `struct_names` depends on `methods`
- `autodereference` depends on `struct_names`
- `mutability` depends on `arguments`
- `defer` depends on `mutability`

## Benefits

1. **Modularity**: Each feature is self-contained in its own module
2. **Flexibility**: Features can be easily enabled/disabled
3. **Maintainability**: Clear separation of concerns
4. **Extensibility**: New features can be added without modifying core transpiler logic
5. **Order Management**: Dependencies ensure correct execution order
6. **Testability**: Features can be tested in isolation

## Implementation Details

The feature registry:
- Stores features in the order they are registered
- Validates and transforms by iterating through enabled features
- Checks dependencies before executing each feature
- Detects circular dependencies
- Provides a clean API for feature management
