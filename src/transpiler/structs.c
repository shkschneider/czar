/*
 * CZar - C semantic authority layer
 * Struct typedef transformation implementation (transpiler/structs.c)
 *
 * Handles automatic typedef generation for named structs.
 * Transforms: struct Name { ... }; into typedef struct { ... } Name;
 */

#define _POSIX_C_SOURCE 200809L

#include "structs.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: struct identifier { ... }; */
    /* Transform to: typedef struct { ... } identifier; */

    for (size_t i = 0; i < ast->child_count; i++) {
        /* Need at least: struct, whitespace, identifier, whitespace, { */
        if (i + 4 >= ast->child_count) {
            continue;
        }

        ASTNode *n1 = ast->children[i];
        ASTNode *n2 = ast->children[i + 1];
        ASTNode *n3 = ast->children[i + 2];

        if (n1->type != AST_TOKEN || n2->type != AST_TOKEN || n3->type != AST_TOKEN) {
            continue;
        }

        Token *t1 = &n1->token;
        Token *t2 = &n2->token;
        Token *t3 = &n3->token;

        /* Check for: struct <whitespace> identifier */
        if (t1->type == TOKEN_IDENTIFIER && t1->text && strcmp(t1->text, "struct") == 0 &&
            t2->type == TOKEN_WHITESPACE &&
            t3->type == TOKEN_IDENTIFIER) {

            /* Look ahead to find the opening brace { - it should be immediately after the struct name */
            /* Pattern: struct Name { (with optional whitespace) */
            /* We want to reject: struct Name x = { (variable declaration) */
            size_t brace_idx = 0;
            int found_brace = 0;
            int found_other = 0;
            for (size_t j = i + 3; j < ast->child_count && j < i + 10; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_WHITESPACE || tj->type == TOKEN_COMMENT) {
                        continue; /* Skip whitespace and comments */
                    }
                    if (tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, "{") == 0) {
                        brace_idx = j;
                        found_brace = 1;
                        break;
                    }
                    /* If we find anything else (identifier, =, etc), this is not a struct definition */
                    found_other = 1;
                    break;
                }
            }

            if (!found_brace || found_other) {
                continue; /* Not a struct definition */
            }

            /* Find the closing brace and semicolon */
            int brace_depth = 0;
            size_t closing_brace_idx = 0;
            for (size_t j = brace_idx; j < ast->child_count; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_PUNCTUATION) {
                        if (tj->text && strcmp(tj->text, "{") == 0) {
                            brace_depth++;
                        } else if (tj->text && strcmp(tj->text, "}") == 0) {
                            brace_depth--;
                            if (brace_depth == 0) {
                                closing_brace_idx = j;
                                break;
                            }
                        }
                    }
                }
            }

            if (closing_brace_idx == 0) {
                continue; /* Couldn't find matching closing brace */
            }

            /* Now we have a valid struct definition from i to closing_brace_idx */
            /* Transform: struct Name { ... } to typedef struct Name { ... } Name */
            /* This allows both "struct Name" and "Name" to be used */

            /* Step 1: Save the struct name (t3->text) - we'll need it twice */
            char *struct_name = strdup(t3->text);
            if (!struct_name) {
                continue; /* Memory allocation failed */
            }

            /* Step 2: Replace "struct" with "typedef struct" */
            char *new_text = strdup("typedef struct");
            if (new_text) {
                free(t1->text);
                t1->text = new_text;
                t1->length = strlen(new_text);
            }

            /* Step 3: Keep the struct name after struct keyword (DON'T make it anonymous) */
            /* This allows "struct Name" to still work */

            /* Step 4: After the closing brace, add the typedef name */
            /* Look for whitespace and semicolon after closing brace */
            size_t semicolon_idx = 0;
            for (size_t j = closing_brace_idx + 1; j < ast->child_count && j < closing_brace_idx + 5; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, ";") == 0) {
                        semicolon_idx = j;
                        break;
                    }
                }
            }

            if (semicolon_idx > 0) {
                /* Insert the struct name before the semicolon */
                /* Find the token right before semicolon (should be whitespace or closing brace) */
                size_t insert_pos = semicolon_idx;

                /* We need to insert: " Name" before the semicolon */
                /* Create a new token for the space */
                ASTNode *space_node = malloc(sizeof(ASTNode));
                if (space_node) {
                    space_node->type = AST_TOKEN;
                    space_node->token.type = TOKEN_WHITESPACE;
                    space_node->token.text = strdup(" ");
                    space_node->token.length = 1;
                    space_node->token.line = t1->line;
                    space_node->token.column = 0;
                    space_node->children = NULL;
                    space_node->child_count = 0;
                    space_node->child_capacity = 0;
                }

                /* Create a new token for the name */
                ASTNode *name_node = malloc(sizeof(ASTNode));
                if (name_node) {
                    name_node->type = AST_TOKEN;
                    name_node->token.type = TOKEN_IDENTIFIER;
                    name_node->token.text = struct_name; /* Transfer ownership */
                    name_node->token.length = strlen(struct_name);
                    name_node->token.line = t1->line;
                    name_node->token.column = 0;
                    name_node->children = NULL;
                    name_node->child_count = 0;
                    name_node->child_capacity = 0;

                    /* Insert the nodes before the semicolon */
                    /* We need to grow the children array and shift elements */
                    size_t new_count = ast->child_count + 2;
                    if (new_count > ast->child_capacity) {
                        size_t new_capacity = new_count * 2;
                        ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
                        if (new_children) {
                            ast->children = new_children;
                            ast->child_capacity = new_capacity;
                        } else {
                            /* Memory allocation failed, clean up */
                            free(space_node);
                            free(name_node);
                            free(struct_name);
                            continue;
                        }
                    }

                    /* Shift elements to make room */
                    for (size_t j = ast->child_count; j > insert_pos; j--) {
                        ast->children[j + 1] = ast->children[j - 1];
                    }

                    /* Insert the new nodes */
                    ast->children[insert_pos] = space_node;
                    ast->children[insert_pos + 1] = name_node;
                    ast->child_count += 2;

                    /* Skip ahead so we don't process this struct again */
                    i = semicolon_idx + 2;
                } else {
                    free(struct_name);
                    if (space_node) free(space_node);
                }
            } else {
                free(struct_name);
            }
        }
    }
}
