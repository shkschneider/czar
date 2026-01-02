/*
 * CZar - C semantic authority layer
 * Transpiler implementation (transpiler.c)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#define _POSIX_C_SOURCE 200809L

#include "transpiler.h"
#include <stdlib.h>
#include <string.h>

/* CZar type mapping structure */
typedef struct {
    const char *czar_name;
    const char *c_name;
} Mapping;

/* CZar type to C type mappings */
static const Mapping type_mappings[] = {
    {"bool", "bool"},

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

/* CZar constant to C constant mappings */
static const Mapping constant_mappings[] = {
    /* Unsigned integer constants */
    {"U8_MIN", "0"},
    {"U8_MAX", "UINT8_MAX"},
    {"U16_MIN", "0"},
    {"U16_MAX", "UINT16_MAX"},
    {"U32_MIN", "0"},
    {"U32_MAX", "UINT32_MAX"},
    {"U64_MIN", "0"},
    {"U64_MAX", "UINT64_MAX"},

    /* Signed integer constants */
    {"I8_MIN", "INT8_MIN"},
    {"I8_MAX", "INT8_MAX"},
    {"I16_MIN", "INT16_MIN"},
    {"I16_MAX", "INT16_MAX"},
    {"I32_MIN", "INT32_MIN"},
    {"I32_MAX", "INT32_MAX"},
    {"I64_MIN", "INT64_MIN"},
    {"I64_MAX", "INT64_MAX"},

    /* Size type constants */
    {"USIZE_MIN", "0"},
    {"USIZE_MAX", "SIZE_MAX"},
    {"ISIZE_MIN", "PTRDIFF_MIN"},
    {"ISIZE_MAX", "PTRDIFF_MAX"},

    {NULL, NULL} /* Sentinel */
};

/* CZar function to C function mappings */
static const Mapping function_mappings[] = {
    {"ASSERT", "cz_assert"},
    {"TODO", "cz_todo"},
    {"FIXME", "cz_fixme"},
    {"UNREACHABLE", "cz_unreachable"},
    {NULL, NULL} /* Sentinel */
};

/* Check if identifier is a CZar type and return C equivalent */
static const char *get_c_type_for_czar_type(const char *identifier) {
    for (int i = 0; type_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, type_mappings[i].czar_name) == 0) {
            return type_mappings[i].c_name;
        }
    }
    return NULL;
}

/* Check if identifier is a CZar constant and return C equivalent */
static const char *get_c_constant_for_czar_constant(const char *identifier) {
    for (int i = 0; constant_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, constant_mappings[i].czar_name) == 0) {
            return constant_mappings[i].c_name;
        }
    }
    return NULL;
}

/* Check if identifier is a CZar constant and return C equivalent */
static const char *get_c_function_for_czar_function(const char *identifier) {
    for (int i = 0; function_mappings[i].czar_name != NULL; i++) {
        if (strcmp(identifier, function_mappings[i].czar_name) == 0) {
            return function_mappings[i].c_name;
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
        } else {
            /* Check if this identifier is a CZar constant */
            const char *c_constant = get_c_constant_for_czar_constant(node->token.text);
            if (c_constant) {
                /* Replace CZar constant with C constant */
                char *new_text = strdup(c_constant);
                if (new_text) {
                    free(node->token.text);
                    node->token.text = new_text;
                    node->token.length = strlen(c_constant);
                }
                /* If strdup fails, keep the original text */
            } else {
                /* Check if this identifier is a CZar function */
                const char *c_function = get_c_function_for_czar_function(node->token.text);
                if (c_function) {
                    /* Replace CZar function with C function */
                    char *new_text = strdup(c_function);
                    if (new_text) {
                        free(node->token.text);
                        node->token.text = new_text;
                        node->token.length = strlen(c_function);
                    }
                    /* If strdup fails, keep the original text */
                }
            }
        }
    }

    /* Handle include directive replacements */
    if (node->type == AST_TOKEN && node->token.type == TOKEN_PREPROCESSOR) {
        /* Check for #include "cz.h" or #include "cz/types.h" or #include "cz/runtime.h" */
        if (strstr(node->token.text, "#include") != NULL) {
            if (strstr(node->token.text, "\"cz.h\"") != NULL) {
                /* Replace #include "cz.h" with standard headers + cz.h for runtime */
                char *new_text = strdup("#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include \"cz.h\"\n");
                if (new_text) {
                    free(node->token.text);
                    node->token.text = new_text;
                    node->token.length = strlen(new_text);
                }
            }
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
