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
#include <dirent.h>
#include <sys/stat.h>
#include <libgen.h>

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

/* Helper function to check if a path is a directory */
static int is_directory(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    return 0;
}

/* Helper function to resolve module path relative to source file */
static char* resolve_module_path(const char *source_filename, const char *module_path) {
    if (!source_filename || !module_path) {
        return NULL;
    }

    /* Get directory of source file */
    char *source_copy = strdup(source_filename);
    if (!source_copy) {
        return NULL;
    }

    char *source_dir = dirname(source_copy);

    /* Build full path: source_dir/module_path */
    size_t full_path_len = strlen(source_dir) + strlen(module_path) + 2; /* +2 for / and \0 */
    char *full_path = malloc(full_path_len);
    if (!full_path) {
        free(source_copy);
        return NULL;
    }

    snprintf(full_path, full_path_len, "%s/%s", source_dir, module_path);
    free(source_copy);

    return full_path;
}

/* Helper function to emit includes for all .cz files in a module directory */
static void emit_module_includes(const char *source_filename, const char *module_path, FILE *output) {
    /* Resolve full path to module directory */
    char *full_module_path = resolve_module_path(source_filename, module_path);
    if (!full_module_path) {
        /* If path resolution fails, emit a comment */
        fprintf(output, "/* Warning: could not resolve module path: %s */\n", module_path);
        return;
    }

    /* Check if it's a directory */
    if (!is_directory(full_module_path)) {
        /* Not a directory - treat as single file import (old behavior) */
        fprintf(output, "#include \"%s.cz.h\"", module_path);
        free(full_module_path);
        return;
    }

    /* Open directory and scan for .cz files */
    DIR *dir = opendir(full_module_path);
    if (!dir) {
        /* Directory doesn't exist or can't be opened */
        fprintf(output, "/* Warning: could not open module directory: %s */\n", module_path);
        free(full_module_path);
        return;
    }

    struct dirent *entry;
    int found_files = 0;

    while ((entry = readdir(dir)) != NULL) {
        /* Check if file ends with .cz */
        size_t name_len = strlen(entry->d_name);
        if (name_len > 3 && strcmp(entry->d_name + name_len - 3, ".cz") == 0) {
            /* Emit #include for this .cz file's header */
            if (found_files > 0) {
                fprintf(output, "\n");
            }
            fprintf(output, "#include \"%s/%s.h\"", module_path, entry->d_name);
            found_files++;
        }
    }

    closedir(dir);
    free(full_module_path);

    if (found_files == 0) {
        /* No .cz files found in directory */
        fprintf(output, "/* Warning: no .cz files found in module: %s */", module_path);
    }
}

/* Helper function to check if AST contains any #import directives */
static int has_import_directives(ASTNode *node) {
    if (!node) {
        return 0;
    }

    /* Check if this node is an #import directive */
    if (node->type == AST_TOKEN && node->token.type == TOKEN_PREPROCESSOR) {
        if (node->token.length >= 7 && strncmp(node->token.text, "#import", 7) == 0) {
            return 1;
        }
    }

    /* Recursively check children */
    for (size_t i = 0; i < node->child_count; i++) {
        if (has_import_directives(node->children[i])) {
            return 1;
        }
    }

    return 0;
}


/* Emit AST node recursively */
static void emit_node(ASTNode *node, FILE *output, const char *source_filename) {
    if (!node) {
        return;
    }

    /* Emit token nodes */
    if (node->type == AST_TOKEN) {
        if (node->token.text && node->token.length > 0) {
            /* Check if this is an #import directive that needs transformation */
            if (node->token.type == TOKEN_PREPROCESSOR &&
                node->token.length >= 7 &&
                strncmp(node->token.text, "#import", 7) == 0) {
                /* Extract module path from #import "module/path" */
                const char *import_start = node->token.text;
                const char *quote_start = strchr(import_start, '"');

                if (quote_start) {
                    const char *quote_end = strchr(quote_start + 1, '"');
                    if (quote_end) {
                        /* Extract module path */
                        size_t module_len = quote_end - quote_start - 1;
                        char *module_path = malloc(module_len + 1);
                        if (module_path) {
                            memcpy(module_path, quote_start + 1, module_len);
                            module_path[module_len] = '\0';

                            /* Emit includes for all .cz files in the module */
                            emit_module_includes(source_filename, module_path, output);

                            free(module_path);

                            /* Emit rest of line (comments, whitespace) */
                            const char *rest = quote_end + 1;
                            size_t rest_len = (import_start + node->token.length) - rest;
                            if (rest_len > 0) {
                                fwrite(rest, 1, rest_len, output);
                            }
                            return;
                        }
                    }
                }
            }

            /* Regular token emission */
            fwrite(node->token.text, 1, node->token.length, output);
        }
    }

    /* Recursively emit children */
    for (size_t i = 0; i < node->child_count; i++) {
        emit_node(node->children[i], output, source_filename);
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

    emit_node(transpiler->ast, output, transpiler->filename);
}

/* Helper to check if position i is at the START of a function definition */
static int is_function_start(ASTNode **children, size_t i, size_t count) {
    /* Position i should be at or near the return type of the function
     * Pattern: [type] identifier ( ... ) {
     * But NOT: struct/union/enum/typedef ... {
     */
    if (i >= count) return 0;

    /* Skip whitespace and comments to find the first significant token */
    while (i < count && children[i]->type == AST_TOKEN) {
        Token *t = &children[i]->token;
        if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) {
            i++;
            continue;
        }
        break;
    }
    if (i >= count) return 0;

    /* Check if we start with a keyword that indicates NOT a function */
    if (children[i]->type == AST_TOKEN) {
        Token *t = &children[i]->token;

        /* If it's a preprocessor directive, it's not a function */
        if (t->type == TOKEN_PREPROCESSOR) {
            return 0;
        }

        /* If it starts with struct/union/enum/typedef, not a function */
        if (t->type == TOKEN_KEYWORD) {
            if ((t->length == 6 && strncmp(t->text, "struct", 6) == 0) ||
                (t->length == 5 && strncmp(t->text, "union", 5) == 0) ||
                (t->length == 4 && strncmp(t->text, "enum", 4) == 0) ||
                (t->length == 7 && strncmp(t->text, "typedef", 7) == 0)) {
                return 0;
            }
        }
    }

    /* Now look for the function pattern: ( ... ) { */
    int found_open_paren = 0;
    int found_close_paren = 0;

    for (size_t j = i; j < count && j < i + 100; j++) {
        if (children[j]->type != AST_TOKEN) continue;

        Token *t = &children[j]->token;
        if (t->type == TOKEN_PUNCTUATION && t->length == 1) {
            if (t->text[0] == '(') {
                found_open_paren = 1;
            } else if (t->text[0] == ')') {
                found_close_paren = 1;
            } else if (t->text[0] == '{') {
                if (found_open_paren && found_close_paren) {
                    return 1;  /* Function definition: (...) { */
                } else {
                    return 0;  /* Brace without proper function signature */
                }
            } else if (t->text[0] == ';') {
                return 0;  /* Semicolon before brace - not a definition */
            }
        }
    }
    return 0;
}

/* Helper to check if node is a preprocessor directive */
static int is_preprocessor(ASTNode *node) {
    return node && node->type == AST_TOKEN && node->token.type == TOKEN_PREPROCESSOR;
}

/* Helper to find end of preprocessor line (including #pragma) */
static size_t find_preprocessor_end(ASTNode **children, size_t start, size_t count) {
    for (size_t i = start; i < count; i++) {
        if (children[i]->type == AST_TOKEN) {
            Token *t = &children[i]->token;
            /* Preprocessor directives end at newline in whitespace */
            if (t->type == TOKEN_WHITESPACE && t->length > 0) {
                for (size_t j = 0; j < t->length; j++) {
                    if (t->text[j] == '\n') {
                        return i;
                    }
                }
            }
        }
    }
    return start;
}

/* Helper to find the end of a function body */
static size_t find_function_end(ASTNode **children, size_t start, size_t count) {
    int brace_depth = 0;
    int started = 0;

    for (size_t i = start; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *t = &children[i]->token;
        if (t->type == TOKEN_PUNCTUATION && t->length == 1) {
            if (t->text[0] == '{') {
                brace_depth++;
                started = 1;
            } else if (t->text[0] == '}') {
                brace_depth--;
                if (started && brace_depth == 0) {
                    return i;
                }
            }
        }
    }
    return count;
}

/* Emit transformed AST as C header file (declarations only) */
void transpiler_emit_header(Transpiler *transpiler, FILE *output) {
    if (!transpiler || !transpiler->ast || !output) {
        return;
    }

    /* Emit pragma once */
    fprintf(output, "#pragma once\n\n");

    /* Emit standard C includes */
    fprintf(output, "#include <stdlib.h>\n");
    fprintf(output, "#include <stdio.h>\n");
    fprintf(output, "#include <stdint.h>\n");
    fprintf(output, "#include <stddef.h>\n");
    fprintf(output, "#include <stdbool.h>\n");
    fprintf(output, "#include <assert.h>\n");
    fprintf(output, "#include <stdarg.h>\n");
    fprintf(output, "#include <string.h>\n");
    fprintf(output, "\n");

    /* Emit everything except function bodies */
    if (transpiler->ast->type == AST_TRANSLATION_UNIT) {
        ASTNode **children = transpiler->ast->children;
        size_t count = transpiler->ast->child_count;

        for (size_t i = 0; i < count; i++) {
            /* Skip user #include directives (already in standard includes) */
            if (is_preprocessor(children[i])) {
                if (children[i]->type == AST_TOKEN &&
                    children[i]->token.type == TOKEN_PREPROCESSOR &&
                    children[i]->token.length >= 8 &&
                    strncmp(children[i]->token.text, "#include", 8) == 0) {
                    size_t end = find_preprocessor_end(children, i, count);
                    i = end;
                    continue;
                }
                /* Keep other preprocessor directives like #pragma */
            }

            /* Check if this is a function definition (has body) */
            if (is_function_start(children, i, count)) {
                /* Find where the opening brace is */
                size_t brace_pos = i;
                while (brace_pos < count) {
                    if (children[brace_pos]->type == AST_TOKEN &&
                        children[brace_pos]->token.type == TOKEN_PUNCTUATION &&
                        children[brace_pos]->token.length == 1 &&
                        children[brace_pos]->token.text[0] == '{') {
                        break;
                    }
                    brace_pos++;
                }

                /* Emit function signature (up to but not including the opening brace) */
                for (size_t j = i; j < brace_pos; j++) {
                    emit_node(children[j], output, transpiler->filename);
                }

                /* Replace function body with semicolon for declaration */
                fprintf(output, ";\n");

                /* Skip to end of function body */
                i = find_function_end(children, brace_pos, count);
            } else {
                /* Everything else (structs, typedefs, globals, pragmas) - emit as-is */
                emit_node(children[i], output, transpiler->filename);
            }
        }
    } else {
        emit_node(transpiler->ast, output, transpiler->filename);
    }
}

/* Helper to find end of any brace block */
static size_t find_brace_block_end(ASTNode **children, size_t start, size_t count) {
    int brace_depth = 0;
    int started = 0;

    for (size_t i = start; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *t = &children[i]->token;
        if (t->type == TOKEN_PUNCTUATION && t->length == 1) {
            if (t->text[0] == '{') {
                if (!started) {
                    /* This is the opening brace we're starting from */
                    brace_depth = 1;
                    started = 1;
                } else {
                    brace_depth++;
                }
            } else if (t->text[0] == '}') {
                brace_depth--;
                if (started && brace_depth == 0) {
                    return i;
                }
            }
        }
    }
    return count;
}

/* Helper to find the start of a statement/declaration (scan backwards to previous semicolon or start) */
static size_t find_statement_start(ASTNode **children, size_t pos, size_t count) {
    /* Scan backwards to find the previous semicolon, closing brace, or start of file */
    for (size_t i = (pos > 0 ? pos - 1 : 0); ; i--) {
        if (children[i]->type == AST_TOKEN && children[i]->token.type == TOKEN_PUNCTUATION && children[i]->token.length == 1) {
            char c = children[i]->token.text[0];
            if (c == ';' || c == '}') {
                return i + 1;  /* Start after the semicolon or brace */
            }
        }
        if (i == 0) {
            return 0;  /* Start of file */
        }
    }
}

/* Helper to find the end of a statement (scan forward to next semicolon or closing brace at depth 0) */
static size_t find_statement_end(ASTNode **children, size_t start, size_t count) {
    int brace_depth = 0;
    for (size_t i = start; i < count; i++) {
        if (children[i]->type == AST_TOKEN && children[i]->token.type == TOKEN_PUNCTUATION && children[i]->token.length == 1) {
            char c = children[i]->token.text[0];
            if (c == '{') {
                brace_depth++;
            } else if (c == '}') {
                brace_depth--;
                if (brace_depth <= 0) {
                    return i;
                }
            } else if (c == ';' && brace_depth == 0) {
                return i;
            }
        }
    }
    return count;
}

/* Emit transformed AST as C source file (implementations only) */
void transpiler_emit_source(Transpiler *transpiler, FILE *output, const char *header_name) {
    if (!transpiler || !transpiler->ast || !output) {
        return;
    }

    /* Include the generated header */
    fprintf(output, "#include \"%s\"\n", header_name);

    /* Auto-include all other .cz files from the same module (directory) */
    /* Only do this if the file uses the module system (has #import directives) */
    if (transpiler->filename && has_import_directives(transpiler->ast)) {
        char *filename_copy = strdup(transpiler->filename);
        if (filename_copy) {
            char *dir_path = dirname(filename_copy);

            /* Get just the filename without directory */
            char *filename_copy2 = strdup(transpiler->filename);
            if (filename_copy2) {
                const char *base_name = basename(filename_copy2);

                /* Open directory and scan for other .cz files */
                DIR *dir = opendir(dir_path);
                if (dir) {
                    struct dirent *entry;

                    while ((entry = readdir(dir)) != NULL) {
                        /* Check if file ends with .cz and is not the current file */
                        size_t name_len = strlen(entry->d_name);
                        if (name_len > 3 && strcmp(entry->d_name + name_len - 3, ".cz") == 0) {
                            /* Skip the current file itself */
                            if (strcmp(entry->d_name, base_name) != 0) {
                                /* Skip main.cz as it typically only exports main() */
                                if (strcmp(entry->d_name, "main.cz") != 0) {
                                    fprintf(output, "#include \"%s.h\"\n", entry->d_name);
                                }
                            }
                        }
                    }

                    closedir(dir);
                }
                free(filename_copy2);
            }
            free(filename_copy);
        }
    }

    fprintf(output, "\n");

    /* Emit function definitions only */
    if (transpiler->ast->type == AST_TRANSLATION_UNIT) {
        ASTNode **children = transpiler->ast->children;
        size_t count = transpiler->ast->child_count;

        /* Scan through tokens looking for function definitions */
        for (size_t i = 0; i < count; i++) {
            /* Check if we're at the start of a function definition */
            if (is_function_start(children, i, count)) {
                /* Find the end of the function body */
                size_t func_end = find_function_end(children, i, count);

                /* Emit the entire function definition */
                for (size_t j = i; j <= func_end && j < count; j++) {
                    emit_node(children[j], output, transpiler->filename);
                }
                fprintf(output, "\n\n");

                /* Skip past the function */
                i = func_end;
            }
            /* Skip all other tokens - they're in the header */
        }
    }
}
