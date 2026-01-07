/*
 * CZar - C semantic authority layer
 * Struct typedef transformation implementation (transpiler/structs.c)
 *
 * Handles automatic typedef generation for named structs.
 * Transforms: struct Name { ... }; into typedef struct Name_s { ... } Name_t;
 * Replaces all uses of Name with Name_t in generated C code.
 * Methods use the base name: Name_method (not Name_t_method)
 */

#include "../cz.h"
#include "structs.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Maximum number of struct types we can track */
#define MAX_STRUCT_TYPES 256

/* Tracked struct type names */
static char *tracked_struct_types[MAX_STRUCT_TYPES];
static size_t tracked_struct_count = 0;

/* Track a struct type name */
static void track_struct_name(const char *name) {
    if (tracked_struct_count >= MAX_STRUCT_TYPES) {
        return;
    }
    
    /* Check if already tracked */
    for (size_t i = 0; i < tracked_struct_count; i++) {
        if (tracked_struct_types[i] && strcmp(tracked_struct_types[i], name) == 0) {
            return;
        }
    }
    
    /* Add new struct type */
    tracked_struct_types[tracked_struct_count] = strdup(name);
    if (tracked_struct_types[tracked_struct_count]) {
        tracked_struct_count++;
    }
}

/* Check if an identifier is a tracked struct type */
static int is_tracked_struct(const char *name) {
    for (size_t i = 0; i < tracked_struct_count; i++) {
        if (tracked_struct_types[i] && strcmp(tracked_struct_types[i], name) == 0) {
            return 1;
        }
    }
    return 0;
}

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
            /* Transform: struct Name { ... } to typedef struct Name_s { ... } Name_t */
            /* Also create typedef for backward compatibility: typedef struct Name_s Name_bc */
            /* Methods use base name: Name_method (not Name_t_method) */

            /* Step 1: Save the struct name (t3->text) */
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

            /* Step 3: Append "_s" to the struct name (e.g., Name -> Name_s) */
            size_t struct_name_len = strlen(struct_name);
            char *struct_name_s = malloc(struct_name_len + 3); /* "_s" + null terminator */
            if (struct_name_s) {
                strcpy(struct_name_s, struct_name);
                strcat(struct_name_s, "_s");
                
                /* Replace the identifier with Name_s */
                free(t3->text);
                t3->text = struct_name_s;
                t3->length = strlen(struct_name_s);
            }

            /* Step 4: After the closing brace, add the typedef name as Name_t */
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
                /* Insert the typedef name as " Name_t" before the semicolon */
                size_t insert_pos = semicolon_idx;

                /* Create Name_t from struct_name */
                size_t typedef_name_len = strlen(struct_name);
                char *typedef_name = malloc(typedef_name_len + 3); /* "_t" + null terminator */
                if (!typedef_name) {
                    free(struct_name);
                    continue;
                }
                strcpy(typedef_name, struct_name);
                strcat(typedef_name, "_t");

                /* We need to insert: " Name_t" before the semicolon */
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

                /* Create a new token for the typedef name (Name_t) */
                ASTNode *name_node = malloc(sizeof(ASTNode));
                if (name_node) {
                    name_node->type = AST_TOKEN;
                    name_node->token.type = TOKEN_IDENTIFIER;
                    name_node->token.text = typedef_name; /* Transfer ownership */
                    name_node->token.length = strlen(typedef_name);
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

                    /* Track this struct name for later replacement */
                    track_struct_name(struct_name);

                    /* Skip ahead so we don't process this struct again */
                    i = semicolon_idx + 2; /* +2 for Name_t we added */
                    
                    /* Free struct_name as we've created Name_s and Name_t separately */
                    free(struct_name);
                } else {
                    free(struct_name);
                    free(typedef_name);
                    if (space_node) free(space_node);
                }
            } else {
                free(struct_name);
            }
        }
    }
}

/* Transform struct initialization syntax
 * Handles:
 * - MyStruct s = {} -> MyStruct s = {0}
 * - MyStruct s = MyStruct {} -> MyStruct s = {0}
 * - MyStruct s = MyStruct {0} -> MyStruct s = {0}
 */
void transpiler_transform_struct_init(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: = { or = StructName { */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (i + 2 >= ast->child_count) {
            continue;
        }

        ASTNode *n1 = ast->children[i];
        if (n1->type != AST_TOKEN || n1->token.type != TOKEN_OPERATOR ||
            !n1->token.text || strcmp(n1->token.text, "=") != 0) {
            continue;
        }

        /* Found =, now look for what comes after (skipping whitespace) */
        size_t next_idx = i + 1;
        while (next_idx < ast->child_count &&
               ast->children[next_idx]->type == AST_TOKEN &&
               ast->children[next_idx]->token.type == TOKEN_WHITESPACE) {
            next_idx++;
        }

        if (next_idx >= ast->child_count) {
            continue;
        }

        ASTNode *next = ast->children[next_idx];
        if (next->type != AST_TOKEN) {
            continue;
        }

        /* Case 1: = {} (empty braces) */
        if (next->token.type == TOKEN_PUNCTUATION && next->token.text &&
            strcmp(next->token.text, "{") == 0) {
            /* Check if followed by } */
            size_t close_idx = next_idx + 1;
            while (close_idx < ast->child_count &&
                   ast->children[close_idx]->type == AST_TOKEN &&
                   ast->children[close_idx]->token.type == TOKEN_WHITESPACE) {
                close_idx++;
            }

            if (close_idx < ast->child_count &&
                ast->children[close_idx]->type == AST_TOKEN &&
                ast->children[close_idx]->token.type == TOKEN_PUNCTUATION &&
                ast->children[close_idx]->token.text &&
                strcmp(ast->children[close_idx]->token.text, "}") == 0) {
                /* Insert 0 between { and } */
                ASTNode *zero_node = malloc(sizeof(ASTNode));
                if (zero_node) {
                    zero_node->type = AST_TOKEN;
                    zero_node->token.type = TOKEN_NUMBER;
                    zero_node->token.text = strdup("0");
                    zero_node->token.length = 1;
                    zero_node->token.line = next->token.line;
                    zero_node->token.column = 0;
                    zero_node->children = NULL;
                    zero_node->child_count = 0;
                    zero_node->child_capacity = 0;

                    if (zero_node->token.text) {
                        /* Insert zero_node between { and } */
                        size_t insert_pos = next_idx + 1;
                        size_t new_count = ast->child_count + 1;

                        if (new_count > ast->child_capacity) {
                            size_t new_capacity = new_count * 2;
                            ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
                            if (new_children) {
                                ast->children = new_children;
                                ast->child_capacity = new_capacity;
                            } else {
                                free(zero_node->token.text);
                                free(zero_node);
                                continue;
                            }
                        }

                        /* Shift elements */
                        for (size_t j = ast->child_count; j > insert_pos; j--) {
                            ast->children[j] = ast->children[j - 1];
                        }

                        ast->children[insert_pos] = zero_node;
                        ast->child_count++;
                    } else {
                        free(zero_node);
                    }
                }
            }
        }
        /* Case 2: = StructName { ... } */
        else if (next->token.type == TOKEN_IDENTIFIER) {
            /* Look for { after the identifier */
            size_t brace_idx = next_idx + 1;
            while (brace_idx < ast->child_count &&
                   ast->children[brace_idx]->type == AST_TOKEN &&
                   ast->children[brace_idx]->token.type == TOKEN_WHITESPACE) {
                brace_idx++;
            }

            if (brace_idx < ast->child_count &&
                ast->children[brace_idx]->type == AST_TOKEN &&
                ast->children[brace_idx]->token.type == TOKEN_PUNCTUATION &&
                ast->children[brace_idx]->token.text &&
                strcmp(ast->children[brace_idx]->token.text, "{") == 0) {

                /* This is StructName { ... } pattern */
                /* Check what's inside the braces */
                size_t inside_idx = brace_idx + 1;
                while (inside_idx < ast->child_count &&
                       ast->children[inside_idx]->type == AST_TOKEN &&
                       ast->children[inside_idx]->token.type == TOKEN_WHITESPACE) {
                    inside_idx++;
                }

                /* Check if empty */
                int is_empty = 0;

                if (inside_idx < ast->child_count &&
                    ast->children[inside_idx]->type == AST_TOKEN) {
                    if (ast->children[inside_idx]->token.type == TOKEN_PUNCTUATION &&
                        ast->children[inside_idx]->token.text &&
                        strcmp(ast->children[inside_idx]->token.text, "}") == 0) {
                        is_empty = 1;
                    }
                }

                /* Transform by removing the struct name */
                /* = StructName { -> = { */
                free(next->token.text);
                next->token.text = strdup("");
                next->token.length = 0;

                /* If empty, add 0 */
                if (is_empty) {

                    ASTNode *zero_node = malloc(sizeof(ASTNode));
                    if (zero_node) {
                        zero_node->type = AST_TOKEN;
                        zero_node->token.type = TOKEN_NUMBER;
                        zero_node->token.text = strdup("0");
                        zero_node->token.length = 1;
                        zero_node->token.line = ast->children[brace_idx]->token.line;
                        zero_node->token.column = 0;
                        zero_node->children = NULL;
                        zero_node->child_count = 0;
                        zero_node->child_capacity = 0;

                        if (zero_node->token.text) {
                            /* Insert before } */
                            size_t insert_pos = brace_idx + 1;
                            size_t new_count = ast->child_count + 1;

                            if (new_count > ast->child_capacity) {
                                size_t new_capacity = new_count * 2;
                                ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
                                if (new_children) {
                                    ast->children = new_children;
                                    ast->child_capacity = new_capacity;
                                } else {
                                    free(zero_node->token.text);
                                    free(zero_node);
                                    continue;
                                }
                            }

                            /* Shift elements */
                            for (size_t j = ast->child_count; j > insert_pos; j--) {
                                ast->children[j] = ast->children[j - 1];
                            }

                            ast->children[insert_pos] = zero_node;
                            ast->child_count++;
                        } else {
                            free(zero_node);
                        }
                    }
                }
            }
        }
    }
}

/* Replace all uses of tracked struct names with their _t variants
 * For example: Vec2 -> Vec2_t
 * This ensures the generated C code uses the typedef names consistently
 */
void transpiler_replace_struct_names(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Walk through all tokens and replace struct type names */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            continue;
        }

        Token *token = &ast->children[i]->token;
        
        /* Check if this is an identifier that matches a tracked struct type */
        if (token->type == TOKEN_IDENTIFIER && token->text && is_tracked_struct(token->text)) {
            /* Replace Name with Name_t */
            size_t name_len = strlen(token->text);
            char *new_name = malloc(name_len + 3); /* "_t" + null terminator */
            if (new_name) {
                strcpy(new_name, token->text);
                strcat(new_name, "_t");
                
                free(token->text);
                token->text = new_name;
                token->length = strlen(new_name);
            }
        }
    }
}
