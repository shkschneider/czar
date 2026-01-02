/*
 * CZar - C semantic authority layer
 * Transpiler header (transpiler.h)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#ifndef TRANSPILER_H
#define TRANSPILER_H

#include "parser.h"
#include <stdio.h>

/* Transpiler structure */
typedef struct {
    ASTNode *ast;
    const char *filename;
    const char *source;
} Transpiler;

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast, const char *filename, const char *source);

/* Transform AST (apply CZar-specific transformations) */
void transpiler_transform(Transpiler *transpiler);

/* Emit transformed AST as C code to output file */
void transpiler_emit(Transpiler *transpiler, FILE *output);

#endif /* TRANSPILER_H */
