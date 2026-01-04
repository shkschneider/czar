/*
 * CZar - C semantic authority layer
 * Transpiler mutability module (transpiler/mutability.c)
 *
 * Validates mutability rules and tracks mutable/immutable variables.
 */

#define _POSIX_C_SOURCE 200809L

#include "mutability.h"
#include "../errors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Symbol table entry for tracking mutability */
typedef struct MutabilitySymbol {
    char *name;                    /* Variable name */
    int is_mutable;                /* 1 if mutable, 0 if immutable */
    int line;                      /* Line where declared */
    struct MutabilitySymbol *next; /* Next symbol in linked list */
} MutabilitySymbol;

/* Global context for error reporting */
static const char *g_filename = NULL;
static const char *g_source = NULL;

/* Symbol table (linked list) */
static MutabilitySymbol *g_symbol_table = NULL;

/* Helper: Compare token text */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Helper: Add symbol to table */
static void add_symbol(const char *name, int is_mutable, int line) {
    MutabilitySymbol *sym = malloc(sizeof(MutabilitySymbol));
    if (!sym) return;
    
    sym->name = strdup(name);
    sym->is_mutable = is_mutable;
    sym->line = line;
    sym->next = g_symbol_table;
    g_symbol_table = sym;
}

/* Helper: Find symbol in table */
static MutabilitySymbol *find_symbol(const char *name) {
    for (MutabilitySymbol *sym = g_symbol_table; sym; sym = sym->next) {
        if (strcmp(sym->name, name) == 0) {
            return sym;
        }
    }
    return NULL;
}

/* Helper: Clear symbol table */
static void clear_symbols(void) {
    while (g_symbol_table) {
        MutabilitySymbol *next = g_symbol_table->next;
        free(g_symbol_table->name);
        free(g_symbol_table);
        g_symbol_table = next;
    }
}

/* Helper: Check if token is a type keyword */
static int is_type_keyword(const char *text) {
    /* C standard types */
    if (strcmp(text, "int") == 0 || strcmp(text, "char") == 0 ||
        strcmp(text, "short") == 0 || strcmp(text, "long") == 0 ||
        strcmp(text, "float") == 0 || strcmp(text, "double") == 0 ||
        strcmp(text, "void") == 0 || strcmp(text, "signed") == 0 ||
        strcmp(text, "unsigned") == 0) {
        return 1;
    }

    /* CZar types (before transformation) */
    if (strcmp(text, "u8") == 0 || strcmp(text, "u16") == 0 ||
        strcmp(text, "u32") == 0 || strcmp(text, "u64") == 0 ||
        strcmp(text, "i8") == 0 || strcmp(text, "i16") == 0 ||
        strcmp(text, "i32") == 0 || strcmp(text, "i64") == 0 ||
        strcmp(text, "f32") == 0 || strcmp(text, "f64") == 0 ||
        strcmp(text, "usize") == 0 || strcmp(text, "isize") == 0) {
        return 1;
    }

    /* CZar types (after transformation to C types) */
    if (strcmp(text, "uint8_t") == 0 || strcmp(text, "uint16_t") == 0 ||
        strcmp(text, "uint32_t") == 0 || strcmp(text, "uint64_t") == 0 ||
        strcmp(text, "int8_t") == 0 || strcmp(text, "int16_t") == 0 ||
        strcmp(text, "int32_t") == 0 || strcmp(text, "int64_t") == 0 ||
        strcmp(text, "size_t") == 0 || strcmp(text, "ptrdiff_t") == 0) {
        return 1;
    }

    return 0;
}

/* Helper: Check if token is an aggregate keyword */
static int is_aggregate_keyword(const char *text) {
    return strcmp(text, "struct") == 0 ||
           strcmp(text, "union") == 0 ||
           strcmp(text, "enum") == 0;
}

/* Helper: Skip whitespace and comment tokens */
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

/* Helper: Check if we're in a function scope */
static int in_function_scope(ASTNode **children, size_t count, size_t current) {
    int brace_depth = 0;
    size_t last_open_brace_index = 0;
    int found_open_brace = 0;

    /* Scan backwards to find the most recent unclosed { */
    for (size_t i = 0; i < current && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "{")) {
                brace_depth++;
                last_open_brace_index = i;
                found_open_brace = 1;
            } else if (token_text_equals(tok, "}")) {
                if (brace_depth > 0) {
                    brace_depth--;
                    if (brace_depth == 0) {
                        found_open_brace = 0;
                    }
                }
            }
        }
    }

    if (!found_open_brace || brace_depth == 0) {
        return 0;
    }

    /* Check if the last unclosed { is a struct/union/enum definition */
    for (size_t j = (last_open_brace_index > 30 ? last_open_brace_index - 30 : 0);
         j < last_open_brace_index; j++) {
        if (children[j]->type != AST_TOKEN) continue;
        Token *prev = &children[j]->token;

        if ((prev->type == TOKEN_KEYWORD || prev->type == TOKEN_IDENTIFIER) &&
            is_aggregate_keyword(prev->text)) {
            int has_semicolon = 0;
            for (size_t k = j + 1; k < last_open_brace_index; k++) {
                if (children[k]->type == AST_TOKEN &&
                    children[k]->token.type == TOKEN_PUNCTUATION &&
                    token_text_equals(&children[k]->token, ";")) {
                    has_semicolon = 1;
                    break;
                }
            }
            if (!has_semicolon) {
                return 0;
            }
        }
    }

    return 1;
}

/* Helper: Check if we're inside function parameters (between ( and )) */
static int in_function_parameters(ASTNode **children, size_t count, size_t current) {
    int paren_depth = 0;
    int found_open_paren = 0;
    size_t last_open_paren = 0;

    /* Scan backwards to find if we're inside parentheses */
    for (size_t i = 0; i < current && i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;

        if (tok->type == TOKEN_PUNCTUATION) {
            if (token_text_equals(tok, "(")) {
                paren_depth++;
                last_open_paren = i;
                found_open_paren = 1;
            } else if (token_text_equals(tok, ")")) {
                if (paren_depth > 0) {
                    paren_depth--;
                    if (paren_depth == 0) {
                        found_open_paren = 0;
                    }
                }
            }
        }
    }

    if (!found_open_paren || paren_depth == 0) {
        return 0;
    }

    /* Check if there's a function name or type before the open paren */
    /* Look backwards from the open paren for an identifier (function name) */
    if (last_open_paren > 0) {
        size_t check_idx = last_open_paren - 1;
        while (check_idx > 0 && children[check_idx]->type == AST_TOKEN &&
               (children[check_idx]->token.type == TOKEN_WHITESPACE ||
                children[check_idx]->token.type == TOKEN_COMMENT)) {
            check_idx--;
        }
        if (children[check_idx]->type == AST_TOKEN &&
            children[check_idx]->token.type == TOKEN_IDENTIFIER) {
            /* This looks like a function declaration or call */
            return 1;
        }
    }

    return 0;
}

/* Scan and track function parameter declarations */
static void scan_function_parameters(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Check if we're in function parameters */
        if (!in_function_parameters(children, count, i)) {
            continue;
        }

        /* Check for 'mut' keyword in parameters */
        if (token->type == TOKEN_IDENTIFIER && token_text_equals(token, "mut")) {
            /* Look for the type after 'mut' */
            size_t j = skip_whitespace(children, count, i + 1);
            
            if (j >= count || children[j]->type != AST_TOKEN) continue;
            
            Token *type_token = &children[j]->token;
            
            /* Check if this is a type */
            if (!is_type_keyword(type_token->text) && !is_aggregate_keyword(type_token->text)) {
                continue;
            }

            /* For struct/union/enum, skip the tag name */
            if (is_aggregate_keyword(type_token->text)) {
                j = skip_whitespace(children, count, j + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_IDENTIFIER) {
                    j = skip_whitespace(children, count, j + 1);
                }
            } else {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Handle pointer types */
            while (j < count && children[j]->type == AST_TOKEN &&
                   children[j]->token.type == TOKEN_OPERATOR &&
                   token_text_equals(&children[j]->token, "*")) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Get the parameter name */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            Token *param_name = &children[j]->token;
            add_symbol(param_name->text, 1, param_name->line);  /* mutable parameter */
            continue;
        }

        /* Check for type keywords (without 'mut' - immutable parameter by default) */
        if ((token->type == TOKEN_IDENTIFIER || token->type == TOKEN_KEYWORD) &&
            (is_type_keyword(token->text) || is_aggregate_keyword(token->text))) {
            
            /* Check if this is preceded by 'mut' */
            if (i > 0) {
                size_t prev = i - 1;
                while (prev > 0 && children[prev]->type == AST_TOKEN &&
                       (children[prev]->token.type == TOKEN_WHITESPACE ||
                        children[prev]->token.type == TOKEN_COMMENT)) {
                    prev--;
                }
                if (children[prev]->type == AST_TOKEN &&
                    children[prev]->token.type == TOKEN_IDENTIFIER &&
                    token_text_equals(&children[prev]->token, "mut")) {
                    continue;  /* Already handled above */
                }
            }

            int is_aggregate = is_aggregate_keyword(token->text);

            /* Find the parameter name after the type */
            size_t j = skip_whitespace(children, count, i + 1);

            /* For struct/union/enum, skip the tag name */
            if (is_aggregate && j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Handle const, volatile, etc. */
            while (j < count && children[j]->type == AST_TOKEN) {
                Token *mod = &children[j]->token;
                if (mod->type == TOKEN_KEYWORD ||
                    (mod->type == TOKEN_IDENTIFIER &&
                     (strcmp(mod->text, "const") == 0 ||
                      strcmp(mod->text, "volatile") == 0 ||
                      strcmp(mod->text, "static") == 0 ||
                      strcmp(mod->text, "register") == 0 ||
                      strcmp(mod->text, "auto") == 0))) {
                    j = skip_whitespace(children, count, j + 1);
                } else {
                    break;
                }
            }

            /* Handle pointer types */
            while (j < count && children[j]->type == AST_TOKEN &&
                   children[j]->token.type == TOKEN_OPERATOR &&
                   token_text_equals(&children[j]->token, "*")) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Get the parameter name */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            Token *param_name = &children[j]->token;
            add_symbol(param_name->text, 0, param_name->line);  /* immutable parameter */
        }
    }
}

/* Scan and track variable declarations */
static void scan_variable_declarations(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Check for 'mut' keyword */
        if (token->type == TOKEN_IDENTIFIER && token_text_equals(token, "mut")) {
            /* Look for the type after 'mut', skipping modifiers */
            size_t j = skip_whitespace(children, count, i + 1);
            
            /* Skip modifiers like const, volatile, static, etc. */
            while (j < count && children[j]->type == AST_TOKEN) {
                Token *mod = &children[j]->token;
                if (mod->type == TOKEN_KEYWORD ||
                    (mod->type == TOKEN_IDENTIFIER &&
                     (strcmp(mod->text, "const") == 0 ||
                      strcmp(mod->text, "volatile") == 0 ||
                      strcmp(mod->text, "static") == 0 ||
                      strcmp(mod->text, "register") == 0 ||
                      strcmp(mod->text, "auto") == 0))) {
                    j = skip_whitespace(children, count, j + 1);
                } else {
                    break;
                }
            }
            
            if (j >= count || children[j]->type != AST_TOKEN) continue;
            
            Token *type_token = &children[j]->token;
            
            /* Check if this is a type */
            if (!is_type_keyword(type_token->text) && !is_aggregate_keyword(type_token->text)) {
                continue;
            }

            /* Check if we're in function scope */
            if (!in_function_scope(children, count, i)) {
                continue;
            }

            /* For struct/union/enum, skip the tag name */
            if (is_aggregate_keyword(type_token->text)) {
                j = skip_whitespace(children, count, j + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_IDENTIFIER) {
                    j = skip_whitespace(children, count, j + 1);
                }
            } else {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Handle pointer types */
            while (j < count && children[j]->type == AST_TOKEN &&
                   children[j]->token.type == TOKEN_OPERATOR &&
                   token_text_equals(&children[j]->token, "*")) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Get the variable name */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            Token *var_name = &children[j]->token;
            add_symbol(var_name->text, 1, var_name->line);  /* mutable */
            continue;
        }

        /* Check for type keywords (without 'mut' - immutable by default) */
        if ((token->type == TOKEN_IDENTIFIER || token->type == TOKEN_KEYWORD) &&
            (is_type_keyword(token->text) || is_aggregate_keyword(token->text))) {
            
            /* Check if we're in function scope */
            if (!in_function_scope(children, count, i)) {
                continue;
            }

            /* Check if this is preceded by 'mut' */
            if (i > 0) {
                size_t prev = i - 1;
                while (prev > 0 && children[prev]->type == AST_TOKEN &&
                       (children[prev]->token.type == TOKEN_WHITESPACE ||
                        children[prev]->token.type == TOKEN_COMMENT)) {
                    prev--;
                }
                if (children[prev]->type == AST_TOKEN &&
                    children[prev]->token.type == TOKEN_IDENTIFIER &&
                    token_text_equals(&children[prev]->token, "mut")) {
                    continue;  /* Already handled above */
                }
            }

            int is_aggregate = is_aggregate_keyword(token->text);

            /* Find the variable name after the type */
            size_t j = skip_whitespace(children, count, i + 1);

            /* For struct/union/enum, skip the tag name */
            if (is_aggregate && j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Handle const, volatile, etc. */
            while (j < count && children[j]->type == AST_TOKEN) {
                Token *mod = &children[j]->token;
                if (mod->type == TOKEN_KEYWORD ||
                    (mod->type == TOKEN_IDENTIFIER &&
                     (strcmp(mod->text, "const") == 0 ||
                      strcmp(mod->text, "volatile") == 0 ||
                      strcmp(mod->text, "static") == 0 ||
                      strcmp(mod->text, "register") == 0 ||
                      strcmp(mod->text, "auto") == 0))) {
                    j = skip_whitespace(children, count, j + 1);
                } else {
                    break;
                }
            }

            /* Handle pointer types */
            while (j < count && children[j]->type == AST_TOKEN &&
                   children[j]->token.type == TOKEN_OPERATOR &&
                   token_text_equals(&children[j]->token, "*")) {
                j = skip_whitespace(children, count, j + 1);
            }

            /* Get the variable name */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            Token *var_name = &children[j]->token;
            add_symbol(var_name->text, 0, var_name->line);  /* immutable */
        }
    }
}

/* Validate assignments to immutable variables */
static void validate_assignments(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Check for assignment operator */
        if (token->type == TOKEN_OPERATOR) {
            int is_assignment = 0;
            
            /* Check for simple assignment */
            if (token_text_equals(token, "=")) {
                /* Skip if this is a named argument (inside function call parentheses) */
                if (in_function_parameters(children, count, i)) {
                    continue;
                }
                is_assignment = 1;
            }
            /* Check for compound assignments */
            else if (token_text_equals(token, "+=") || token_text_equals(token, "-=") ||
                     token_text_equals(token, "*=") || token_text_equals(token, "/=") ||
                     token_text_equals(token, "%=") || token_text_equals(token, "&=") ||
                     token_text_equals(token, "|=") || token_text_equals(token, "^=") ||
                     token_text_equals(token, "<<=") || token_text_equals(token, ">>=")) {
                is_assignment = 1;
            }
            /* Check for increment/decrement */
            else if (token_text_equals(token, "++") || token_text_equals(token, "--")) {
                /* Find the identifier being incremented/decremented */
                size_t var_idx = 0;
                int found = 0;
                
                /* Check prefix (operator before identifier) */
                if (i + 1 < count) {
                    size_t next = skip_whitespace(children, count, i + 1);
                    if (next < count && children[next]->type == AST_TOKEN &&
                        children[next]->token.type == TOKEN_IDENTIFIER) {
                        var_idx = next;
                        found = 1;
                    }
                }
                
                /* Check postfix (operator after identifier) */
                if (!found && i > 0) {
                    size_t prev = i - 1;
                    while (prev > 0 && children[prev]->type == AST_TOKEN &&
                           (children[prev]->token.type == TOKEN_WHITESPACE ||
                            children[prev]->token.type == TOKEN_COMMENT)) {
                        prev--;
                    }
                    if (children[prev]->type == AST_TOKEN &&
                        children[prev]->token.type == TOKEN_IDENTIFIER) {
                        var_idx = prev;
                        found = 1;
                    }
                }
                
                if (found) {
                    Token *var_token = &children[var_idx]->token;
                    MutabilitySymbol *sym = find_symbol(var_token->text);
                    
                    if (sym && !sym->is_mutable) {
                        char error_msg[512];
                        snprintf(error_msg, sizeof(error_msg),
                                "Cannot modify immutable variable '%s'. Add 'mut' qualifier to make it mutable: mut %s",
                                var_token->text, var_token->text);
                        cz_error(g_filename, g_source, var_token->line, error_msg);
                    }
                }
                continue;
            }
            
            if (!is_assignment) continue;

            /* Find the variable being assigned to */
            if (i == 0) continue;
            
            size_t var_idx = i - 1;
            while (var_idx > 0 && children[var_idx]->type == AST_TOKEN &&
                   (children[var_idx]->token.type == TOKEN_WHITESPACE ||
                    children[var_idx]->token.type == TOKEN_COMMENT)) {
                var_idx--;
            }

            if (children[var_idx]->type != AST_TOKEN ||
                children[var_idx]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            Token *var_token = &children[var_idx]->token;
            
            /* Check if this identifier is a struct field access (preceded by . or ->) */
            /* OR pointer dereference (preceded by *) */
            if (var_idx > 0) {
                size_t check_idx = var_idx - 1;
                while (check_idx > 0 && children[check_idx]->type == AST_TOKEN &&
                       (children[check_idx]->token.type == TOKEN_WHITESPACE ||
                        children[check_idx]->token.type == TOKEN_COMMENT)) {
                    check_idx--;
                }
                if (children[check_idx]->type == AST_TOKEN &&
                    children[check_idx]->token.type == TOKEN_OPERATOR) {
                    if (token_text_equals(&children[check_idx]->token, ".") ||
                        token_text_equals(&children[check_idx]->token, "->") ||
                        token_text_equals(&children[check_idx]->token, "*")) {
                        /* This is a field access or pointer dereference - skip validation */
                        continue;
                    }
                }
            }
            
            /* Check if this is part of a variable declaration (initialization) */
            /* Look backwards for a type keyword immediately before the variable */
            int is_declaration = 0;
            size_t type_idx = 0;
            int found_type = 0;
            
            /* Look backwards for a type keyword */
            for (size_t k = (var_idx > 10 ? var_idx - 10 : 0); k < var_idx; k++) {
                if (children[k]->type == AST_TOKEN &&
                    children[k]->token.type == TOKEN_PUNCTUATION &&
                    token_text_equals(&children[k]->token, ";")) {
                    /* Hit a semicolon - no type keyword found after it */
                    found_type = 0;
                    type_idx = 0;
                }
                if (children[k]->type == AST_TOKEN &&
                    (children[k]->token.type == TOKEN_IDENTIFIER || children[k]->token.type == TOKEN_KEYWORD)) {
                    if (is_type_keyword(children[k]->token.text) || token_text_equals(&children[k]->token, "mut")) {
                        found_type = 1;
                        type_idx = k;
                    }
                }
            }
            
            /* If we found a type keyword and it's close to the variable, it's a declaration */
            if (found_type) {
                /* Check if there's only whitespace/identifiers between type and variable */
                int only_valid_tokens = 1;
                for (size_t k = type_idx + 1; k < var_idx; k++) {
                    if (children[k]->type == AST_TOKEN) {
                        TokenType tt = children[k]->token.type;
                        if (tt != TOKEN_WHITESPACE && tt != TOKEN_COMMENT && 
                            tt != TOKEN_IDENTIFIER && tt != TOKEN_OPERATOR) {
                            only_valid_tokens = 0;
                            break;
                        }
                        /* If we see another identifier that's not 'const', 'volatile', etc, it might be another var */
                        if (tt == TOKEN_IDENTIFIER) {
                            const char *txt = children[k]->token.text;
                            if (strcmp(txt, "const") != 0 && strcmp(txt, "volatile") != 0 &&
                                strcmp(txt, "static") != 0 && strcmp(txt, "register") != 0 &&
                                strcmp(txt, "auto") != 0 && strcmp(txt, "mut") != 0) {
                                /* This might be the variable name we're looking at */
                                if (strcmp(txt, var_token->text) != 0) {
                                    only_valid_tokens = 0;
                                    break;
                                }
                            }
                        }
                    }
                }
                if (only_valid_tokens) {
                    is_declaration = 1;
                }
            }

            if (is_declaration) {
                continue;  /* This is initialization, not assignment */
            }

            MutabilitySymbol *sym = find_symbol(var_token->text);
            
            if (sym && !sym->is_mutable) {
                char error_msg[512];
                snprintf(error_msg, sizeof(error_msg),
                        "Cannot assign to immutable variable '%s'. Add 'mut' qualifier to make it mutable: mut %s",
                        var_token->text, var_token->text);
                cz_error(g_filename, g_source, var_token->line, error_msg);
            }
        }
    }
}

/* Validate mutability rules */
void transpiler_validate_mutability(ASTNode *ast, const char *filename, const char *source) {
    if (!ast) {
        return;
    }

    /* Set global context for error reporting */
    g_filename = filename;
    g_source = source;

    /* Clear any existing symbol table */
    clear_symbols();

    /* Scan and track function parameters */
    scan_function_parameters(ast);

    /* Scan and track variable declarations */
    scan_variable_declarations(ast);

    /* Validate assignments */
    validate_assignments(ast);

    /* Clean up */
    clear_symbols();
}

/* Transform mutability keywords */
void transpiler_transform_mutability(ASTNode *ast) {
    if (!ast) {
        return;
    }

    if (ast->type == AST_TOKEN) {
        /* Remove 'mut' keyword by replacing it with empty string */
        if (ast->token.type == TOKEN_IDENTIFIER &&
            strcmp(ast->token.text, "mut") == 0) {
            /* Replace 'mut' with empty string */
            free(ast->token.text);
            ast->token.text = strdup("");
            ast->token.length = 0;
        }
    }

    /* Recursively transform children */
    for (size_t i = 0; i < ast->child_count; i++) {
        transpiler_transform_mutability(ast->children[i]);
    }
}
