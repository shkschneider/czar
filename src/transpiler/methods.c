/*
 * CZar - C semantic authority layer
 * Struct methods transformation implementation (transpiler/methods.c)
 *
 * Handles transformation of struct methods:
 * - Method declarations: RetType StructName.method() -> RetType StructName_method(StructName* self)
 * - Method calls: instance.method() -> StructName_method(&instance)
 * - Static method calls: StructName.method(&v) -> StructName_method(&v)
 */

#include "../cz.h"
#include "methods.h"
#include "../warnings.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

/* Maximum number of methods we can track */
#define MAX_METHODS 256

/* Maximum number of struct types we can track */
#define MAX_STRUCT_TYPES 128

/* Tracked method information */
typedef struct {
    char *struct_name;  /* e.g., "Vec2" */
    char *method_name;  /* e.g., "length" */
} MethodInfo;

/* Tracked struct type information */
typedef struct {
    char *name;  /* struct type name */
} StructType;

/* Global state for tracking methods and struct types */
static MethodInfo methods[MAX_METHODS];
static size_t method_count = 0;
static StructType struct_types[MAX_STRUCT_TYPES];
static size_t struct_type_count = 0;

/* Add a method to tracking */
static void track_method(const char *struct_name, const char *method_name) {
    if (method_count >= MAX_METHODS) {
        fprintf(stderr, "Warning: " WARN_MAX_METHOD_TRACKING_LIMIT "\n", MAX_METHODS);
        return;
    }

    /* Check if already tracked */
    for (size_t i = 0; i < method_count; i++) {
        if (methods[i].struct_name && methods[i].method_name &&
            strcmp(methods[i].struct_name, struct_name) == 0 &&
            strcmp(methods[i].method_name, method_name) == 0) {
            return;
        }
    }

    /* Add new method */
    char *struct_name_copy = strdup(struct_name);
    char *method_name_copy = strdup(method_name);
    if (!struct_name_copy || !method_name_copy) {
        /* Memory allocation failed, clean up and return */
        free(struct_name_copy);
        free(method_name_copy);
        return;
    }

    methods[method_count].struct_name = struct_name_copy;
    methods[method_count].method_name = method_name_copy;
    method_count++;
}

/* Check if a method is tracked */
static int is_tracked_method(const char *struct_name, const char *method_name) {
    for (size_t i = 0; i < method_count; i++) {
        if (methods[i].struct_name && methods[i].method_name &&
            strcmp(methods[i].struct_name, struct_name) == 0 &&
            strcmp(methods[i].method_name, method_name) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Add a struct type to tracking */
static void track_struct_type(const char *name) {
    if (struct_type_count >= MAX_STRUCT_TYPES) {
        fprintf(stderr, "Warning: " WARN_MAX_STRUCT_TYPE_TRACKING_LIMIT "\n", MAX_STRUCT_TYPES);
        return;
    }

    /* Check if already tracked */
    for (size_t i = 0; i < struct_type_count; i++) {
        if (struct_types[i].name && strcmp(struct_types[i].name, name) == 0) {
            return;
        }
    }

    /* Add new struct type */
    char *name_copy = strdup(name);
    if (!name_copy) {
        return;
    }

    struct_types[struct_type_count].name = name_copy;
    struct_type_count++;
}

/* Check if an identifier is a known struct type */
static int is_struct_type(const char *name) {
    for (size_t i = 0; i < struct_type_count; i++) {
        if (struct_types[i].name && strcmp(struct_types[i].name, name) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Clear tracking */
static void clear_tracking(void) {
    for (size_t i = 0; i < method_count; i++) {
        free(methods[i].struct_name);
        free(methods[i].method_name);
    }
    method_count = 0;

    for (size_t i = 0; i < struct_type_count; i++) {
        free(struct_types[i].name);
    }
    struct_type_count = 0;
}

/* Helper: Skip whitespace and comments in token stream */
static size_t skip_whitespace(ASTNode *ast, size_t start, size_t max) {
    for (size_t i = start; i < ast->child_count && i < max; i++) {
        if (ast->children[i]->type == AST_TOKEN) {
            Token *t = &ast->children[i]->token;
            if (t->type != TOKEN_WHITESPACE && t->type != TOKEN_COMMENT) {
                return i;
            }
        }
    }
    return ast->child_count;
}

/* Helper: Find the next non-whitespace token */
static ASTNode* get_next_non_ws_node(ASTNode *ast, size_t start, size_t *out_idx) {
    size_t idx = skip_whitespace(ast, start, ast->child_count);
    if (out_idx) *out_idx = idx;
    if (idx < ast->child_count) {
        return ast->children[idx];
    }
    return NULL;
}

/* First pass: Scan for struct definitions to track struct types */
static void scan_struct_definitions(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            continue;
        }

        Token *t = &ast->children[i]->token;

        /* Look for: struct StructName { or typedef struct StructName { */
        if (t->type == TOKEN_IDENTIFIER && t->text &&
            (strcmp(t->text, "struct") == 0 || strcmp(t->text, "typedef struct") == 0)) {

            /* Get next non-whitespace token (struct name) */
            size_t name_idx;
            ASTNode *name_node = get_next_non_ws_node(ast, i + 1, &name_idx);
            if (!name_node || name_node->type != AST_TOKEN) {
                continue;
            }

            Token *name_token = &name_node->token;
            if (name_token->type == TOKEN_IDENTIFIER && name_token->text) {
                /* Check if followed by { to ensure it's a definition */
                size_t brace_idx;
                ASTNode *brace_node = get_next_non_ws_node(ast, name_idx + 1, &brace_idx);
                if (brace_node && brace_node->type == AST_TOKEN) {
                    Token *brace_token = &brace_node->token;
                    if (brace_token->type == TOKEN_PUNCTUATION && brace_token->text &&
                        strcmp(brace_token->text, "{") == 0) {
                        /* This is a struct definition */
                        /* Extract base name if it ends with _s (from new typedef format) */
                        char *base_name = strdup(name_token->text);
                        if (base_name) {
                            size_t len = strlen(base_name);
                            if (len > 2 && strcmp(base_name + len - 2, "_s") == 0) {
                                /* Remove _s suffix to get base name for methods */
                                base_name[len - 2] = '\0';
                            }
                            track_struct_type(base_name);
                            free(base_name);
                        }

                        /* Find closing brace and check for typedef name */
                        int brace_depth = 0;
                        size_t closing_brace_idx = 0;
                        for (size_t j = brace_idx; j < ast->child_count; j++) {
                            if (ast->children[j]->type == AST_TOKEN) {
                                Token *tj = &ast->children[j]->token;
                                if (tj->type == TOKEN_PUNCTUATION && tj->text) {
                                    if (strcmp(tj->text, "{") == 0) {
                                        brace_depth++;
                                    } else if (strcmp(tj->text, "}") == 0) {
                                        brace_depth--;
                                        if (brace_depth == 0) {
                                            closing_brace_idx = j;
                                            break;
                                        }
                                    }
                                }
                            }
                        }

                        /* Check for typedef name after closing brace */
                        if (closing_brace_idx > 0) {
                            size_t typedef_name_idx;
                            ASTNode *typedef_name_node = get_next_non_ws_node(ast, closing_brace_idx + 1, &typedef_name_idx);
                            if (typedef_name_node && typedef_name_node->type == AST_TOKEN) {
                                Token *typedef_name_token = &typedef_name_node->token;
                                if (typedef_name_token->type == TOKEN_IDENTIFIER && typedef_name_token->text) {
                                    /* Track the typedef name too, stripping _t suffix if present */
                                    char *typedef_base = strdup(typedef_name_token->text);
                                    if (typedef_base) {
                                        size_t len = strlen(typedef_base);
                                        if (len > 2 && strcmp(typedef_base + len - 2, "_t") == 0) {
                                            /* Remove _t suffix to get base name for methods */
                                            typedef_base[len - 2] = '\0';
                                        }
                                        track_struct_type(typedef_base);
                                        free(typedef_base);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/* Second pass: Transform method declarations */
static void transform_method_declarations(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: ReturnType StructName.methodName(...) { */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (i + 2 >= ast->child_count) {
            continue;
        }

        /* Look for identifier followed by . */
        ASTNode *n1 = ast->children[i];
        if (n1->type != AST_TOKEN || n1->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        /* Skip whitespace */
        size_t dot_idx = skip_whitespace(ast, i + 1, ast->child_count);
        if (dot_idx >= ast->child_count) {
            continue;
        }

        ASTNode *dot_node = ast->children[dot_idx];
        if (dot_node->type != AST_TOKEN ||
            (dot_node->token.type != TOKEN_PUNCTUATION && dot_node->token.type != TOKEN_OPERATOR) ||
            !dot_node->token.text || strcmp(dot_node->token.text, ".") != 0) {
            continue;
        }

        /* Get the identifier after the dot */
        size_t method_idx = skip_whitespace(ast, dot_idx + 1, ast->child_count);
        if (method_idx >= ast->child_count) {
            continue;
        }

        ASTNode *method_node = ast->children[method_idx];
        if (method_node->type != AST_TOKEN || method_node->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        /* Check if followed by ( to confirm it's a function declaration */
        size_t paren_idx = skip_whitespace(ast, method_idx + 1, ast->child_count);
        if (paren_idx >= ast->child_count) {
            continue;
        }

        ASTNode *paren_node = ast->children[paren_idx];
        if (paren_node->type != AST_TOKEN || paren_node->token.type != TOKEN_PUNCTUATION ||
            !paren_node->token.text || strcmp(paren_node->token.text, "(") != 0) {
            continue;
        }

        /* Check if the identifier before the dot is a known struct type */
        const char *struct_name = n1->token.text;
        const char *method_name = method_node->token.text;

        if (!is_struct_type(struct_name)) {
            continue;
        }

        /* Check if this is a function definition (has a body {...}) or just a call */
        /* First, find the closing paren to see if there's a brace after it */
        int paren_depth = 0;
        size_t close_paren_idx = paren_idx;
        int has_params = 0;

        for (size_t j = paren_idx; j < ast->child_count; j++) {
            if (ast->children[j]->type == AST_TOKEN) {
                Token *tj = &ast->children[j]->token;
                if (tj->type == TOKEN_PUNCTUATION && tj->text) {
                    if (strcmp(tj->text, "(") == 0) {
                        paren_depth++;
                    } else if (strcmp(tj->text, ")") == 0) {
                        paren_depth--;
                        if (paren_depth == 0) {
                            close_paren_idx = j;
                            break;
                        }
                    }
                }
                /* Check if there's any non-whitespace content between parens */
                if (paren_depth > 0 && j > paren_idx) {
                    if (tj->type != TOKEN_WHITESPACE && tj->type != TOKEN_COMMENT &&
                        !(tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, ")") == 0)) {
                        has_params = 1;
                    }
                }
            }
        }

        /* Check if there's a function body after the closing paren */
        /* Look for { after the ) */
        size_t brace_idx;
        ASTNode *brace_node = get_next_non_ws_node(ast, close_paren_idx + 1, &brace_idx);
        if (!brace_node || brace_node->type != AST_TOKEN ||
            brace_node->token.type != TOKEN_PUNCTUATION ||
            !brace_node->token.text || strcmp(brace_node->token.text, "{") != 0) {
            /* Not a function definition, skip - this is just a method call */
            continue;
        }

        /* This is a method declaration! Now we can transform it. */
        /* Save copies of names before modifying tokens */
        char *struct_name_copy = strdup(struct_name);
        char *method_name_copy = strdup(method_name);
        if (!struct_name_copy || !method_name_copy) {
            free(struct_name_copy);
            free(method_name_copy);
            continue;
        }

        track_method(struct_name_copy, method_name_copy);

        /* Step 1: Replace "StructName.methodName" with "StructName_methodName" */
        size_t new_name_len = strlen(struct_name_copy) + 1 + strlen(method_name_copy) + 1;
        char *new_name = malloc(new_name_len);
        if (new_name) {
            snprintf(new_name, new_name_len, "%s_%s", struct_name_copy, method_name_copy);

            /* Replace the struct name token with the combined name */
            free(n1->token.text);
            n1->token.text = new_name;
            n1->token.length = strlen(new_name);

            /* Remove the dot and method name tokens */
            /* Mark them for removal by setting text to NULL */
            if (dot_node->token.text) {
                free(dot_node->token.text);
                dot_node->token.text = strdup("");
                dot_node->token.length = 0;
            }
            if (method_node->token.text) {
                free(method_node->token.text);
                method_node->token.text = strdup("");
                method_node->token.length = 0;
            }
        }

        /* Step 2: Add self parameter */

        /* Create struct name token */
        ASTNode *struct_name_node = malloc(sizeof(ASTNode));
        if (!struct_name_node) {
            free(struct_name_copy);
            free(method_name_copy);
            continue;
        }
        struct_name_node->type = AST_TOKEN;
        struct_name_node->token.type = TOKEN_IDENTIFIER;
        struct_name_node->token.text = struct_name_copy; /* Transfer ownership */
        struct_name_node->token.length = strlen(struct_name_copy);
        struct_name_node->token.line = n1->token.line;
        struct_name_node->token.column = 0;
        struct_name_node->children = NULL;
        struct_name_node->child_count = 0;
        struct_name_node->child_capacity = 0;

        /* Create pointer token */
        ASTNode *ptr_node = malloc(sizeof(ASTNode));
        if (!ptr_node) {
            free(struct_name_node);
            free(method_name_copy);
            continue;
        }
        ptr_node->type = AST_TOKEN;
        ptr_node->token.type = TOKEN_OPERATOR;
        ptr_node->token.text = strdup("*");
        ptr_node->token.length = 1;
        ptr_node->token.line = n1->token.line;
        ptr_node->token.column = 0;
        ptr_node->children = NULL;
        ptr_node->child_count = 0;
        ptr_node->child_capacity = 0;

        /* Create space token */
        ASTNode *space_node = malloc(sizeof(ASTNode));
        if (!space_node) {
            free(struct_name_node);
            free(ptr_node);
            free(method_name_copy);
            continue;
        }
        space_node->type = AST_TOKEN;
        space_node->token.type = TOKEN_WHITESPACE;
        space_node->token.text = strdup(" ");
        space_node->token.length = 1;
        space_node->token.line = n1->token.line;
        space_node->token.column = 0;
        space_node->children = NULL;
        space_node->child_count = 0;
        space_node->child_capacity = 0;

        /* Create self token */
        ASTNode *self_node = malloc(sizeof(ASTNode));
        if (!self_node) {
            free(struct_name_node);
            free(ptr_node);
            free(space_node);
            free(method_name_copy);
            continue;
        }
        self_node->type = AST_TOKEN;
        self_node->token.type = TOKEN_IDENTIFIER;
        self_node->token.text = strdup("self");
        self_node->token.length = 4;
        self_node->token.line = n1->token.line;
        self_node->token.column = 0;
        self_node->children = NULL;
        self_node->child_count = 0;
        self_node->child_capacity = 0;

        /* If there are existing params, add "," and " " after self */
        ASTNode *comma_node = NULL;
        ASTNode *comma_space_node = NULL;
        if (has_params) {
            comma_node = malloc(sizeof(ASTNode));
            if (!comma_node) {
                free(struct_name_node);
                free(ptr_node);
                free(space_node);
                free(self_node);
                free(method_name_copy);
                continue;
            }
            comma_node->type = AST_TOKEN;
            comma_node->token.type = TOKEN_PUNCTUATION;
            comma_node->token.text = strdup(",");
            comma_node->token.length = 1;
            comma_node->token.line = n1->token.line;
            comma_node->token.column = 0;
            comma_node->children = NULL;
            comma_node->child_count = 0;
            comma_node->child_capacity = 0;

            comma_space_node = malloc(sizeof(ASTNode));
            if (!comma_space_node) {
                free(struct_name_node);
                free(ptr_node);
                free(space_node);
                free(self_node);
                free(comma_node);
                free(method_name_copy);
                continue;
            }
            comma_space_node->type = AST_TOKEN;
            comma_space_node->token.type = TOKEN_WHITESPACE;
            comma_space_node->token.text = strdup(" ");
            comma_space_node->token.length = 1;
            comma_space_node->token.line = n1->token.line;
            comma_space_node->token.column = 0;
            comma_space_node->children = NULL;
            comma_space_node->child_count = 0;
            comma_space_node->child_capacity = 0;
        }

        /* Insert nodes after opening paren: StructName * space self [, space] */
        size_t insert_pos = paren_idx + 1;
        size_t nodes_to_insert = has_params ? 6 : 4; /* struct_name, *, space, self, [comma, space] */
        size_t new_count = ast->child_count + nodes_to_insert;

        if (new_count > ast->child_capacity) {
            size_t new_capacity = new_count * 2;
            ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
            if (new_children) {
                ast->children = new_children;
                ast->child_capacity = new_capacity;
            } else {
                free(struct_name_node);
                free(ptr_node);
                free(space_node);
                free(self_node);
                if (comma_node) free(comma_node);
                if (comma_space_node) free(comma_space_node);
                free(method_name_copy);
                continue;
            }
        }

        /* Shift elements */
        for (size_t j = ast->child_count; j > insert_pos; j--) {
            ast->children[j + nodes_to_insert - 1] = ast->children[j - 1];
        }

        /* Insert self parameter tokens */
        ast->children[insert_pos] = struct_name_node;
        ast->children[insert_pos + 1] = ptr_node;
        ast->children[insert_pos + 2] = space_node;
        ast->children[insert_pos + 3] = self_node;
        if (has_params && comma_node && comma_space_node) {
            ast->children[insert_pos + 4] = comma_node;
            ast->children[insert_pos + 5] = comma_space_node;
        }
        ast->child_count += nodes_to_insert;

        /* Free the method name copy (struct name was transferred to node) */
        free(method_name_copy);

        /* Skip past this method declaration */
        i = close_paren_idx;
    }
}

/* Third pass: Transform method calls */
static void transform_method_calls(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: identifier.methodName(...) */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (i + 4 >= ast->child_count) {
            continue;
        }

        /* Look for identifier followed by . */
        ASTNode *n1 = ast->children[i];
        if (n1->type != AST_TOKEN || n1->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        /* Check for dot */
        size_t dot_idx = skip_whitespace(ast, i + 1, ast->child_count);
        if (dot_idx >= ast->child_count) {
            continue;
        }

        ASTNode *dot_node = ast->children[dot_idx];
        if (dot_node->type != AST_TOKEN ||
            (dot_node->token.type != TOKEN_PUNCTUATION && dot_node->token.type != TOKEN_OPERATOR) ||
            !dot_node->token.text || strcmp(dot_node->token.text, ".") != 0) {
            continue;
        }

        /* Get method name */
        size_t method_idx = skip_whitespace(ast, dot_idx + 1, ast->child_count);
        if (method_idx >= ast->child_count) {
            continue;
        }

        ASTNode *method_node = ast->children[method_idx];
        if (method_node->type != AST_TOKEN || method_node->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        /* Check for opening paren */
        size_t paren_idx = skip_whitespace(ast, method_idx + 1, ast->child_count);
        if (paren_idx >= ast->child_count) {
            continue;
        }

        ASTNode *paren_node = ast->children[paren_idx];
        if (paren_node->type != AST_TOKEN || paren_node->token.type != TOKEN_PUNCTUATION ||
            !paren_node->token.text || strcmp(paren_node->token.text, "(") != 0) {
            continue;
        }

        /* Check if this is a tracked method call */
        const char *instance_name = n1->token.text;
        const char *method_name = method_node->token.text;

        /* Save copies before modifying tokens */
        char *instance_name_copy = strdup(instance_name);
        if (!instance_name_copy) {
            continue;
        }

        /* We need to determine the struct type of the instance */
        /* For simplicity, we'll try all tracked struct types to see if the method exists */
        /* But skip this if the instance name itself is a struct type (static call) */
        char *struct_name = NULL;
        if (!is_struct_type(instance_name_copy)) {
            for (size_t j = 0; j < struct_type_count; j++) {
                if (is_tracked_method(struct_types[j].name, method_name)) {
                    struct_name = struct_types[j].name;
                    break;
                }
            }
        }

        if (!struct_name) {
            /* Also check if the instance name is itself a struct type (static call) */
            if (is_struct_type(instance_name_copy) && is_tracked_method(instance_name_copy, method_name)) {
                /* Static call: StructName.method(...) */
                /* Special case for Log struct: use cz_log_* naming */
                char *new_name = NULL;
                if (strcmp(instance_name_copy, "Log") == 0) {
                    /* Transform Log.method to cz_log_method */
                    size_t new_name_len = strlen("cz_log_") + strlen(method_name) + 1;
                    new_name = malloc(new_name_len);
                    if (new_name) {
                        snprintf(new_name, new_name_len, "cz_log_%s", method_name);
                    }
                } else {
                    /* Transform to: StructName_method(...) - no & needed, params are as-is */
                    size_t new_name_len = strlen(instance_name_copy) + 1 + strlen(method_name) + 1;
                    new_name = malloc(new_name_len);
                    if (new_name) {
                        snprintf(new_name, new_name_len, "%s_%s", instance_name_copy, method_name);
                    }
                }

                if (new_name) {
                    /* Replace instance name with combined name */
                    free(n1->token.text);
                    n1->token.text = new_name;
                    n1->token.length = strlen(new_name);

                    /* Remove dot and method name */
                    if (dot_node->token.text) {
                        free(dot_node->token.text);
                        dot_node->token.text = strdup("");
                        dot_node->token.length = 0;
                    }
                    if (method_node->token.text) {
                        free(method_node->token.text);
                        method_node->token.text = strdup("");
                        method_node->token.length = 0;
                    }
                }
                free(instance_name_copy);
                continue;
            }
            free(instance_name_copy);
            continue;
        }

        /* Instance method call: instance.method(...) */
        /* Transform to: StructName_method(&instance, ...) */

        /* Replace "instance.method" with "StructName_method" */
        size_t new_name_len = strlen(struct_name) + 1 + strlen(method_name) + 1;
        char *new_name = malloc(new_name_len);
        if (!new_name) {
            continue;
        }
        snprintf(new_name, new_name_len, "%s_%s", struct_name, method_name);

        free(n1->token.text);
        n1->token.text = new_name;
        n1->token.length = strlen(new_name);

        /* Remove dot and method name */
        if (dot_node->token.text) {
            free(dot_node->token.text);
            dot_node->token.text = strdup("");
            dot_node->token.length = 0;
        }
        if (method_node->token.text) {
            free(method_node->token.text);
            method_node->token.text = strdup("");
            method_node->token.length = 0;
        }

        /* Add &instance as first argument */
        /* Find if there are existing arguments */
        int paren_depth = 0;
        size_t close_paren_idx = paren_idx;
        int has_args = 0;

        for (size_t j = paren_idx; j < ast->child_count; j++) {
            if (ast->children[j]->type == AST_TOKEN) {
                Token *tj = &ast->children[j]->token;
                if (tj->type == TOKEN_PUNCTUATION && tj->text) {
                    if (strcmp(tj->text, "(") == 0) {
                        paren_depth++;
                    } else if (strcmp(tj->text, ")") == 0) {
                        paren_depth--;
                        if (paren_depth == 0) {
                            close_paren_idx = j;
                            break;
                        }
                    }
                }
                /* Check for non-whitespace content */
                if (paren_depth > 0 && j > paren_idx && tj->type != TOKEN_WHITESPACE && tj->type != TOKEN_COMMENT) {
                    if (!(tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, ")") == 0)) {
                        has_args = 1;
                    }
                }
            }
        }

        /* Create &instance as separate tokens */
        /* Create & token */
        ASTNode *addr_node = malloc(sizeof(ASTNode));
        if (!addr_node) {
            free(instance_name_copy);
            continue;
        }
        addr_node->type = AST_TOKEN;
        addr_node->token.type = TOKEN_OPERATOR;
        addr_node->token.text = strdup("&");
        addr_node->token.length = 1;
        addr_node->token.line = n1->token.line;
        addr_node->token.column = 0;
        addr_node->children = NULL;
        addr_node->child_count = 0;
        addr_node->child_capacity = 0;

        /* Create instance token */
        ASTNode *instance_node = malloc(sizeof(ASTNode));
        if (!instance_node) {
            free(addr_node);
            free(instance_name_copy);
            continue;
        }
        instance_node->type = AST_TOKEN;
        instance_node->token.type = TOKEN_IDENTIFIER;
        instance_node->token.text = instance_name_copy; /* Transfer ownership */
        instance_node->token.length = strlen(instance_name_copy);
        instance_node->token.line = n1->token.line;
        instance_node->token.column = 0;
        instance_node->children = NULL;
        instance_node->child_count = 0;
        instance_node->child_capacity = 0;

        /* If there are existing args, add "," and " " after instance */
        ASTNode *comma_node = NULL;
        ASTNode *comma_space_node = NULL;
        if (has_args) {
            comma_node = malloc(sizeof(ASTNode));
            if (!comma_node) {
                free(addr_node);
                free(instance_node);
                continue;
            }
            comma_node->type = AST_TOKEN;
            comma_node->token.type = TOKEN_PUNCTUATION;
            comma_node->token.text = strdup(",");
            comma_node->token.length = 1;
            comma_node->token.line = n1->token.line;
            comma_node->token.column = 0;
            comma_node->children = NULL;
            comma_node->child_count = 0;
            comma_node->child_capacity = 0;

            comma_space_node = malloc(sizeof(ASTNode));
            if (!comma_space_node) {
                free(addr_node);
                free(instance_node);
                free(comma_node);
                continue;
            }
            comma_space_node->type = AST_TOKEN;
            comma_space_node->token.type = TOKEN_WHITESPACE;
            comma_space_node->token.text = strdup(" ");
            comma_space_node->token.length = 1;
            comma_space_node->token.line = n1->token.line;
            comma_space_node->token.column = 0;
            comma_space_node->children = NULL;
            comma_space_node->child_count = 0;
            comma_space_node->child_capacity = 0;
        }

        /* Insert after opening paren: & instance [, space] */
        size_t insert_pos = paren_idx + 1;
        size_t nodes_to_insert = has_args ? 4 : 2; /* &, instance, [comma, space] */
        size_t new_count = ast->child_count + nodes_to_insert;

        if (new_count > ast->child_capacity) {
            size_t new_capacity = new_count * 2;
            ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
            if (new_children) {
                ast->children = new_children;
                ast->child_capacity = new_capacity;
            } else {
                free(addr_node);
                free(instance_node);
                if (comma_node) free(comma_node);
                if (comma_space_node) free(comma_space_node);
                continue;
            }
        }

        /* Shift elements */
        for (size_t j = ast->child_count; j > insert_pos; j--) {
            ast->children[j + nodes_to_insert - 1] = ast->children[j - 1];
        }

        /* Insert &instance tokens */
        ast->children[insert_pos] = addr_node;
        ast->children[insert_pos + 1] = instance_node;
        if (has_args && comma_node && comma_space_node) {
            ast->children[insert_pos + 2] = comma_node;
            ast->children[insert_pos + 3] = comma_space_node;
        }
        ast->child_count += nodes_to_insert;

        /* Skip past this method call */
        i = close_paren_idx;
    }
}

/* Transform struct method declarations and calls */
void transpiler_transform_methods(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    clear_tracking();

    /* Pre-register Log struct and its methods for runtime logging */
    track_struct_type("Log");
    track_method("Log", "verbose");
    track_method("Log", "debug");
    track_method("Log", "info");
    track_method("Log", "warning");
    track_method("Log", "error");
    track_method("Log", "fatal");

    /* Pass 1: Scan for struct definitions */
    scan_struct_definitions(ast);

    /* Pass 2: Transform method declarations */
    transform_method_declarations(ast);

    /* Pass 3: Transform method calls */
    transform_method_calls(ast);
}
