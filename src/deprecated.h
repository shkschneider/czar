/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles #deprecated compiler extension directive.
 */

#pragma once

#include "../parser.h"

/* Transform #deprecated directives to __attribute__((deprecated)) */
void transpiler_transform_deprecated(ASTNode_t *ast);
