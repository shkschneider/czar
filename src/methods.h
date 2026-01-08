/*
 * CZar - C semantic authority layer
 * Struct methods transformation header (transpiler/methods.h)
 *
 * Handles transformation of struct methods:
 * - Method declarations: RetType StructName.method() -> RetType StructName_method(StructName* self)
 * - Method calls: instance.method() -> StructName_method(&instance)
 * - Static method calls: StructName.method(&v) -> StructName_method(&v)
 */

#pragma once

#include "../parser.h"

/* Transform struct method declarations and calls */
void transpiler_transform_methods(ASTNode *ast, const char *filename, const char *source);
