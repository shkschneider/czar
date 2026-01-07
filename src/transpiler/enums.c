/*
 * CZar - C semantic authority layer
 * Transpiler enums module (transpiler/enums.c)
 *
 * Handles enum validation and exhaustiveness checking for switch statements.
 */

#include "../cz.h"
#include "enums.h"
#include "switches.h"
#include "../transpiler.h"
#include "../errors.h"
#include "../warnings.h"
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
    char *original_name;  /* Original name from source */
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

/* Check if a string is all uppercase (allows underscores and digits) */
static int is_all_uppercase(const char *str) {
    if (!str || !*str) {
        return 0;
    }

    for (const char *p = str; *p; p++) {
        if (isalpha((unsigned char)*p) && !isupper((unsigned char)*p)) {
            return 0;
        }
    }
    return 1;
}

/* Convert string to uppercase */
static char *to_uppercase(const char *str) {
    if (!str) {
        return NULL;
    }

    char *result = strdup(str);
    if (!result) {
        return NULL;
    }

    for (char *p = result; *p; p++) {
        *p = toupper((unsigned char)*p);
    }
    return result;
}

/* Check if enum value already has the enum prefix */
static int has_enum_prefix(const char *enum_name, const char *value_name) {
    if (!enum_name || !value_name) {
        return 0;
    }

    /* Convert enum name to uppercase for comparison */
    char *enum_upper = to_uppercase(enum_name);
    if (!enum_upper) {
        return 0;
    }

    size_t prefix_len = strlen(enum_upper);
    int has_prefix = (strncmp(value_name, enum_upper, prefix_len) == 0 &&
                      value_name[prefix_len] == '_');

    free(enum_upper);
    return has_prefix;
}

/* Generate prefixed enum value name (e.g., Color + RED -> COLOR_RED) */
static char *generate_prefixed_name(const char *enum_name, const char *value_name) {
    if (!enum_name || !value_name) {
        return NULL;
    }

    /* If already prefixed, return copy of original */
    if (has_enum_prefix(enum_name, value_name)) {
        return strdup(value_name);
    }

    /* Convert enum name to uppercase */
    char *enum_upper = to_uppercase(enum_name);
    if (!enum_upper) {
        return NULL;
    }

    /* Allocate: ENUMNAME_ + value_name + \0 */
    size_t len = strlen(enum_upper) + 1 + strlen(value_name) + 1;
    char *result = malloc(len);
    if (!result) {
        free(enum_upper);
        return NULL;
    }

    snprintf(result, len, "%s_%s", enum_upper, value_name);
    free(enum_upper);
    return result;
}

/* Register an enum declaration */
static void register_enum(const char *enum_name, EnumMember *members, int member_count) {
    if (g_enum_count >= MAX_ENUMS) {
        /* Warn about capacity limit - validation may be incomplete */
        fprintf(stderr, "[CZAR] WARNING: " WARN_MAX_ENUM_TRACKING_LIMIT "\n",
                MAX_ENUMS, enum_name);
        return;
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
    if (!info->name) {
        /* Memory allocation failed, cannot register enum */
        return;
    }
    info->member_count = member_count;

    for (int i = 0; i < member_count && i < MAX_ENUM_MEMBERS; i++) {
        info->members[i].name = strdup(members[i].name);
        info->members[i].original_name = members[i].original_name ?
                                          strdup(members[i].original_name) : NULL;
        if (!info->members[i].name) {
            /* Memory allocation failed, clean up and return */
            for (int j = 0; j < i; j++) {
                free(info->members[j].name);
                free(info->members[j].original_name);
            }
            free(info->name);
            return;
        }
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
            const char *original_name = children[i]->token.text;
            Token *member_token = &children[i]->token;

            /* Validate that enum value is ALL_UPPERCASE */
            if (enum_name && !is_all_uppercase(original_name)) {
                char error_msg[512];
                char *uppercase_suggestion = to_uppercase(original_name);
                snprintf(error_msg, sizeof(error_msg),
                         ERR_ENUM_VALUE_NOT_UPPERCASE,
                         original_name, enum_name,
                         uppercase_suggestion ? uppercase_suggestion : "UPPERCASE_VERSION");
                free(uppercase_suggestion);
                cz_error(g_filename, g_source, member_token->line, error_msg);
            }

            /* Store original name and generate prefixed name */
            members[member_count].original_name = (char *)original_name;
            if (enum_name) {
                members[member_count].name = generate_prefixed_name(enum_name, original_name);
                if (!members[member_count].name) {
                    /* Memory allocation failed, use original */
                    members[member_count].name = (char *)original_name;
                }
            } else {
                members[member_count].name = (char *)original_name;
            }
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

    /* Clean up dynamically allocated prefixed names */
    for (int j = 0; j < member_count; j++) {
        if (members[j].name != members[j].original_name) {
            free(members[j].name);
        }
    }
}

/* Check if a variable is of enum type */
static EnumInfo *get_variable_enum_type(ASTNode **children, size_t count, const char *var_name) {
    /* Search forward through AST for variable declaration
     * Note: This implementation has limitations - it may not detect:
     * - typedef'd enum types
     * - enum variables passed as function parameters
     * - enum members of structs/unions
     */
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

/* Validate switch statement for exhaustiveness and default case */
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

    /* Track which enum members are covered and if default exists */
    int covered[MAX_ENUM_MEMBERS] = {0};
    int has_default = 0;

    /* Scan switch body for case labels and default */
    for (i = switch_body_start; i < switch_body_end; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        Token *tok = &children[i]->token;

        /* Check for default case */
        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            strcmp(tok->text, "default") == 0) {
            has_default = 1;
        }

        if ((tok->type == TOKEN_KEYWORD || tok->type == TOKEN_IDENTIFIER) &&
            strcmp(tok->text, "case") == 0) {

            size_t j = skip_whitespace(children, count, i + 1);

            /* Get case label - could be EnumName.MEMBER or just MEMBER */
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {

                char *case_label = children[j]->token.text;
                int is_scoped = 0;

                /* Check for enum prefix (EnumName.MEMBER syntax) */
                size_t label_start_pos = j;
                j = skip_whitespace(children, count, j + 1);
                if (j < count && children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_OPERATOR &&
                    token_text_equals(&children[j]->token, ".")) {

                    j = skip_whitespace(children, count, j + 1);
                    if (j < count && children[j]->type == AST_TOKEN &&
                        children[j]->token.type == TOKEN_IDENTIFIER) {
                        case_label = children[j]->token.text;
                        is_scoped = 1;
                    }
                }

                /* If this is an enum switch, mark member as covered and warn if unscoped */
                if (enum_info) {
                    for (int k = 0; k < enum_info->member_count; k++) {
                        /* Compare against original name since validation happens before transformation */
                        const char *member_name_to_check = enum_info->members[k].original_name ?
                                                            enum_info->members[k].original_name :
                                                            enum_info->members[k].name;
                        if (strcmp(member_name_to_check, case_label) == 0) {
                            covered[k] = 1;

                            /* Warn if using unscoped enum constant */
                            if (!is_scoped) {
                                char warning_msg[512];
                                snprintf(warning_msg, sizeof(warning_msg),
                                         WARN_UNSCOPED_ENUM_CONSTANT,
                                         case_label, enum_info->name, case_label);
                                cz_warning(g_filename, g_source,
                                          children[label_start_pos]->token.line, warning_msg);
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    /* Check if default case is missing */
    if (!has_default) {
        if (enum_info) {
            /* ERROR: enum switch must have default case */
            char error_msg[512];
            snprintf(error_msg, sizeof(error_msg),
                     ERR_ENUM_SWITCH_MISSING_DEFAULT,
                     enum_info->name);
            cz_error(g_filename, g_source, children[switch_pos]->token.line, error_msg);
        } else {
            /* WARNING: non-enum switch should have default case */
            char warning_msg[512];
            snprintf(warning_msg, sizeof(warning_msg),
                     WARN_SWITCH_MISSING_DEFAULT);
            cz_warning(g_filename, g_source, children[switch_pos]->token.line, warning_msg);
        }
    }

    /* For enum switches with default, check if all members are covered */
    if (enum_info && has_default) {
        for (int k = 0; k < enum_info->member_count; k++) {
            if (!covered[k]) {
                /* Missing case! Use original name for error message */
                const char *member_name = enum_info->members[k].original_name ?
                                          enum_info->members[k].original_name :
                                          enum_info->members[k].name;
                char error_msg[1024];
                snprintf(error_msg, sizeof(error_msg),
                         ERR_ENUM_SWITCH_NOT_EXHAUSTIVE,
                         enum_info->name, member_name);
                cz_error(g_filename, g_source, children[switch_pos]->token.line, error_msg);
            }
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

/* Scan AST for switch statements and validate enum exhaustiveness */
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
            /* Only validate enum-specific exhaustiveness */
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

    /* Validate switch case control flow (generic switch validation) */
    transpiler_validate_switch_case_control_flow(ast, filename, source);

    /* Second pass: validate enum-specific switch exhaustiveness */
    scan_switch_statements(ast);
}

/* Remove enum prefix from scoped case labels (EnumName.MEMBER -> MEMBER) */
static void strip_enum_prefixes(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* Strip EnumName. prefix from all scoped enum references */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN ||
            children[i]->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        const char *identifier = children[i]->token.text;

        /* Check if this identifier is a registered enum name */
        EnumInfo *enum_info = find_enum(identifier);
        if (!enum_info) {
            /* Not an enum, skip */
            continue;
        }

        /* Check if this is EnumName followed by . and MEMBER */
        size_t j = skip_whitespace(children, count, i + 1);
        if (j < count && children[j]->type == AST_TOKEN &&
            children[j]->token.type == TOKEN_OPERATOR &&
            token_text_equals(&children[j]->token, ".")) {

            size_t k = skip_whitespace(children, count, j + 1);
            if (k < count && children[k]->type == AST_TOKEN &&
                children[k]->token.type == TOKEN_IDENTIFIER) {

                const char *member_name = children[k]->token.text;

                /* Verify this is actually an enum member */
                int is_member = 0;
                for (int m = 0; m < enum_info->member_count; m++) {
                    if (enum_info->members[m].original_name &&
                        strcmp(enum_info->members[m].original_name, member_name) == 0) {
                        is_member = 1;
                        break;
                    }
                }

                if (is_member) {
                    /* This is EnumName.MEMBER pattern - remove EnumName and dot */
                    /* Replace EnumName with empty string */
                    free(children[i]->token.text);
                    children[i]->token.text = strdup("");
                    if (children[i]->token.text) {
                        children[i]->token.length = 0;
                    }

                    /* Replace . with empty string */
                    free(children[j]->token.text);
                    children[j]->token.text = strdup("");
                    if (children[j]->token.text) {
                        children[j]->token.length = 0;
                    }
                }
            }
        }
    }
}


/* Prefix enum members in declarations and update all references */
static void prefix_enum_members(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    ASTNode **children = ast->children;
    size_t count = ast->child_count;

    /* First pass: Transform enum declarations to use prefixed names */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) {
            continue;
        }

        Token *token = &children[i]->token;

        /* Look for enum keyword */
        if ((token->type == TOKEN_KEYWORD || token->type == TOKEN_IDENTIFIER) &&
            token_text_equals(token, "enum")) {

            /* Skip to get enum name */
            size_t j = skip_whitespace(children, count, i + 1);
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }

            const char *enum_name = children[j]->token.text;
            EnumInfo *enum_info = find_enum(enum_name);
            if (!enum_info) {
                continue;
            }

            /* Find opening brace */
            j = skip_whitespace(children, count, j + 1);
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_PUNCTUATION ||
                !token_text_equals(&children[j]->token, "{")) {
                continue;
            }
            j = skip_whitespace(children, count, j + 1);

            /* Replace member names with prefixed versions */
            int member_idx = 0;
            while (j < count && member_idx < enum_info->member_count) {
                /* Check for closing brace */
                if (children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_PUNCTUATION &&
                    token_text_equals(&children[j]->token, "}")) {
                    break;
                }

                /* Check if this is a member name */
                if (children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_IDENTIFIER) {

                    /* Check if this matches the original member name */
                    if (enum_info->members[member_idx].original_name &&
                        strcmp(children[j]->token.text, enum_info->members[member_idx].original_name) == 0) {

                        /* Replace with prefixed name */
                        free(children[j]->token.text);
                        children[j]->token.text = strdup(enum_info->members[member_idx].name);
                        children[j]->token.length = strlen(enum_info->members[member_idx].name);
                        member_idx++;
                    }
                }
                j++;
            }
        }
    }

    /* Second pass: Update all references to enum members */
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN ||
            children[i]->token.type != TOKEN_IDENTIFIER) {
            continue;
        }

        const char *identifier = children[i]->token.text;

        /* Check all registered enums to see if this is a member */
        for (int e = 0; e < g_enum_count; e++) {
            EnumInfo *enum_info = &g_enums[e];
            for (int m = 0; m < enum_info->member_count; m++) {
                if (enum_info->members[m].original_name &&
                    strcmp(identifier, enum_info->members[m].original_name) == 0) {

                    /* Check if this is not already in the enum declaration
                     * (we don't want to replace it twice) */
                    int in_enum_decl = 0;

                    /* Look backwards for enum keyword */
                    for (size_t k = i; k > 0 && k > i - 20; k--) {
                        if (children[k]->type == AST_TOKEN &&
                            (children[k]->token.type == TOKEN_KEYWORD ||
                             children[k]->token.type == TOKEN_IDENTIFIER) &&
                            token_text_equals(&children[k]->token, "enum")) {

                            /* Check if this enum matches */
                            size_t name_idx = skip_whitespace(children, count, k + 1);
                            if (name_idx < count && children[name_idx]->type == AST_TOKEN &&
                                strcmp(children[name_idx]->token.text, enum_info->name) == 0) {
                                /* Look for opening brace */
                                size_t brace_idx = skip_whitespace(children, count, name_idx + 1);
                                if (brace_idx < count && children[brace_idx]->type == AST_TOKEN &&
                                    token_text_equals(&children[brace_idx]->token, "{")) {
                                    /* Find closing brace */
                                    size_t close_idx = brace_idx + 1;
                                    int depth = 1;
                                    while (close_idx < count && depth > 0) {
                                        if (children[close_idx]->type == AST_TOKEN &&
                                            children[close_idx]->token.type == TOKEN_PUNCTUATION) {
                                            if (token_text_equals(&children[close_idx]->token, "{")) depth++;
                                            else if (token_text_equals(&children[close_idx]->token, "}")) depth--;
                                        }
                                        close_idx++;
                                    }
                                    /* Check if current position is within enum declaration */
                                    if (i > brace_idx && i < close_idx) {
                                        in_enum_decl = 1;
                                    }
                                }
                            }
                            break;
                        }
                    }

                    if (!in_enum_decl) {
                        /* Replace with prefixed name */
                        free(children[i]->token.text);
                        children[i]->token.text = strdup(enum_info->members[m].name);
                        children[i]->token.length = strlen(enum_info->members[m].name);
                    }
                    goto next_identifier;
                }
            }
        }
        next_identifier:;
    }
}

/* Transform switch statements on enums to add default: UNREACHABLE() if missing */
void transpiler_transform_enums(ASTNode *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Strip enum prefixes from scoped case labels (EnumName.MEMBER -> MEMBER) */
    strip_enum_prefixes(ast);

    /* Prefix enum members in declarations and update all references */
    prefix_enum_members(ast);

    /* Transform continue in switch cases to fallthrough (generic switch transformation) */
    transpiler_transform_switch_continue_to_fallthrough(ast);

    /* Insert default: inline unreachable code into all switches without defaults (generic switch transformation) */
    transpiler_insert_switch_default_cases(ast, filename);
}
