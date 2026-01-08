/*
 * CZar - C semantic authority layer
 * Transpiler header (transpiler.h)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#pragma once

#include "parser.h"
#include "transpiler/pragma.h"
#include "transpiler/imports.h"
#include <stdio.h>

/* Transpiler structure */
typedef struct {
    ASTNode *ast;
    const char *filename;
    const char *source;
    PragmaContext pragma_ctx;  /* Pragma settings */
    ModuleContext module_ctx;  /* Module/import context */
} Transpiler;

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast, const char *filename, const char *source);

/* Transform AST (apply CZar-specific transformations) */
void transpiler_transform(Transpiler *transpiler);

/* Emit transformed AST as C code to output file */
void transpiler_emit(Transpiler *transpiler, FILE *output);

