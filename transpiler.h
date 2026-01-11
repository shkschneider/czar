/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#pragma once

#include "parser.h"
#include "src/pragma.h"
#include "registry.h"
#include <stdio.h>

/* Transpiler structure */
typedef struct Transpiler_s {
    ASTNode_t *ast;
    const char *filename;
    const char *source;
    PragmaContext pragma_ctx;  /* Pragma settings */
    FeatureRegistry registry;  /* Feature registry */
} Transpiler_t;

/* Initialize transpiler with AST */
void transpiler_init(Transpiler_t *transpiler, ASTNode_t *ast, const char *filename, const char *source);

/* Clean up transpiler resources */
void transpiler_cleanup(Transpiler_t *transpiler);

/* Transform AST (apply CZar-specific transformations) */
void transpiler_transform(Transpiler_t *transpiler);

/* Emit transformed AST as C code to output file */
void transpiler_emit(Transpiler_t *transpiler, FILE *output);

/* Emit transformed AST as C header file (declarations only) */
void transpiler_emit_header(Transpiler_t *transpiler, FILE *output);

/* Emit transformed AST as C source file (implementations only) */
void transpiler_emit_source(Transpiler_t *transpiler, FILE *output, const char *header_name);

