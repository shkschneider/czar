/*
 * CZar - C semantic authority layer
 * Transpiler implementation (transpiler.c)
 *
 * Transforms AST by applying CZar-specific transformations.
 */

#include "src/cz.h"
#include "transpiler.h"
#include "src/arguments.h"
#include "src/autodereference.h"
#include "src/casts.h"
#include "src/constants.h"
#include "src/defer.h"
#include "src/deprecated.h"
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
#include "features.h"
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
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
    /* Initialize feature registry and register all features */
    feature_registry_init(&transpiler->registry);
    register_all_features(&transpiler->registry);
}

/* Clean up transpiler resources */
void transpiler_cleanup(Transpiler *transpiler) {
    if (!transpiler) {
        return;
    }
    feature_registry_free(&transpiler->registry);
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

    /* Execute validation phase for all enabled features */
    feature_registry_validate(&transpiler->registry, transpiler->ast, transpiler->filename, transpiler->source);

    /* Execute transformation phase for all enabled features */
    feature_registry_transform(&transpiler->registry, transpiler->ast, transpiler->filename, transpiler->source);

    /* Apply identifier transformations (types, constants, unused) */
    transform_node(transpiler->ast);

    /* Transform cast expressions (must be after types are transformed) */
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

    /* Copy the dirname result since dirname may modify the input string */
    char *source_dir_copy = strdup(source_dir);
    free(source_copy);

    if (!source_dir_copy) {
        return NULL;
    }

    /* Build full path: source_dir/module_path */
    size_t dir_len = strlen(source_dir_copy);
    size_t mod_len = strlen(module_path);

    /* Check for overflow: dir_len + mod_len + 2 should not overflow */
    if (dir_len > SIZE_MAX - mod_len - 2) {
        free(source_dir_copy);
        return NULL;
    }

    size_t full_path_len = dir_len + mod_len + 2; /* +2 for / and \0 */
    char *full_path = malloc(full_path_len);
    if (!full_path) {
        free(source_dir_copy);
        return NULL;
    }

    snprintf(full_path, full_path_len, "%s/%s", source_dir_copy, module_path);
    free(source_dir_copy);

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
        const size_t cz_ext_len = 3; /* length of ".cz" */
        if (name_len > cz_ext_len && strcmp(entry->d_name + name_len - cz_ext_len, ".cz") == 0) {
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
                        } else {
                            /* Memory allocation failed - emit warning and continue with default */
                            fprintf(output, "/* Warning: memory allocation failed for import directive */\n");
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

/* Helper to check if a token is the "export" keyword */
static int is_export_keyword(ASTNode *node) {
    if (!node || node->type != AST_TOKEN) {
        return 0;
    }
    Token *t = &node->token;
    return (t->type == TOKEN_IDENTIFIER && t->length == 6 && strncmp(t->text, "export", 6) == 0);
}

/* Helper to check if declaration starting at position i has export keyword */
static int has_export_keyword(ASTNode **children, size_t start_pos, size_t count) {
    /* Scan backwards from start_pos to find export keyword before significant tokens */
    /* We need to go back further to skip over comments and whitespace */
    size_t search_start = (start_pos > 20) ? (start_pos - 20) : 0;

    for (size_t i = start_pos; i > search_start; i--) {
        if (children[i]->type == AST_TOKEN) {
            Token *t = &children[i]->token;
            /* Skip whitespace and comments */
            if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) {
                continue;
            }
            /* Check if we found export keyword */
            if (is_export_keyword(children[i])) {
                return 1;
            }
            /* If we hit a semicolon or closing brace, we've gone too far back */
            if (t->type == TOKEN_PUNCTUATION && t->length == 1 && (t->text[0] == ';' || t->text[0] == '}')) {
                break;
            }
        }
    }

    /* Also check forward from start_pos (export might be right at the beginning) */
    for (size_t i = start_pos; i < count && i < start_pos + 10; i++) {
        if (children[i]->type == AST_TOKEN) {
            Token *t = &children[i]->token;
            /* Skip whitespace and comments */
            if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) {
                continue;
            }
            /* Check if we found export keyword */
            if (is_export_keyword(children[i])) {
                return 1;
            }
            /* Stop at first significant token that's not export */
            if (t->type == TOKEN_KEYWORD || t->type == TOKEN_IDENTIFIER) {
                break;
            }
        }
    }

    return 0;
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

    /* Skip export keyword if present */
    if (is_export_keyword(children[i])) {
        i++;
        /* Skip whitespace after export */
        while (i < count && children[i]->type == AST_TOKEN) {
            Token *t = &children[i]->token;
            if (t->type == TOKEN_WHITESPACE || t->type == TOKEN_COMMENT) {
                i++;
                continue;
            }
            break;
        }
        if (i >= count) return 0;
    }

    /* Check if we start with a keyword that indicates NOT a function */
    if (children[i]->type == AST_TOKEN) {
        Token *t = &children[i]->token;

        /* If it's a preprocessor directive, it's not a function */
        if (t->type == TOKEN_PREPROCESSOR) {
            return 0;
        }

        /* If it starts with struct/union/enum/typedef, not a function */
        if (t->type == TOKEN_IDENTIFIER) {
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

/* Forward declaration */
static size_t find_brace_block_end(ASTNode **children, size_t start, size_t count);

/* Helper to check if position i is EXACTLY at a struct/enum/union/typedef keyword */
static int is_at_struct_or_typedef_keyword(ASTNode **children, size_t i, size_t count) {
    if (i >= count) return 0;

    if (children[i]->type == AST_TOKEN && children[i]->token.type == TOKEN_IDENTIFIER) {
        Token *t = &children[i]->token;
        if ((t->length == 6 && strncmp(t->text, "struct", 6) == 0) ||
            (t->length == 5 && strncmp(t->text, "union", 5) == 0) ||
            (t->length == 4 && strncmp(t->text, "enum", 4) == 0) ||
            (t->length == 7 && strncmp(t->text, "typedef", 7) == 0)) {
            return 1;
        }
    }

    return 0;
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

/* Helper to emit nodes in a range, skipping the export keyword */
static void emit_node_range_skip_export(ASTNode **children, size_t start, size_t end, FILE *output, const char *source_filename) {
    for (size_t j = start; j < end; j++) {
        /* Skip the export keyword itself */
        if (is_export_keyword(children[j])) {
            continue;
        }
        emit_node(children[j], output, source_filename);
    }
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

    /* Emit everything except function bodies, and only exported items */
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
                emit_node(children[i], output, transpiler->filename);
                continue;
            }

            /* Check if this is a function definition (has body) */
            if (is_function_start(children, i, count)) {
                /* Check if this function has export keyword */
                int is_exported = has_export_keyword(children, i, count);

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

                if (is_exported) {
                    /* Emit function signature (up to but not including the opening brace), skip export keyword */
                    emit_node_range_skip_export(children, i, brace_pos, output, transpiler->filename);

                    /* Replace function body with semicolon for declaration */
                    fprintf(output, ";\n");
                }

                /* Skip to end of function body */
                i = find_function_end(children, brace_pos, count);
            } else if (is_at_struct_or_typedef_keyword(children, i, count)) {
                /* We're at the struct/typedef/enum/union keyword itself */
                /* Scan backward to see if there's an export keyword before this */
                int is_exported = 0;
                size_t decl_start = i;

                /* Look backward for export keyword (within last few tokens) */
                for (size_t j = (i > 10 ? i - 10 : 0); j < i; j++) {
                    if (is_export_keyword(children[j])) {
                        is_exported = 1;
                        decl_start = j;  /* Start from export keyword */
                        break;
                    }
                    /* Stop if we hit a semicolon or brace */
                    if (children[j]->type == AST_TOKEN && children[j]->token.type == TOKEN_PUNCTUATION &&
                        children[j]->token.length == 1 && (children[j]->token.text[0] == ';' || children[j]->token.text[0] == '}')) {
                        decl_start = j + 1;
                    }
                }

                /* Find the end of this declaration */
                size_t decl_end = i;
                for (size_t j = i; j < count; j++) {
                    if (children[j]->type == AST_TOKEN && children[j]->token.type == TOKEN_PUNCTUATION && children[j]->token.length == 1) {
                        if (children[j]->token.text[0] == '{') {
                            decl_end = find_brace_block_end(children, j, count);
                            /* Look for semicolon after closing brace (for typedef) */
                            for (size_t k = decl_end + 1; k < count && k < decl_end + 20; k++) {
                                if (children[k]->type == AST_TOKEN && children[k]->token.type == TOKEN_PUNCTUATION &&
                                    children[k]->token.length == 1 && children[k]->token.text[0] == ';') {
                                    decl_end = k;
                                    break;
                                }
                                /* Skip whitespace, comments, and identifiers (type name) */
                                if (children[k]->type == AST_TOKEN &&
                                    children[k]->token.type != TOKEN_WHITESPACE &&
                                    children[k]->token.type != TOKEN_COMMENT &&
                                    children[k]->token.type != TOKEN_IDENTIFIER) {
                                    break;  /* Stop at other tokens */
                                }
                            }
                            break;
                        } else if (children[j]->token.text[0] == ';') {
                            decl_end = j;
                            break;
                        }
                    }
                }

                if (is_exported) {
                    /* Emit the struct/typedef declaration, skip export keyword */
                    emit_node_range_skip_export(children, decl_start, decl_end + 1, output, transpiler->filename);
                }

                /* Skip past this entire declaration */
                i = decl_end;
            } else {
                /* For other tokens (whitespace, comments, etc.), emit as-is */
                /* But skip standalone export keywords */
                if (!is_export_keyword(children[i])) {
                    emit_node(children[i], output, transpiler->filename);
                }
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

/* Emit transformed AST as C source file (implementations only) */
void transpiler_emit_source(Transpiler *transpiler, FILE *output, const char *header_name) {
    if (!transpiler || !transpiler->ast || !output) {
        return;
    }

    /* Include the generated header */
    fprintf(output, "#include \"%s\"\n", header_name);

    /* Emit code from enabled features (e.g., defer cleanup functions) */
    feature_registry_emit(&transpiler->registry, output);

    /* Auto-include all other .cz.h files from the same module (directory) */
    /* This happens unconditionally for module directories */
    /* Skip for directories that look like test collections */
    if (transpiler->filename) {
        /* Check if this looks like a test directory that shouldn't auto-include */
        char *dir_copy_test = strdup(transpiler->filename);
        int skip_auto_include = 0;
        if (dir_copy_test) {
            char *dir_result_test = dirname(dir_copy_test);
            char *base_dir_name = basename(dir_result_test);

            /* Skip auto-include for "test" directories (but not subdirectories like "test/app") */
            if (strcmp(base_dir_name, "test") == 0) {
                /* Count .cz files - if many, it's likely a test collection */
                DIR *dir_test = opendir(dir_result_test);
                if (dir_test) {
                    struct dirent *entry_test;
                    int cz_count = 0;
                    while ((entry_test = readdir(dir_test)) != NULL) {
                        size_t name_len = strlen(entry_test->d_name);
                        if (name_len > 3 && strcmp(entry_test->d_name + name_len - 3, ".cz") == 0) {
                            cz_count++;
                            if (cz_count > 5) {
                                /* Many test files, don't auto-include */
                                skip_auto_include = 1;
                                break;
                            }
                        }
                    }
                    closedir(dir_test);
                }
            }
            free(dir_copy_test);
        }

        if (skip_auto_include) {
            fprintf(output, "\n");
            goto emit_functions;
        }
    }

    if (transpiler->filename) {
        /* Get directory path */
        char *dir_copy = strdup(transpiler->filename);
        if (!dir_copy) {
            fprintf(output, "\n");
            goto emit_functions;
        }
        char *dir_result = dirname(dir_copy);
        char *dir_path = strdup(dir_result);
        free(dir_copy);

        if (!dir_path) {
            fprintf(output, "\n");
            goto emit_functions;
        }

        /* Get base filename */
        char *basename_copy = strdup(transpiler->filename);
        if (!basename_copy) {
            free(dir_path);
            fprintf(output, "\n");
            goto emit_functions;
        }
        char *basename_result = basename(basename_copy);
        char *base_name = strdup(basename_result);
        free(basename_copy);

        if (!base_name) {
            free(dir_path);
            fprintf(output, "\n");
            goto emit_functions;
        }

        /* Open directory and scan for other .cz files */
        DIR *dir = opendir(dir_path);
        if (dir) {
            struct dirent *entry;

            /* Determine if we need a directory prefix for includes */
            /* If dir_path is "." we don't need a prefix, otherwise we do */
            int need_prefix = (strcmp(dir_path, ".") != 0);

            /* Extract directory name for prefix if needed */
            char *dir_prefix = NULL;
            if (need_prefix) {
                /* Get the last component of dir_path for the prefix */
                char *dir_copy2 = strdup(dir_path);
                if (dir_copy2) {
                    char *base_dir = basename(dir_copy2);
                    dir_prefix = strdup(base_dir);
                    free(dir_copy2);
                }
            }

            while ((entry = readdir(dir)) != NULL) {
                /* Check if file ends with .cz and is not the current file */
                size_t name_len = strlen(entry->d_name);
                const size_t cz_ext_len = 3; /* length of ".cz" */
                if (name_len > cz_ext_len && strcmp(entry->d_name + name_len - cz_ext_len, ".cz") == 0) {
                    /* Skip the current file itself */
                    if (strcmp(entry->d_name, base_name) != 0) {
                        if (dir_prefix) {
                            fprintf(output, "#include \"%s/%s.h\"\n", dir_prefix, entry->d_name);
                        } else {
                            fprintf(output, "#include \"%s.h\"\n", entry->d_name);
                        }
                    }
                }
            }

            if (dir_prefix) {
                free(dir_prefix);
            }
            closedir(dir);
        }

        free(base_name);
        free(dir_path);
    }

    fprintf(output, "\n");

emit_functions:
    /* Emit function definitions and non-exported structs/typedefs */
    if (transpiler->ast->type == AST_TRANSLATION_UNIT) {
        ASTNode **children = transpiler->ast->children;
        size_t count = transpiler->ast->child_count;

        /* Scan through tokens looking for function definitions and non-exported items */
        for (size_t i = 0; i < count; i++) {
            /* Check if we're at the start of a function definition */
            if (is_function_start(children, i, count)) {
                /* Find the end of the function body */
                size_t func_end = find_function_end(children, i, count);

                /* Emit the entire function definition, skip export keyword */
                emit_node_range_skip_export(children, i, func_end + 1, output, transpiler->filename);
                fprintf(output, "\n\n");

                /* Skip past the function */
                i = func_end;
            } else if (is_at_struct_or_typedef_keyword(children, i, count)) {
                /* We're at a struct/typedef/enum/union keyword */
                /* Scan backward to see if there's an export keyword */
                int is_exported = 0;
                size_t decl_start = i;

                for (size_t j = (i > 10 ? i - 10 : 0); j < i; j++) {
                    if (is_export_keyword(children[j])) {
                        is_exported = 1;
                        decl_start = j;
                        break;
                    }
                    if (children[j]->type == AST_TOKEN && children[j]->token.type == TOKEN_PUNCTUATION &&
                        children[j]->token.length == 1 && (children[j]->token.text[0] == ';' || children[j]->token.text[0] == '}')) {
                        decl_start = j + 1;
                    }
                }

                /* Only emit non-exported structs/typedefs in the source file */
                if (!is_exported) {
                    /* Find the end of this declaration (semicolon or brace block) */
                    size_t decl_end = i;

                    /* Find the opening brace or semicolon */
                    for (size_t j = i; j < count; j++) {
                        if (children[j]->type == AST_TOKEN && children[j]->token.type == TOKEN_PUNCTUATION && children[j]->token.length == 1) {
                            if (children[j]->token.text[0] == '{') {
                                decl_end = find_brace_block_end(children, j, count);
                                /* Look for semicolon after closing brace (for typedef) */
                                for (size_t k = decl_end + 1; k < count && k < decl_end + 20; k++) {
                                    if (children[k]->type == AST_TOKEN && children[k]->token.type == TOKEN_PUNCTUATION &&
                                        children[k]->token.length == 1 && children[k]->token.text[0] == ';') {
                                        decl_end = k;
                                        break;
                                    }
                                    /* Skip whitespace, comments, and identifiers (type name) */
                                    if (children[k]->type == AST_TOKEN &&
                                        children[k]->token.type != TOKEN_WHITESPACE &&
                                        children[k]->token.type != TOKEN_COMMENT &&
                                        children[k]->token.type != TOKEN_IDENTIFIER) {
                                        break;  /* Stop at other tokens */
                                    }
                                }
                                break;
                            } else if (children[j]->token.text[0] == ';') {
                                decl_end = j;
                                break;
                            }
                        }
                    }

                    /* Emit the struct/typedef declaration from decl_start */
                    for (size_t j = decl_start; j <= decl_end && j < count; j++) {
                        emit_node(children[j], output, transpiler->filename);
                    }
                    fprintf(output, "\n\n");

                    i = decl_end;
                } else {
                    /* It's exported, skip it (already in header) - find the end and skip past it */
                    size_t decl_end = i;
                    for (size_t j = i; j < count; j++) {
                        if (children[j]->type == AST_TOKEN && children[j]->token.type == TOKEN_PUNCTUATION && children[j]->token.length == 1) {
                            if (children[j]->token.text[0] == '{') {
                                decl_end = find_brace_block_end(children, j, count);
                                for (size_t k = decl_end + 1; k < count && k < decl_end + 20; k++) {
                                    if (children[k]->type == AST_TOKEN && children[k]->token.type == TOKEN_PUNCTUATION &&
                                        children[k]->token.length == 1 && children[k]->token.text[0] == ';') {
                                        decl_end = k;
                                        break;
                                    }
                                    /* Skip whitespace, comments, and identifiers (type name) */
                                    if (children[k]->type == AST_TOKEN &&
                                        children[k]->token.type != TOKEN_WHITESPACE &&
                                        children[k]->token.type != TOKEN_COMMENT &&
                                        children[k]->token.type != TOKEN_IDENTIFIER) {
                                        break;  /* Stop at other tokens */
                                    }
                                }
                                break;
                            } else if (children[j]->token.text[0] == ';') {
                                decl_end = j;
                                break;
                            }
                        }
                    }
                    i = decl_end;
                }
            }
            /* Skip all other tokens - they're in the header or are whitespace */
        }
    }
}
