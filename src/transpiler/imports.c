/*
 * CZar - C semantic authority layer
 * Import/Module implementation (imports.c)
 *
 * Handles #import directives and module system.
 */

#include "../cz.h"
#include "imports.h"
#include "../errors.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <dirent.h>
#include <libgen.h>

/* Initialize module context with main file path */
void module_context_init(ModuleContext *ctx, const char *main_file_path) {
    if (!ctx) return;

    ctx->imports = NULL;
    ctx->import_count = 0;
    ctx->import_capacity = 0;

    /* Extract directory from main file path */
    if (main_file_path) {
        char *path_copy = strdup(main_file_path);
        if (path_copy) {
            char *dir = dirname(path_copy);
            ctx->main_file_dir = strdup(dir);
            free(path_copy);
        } else {
            ctx->main_file_dir = strdup(".");
        }
    } else {
        ctx->main_file_dir = strdup(".");
    }
}

/* Free module context */
void module_context_free(ModuleContext *ctx) {
    if (!ctx) return;

    /* Free imports */
    for (size_t i = 0; i < ctx->import_count; i++) {
        if (ctx->imports[i]) {
            free(ctx->imports[i]->module_path);
            free(ctx->imports[i]);
        }
    }
    free(ctx->imports);
    free(ctx->main_file_dir);
}

/* Add import directive to context */
static void add_import(ModuleContext *ctx, const char *module_path, int line) {
    if (!ctx || !module_path) return;

    /* Allocate import directive */
    ImportDirective *import = malloc(sizeof(ImportDirective));
    if (!import) return;

    import->module_path = strdup(module_path);
    import->line = line;

    /* Expand imports array if needed */
    if (ctx->import_count >= ctx->import_capacity) {
        size_t new_capacity = ctx->import_capacity == 0 ? 8 : ctx->import_capacity * 2;
        ImportDirective **new_imports = realloc(ctx->imports, new_capacity * sizeof(ImportDirective*));
        if (!new_imports) {
            free(import->module_path);
            free(import);
            return;
        }
        ctx->imports = new_imports;
        ctx->import_capacity = new_capacity;
    }

    ctx->imports[ctx->import_count++] = import;
}

/* Check if token is #import directive */
static int is_import_directive(ASTNode *node) {
    if (!node || node->type != AST_TOKEN) return 0;
    if (node->token.type != TOKEN_PREPROCESSOR) return 0;

    /* Check if text starts with #import */
    const char *text = node->token.text;
    if (!text) return 0;

    /* Skip whitespace after # */
    const char *p = text;
    if (*p == '#') p++;
    while (*p == ' ' || *p == '\t') p++;

    return strncmp(p, "import", 6) == 0;
}

/* Extract module path from #import directive */
static char* extract_module_path(const char *import_text) {
    if (!import_text) return NULL;

    /* Find opening quote */
    const char *start = strchr(import_text, '"');
    if (!start) return NULL;
    start++; /* Skip opening quote */

    /* Find closing quote */
    const char *end = strchr(start, '"');
    if (!end) return NULL;

    /* Extract path */
    size_t length = end - start;
    char *path = malloc(length + 1);
    if (!path) return NULL;

    strncpy(path, start, length);
    path[length] = '\0';

    return path;
}

/* Extract #import directives from AST recursively */
static void extract_imports_recursive(ASTNode *node, ModuleContext *ctx) {
    if (!node) return;

    /* Check if this is an import directive */
    if (is_import_directive(node)) {
        char *module_path = extract_module_path(node->token.text);
        if (module_path) {
            add_import(ctx, module_path, node->token.line);
            free(module_path);
        }
    }

    /* Recursively process children */
    for (size_t i = 0; i < node->child_count; i++) {
        extract_imports_recursive(node->children[i], ctx);
    }
}

/* Extract #import directives from AST */
void transpiler_extract_imports(ASTNode *ast, ModuleContext *ctx) {
    if (!ast || !ctx) return;
    extract_imports_recursive(ast, ctx);
}

/* Generate header file (.cz.h) for a .cz file */
int transpiler_generate_header(const char *cz_file_path, const char *output_header_path) {
    if (!cz_file_path || !output_header_path) return 0;

    /* Read the .cz file */
    FILE *input = fopen(cz_file_path, "r");
    if (!input) return 0;

    /* Get file size */
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    fseek(input, 0, SEEK_SET);

    if (size <= 0) {
        fclose(input);
        return 0;
    }

    /* Read content */
    char *content = malloc(size + 1);
    if (!content) {
        fclose(input);
        return 0;
    }

    size_t bytes_read = fread(content, 1, size, input);
    content[bytes_read] = '\0';
    fclose(input);

    /* Parse the content (simplified - extract function and struct declarations) */
    FILE *output = fopen(output_header_path, "w");
    if (!output) {
        free(content);
        return 0;
    }

    /* Write header guard */
    fprintf(output, "/* Generated header from %s */\n", cz_file_path);
    fprintf(output, "#pragma once\n\n");

    /* Write necessary includes for CZar types */
    fprintf(output, "#include <stdint.h>\n");
    fprintf(output, "#include <stddef.h>\n");
    fprintf(output, "#include <stdbool.h>\n\n");

    /* Extract declarations: structs, enums, typedefs, and function signatures */
    /* Function implementations stay in .c files */
    char *p = content;
    while (*p) {
        /* Skip whitespace */
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (!*p) break;

        /* Skip line comments */
        if (*p == '/' && *(p+1) == '/') {
            while (*p && *p != '\n') p++;
            continue;
        }

        /* Skip block comments */
        if (*p == '/' && *(p+1) == '*') {
            p += 2;
            while (*p && !(*p == '*' && *(p+1) == '/')) p++;
            if (*p) p += 2;
            continue;
        }

        char *line_start = p;

        /* Check for struct definition */
        if (strncmp(p, "struct ", 7) == 0) {
            /* Extract entire struct definition including all fields */
            char *struct_start = p;
            int brace_count = 0;
            int found_opening_brace = 0;

            /* Find opening brace */
            while (*p && !found_opening_brace) {
                if (*p == '{') {
                    brace_count = 1;
                    found_opening_brace = 1;
                    p++;
                    break;
                }
                p++;
            }

            if (found_opening_brace) {
                /* Find matching closing brace */
                while (*p && brace_count > 0) {
                    if (*p == '{') brace_count++;
                    if (*p == '}') brace_count--;
                    p++;
                }

                /* Find the semicolon after closing brace */
                while (*p && *p != ';' && *p != '\n') p++;
                if (*p == ';') p++;

                /* Write the complete struct definition */
                fprintf(output, "%.*s\n\n", (int)(p - struct_start), struct_start);
                continue;
            }
        }

        /* Check for enum definition */
        if (strncmp(p, "enum ", 5) == 0) {
            /* Extract entire enum definition */
            char *enum_start = p;
            int brace_count = 0;
            int found_opening_brace = 0;

            /* Find opening brace */
            while (*p && !found_opening_brace) {
                if (*p == '{') {
                    brace_count = 1;
                    found_opening_brace = 1;
                    p++;
                    break;
                }
                p++;
            }

            if (found_opening_brace) {
                /* Find matching closing brace */
                while (*p && brace_count > 0) {
                    if (*p == '{') brace_count++;
                    if (*p == '}') brace_count--;
                    p++;
                }

                /* Find the semicolon after closing brace */
                while (*p && *p != ';' && *p != '\n') p++;
                if (*p == ';') p++;

                /* Write the complete enum definition */
                fprintf(output, "%.*s\n\n", (int)(p - enum_start), enum_start);
                continue;
            }
        }

        /* Check for typedef */
        if (strncmp(p, "typedef ", 8) == 0) {
            /* Extract typedef declaration */
            char *typedef_start = p;

            /* Find the semicolon */
            while (*p && *p != ';') p++;
            if (*p == ';') p++;

            /* Write the typedef */
            fprintf(output, "%.*s\n", (int)(p - typedef_start), typedef_start);
            continue;
        }

        /* Check for function definition */
        char *paren = NULL;
        char *brace = NULL;

        /* Find '(' and '{' on the same logical line */
        while (*p && *p != '\n' && *p != '{' && *p != ';') {
            if (*p == '(') paren = p;
            p++;
        }

        if (*p == '{') brace = p;

        /* If we found both '(' and '{', this is a function definition */
        if (paren && brace) {
            /* Extract the function signature (declaration only, not implementation) */
            fprintf(output, "%.*s;\n", (int)(brace - line_start), line_start);

            /* Skip function body */
            int brace_count = 1;
            p++; /* Skip opening '{' */
            while (*p && brace_count > 0) {
                if (*p == '{') brace_count++;
                if (*p == '}') brace_count--;
                p++;
            }
        } else {
            /* Not a recognized declaration, move to next line */
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
        }
    }

    free(content);
    fclose(output);

    return 1;
}

/* Transform #import directive to #include */
static void transform_import_node(ASTNode *node, ModuleContext *ctx) {
    if (!node || !ctx) return;
    if (!is_import_directive(node)) return;

    /* Extract module path */
    char *module_path = extract_module_path(node->token.text);
    if (!module_path) return;

    /* Build path to imported directory relative to main file */
    char full_path[1024];
    if (ctx->main_file_dir && strcmp(ctx->main_file_dir, ".") != 0) {
        snprintf(full_path, sizeof(full_path), "%s/%s", ctx->main_file_dir, module_path);
    } else {
        snprintf(full_path, sizeof(full_path), "%s", module_path);
    }

    /* Find all .cz.h files in the directory */
    DIR *dir = opendir(full_path);
    if (!dir) {
        /* Directory doesn't exist or can't be opened */
        /* Keep as comment */
        size_t new_size = strlen(module_path) + 256;
        char *new_text = malloc(new_size);
        if (new_text) {
            snprintf(new_text, new_size, "/* #import \"%s\" - directory not found */", module_path);
            free(node->token.text);
            node->token.text = new_text;
            node->token.length = strlen(new_text);
            node->token.type = TOKEN_COMMENT;
        }
        free(module_path);
        return;
    }

    /* Collect all .cz.h files */
    char *includes_text = malloc(4096);
    if (!includes_text) {
        closedir(dir);
        free(module_path);
        return;
    }

    includes_text[0] = '\0';
    size_t text_len = 0;
    size_t text_capacity = 4096;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        /* Check if file ends with .cz.h */
        size_t name_len = strlen(entry->d_name);
        if (name_len > 5 && strcmp(entry->d_name + name_len - 5, ".cz.h") == 0) {
            /* Generate #include directive */
            char include_line[512];
            snprintf(include_line, sizeof(include_line), "#include \"%s/%s\"\n", module_path, entry->d_name);

            size_t line_len = strlen(include_line);
            /* Expand buffer if needed */
            if (text_len + line_len + 1 > text_capacity) {
                text_capacity *= 2;
                char *new_buf = realloc(includes_text, text_capacity);
                if (!new_buf) {
                    free(includes_text);
                    closedir(dir);
                    free(module_path);
                    return;
                }
                includes_text = new_buf;
            }

            strcat(includes_text, include_line);
            text_len += line_len;
        }
    }
    closedir(dir);

    /* If we found no headers, add a comment */
    if (text_len == 0) {
        snprintf(includes_text, text_capacity, "/* #import \"%s\" - no headers found */", module_path);
    }

    /* Replace the #import with the includes */
    free(node->token.text);
    node->token.text = includes_text;
    node->token.length = strlen(includes_text);
    node->token.type = TOKEN_PREPROCESSOR;

    free(module_path);
}

/* Transform #import directives to #include directives recursively */
static void transform_imports_recursive(ASTNode *node, ModuleContext *ctx) {
    if (!node) return;

    /* Transform if this is an import directive */
    if (is_import_directive(node)) {
        transform_import_node(node, ctx);
    }

    /* Recursively process children */
    for (size_t i = 0; i < node->child_count; i++) {
        transform_imports_recursive(node->children[i], ctx);
    }
}

/* Transform #import directives to #include directives in AST */
void transpiler_transform_imports(ASTNode *ast, ModuleContext *ctx) {
    if (!ast || !ctx) return;
    transform_imports_recursive(ast, ctx);
}

/* Split a generated .cz.c file into .cz.h (declarations) and update .cz.c (implementations + include) */
int transpiler_split_c_file(const char *c_file_path) {
    if (!c_file_path) return 0;

    /* Read the .c file */
    FILE *input = fopen(c_file_path, "r");
    if (!input) return 0;

    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    fseek(input, 0, SEEK_SET);

    if (size <= 0) {
        fclose(input);
        return 0;
    }

    char *content = malloc(size + 1);
    if (!content) {
        fclose(input);
        return 0;
    }

    size_t bytes_read = fread(content, 1, size, input);
    content[bytes_read] = '\0';
    fclose(input);

    /* Create header file path: file.cz.c -> file.cz.h */
    char header_path[1024];
    snprintf(header_path, sizeof(header_path), "%.*sh", (int)(strlen(c_file_path) - 1), c_file_path);

    /* Open header file for writing */
    FILE *header = fopen(header_path, "w");
    if (!header) {
        free(content);
        return 0;
    }

    /* Write header guard and includes */
    fprintf(header, "/* Generated header */\n");
    fprintf(header, "#pragma once\n\n");
    fprintf(header, "#include <stdint.h>\n");
    fprintf(header, "#include <stddef.h>\n");
    fprintf(header, "#include <stdbool.h>\n\n");

    /* Open temporary file for new .c content */
    char temp_path[1024];
    snprintf(temp_path, sizeof(temp_path), "%s.tmp", c_file_path);
    FILE *temp_c = fopen(temp_path, "w");
    if (!temp_c) {
        fclose(header);
        free(content);
        return 0;
    }

    /* Write the runtime header to .c file */
    char *p = content;
    char *user_code_start = strstr(content, "/* Module system:");
    if (!user_code_start) {
        /* Fallback: look for first user function */
        user_code_start = content;
        while (*user_code_start && strncmp(user_code_start, "\nint", 4) != 0 &&
               strncmp(user_code_start, "\nenum", 5) != 0 &&
               strncmp(user_code_start, "\ntypedef struct", 15) != 0) {
            user_code_start++;
        }
    }

    /* Write runtime to .c file */
    if (user_code_start > content) {
        fwrite(content, 1, user_code_start - content, temp_c);
    }

    /* Add include of own header */
    char *filename = strrchr(c_file_path, '/');
    if (!filename) filename = (char*)c_file_path;
    else filename++;

    char header_name[256];
    snprintf(header_name, sizeof(header_name), "%.*sh", (int)(strlen(filename) - 1), filename);
    fprintf(temp_c, "\n#include \"%s\"\n\n", header_name);

    /* Process user code: extract declarations to header, keep implementations in .c */
    p = user_code_start;
    while (*p) {
        /* Skip whitespace and comments */
        while (*p == ' ' || *p == '\t' || *p == '\n') {
            fputc(*p, temp_c);
            p++;
        }
        if (!*p) break;

        /* Skip line comments */
        if (*p == '/' && *(p+1) == '/') {
            while (*p && *p != '\n') {
                fputc(*p, temp_c);
                p++;
            }
            if (*p) {
                fputc(*p, temp_c);
                p++;
            }
            continue;
        }

        /* Skip block comments */
        if (*p == '/' && *(p+1) == '*') {
            while (*p && !(*p == '*' && *(p+1) == '/')) {
                fputc(*p, temp_c);
                p++;
            }
            if (*p) {
                fputc(*p, temp_c);
                p++;
                if (*p) {
                    fputc(*p, temp_c);
                    p++;
                }
            }
            continue;
        }

        /* Handle preprocessor directives - copy to .c only */
        if (*p == '#') {
            while (*p && *p != '\n') {
                fputc(*p, temp_c);
                p++;
            }
            if (*p) {
                fputc(*p, temp_c);
                p++;
            }
            continue;
        }

        char *decl_start = p;

        /* Check for typedef struct */
        if (strncmp(p, "typedef struct", 14) == 0) {
            int brace_count = 0;
            while (*p && !(brace_count == 0 && *p == ';')) {
                if (*p == '{') brace_count++;
                if (*p == '}') brace_count--;
                p++;
            }
            if (*p == ';') p++;
            /* Write to header */
            fprintf(header, "%.*s\n\n", (int)(p - decl_start), decl_start);
            /* Don't write to .c */
            continue;
        }

        /* Check for enum definition (not a function returning an enum) */
        if (strncmp(p, "enum ", 5) == 0) {
            /* Check if this is an enum definition (has opening brace) or a function return type */
            char *check_p = p + 5;
            int is_enum_def = 0;

            /* Skip enum name */
            while (*check_p && (*check_p == ' ' || *check_p == '\t' ||
                               (*check_p >= 'a' && *check_p <= 'z') ||
                               (*check_p >= 'A' && *check_p <= 'Z') ||
                               (*check_p >= '0' && *check_p <= '9') ||
                               *check_p == '_')) {
                check_p++;
            }

            /* Skip whitespace */
            while (*check_p && (*check_p == ' ' || *check_p == '\t' || *check_p == '\n')) check_p++;

            /* If we find '{', it's an enum definition */
            if (*check_p == '{') {
                is_enum_def = 1;
            }

            if (is_enum_def) {
                int brace_count = 0;
                int found_brace = 0;
                while (*p && !found_brace) {
                    if (*p == '{') {
                        found_brace = 1;
                        brace_count = 1;
                    }
                    p++;
                }
                if (found_brace) {
                    while (*p && brace_count > 0) {
                        if (*p == '{') brace_count++;
                        if (*p == '}') brace_count--;
                        p++;
                    }
                    while (*p && *p != ';') p++;
                    if (*p == ';') p++;
                    /* Write to header */
                    fprintf(header, "%.*s\n\n", (int)(p - decl_start), decl_start);
                    /* Don't write to .c */
                    continue;
                }
            }
        }

        /* Check for simple typedef */
        if (strncmp(p, "typedef ", 8) == 0 && strstr(p, "struct") != p + 8) {
            while (*p && *p != ';') p++;
            if (*p == ';') p++;
            /* Write to header */
            fprintf(header, "%.*s\n", (int)(p - decl_start), decl_start);
            /* Don't write to .c */
            continue;
        }

        /* Check for function definition */
        /* Look for pattern: type name(...) { on same or next few lines */
        char *line_p = p;
        char *paren = NULL;
        char *brace = NULL;
        int found_function = 0;

        /* Scan ahead to find ( and { within reasonable distance */
        int chars_scanned = 0;
        while (*line_p && chars_scanned < 200) {
            if (*line_p == '(') {
                paren = line_p;
            } else if (*line_p == '{' && paren) {
                brace = line_p;
                found_function = 1;
                break;
            } else if (*line_p == ';') {
                /* Hit semicolon before brace, not a function definition */
                break;
            }
            line_p++;
            chars_scanned++;
        }

        if (found_function && paren && brace) {
            /* This is a function definition */
            /* Write signature to header */
            fprintf(header, "%.*s;\n", (int)(brace - decl_start), decl_start);

            /* Write full function to .c */
            while (decl_start < brace) {
                fputc(*decl_start, temp_c);
                decl_start++;
            }
            fputc(*brace, temp_c);
            p = brace + 1;

            /* Copy function body to .c */
            int brace_count = 1;
            while (*p && brace_count > 0) {
                if (*p == '{') brace_count++;
                if (*p == '}') brace_count--;
                fputc(*p, temp_c);
                p++;
            }
            continue;
        }

        /* Default: copy to .c */
        fputc(*p, temp_c);
        p++;
    }

    fclose(header);
    fclose(temp_c);
    free(content);

    /* Replace original .c file with temp file */
    remove(c_file_path);
    rename(temp_path, c_file_path);

    fprintf(stdout, "%s %s", c_file_path, header_path);

    return 1;
}
