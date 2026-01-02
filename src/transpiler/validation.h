/*
 * CZar - C semantic authority layer
 * Transpiler validation module (transpiler/validation.h)
 *
 * Validates CZar semantic rules and reports errors.
 */

#ifndef TRANSPILER_VALIDATION_H
#define TRANSPILER_VALIDATION_H

#include "../parser.h"

/* Validate AST for CZar semantic rules */
void transpiler_validate(ASTNode *ast);

#endif /* TRANSPILER_VALIDATION_H */
