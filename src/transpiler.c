/*
 * CZar - C semantic authority layer
 * Transpiler implementation (transpiler.c)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#define _POSIX_C_SOURCE 200809L

#include "transpiler.h"
#include "transpiler/types.h"
#include "transpiler/constants.h"
#include "transpiler/runtime.h"
#include "transpiler/unused.h"
#include "transpiler/validation.h"
#include "transpiler/casts.h"
#include "transpiler/autodereference.h"
#include "transpiler/structs.h"
#include "transpiler/methods.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Initialize transpiler with AST */
void transpiler_init(Transpiler *transpiler, ASTNode *ast, const char *filename, const char *source) {
    transpiler->ast = ast;
    transpiler->filename = filename;
    transpiler->source = source;
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
                    const char *c_function = transpiler_get_c_function(node->token.text);
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

    /* Transform named structs to typedef structs */
    transpiler_transform_structs(transpiler->ast);

    /* Transform struct initialization syntax */
    transpiler_transform_struct_init(transpiler->ast);

    /* Transform struct methods (before autodereference) */
    transpiler_transform_methods(transpiler->ast);

    /* Transform member access operators (. to -> for pointers) */
    transpiler_transform_autodereference(transpiler->ast);

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

    /* Inject runtime macro definitions at the beginning */
    fprintf(output, "%s", transpiler_get_runtime_macros());

    emit_node(transpiler->ast, output);
}

/* Helper function to get source line for error reporting */
static const char *get_source_line(const char *source, int line_num, char *buffer, size_t buffer_size) {
    if (!source || line_num < 1) {
        return NULL;
    }

    const char *line_start = source;
    int current_line = 1;

    /* Find the start of the target line */
    while (current_line < line_num && *line_start) {
        if (*line_start == '\n') {
            current_line++;
        }
        line_start++;
    }

    if (current_line != line_num || !*line_start) {
        return NULL;
    }

    /* Copy the line to buffer */
    const char *line_end = line_start;
    while (*line_end && *line_end != '\n' && *line_end != '\r') {
        line_end++;
    }

    size_t line_len = line_end - line_start;
    if (line_len >= buffer_size) {
        line_len = buffer_size - 1;
    }

    strncpy(buffer, line_start, line_len);
    buffer[line_len] = '\0';

    return buffer;
}

/* Report a CZar error and exit */
void cz_error(const char *filename, const char *source, int line, const char *message) {
    fprintf(stderr, "[CZAR] ERROR at %s:%d: %s\n",
            filename ? filename : "<unknown>", line, message);

    /* Try to show the problematic line */
    char line_buffer[512];
    const char *source_line = get_source_line(source, line, line_buffer, sizeof(line_buffer));
    if (source_line) {
        /* Trim leading whitespace for display */
        while (*source_line && isspace((unsigned char)*source_line)) {
            source_line++;
        }
        if (*source_line) {
            fprintf(stderr, "    > %s\n", source_line);
        }
    }

    exit(1);
}

/* Report a CZar warning */
void cz_warning(const char *filename, const char *source, int line, const char *message) {
    fprintf(stdout, "[CZAR] WARNING at %s:%d: %s\n",
            filename ? filename : "<unknown>", line, message);

    /* Try to show the problematic line */
    char line_buffer[512];
    const char *source_line = get_source_line(source, line, line_buffer, sizeof(line_buffer));
    if (source_line) {
        /* Trim leading whitespace for display */
        while (*source_line && isspace((unsigned char)*source_line)) {
            source_line++;
        }
        if (*source_line) {
            fprintf(stdout, "    > %s\n", source_line);
        }
    }
}
