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

/* Check if character is valid in a C identifier */
__attribute__((unused)) static int is_c_identifier_char(char c, int first) {
    if (first) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
    }
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || 
           (c >= '0' && c <= '9') || c == '_';
}

/* Check if node represents a function declaration */
__attribute__((unused)) static int is_function_declaration(ASTNode *node, size_t index) {
    if (!node || index >= node->child_count) return 0;
    
    /* Look for pattern: type identifier ( ... ) { or ; */
    /* This is a simple heuristic */
    for (size_t i = index; i < node->child_count && i < index + 20; i++) {
        ASTNode *child = node->children[i];
        if (child && child->type == AST_TOKEN) {
            if (child->token.type == TOKEN_PUNCTUATION && 
                strcmp(child->token.text, "(") == 0) {
                return 1;
            }
            if (child->token.type == TOKEN_PUNCTUATION && 
                (strcmp(child->token.text, ";") == 0 || 
                 strcmp(child->token.text, ",") == 0)) {
                return 0;
            }
        }
    }
    return 0;
}

/* Check if node represents a struct/enum declaration */
__attribute__((unused)) static int is_struct_or_enum_declaration(ASTNode *node, size_t index) {
    if (!node || index >= node->child_count) return 0;
    
    ASTNode *child = node->children[index];
    if (!child || child->type != AST_TOKEN) return 0;
    if (child->token.type != TOKEN_KEYWORD) return 0;
    
    const char *text = child->token.text;
    return strcmp(text, "struct") == 0 || 
           strcmp(text, "enum") == 0 ||
           strcmp(text, "typedef") == 0;
}

/* Extract declaration for header (simple version) */
__attribute__((unused)) static void extract_declaration_for_header(ASTNode *node, size_t start_idx, FILE *output) {
    if (!node || !output) return;
    
    int brace_depth = 0;
    int paren_depth = 0;
    int found_semicolon = 0;
    
    /* Write tokens until we find the end of declaration */
    for (size_t i = start_idx; i < node->child_count && !found_semicolon; i++) {
        ASTNode *child = node->children[i];
        if (!child || child->type != AST_TOKEN) continue;
        
        /* Track braces and parens */
        if (child->token.type == TOKEN_PUNCTUATION) {
            if (strcmp(child->token.text, "{") == 0) {
                brace_depth++;
                /* For function declarations, replace body with ; */
                if (paren_depth == 0 && brace_depth == 1) {
                    fprintf(output, ";\n");
                    found_semicolon = 1;
                    break;
                }
            } else if (strcmp(child->token.text, "}") == 0) {
                brace_depth--;
                if (brace_depth < 0) break;
                /* Write the closing brace for struct/enum */
                fwrite(child->token.text, 1, child->token.length, output);
                continue;
            } else if (strcmp(child->token.text, "(") == 0) {
                paren_depth++;
            } else if (strcmp(child->token.text, ")") == 0) {
                paren_depth--;
            } else if (strcmp(child->token.text, ";") == 0 && brace_depth == 0) {
                fwrite(child->token.text, 1, child->token.length, output);
                fprintf(output, "\n");
                found_semicolon = 1;
                break;
            }
        }
        
        /* Skip function bodies */
        if (brace_depth > 0 && paren_depth == 0) {
            continue;
        }
        
        /* Write token */
        if (child->token.text && child->token.length > 0) {
            fwrite(child->token.text, 1, child->token.length, output);
        }
    }
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
    
    /* Parse the content (simplified - just extract function and struct declarations) */
    FILE *output = fopen(output_header_path, "w");
    if (!output) {
        free(content);
        return 0;
    }
    
    /* Write header guard */
    fprintf(output, "#pragma once\n\n");
    
    /* Write necessary includes for CZar types */
    fprintf(output, "#include <stdint.h>\n");
    fprintf(output, "#include <stddef.h>\n");
    fprintf(output, "#include <stdbool.h>\n\n");
    
    /* Simple approach: write the whole file but remove function bodies */
    /* This is a simplified version - ideally would parse and extract only declarations */
    fprintf(output, "/* Generated header from %s */\n\n", cz_file_path);
    
    /* TODO: Properly parse and extract declarations */
    /* For now, we'll do a simple text-based extraction */
    
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
    
    /* Build new #include directive */
    /* Transform #import "lib" to #include for generated headers */
    /* For now, we'll just transform to a comment noting what needs to be done */
    
    /* Create new text for #include */
    size_t new_size = strlen(module_path) + 256;
    char *new_text = malloc(new_size);
    if (new_text) {
        /* For now, just comment it out and add a note */
        snprintf(new_text, new_size, "/* #import \"%s\" - TODO: include generated headers */", module_path);
        
        free(node->token.text);
        node->token.text = new_text;
        node->token.length = strlen(new_text);
        node->token.type = TOKEN_COMMENT;
    }
    
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
