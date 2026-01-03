/*
 * CZar - C semantic authority layer
 * Transpiler enums module (transpiler/enums.c)
 *
 * Handles enum validation and exhaustiveness checking for switch statements.
 */

#define _POSIX_C_SOURCE 200809L

#include "enums.h"
#include "../transpiler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Maximum number of enums and enum members we can track */
#define MAX_ENUMS 256
#define MAX_ENUM_MEMBERS 256

/* Structure to hold enum member information */
typedef struct {
    char *name;
} EnumMember;

/* Structure to hold enum information */
typedef struct {
    char *name;           /* Name of the enum */
    EnumMember members[MAX_ENUM_MEMBERS];
    int member_count;
} EnumInfo;

/* Global enum registry */
static EnumInfo g_enums[MAX_ENUMS];
static int g_enum_count = 0;

/* Global context for error reporting */
static const char *g_filename = NULL;
static const char *g_source = NULL;

/* Helper function to check if token text matches */
static int token_text_equals(Token *token, const char *text) {
    if (!token || !token->text || !text) {
        return 0;
    }
    return strcmp(token->text, text) == 0;
}

/* Skip whitespace and comment tokens */
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

/* Register an enum declaration */
static void register_enum(const char *enum_name, EnumMember *members, int member_count) {
    if (g_enum_count >= MAX_ENUMS) {
        return; /* Silently ignore if we're at capacity */
    }

    /* Check if enum already exists */
    for (int i = 0; i < g_enum_count; i++) {
        if (g_enums[i].name && strcmp(g_enums[i].name, enum_name) == 0) {
            /* Already registered, skip */
            return;
        }
    }

    EnumInfo *info = &g_enums[g_enum_count];
    info->name = strdup(enum_name);
    info->member_count = member_count;

    for (int i = 0; i < member_count && i < MAX_ENUM_MEMBERS; i++) {
        info->members[i].name = strdup(members[i].name);
    }

    g_enum_count++;
}

/* Find enum by name */
static EnumInfo *find_enum(const char *enum_name) {
    if (!enum_name) {
        return NULL;
    }

    for (int i = 0; i < g_enum_count; i++) {
        if (g_enums[i].name && strcmp(g_enums[i].name, enum_name) == 0) {
            return &g_enums[i];
        }
    }
    return NULL;
}

/* Parse enum declaration and register it */
static void parse_enum_declaration(ASTNode **children, size_t count, size_t enum_pos) {
    size_t i = skip_whitespace(children, count, enum_pos + 1);

    /* Get enum name (optional) */
    char *enum_name = NULL;
    if (i < count && children[i]->type == AST_TOKEN &&
        children[i]->token.type == TOKEN_IDENTIFIER) {
        enum_name = children[i]->token.text;
        i = skip_whitespace(children, count, i + 1);
    }

    /* Find opening brace */
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_PUNCTUATION ||
        !token_text_equals(&children[i]->token, "{")) {
        return; /* Not an enum definition */
    }

    i = skip_whitespace(children, count, i + 1);

    /* Parse enum members */
    EnumMember members[MAX_ENUM_MEMBERS];
    int member_count = 0;

    while (i < count && member_count < MAX_ENUM_MEMBERS) {
        /* Check for closing brace */
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_PUNCTUATION &&
            token_text_equals(&children[i]->token, "}")) {
            break;
        }

        /* Get member name */
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_IDENTIFIER) {
            members[member_count].name = children[i]->token.text;
            member_count++;

            i = skip_whitespace(children, count, i + 1);

            /* Skip optional = value */
            if (i < count && children[i]->type == AST_TOKEN &&
                children[i]->token.type == TOKEN_OPERATOR &&
                token_text_equals(&children[i]->token, "=")) {
                i = skip_whitespace(children, count, i + 1);
                
                /* Skip value (number or expression) */
                while (i < count && children[i]->type == AST_TOKEN) {
                    Token *tok = &children[i]->token;
                    if (tok->type == TOKEN_PUNCTUATION &&
                        (token_text_equals(tok, ",") || token_text_equals(tok, "}"))) {
                        break;
                    }
                    i++;
                }
                i = skip_whitespace(children, count, i);
            }

            /* Skip comma */
            if (i < count && children[i]->type == AST_TOKEN &&
                children[i]->token.type == TOKEN_PUNCTUATION &&
                token_text_equals(&children[i]->token, ",")) {
                i = skip_whitespace(children, count, i + 1);
            }
        } else {
            i++;
        }
    }

    /* Register the enum if it has a name and members */
    if (enum_name && member_count > 0) {
        register_enum(enum_name, members, member_count);
    }
}

/* Check if a variable is of enum type */
static EnumInfo *get_variable_enum_type(ASTNode **children, size_t count, const char *var_name) {
    /* Search backwards for variable declaration */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;

        /* Look for "enum EnumName var_name" pattern */
        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            strcmp(tok->text, "enum") == 0) {
            
            size_t j = skip_whitespace(children, count, i + 1);
            
            /* Get enum type name */
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                char *enum_type = children[j]->token.text;
                
                j = skip_whitespace(children, count, j + 1);
                
                /* Check if this declaration is for our variable */
                while (j < count) {
                    if (children[j]->type != AST_TOKEN) {
                        j++;
                        continue;
                    }
                    
                    Token *vtok = &children[j]->token;
                    
                    /* Skip pointer markers */
                    if (vtok->type == TOKEN_OPERATOR && token_text_equals(vtok, "*")) {
                        j = skip_whitespace(children, count, j + 1);
                        continue;
                    }
                    
                    /* Check if this is our variable */
                    if (vtok->type == TOKEN_IDENTIFIER && strcmp(vtok->text, var_name) == 0) {
                        /* Found it! Return the enum info */
                        return find_enum(enum_type);
                    }
                    
                    /* If we hit a semicolon or comma, check next variable */
                    if (vtok->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(vtok, ";")) {
                            break; /* End of declaration */
                        } else if (token_text_equals(vtok, ",")) {
                            j = skip_whitespace(children, count, j + 1);
                            continue; /* Next variable in declaration */
                        } else if (token_text_equals(vtok, "=") || token_text_equals(vtok, "(") ||
                                   token_text_equals(vtok, "[")) {
                            /* Skip initialization or function params */
                            break;
                        }
                    }
                    
                    j++;
                }
            }
        }
    }
    
    return NULL;
}

/* Validate switch statement for exhaustiveness */
static void validate_switch_exhaustiveness(ASTNode **children, size_t count, size_t switch_pos) {
    /* Find the switch expression */
    size_t i = skip_whitespace(children, count, switch_pos + 1);
    
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_PUNCTUATION ||
        !token_text_equals(&children[i]->token, "(")) {
        return;
    }
    
    i = skip_whitespace(children, count, i + 1);
    
    /* Get the switched variable/expression */
    char *switch_var = NULL;
    if (i < count && children[i]->type == AST_TOKEN &&
        children[i]->token.type == TOKEN_IDENTIFIER) {
        switch_var = children[i]->token.text;
    }
    
    if (!switch_var) {
        return; /* Can't determine what we're switching on */
    }
    
    /* Check if the variable is of enum type */
    EnumInfo *enum_info = get_variable_enum_type(children, count, switch_var);
    if (!enum_info) {
        return; /* Not an enum type, no exhaustiveness check needed */
    }
    
    /* Find closing paren */
    int paren_depth = 1;
    i++;
    while (i < count && paren_depth > 0) {
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_PUNCTUATION) {
            if (token_text_equals(&children[i]->token, "(")) {
                paren_depth++;
            } else if (token_text_equals(&children[i]->token, ")")) {
                paren_depth--;
            }
        }
        i++;
    }
    
    i = skip_whitespace(children, count, i);
    
    /* Find opening brace of switch body */
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_PUNCTUATION ||
        !token_text_equals(&children[i]->token, "{")) {
        return;
    }
    
    size_t switch_body_start = i;
    
    /* Find closing brace of switch body */
    int brace_depth = 1;
    i++;
    size_t switch_body_end = i;
    while (i < count && brace_depth > 0) {
        if (children[i]->type == AST_TOKEN &&
            children[i]->token.type == TOKEN_PUNCTUATION) {
            if (token_text_equals(&children[i]->token, "{")) {
                brace_depth++;
            } else if (token_text_equals(&children[i]->token, "}")) {
                brace_depth--;
                if (brace_depth == 0) {
                    switch_body_end = i;
                }
            }
        }
        i++;
    }
    
    /* Track which enum members are covered */
    int covered[MAX_ENUM_MEMBERS] = {0};
    
    /* Scan switch body for case labels */
    for (i = switch_body_start; i < switch_body_end; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;
        
        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            strcmp(tok->text, "case") == 0) {
            
            size_t j = skip_whitespace(children, count, i + 1);
            
            /* Get case label - could be EnumName.MEMBER or just MEMBER */
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                
                char *case_label = children[j]->token.text;
                
                /* Check for enum prefix (EnumName.MEMBER syntax) */
                j = skip_whitespace(children, count, j + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_OPERATOR &&
                    token_text_equals(&children[j]->token, ".")) {
                    
                    j = skip_whitespace(children, count, j + 1);
                    if (j < count && children[j]->type == AST_TOKEN &&
                        children[j]->token.type == TOKEN_IDENTIFIER) {
                        case_label = children[j]->token.text;
                    }
                }
                
                /* Mark this member as covered */
                for (int k = 0; k < enum_info->member_count; k++) {
                    if (strcmp(enum_info->members[k].name, case_label) == 0) {
                        covered[k] = 1;
                        break;
                    }
                }
            }
        }
    }
    
    /* Check if all members are covered */
    for (int k = 0; k < enum_info->member_count; k++) {
        if (!covered[k]) {
            /* Missing case! */
            char error_msg[1024];
            snprintf(error_msg, sizeof(error_msg),
                     "Non-exhaustive switch on enum '%s': missing case for '%s'. "
                     "All enum values must be explicitly handled.",
                     enum_info->name, enum_info->members[k].name);
            cz_error(g_filename, g_source, children[switch_pos]->token.line, error_msg);
        }
    }
}

/* Scan AST for enum declarations */
static void scan_enum_declarations(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Look for "enum" keyword */
        if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER) &&
            strcmp(token->text, "enum") == 0) {
            parse_enum_declaration(children, count, i);
        }
    }
}

/* Scan AST for switch statements */
static void scan_switch_statements(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;

        Token *token = &children[i]->token;

        /* Look for "switch" keyword */
        if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER) &&
            strcmp(token->text, "switch") == 0) {
            validate_switch_exhaustiveness(children, count, i);
        }
    }
}

/* Validate enum declarations and switch statements for exhaustiveness */
void transpiler_validate_enums(ASTNode *ast, const char *filename, const char *source) {
    if (!ast) {
        return;
    }

    /* Reset global state */
    for (int i = 0; i < g_enum_count; i++) {
        free(g_enums[i].name);
        for (int j = 0; j < g_enums[i].member_count; j++) {
            free(g_enums[i].members[j].name);
        }
    }
    g_enum_count = 0;

    /* Set global context for error reporting */
    g_filename = filename;
    g_source = source;

    /* First pass: scan for enum declarations */
    scan_enum_declarations(ast);

    /* Second pass: validate switch statements */
    scan_switch_statements(ast);
}

/* Transform switch statements on enums to add default: UNREACHABLE() if missing */
void transpiler_transform_enums(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Note: This function would insert default: UNREACHABLE() clauses,
     * but doing so requires modifying the AST structure in complex ways.
     * For the initial implementation, we rely on validation to enforce
     * exhaustiveness, and developers must write explicit default cases
     * or handle all enum values. */
}
