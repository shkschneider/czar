/*
 * CZar - C semantic authority layer
 * Transpiler implementation (transpiler.c)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#include "transpiler.h"
#include "src/arguments.h"
#include "src/autodereference.h"
#include "src/casts.h"
#include "src/constants.h"
#include "src/enums.h"
#include "src/errors.h"
#include "src/fixme.h"
#include "src/functions.h"
#include "src/methods.h"
#include "src/mutability.h"
#include "src/pragma.h"
#include "src/structs.h"
#include "src/todo.h"
#include "src/types.h"
#include "src/unreachable.h"
#include "src/unused.h"
#include "src/validation.h"
#include "src/warnings.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Global context for error/warning reporting */
const char *g_filename = NULL;
const char *g_source = NULL;

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast, const char *filename, const char *source) {
    transpiler->ast = ast;
    transpiler->filename = filename;
    transpiler->source = source;
    /* Initialize pragma context with defaults */
    pragma_context_init(&transpiler->pragma_ctx);
    /* Parse pragmas from AST to update context */
    transpiler_parse_pragmas(ast, &transpiler->pragma_ctx);
    /* Reset unused counter for each translation unit */
    transpiler_reset_unused_counter();
}

/* Transform AST node recursively */
static void transform_node(ASTNode *node) {
    if (!node) {
        return;
    }

    /* Transform token nodes */
    if (node->type == AST_TOKEN && node->token.type == TOKEN_IDENTIFIER) {
        /* Check if this is the special _ identifier */
        if (strcmp(node->token.text, "_") == 0) {
            /* Replace _ with unique unused variable name */
            char *new_text = transpiler_transform_unused_identifier();
            if (new_text) {
                free(node->token.text);
                node->token.text = new_text;
                node->token.length = strlen(new_text);
            } else {
                /* If transformation fails, create a fallback name to avoid duplicate _ */
                static int fallback_counter = 0;
                char fallback[32];
                snprintf(fallback, sizeof(fallback), "_unused_fallback_%d", fallback_counter++);
                char *fallback_text = strdup(fallback);
                if (fallback_text) {
                    free(node->token.text);
                    node->token.text = fallback_text;
                    node->token.length = strlen(fallback_text);
                }
                /* If even fallback fails, keep original _ (may cause C compilation error) */
            }
        } else {
            /* Check if this identifier is a CZar type */
            const char *c_type = transpiler_get_c_type(node->token.text);
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
                const char *c_constant = transpiler_get_c_constant(node->token.text);
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

    /* First validate the AST for CZar semantic rules */
    transpiler_validate(transpiler->ast, transpiler->filename, transpiler->source);

    /* Validate cast expressions */
    transpiler_validate_casts(transpiler->ast, transpiler->filename, transpiler->source);

    /* Validate enum declarations and switch exhaustiveness */
    transpiler_validate_enums(transpiler->ast, transpiler->filename, transpiler->source);

    /* Validate function declarations (empty parameter lists) */
    transpiler_validate_functions(transpiler->ast, transpiler->filename, transpiler->source);

    /* Transform function declarations (main return type, empty parameter lists to void) */
    transpiler_transform_functions(transpiler->ast);

    /* Transform named structs to typedef structs */
    transpiler_transform_structs(transpiler->ast);

    /* Transform struct initialization syntax */
    transpiler_transform_struct_init(transpiler->ast);

    /* Transform struct methods (before autodereference) */
    transpiler_transform_methods(transpiler->ast, transpiler->filename, transpiler->source);

    /* Replace struct names with _t variants in generated C code */
    /* Must be AFTER method transformations to preserve base names in methods */
    transpiler_replace_struct_names(transpiler->ast);

    /* Transform member access operators (. to -> for pointers) */
    transpiler_transform_autodereference(transpiler->ast);

    /* Transform enums (add default: inline unreachable if needed) */
    transpiler_transform_enums(transpiler->ast, transpiler->filename);

    /* Expand runtime function calls inline with .cz file location (before transforming identifiers) */
    transpiler_expand_unreachable(transpiler->ast, transpiler->filename);
    transpiler_expand_todo(transpiler->ast, transpiler->filename);
    transpiler_expand_fixme(transpiler->ast, transpiler->filename);

    /* Transform named arguments (strip labels) - must run before type transformations */
    transpiler_transform_named_arguments(transpiler->ast, transpiler->filename, transpiler->source);

    /* Transform mutability (mut keyword and const insertion) */
    /* Must run after named arguments but before type transformations */
    transpiler_transform_mutability(transpiler->ast, transpiler->filename, transpiler->source);

    /* Then apply transformations */
    transform_node(transpiler->ast);

    /* Transform cast expressions */
    transpiler_transform_casts(transpiler->ast);
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

    /* Emit standard C includes */
    fprintf(output, "#include <stdlib.h>\n");
    fprintf(output, "#include <stdio.h>\n");
    fprintf(output, "#include <stdint.h>\n");
    fprintf(output, "#include <stdbool.h>\n");
    fprintf(output, "#include <assert.h>\n");
    fprintf(output, "#include <stdarg.h>\n");
    fprintf(output, "#include <string.h>\n");
    fprintf(output, "\n");

    emit_node(transpiler->ast, output);
}

