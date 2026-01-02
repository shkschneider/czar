/*
 * CZar - C semantic authority layer
 * Cast handling header (transpiler/casts.h)
 *
 * Handles cast validation and transformation.
 */

#ifndef TRANSPILER_CASTS_H
#define TRANSPILER_CASTS_H

#include "../parser.h"

/* Validate and transform casts in AST */
void transpiler_validate_casts(ASTNode *ast, const char *filename, const char *source);

/* Transform cast expressions to C equivalents */
void transpiler_transform_casts(ASTNode *ast);

#endif /* TRANSPILER_CASTS_H */
