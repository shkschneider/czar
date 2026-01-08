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
    
    /* Simple text-based extraction of declarations */
    /* Look for function declarations: lines that contain '(' followed by ')' and '{' */
    char *p = content;
    while (*p) {
        /* Skip whitespace and comments */
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (*p == '/' && *(p+1) == '/') {
            /* Skip line comment */
            while (*p && *p != '\n') p++;
            continue;
        }
        
        /* Check for function definition */
        char *line_start = p;
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
            /* Extract the function signature */
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
            /* Not a function, move to next line */
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
    
    /* For now, generate a single #include statement */
    /* In a full implementation, we would scan the directory and include all .cz.h files */
    size_t new_size = strlen(module_path) + 256;
    char *new_text = malloc(new_size);
    if (new_text) {
        /* Generate #include for the module directory */
        /* Pattern: #import "lib" becomes includes for lib/ *.cz.h files */
        /* For now, we'll generate a placeholder that at least compiles */
        snprintf(new_text, new_size, "/* #import \"%s\" - module system placeholder */", module_path);
        
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
