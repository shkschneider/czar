/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Handles mutability transformations:
 * - Everything is immutable (const) by default
 * - 'mut' keyword makes things mutable
 * - Transform 'mut Type' to 'Type' (strip mut)
 * - Transform 'Type' to 'const Type' (add const)
 *
 * Strategy:
 * 1. Scan for 'mut' keyword followed by type, remove 'mut'
 * 2. Scan for type declarations without 'mut', add 'const'
 * 3. Handle pointers: both pointer and pointee get const
 * 4. Special case: struct methods - self is always mutable
 */

#include "cz.h"
#include "mutability.h"
#include "warnings.h"
#include "errors.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Known type keywords to check for const insertion */
static const char *type_keywords[] = {
    /* C standard types */
    "void", "char", "short", "int", "long", "float", "double",
    "signed", "unsigned",
    /* C stdint types */
    "int8_t", "int16_t", "int32_t", "int64_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t",
    "size_t", "ptrdiff_t",
    /* CZar types (before transformation) */
    "i8", "i16", "i32", "i64",
    "u8", "u16", "u32", "u64",
    "f32", "f64",
    "isize", "usize",
    "bool",
    NULL
};

/* Check if token text matches */
static int token_equals(Token *token, const char *text) {
    return token && token->text && text && strcmp(token->text, text) == 0;
}

/* Check if identifier is a known type keyword */
static int is_type_keyword(const char *text) {
    if (!text) return 0;
    for (int i = 0; type_keywords[i] != NULL; i++) {
        if (strcmp(text, type_keywords[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Check if token is a type identifier (keyword or struct name) */
/* Skip whitespace and comments */
static size_t skip_whitespace(ASTNode **children, size_t count, size_t i) {
    while (i < count) {
        if (children[i]->type != AST_TOKEN) {
            i++;
            continue;
        }
        TokenType type = children[i]->token.type;
        if (type != TOKEN_WHITESPACE && type != TOKEN_COMMENT) {
            break;
        }
        i++;
    }
    return i;
}

/* Look backward skipping whitespace */
static int find_prev_token(ASTNode **children, size_t current, size_t *result) {
    if (current == 0) return 0;

    for (int i = (int)current - 1; i >= 0; i--) {
        if (children[i]->type != AST_TOKEN) continue;
        TokenType type = children[i]->token.type;
        if (type == TOKEN_WHITESPACE || type == TOKEN_COMMENT) continue;
        *result = (size_t)i;
        return 1;
    }
    return 0;
}

/* Create a new token node */
static ASTNode *create_token_node(const char *text, TokenType type) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) return NULL;

    node->type = AST_TOKEN;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;

    node->token.type = type;
    node->token.text = strdup(text);
    node->token.length = strlen(text);
    node->token.line = 0;
    node->token.column = 0;

    if (!node->token.text) {
        free(node);
        return NULL;
    }

    return node;
}

/* Insertion type enum */
typedef enum {
    INSERT_CONST_BEFORE_TYPE,    /* Insert "const " before type */
    INSERT_CONST_AFTER_STAR      /* Insert " const " after * */
} InsertionType;

/* Struct to track a const insertion */
typedef struct {
    size_t position;             /* Position to insert at */
    InsertionType type;          /* Type of insertion */
} ConstInsertion;

/* Comparison function for qsort - sort by position descending */
static int compare_insertions(const void *a, const void *b) {
    const ConstInsertion *ia = (const ConstInsertion *)a;
    const ConstInsertion *ib = (const ConstInsertion *)b;
    /* Sort descending so we insert from highest position to lowest */
    if (ia->position > ib->position) return -1;
    if (ia->position < ib->position) return 1;
    return 0;
}

/* Insert a node at position in AST children */
static int insert_node_at(ASTNode *ast, size_t pos, ASTNode *new_node) {
    if (!ast || !new_node || pos > ast->child_count) {
        return 0;
    }

    /* Ensure capacity */
    if (ast->child_count >= ast->child_capacity) {
        size_t new_capacity = ast->child_capacity == 0 ? 16 : ast->child_capacity * 2;
        ASTNode **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return 0;
        }
        ast->children = new_children;
        ast->child_capacity = new_capacity;
    }

    /* Shift elements to make room */
    for (size_t i = ast->child_count; i > pos; i--) {
        ast->children[i] = ast->children[i - 1];
    }

    /* Insert new node */
    ast->children[pos] = new_node;
    ast->child_count++;

    return 1;
}

/* Mark a token for deletion by replacing its text with empty string */
static void mark_for_deletion(ASTNode *node) {
    if (node && node->type == AST_TOKEN && node->token.text) {
        free(node->token.text);
        node->token.text = strdup("");
        node->token.length = 0;
    }
}

/* Transform mutability in AST */
void transpiler_transform_mutability(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* Pass 0: Error on const usage (everything is const by default, use mut for mutable) */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &children[i]->token;

        /* Check if this is 'const' keyword in source */
        if (token_equals(tok, "const")) {
            cz_error(filename, source, tok->line,
                "Invalid 'const' keyword. In CZar, everything is immutable by default. Use 'mut' for mutable declarations.");
            /* Mark const for deletion to maintain consistent mut philosophy */
            mark_for_deletion(children[i]);

            /* Also mark any whitespace tokens after const for deletion */
            size_t j = i + 1;
            while (j < count && children[j]->type == AST_TOKEN &&
                   children[j]->token.type == TOKEN_WHITESPACE) {
                mark_for_deletion(children[j]);
                j++;
            }
        }
    }

    /* Pass 1: Mark types following 'mut' for mutable access, and mark 'mut' for deletion */
    int *is_mutable = calloc(count, sizeof(int));
    if (!is_mutable) return; /* Out of memory */

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        if (children[i]->token.type != TOKEN_IDENTIFIER) continue;

        Token *tok = &children[i]->token;

        /* Check if this is 'mut' keyword */
        if (!token_equals(tok, "mut")) continue;

        /* Found 'mut' - look for following type */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j >= count) continue;

        if (children[j]->type == AST_TOKEN &&
            children[j]->token.type == TOKEN_IDENTIFIER) {
            /* Mark the type at position j as mutable */
            is_mutable[j] = 1;
            /* Mark 'mut' for deletion */
            mark_for_deletion(children[i]);

            /* Also mark any whitespace tokens between mut and type for deletion */
            for (size_t k = i + 1; k < j; k++) {
                if (children[k]->type == AST_TOKEN &&
                    children[k]->token.type == TOKEN_WHITESPACE) {
                    mark_for_deletion(children[k]);
                }
            }
        }
    }

    /* Pass 1.5: Validate that 'mut' is only used on pointer parameters */
    /* Scan for function declarations and check parameters marked as mutable */
    for (size_t i = 0; i + 2 < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok_type = &children[i]->token;

        /* Check if this looks like: type identifier( pattern */
        if (tok_type->type != TOKEN_IDENTIFIER) continue;

        /* Check if it's a type keyword (could also be return type) */
        if (!is_type_keyword(tok_type->text)) continue;

        /* Look ahead for identifier */
        size_t name_idx = skip_whitespace(children, count, i + 1);
        if (name_idx >= count) continue;
        if (children[name_idx]->type != AST_TOKEN) continue;
        if (children[name_idx]->token.type != TOKEN_IDENTIFIER) continue;

        /* Look ahead for ( */
        size_t paren_idx = skip_whitespace(children, count, name_idx + 1);
        if (paren_idx >= count) continue;
        if (children[paren_idx]->type != AST_TOKEN) continue;
        if (!token_equals(&children[paren_idx]->token, "(")) continue;

        /* Found function declaration! Now scan the parameter list */
        int depth = 1;
        for (size_t j = paren_idx + 1; j < count && depth > 0; j++) {
            if (children[j]->type != AST_TOKEN) continue;
            Token *param_tok = &children[j]->token;

            if (param_tok->type == TOKEN_PUNCTUATION) {
                if (token_equals(param_tok, "(")) depth++;
                else if (token_equals(param_tok, ")")) {
                    depth--;
                    if (depth == 0) break; /* End of parameter list */
                }
            }

            /* Check if this is a parameter type (use syntax to detect) */
            /* In parameter lists, pattern is: Type name or Type *name */
            /* So any identifier followed by * or another identifier is a type */
            if (param_tok->type == TOKEN_IDENTIFIER) {
                /* Look ahead to see what follows */
                size_t next_idx = skip_whitespace(children, count, j + 1);
                if (next_idx >= count || children[next_idx]->type != AST_TOKEN) continue;

                Token *next_tok = &children[next_idx]->token;

                /* Check if followed by * (pointer) or identifier (parameter name) */
                if (!token_equals(next_tok, "*") && next_tok->type != TOKEN_IDENTIFIER) {
                    continue; /* Not a type pattern */
                }

                /* Skip void */
                if (token_equals(param_tok, "void")) continue;

                /* Skip enum/struct keywords - they're not the type name themselves */
                if (token_equals(param_tok, "enum") || token_equals(param_tok, "struct") ||
                    token_equals(param_tok, "union")) {
                    continue;
                }

                /* Check if this is a pointer type */
                int is_pointer = token_equals(next_tok, "*");

                /* Check if this parameter is marked as mutable */
                if (is_mutable[j]) {
                    /* Error if mutable but not a pointer */
                    if (!is_pointer) {
                        cz_error(filename, source, param_tok->line,
                            "Mutable parameter must be a pointer to have side effects. "
                            "Non-pointer parameters are passed by value. Use pointer type or remove 'mut'.");
                    }
                }
            }
        }
    }

    /* Pass 2: Add 'const' to type identifiers that are not marked as mutable */
    /* For pointers: add const to both type and pointer (const Type * const p) */
    /* Applies to both function parameters AND local variable declarations */

    /* Build list of all const insertions needed */
    ConstInsertion *insertions = malloc(count * 2 * sizeof(ConstInsertion)); /* Max 2 per type (before + after *) */
    size_t insertion_count = 0;

    if (!insertions) {
        free(is_mutable);
        return; /* Out of memory */
    }

    /* Scan for function declarations and mark parameter types for const insertion */
    for (size_t i = 0; i + 2 < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok_type = &children[i]->token;

        /* Check if this looks like: type identifier( pattern */
        /* This is more reliable for detecting function declarations */
        if (tok_type->type != TOKEN_IDENTIFIER) continue;

        /* Check if it's a type keyword (could also be return type) */
        if (!is_type_keyword(tok_type->text)) continue;

        /* Look ahead for identifier */
        size_t name_idx = skip_whitespace(children, count, i + 1);
        if (name_idx >= count) continue;
        if (children[name_idx]->type != AST_TOKEN) continue;
        if (children[name_idx]->token.type != TOKEN_IDENTIFIER) continue;

        /* Look ahead for ( */
        size_t paren_idx = skip_whitespace(children, count, name_idx + 1);
        if (paren_idx >= count) continue;
        if (children[paren_idx]->type != AST_TOKEN) continue;
        if (!token_equals(&children[paren_idx]->token, "(")) continue;

        /* Found function declaration! Now scan the parameter list */
        int depth = 1;
        for (size_t j = paren_idx + 1; j < count && depth > 0; j++) {
            if (children[j]->type != AST_TOKEN) continue;
            Token *param_tok = &children[j]->token;

            if (param_tok->type == TOKEN_PUNCTUATION) {
                if (token_equals(param_tok, "(")) depth++;
                else if (token_equals(param_tok, ")")) {
                    depth--;
                    if (depth == 0) break; /* End of parameter list */
                }
            }

            /* Check if this is a parameter type (use syntax to detect) */
            /* In parameter lists, pattern is: Type name or Type *name */
            /* So any identifier followed by * or another identifier is a type */
            if (param_tok->type == TOKEN_IDENTIFIER) {
                /* Skip tokens marked for deletion (empty text) */
                if (param_tok->text == NULL || param_tok->text[0] == '\0') {
                    continue;
                }

                /* Look ahead to see what follows */
                size_t next_idx = skip_whitespace(children, count, j + 1);
                if (next_idx >= count || children[next_idx]->type != AST_TOKEN) continue;

                Token *next_tok = &children[next_idx]->token;

                /* Check if followed by * (pointer) or identifier (parameter name) */
                if (!token_equals(next_tok, "*") && next_tok->type != TOKEN_IDENTIFIER) {
                    continue; /* Not a type pattern */
                }

                /* Skip void */
                if (token_equals(param_tok, "void")) continue;

                /* Skip enum/struct keywords - they're not the type name themselves */
                if (token_equals(param_tok, "enum") || token_equals(param_tok, "struct") ||
                    token_equals(param_tok, "union")) {
                    continue;
                }

                /* Skip if preceded by enum/struct/union - this is a tag name, not the type */
                size_t prev_idx;
                if (find_prev_token(children, j, &prev_idx)) {
                    Token *prev_tok = &children[prev_idx]->token;
                    if (token_equals(prev_tok, "enum") || token_equals(prev_tok, "struct") ||
                        token_equals(prev_tok, "union")) {
                        continue;
                    }
                }

                /* Handle pointers: add const to both type and pointer */
                /* Pattern: Type *p becomes const Type * const p */
                int is_pointer = token_equals(next_tok, "*");

                /* Skip if marked as mutable */
                if (is_mutable[j]) continue;

                /* Skip if already has const */
                if (find_prev_token(children, j, &prev_idx)) {
                    if (token_equals(&children[prev_idx]->token, "const")) {
                        continue;
                    }
                }

                /* Add to insert list for const before type */
                if (insertion_count < count * 2) {
                    insertions[insertion_count].position = j;
                    insertions[insertion_count].type = INSERT_CONST_BEFORE_TYPE;
                    insertion_count++;
                }

                /* For pointers, also need const after * */
                if (is_pointer) {
                    if (insertion_count < count * 2) {
                        insertions[insertion_count].position = next_idx;
                        insertions[insertion_count].type = INSERT_CONST_AFTER_STAR;
                        insertion_count++;
                    }
                }
            }
        }
    }

    /* Scan for local variable declarations and mark types for const insertion */
    /* Pattern: Type identifier = ... or Type *identifier = ... inside function bodies */
    int brace_depth = 0;
    int in_function_body = 0;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;

        /* Track brace depth to know if we're inside a function */
        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_equals(tok, "{")) {
                brace_depth++;
                /* Simple heuristic: if we see { after ) then we're entering a function body */
                size_t prev_idx;
                if (find_prev_token(children, i, &prev_idx)) {
                    if (token_equals(&children[prev_idx]->token, ")")) {
                        in_function_body = 1;
                    }
                }
            } else if (token_equals(tok, "}")) {
                brace_depth--;
                if (brace_depth == 0) {
                    in_function_body = 0;
                }
            }
        }

        /* Only process if inside a function body */
        if (!in_function_body || brace_depth == 0) continue;

        /* Look for variable declarations: Type identifier = or Type identifier; */
        if (tok->type == TOKEN_IDENTIFIER) {
            /* Skip tokens marked for deletion (empty text) */
            if (tok->text == NULL || tok->text[0] == '\0') {
                continue;
            }

            /* Skip keywords that aren't types */
            if (token_equals(tok, "return") || token_equals(tok, "if") ||
                token_equals(tok, "else") || token_equals(tok, "while") ||
                token_equals(tok, "for") || token_equals(tok, "do") ||
                token_equals(tok, "switch") || token_equals(tok, "case") ||
                token_equals(tok, "break") || token_equals(tok, "continue") ||
                token_equals(tok, "goto") || token_equals(tok, "sizeof") ||
                token_equals(tok, "typedef") || token_equals(tok, "static") ||
                token_equals(tok, "extern") || token_equals(tok, "auto") ||
                token_equals(tok, "register") || token_equals(tok, "inline")) {
                continue;
            }

            /* Look ahead to see what follows */
            size_t next_idx = skip_whitespace(children, count, i + 1);
            if (next_idx >= count || children[next_idx]->type != AST_TOKEN) continue;

            Token *next_tok = &children[next_idx]->token;

            /* Check if followed by * (pointer) or identifier (variable name) */
            if (!token_equals(next_tok, "*") && next_tok->type != TOKEN_IDENTIFIER) {
                continue; /* Not a variable declaration pattern */
            }

            /* If followed by *, this could be pointer declaration OR multiplication */
            /* For pointer declaration, * must be followed by identifier (pointer name) */
            if (token_equals(next_tok, "*")) {
                size_t after_star_idx = skip_whitespace(children, count, next_idx + 1);
                if (after_star_idx >= count || children[after_star_idx]->type != AST_TOKEN) continue;
                Token *after_star = &children[after_star_idx]->token;

                /* Must be followed by identifier (pointer name) for declaration */
                if (after_star->type != TOKEN_IDENTIFIER) {
                    continue; /* Not a declaration - likely multiplication or other use */
                }

                /* Check that pointer name is followed by = or ; or , */
                size_t after_name_idx = skip_whitespace(children, count, after_star_idx + 1);
                if (after_name_idx >= count || children[after_name_idx]->type != AST_TOKEN) continue;
                Token *after_name = &children[after_name_idx]->token;

                if (!token_equals(after_name, "=") && !token_equals(after_name, ";") &&
                    !token_equals(after_name, ",")) {
                    continue; /* Not a declaration */
                }
            }

            /* If followed by identifier, check if that's followed by = or ; */
            if (next_tok->type == TOKEN_IDENTIFIER) {
                size_t after_name_idx = skip_whitespace(children, count, next_idx + 1);
                if (after_name_idx >= count || children[after_name_idx]->type != AST_TOKEN) continue;
                Token *after_name = &children[after_name_idx]->token;

                /* Must be followed by = or ; or , to be a variable declaration */
                if (!token_equals(after_name, "=") && !token_equals(after_name, ";") &&
                    !token_equals(after_name, ",") && !token_equals(after_name, "(")) {
                    continue;
                }

                /* Skip if followed by ( - that's a function call, not a declaration */
                if (token_equals(after_name, "(")) {
                    continue;
                }
            }

            /* Skip void */
            if (token_equals(tok, "void")) continue;

            /* Skip enum/struct/union keywords */
            if (token_equals(tok, "enum") || token_equals(tok, "struct") ||
                token_equals(tok, "union")) {
                continue;
            }

            /* Skip if preceded by enum/struct/union */
            size_t prev_idx;
            if (find_prev_token(children, i, &prev_idx)) {
                Token *prev_tok = &children[prev_idx]->token;
                if (token_equals(prev_tok, "enum") || token_equals(prev_tok, "struct") ||
                    token_equals(prev_tok, "union")) {
                    continue;
                }
            }

            /* Handle pointers */
            int is_pointer = token_equals(next_tok, "*");

            /* Skip if marked as mutable */
            if (is_mutable[i]) continue;

            /* Skip if already has const */
            if (find_prev_token(children, i, &prev_idx)) {
                if (token_equals(&children[prev_idx]->token, "const")) {
                    continue;
                }
            }

            /* Add to insert list for const before type */
            if (insertion_count < count * 2) {
                insertions[insertion_count].position = i;
                insertions[insertion_count].type = INSERT_CONST_BEFORE_TYPE;
                insertion_count++;
            }

            /* For pointers, also need const after * */
            if (is_pointer) {
                if (insertion_count < count * 2) {
                    insertions[insertion_count].position = next_idx;
                    insertions[insertion_count].type = INSERT_CONST_AFTER_STAR;
                    insertion_count++;
                }
            }
        }
    }

    /* Sort insertions by position (descending) so we can insert from highest to lowest */
    /* This way, later insertions don't affect earlier positions */
    qsort(insertions, insertion_count, sizeof(ConstInsertion), compare_insertions);

    /* Apply all insertions in order (highest position first) */
    for (size_t idx = 0; idx < insertion_count; idx++) {
        ConstInsertion ins = insertions[idx];

        if (ins.type == INSERT_CONST_BEFORE_TYPE) {
            /* Insert "const " before type */
            ASTNode *const_node = create_token_node("const", TOKEN_KEYWORD);
            ASTNode *space_node = create_token_node(" ", TOKEN_WHITESPACE);

            if (const_node && space_node) {
                insert_node_at(ast, ins.position, const_node);
                insert_node_at(ast, ins.position + 1, space_node);
            } else {
                /* Cleanup on failure */
                if (const_node) {
                    if (const_node->token.text) free(const_node->token.text);
                    free(const_node);
                }
                if (space_node) {
                    if (space_node->token.text) free(space_node->token.text);
                    free(space_node);
                }
            }
        } else if (ins.type == INSERT_CONST_AFTER_STAR) {
            /* Insert " const " after * */
            /* Check if there's already whitespace after * and mark it for deletion */
            if (ins.position + 1 < ast->child_count && ast->children[ins.position + 1]->type == AST_TOKEN &&
                ast->children[ins.position + 1]->token.type == TOKEN_WHITESPACE) {
                /* Mark existing whitespace for deletion to avoid double spaces */
                mark_for_deletion(ast->children[ins.position + 1]);
            }

            /* Always insert: space + const + space */
            ASTNode *space1_node = create_token_node(" ", TOKEN_WHITESPACE);
            ASTNode *const_node = create_token_node("const", TOKEN_KEYWORD);
            ASTNode *space2_node = create_token_node(" ", TOKEN_WHITESPACE);

            if (space1_node && const_node && space2_node) {
                insert_node_at(ast, ins.position + 1, space1_node);
                insert_node_at(ast, ins.position + 2, const_node);
                insert_node_at(ast, ins.position + 3, space2_node);
            } else {
                /* Cleanup */
                if (space1_node) {
                    if (space1_node->token.text) free(space1_node->token.text);
                    free(space1_node);
                }
                if (const_node) {
                    if (const_node->token.text) free(const_node->token.text);
                    free(const_node);
                }
                if (space2_node) {
                    if (space2_node->token.text) free(space2_node->token.text);
                    free(space2_node);
                }
            }
        }
    }

    free(insertions);
    free(is_mutable);
}
