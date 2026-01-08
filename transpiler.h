/*
 * CZar - C semantic authority layer
 * Transpiler header (transpiler.h)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#pragma once

#include "parser.h"
#include "src/pragma.h"
#include <stdio.h>

/* Transpiler structure */
typedef struct {
    ASTNode *ast;
    const char *filename;
    const char *source;
    PragmaContext pragma_ctx;  /* Pragma settings */
} Transpiler;

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast, const char *filename, const char *source);

/* Transform AST (apply CZar-specific transformations) */
void transpiler_transform(Transpiler *transpiler);

/* Emit transformed AST as C code to output file */
void transpiler_emit(Transpiler *transpiler, FILE *output);

/* Emit transformed AST as C header file (declarations only) */
void transpiler_emit_header(Transpiler *transpiler, FILE *output);

/* Emit transformed AST as C source file (implementations only) */
void transpiler_emit_source(Transpiler *transpiler, FILE *output, const char *header_name);

