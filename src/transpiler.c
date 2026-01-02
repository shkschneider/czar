/*
 * CZar - C semantic authority layer
 * Transpiler implementation (transpiler.c)
 * 
 * Transforms AST by applying CZar-specific transformations.
 */

#include "transpiler.h"
#include <stdlib.h>
#include <string.h>

/* Define strdup if not available */
#ifndef _GNU_SOURCE
static char *strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}
#endif

/* CZar type mapping structure */
typedef struct {
    const char *czar_type;
    const char *c_type;
} TypeMapping;

/* CZar type to C type mappings */
static const TypeMapping type_mappings[] = {
    /* Unsigned integer types */
    {"u8", "uint8_t"},
    {"u16", "uint16_t"},
    {"u32", "uint32_t"},
    {"u64", "uint64_t"},
    
    /* Signed integer types */
    {"i8", "int8_t"},
    {"i16", "int16_t"},
    {"i32", "int32_t"},
    {"i64", "int64_t"},
    
    /* Floating point types */
    {"f32", "float"},
    {"f64", "double"},
    
    /* Architecture-dependent size types */
    {"usize", "size_t"},
    {"isize", "ptrdiff_t"},
    
    {NULL, NULL} /* Sentinel */
};

/* Check if identifier is a CZar type and return C equivalent */
static const char *get_c_type_for_czar_type(const char *identifier) {
    for (int i = 0; type_mappings[i].czar_type != NULL; i++) {
        if (strcmp(identifier, type_mappings[i].czar_type) == 0) {
            return type_mappings[i].c_type;
        }
    }
    return NULL;
}

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast) {
    transpiler->ast = ast;
}

/* Transform AST node recursively */
static void transform_node(ASTNode *node) {
    if (!node) {
        return;
    }
    
    /* Transform token nodes */
    if (node->type == AST_TOKEN && node->token.type == TOKEN_IDENTIFIER) {
        /* Check if this identifier is a CZar type */
        const char *c_type = get_c_type_for_czar_type(node->token.text);
        if (c_type) {
            /* Replace CZar type with C type */
            char *new_text = strdup(c_type);
            if (new_text) {
                free(node->token.text);
                node->token.text = new_text;
                node->token.length = strlen(c_type);
            }
            /* If strdup fails, keep the original text */
        }
    }
    
    /* Recursively transform children */
    for (size_t i = 0; i < node->child_count; i++) {
        transform_node(node->children[i]);
    }
}

/* Transform AST (apply CZar-specific transformations) */
void transpiler_transform(Transpiler *transpiler) {
    if (!transpiler || !transpiler->ast) {
        return;
    }
    
    transform_node(transpiler->ast);
}

/* Emit AST node recursively */
static void emit_node(ASTNode *node, FILE *output) {
    if (!node) {
        return;
    }
    
    /* Emit token nodes */
    if (node->type == AST_TOKEN) {
        if (node->token.text && node->token.length > 0) {
            fwrite(node->token.text, 1, node->token.length, output);
        }
    }
    
    /* Recursively emit children */
    for (size_t i = 0; i < node->child_count; i++) {
        emit_node(node->children[i], output);
    }
}

/* Emit transformed AST as C code to output file */
void transpiler_emit(Transpiler *transpiler, FILE *output) {
    if (!transpiler || !transpiler->ast || !output) {
        return;
    }
    
    emit_node(transpiler->ast, output);
}
