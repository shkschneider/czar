/*
 * CZar - C semantic authority layer
 * Import/Module header (imports.h)
 *
 * Handles #import directives and module system.
 */

#pragma once

#include "../parser.h"
#include <stdio.h>

/* Import directive information */
typedef struct {
    char *module_path;     /* Module path from #import "path" */
    int line;              /* Line number of #import */
} ImportDirective;

/* Module context for tracking imports and generating headers */
typedef struct {
    char *main_file_dir;            /* Directory of main file */
    ImportDirective **imports;       /* Array of import directives */
    size_t import_count;            /* Number of imports */
    size_t import_capacity;         /* Capacity of imports array */
} ModuleContext;

/* Initialize module context with main file path */
void module_context_init(ModuleContext *ctx, const char *main_file_path);

/* Free module context */
void module_context_free(ModuleContext *ctx);

/* Extract #import directives from AST */
void transpiler_extract_imports(ASTNode *ast, ModuleContext *ctx);

/* Generate header file (.cz.h) for a .cz file */
int transpiler_generate_header(const char *cz_file_path, const char *output_header_path);

/* Transform #import directives to #include directives in AST */
void transpiler_transform_imports(ASTNode *ast, ModuleContext *ctx);
