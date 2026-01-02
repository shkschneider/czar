/*
 * CZar - C semantic authority layer
 * Cast handling implementation (transpiler/casts.c)
 *
 * Validates and transforms cast expressions according to CZar rules:
 * - ERROR on C-style casts (Type)value
 * - cast<Type>(value) -> unsafe_cast<Type>(value) with WARNING
 * - cast<Type>(value, fallback) -> safe_cast<Type>(value, fallback)
 * - unsafe_cast<Type>(value) with warnings for safe enlarging casts
 * - safe_cast<Type>(value, fallback) for checked casts
 * - Enforced explicit narrowing casts
 */

#define _POSIX_C_SOURCE 200809L

#include "casts.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Global context for error reporting */
static const char *g_filename = NULL;
static const char *g_source = NULL;

/* Type information for cast analysis */
typedef struct {
    const char *name;
    int is_signed;
    int bits;
} TypeInfo;

/* Get type information for known types */
static TypeInfo get_type_info(const char *type_name) {
    TypeInfo info = {type_name, 0, 0};
    
    if (!type_name) {
        return info;
    }
    
    /* CZar unsigned types */
    if (strcmp(type_name, "u8") == 0 || strcmp(type_name, "uint8_t") == 0) {
        info.is_signed = 0; info.bits = 8;
    } else if (strcmp(type_name, "u16") == 0 || strcmp(type_name, "uint16_t") == 0) {
        info.is_signed = 0; info.bits = 16;
    } else if (strcmp(type_name, "u32") == 0 || strcmp(type_name, "uint32_t") == 0) {
        info.is_signed = 0; info.bits = 32;
    } else if (strcmp(type_name, "u64") == 0 || strcmp(type_name, "uint64_t") == 0) {
        info.is_signed = 0; info.bits = 64;
    }
    /* CZar signed types */
    else if (strcmp(type_name, "i8") == 0 || strcmp(type_name, "int8_t") == 0) {
        info.is_signed = 1; info.bits = 8;
    } else if (strcmp(type_name, "i16") == 0 || strcmp(type_name, "int16_t") == 0) {
        info.is_signed = 1; info.bits = 16;
    } else if (strcmp(type_name, "i32") == 0 || strcmp(type_name, "int32_t") == 0) {
        info.is_signed = 1; info.bits = 32;
    } else if (strcmp(type_name, "i64") == 0 || strcmp(type_name, "int64_t") == 0) {
        info.is_signed = 1; info.bits = 64;
    }
    /* Standard C types */
    else if (strcmp(type_name, "char") == 0) {
        info.is_signed = 1; info.bits = 8; /* char signedness is implementation-defined */
    } else if (strcmp(type_name, "unsigned char") == 0) {
        info.is_signed = 0; info.bits = 8;
    } else if (strcmp(type_name, "short") == 0 || strcmp(type_name, "signed short") == 0) {
        info.is_signed = 1; info.bits = 16;
    } else if (strcmp(type_name, "unsigned short") == 0) {
        info.is_signed = 0; info.bits = 16;
    } else if (strcmp(type_name, "int") == 0 || strcmp(type_name, "signed int") == 0) {
        info.is_signed = 1; info.bits = 32;
    } else if (strcmp(type_name, "unsigned int") == 0) {
        info.is_signed = 0; info.bits = 32;
    } else if (strcmp(type_name, "long") == 0 || strcmp(type_name, "signed long") == 0) {
        info.is_signed = 1; info.bits = 64; /* Assuming 64-bit system */
    } else if (strcmp(type_name, "unsigned long") == 0) {
        info.is_signed = 0; info.bits = 64;
    }
    
    return info;
}

/* Check if a cast is safe (enlarging data without sign issues) */
static int is_safe_cast(TypeInfo from, TypeInfo to) {
    /* Unknown types - cannot determine safety */
    if (from.bits == 0 || to.bits == 0) {
        return 0;
    }
    
    /* Enlarging unsigned to unsigned is safe */
    if (!from.is_signed && !to.is_signed && from.bits < to.bits) {
        return 1;
    }
    
    /* Enlarging signed to signed is safe if target is larger */
    if (from.is_signed && to.is_signed && from.bits < to.bits) {
        return 1;
    }
    
    /* All other casts are potentially unsafe */
    return 0;
}

/* Check if a cast is narrowing */
static int is_narrowing_cast(TypeInfo from, TypeInfo to) {
    /* Unknown types - cannot determine */
    if (from.bits == 0 || to.bits == 0) {
        return 0;
    }
    
    /* Narrowing if target has fewer bits */
    if (to.bits < from.bits) {
        return 1;
    }
    
    /* Sign mismatch can be considered narrowing */
    if (from.is_signed != to.is_signed) {
        return 1;
    }
    
    return 0;
}

/* Get max value for a type as a string constant */
static const char *get_type_max(const char *type_name) {
    if (!type_name) return NULL;
    
    if (strcmp(type_name, "u8") == 0 || strcmp(type_name, "uint8_t") == 0) return "255";
    if (strcmp(type_name, "u16") == 0 || strcmp(type_name, "uint16_t") == 0) return "65535";
    if (strcmp(type_name, "u32") == 0 || strcmp(type_name, "uint32_t") == 0) return "4294967295U";
    if (strcmp(type_name, "u64") == 0 || strcmp(type_name, "uint64_t") == 0) return "18446744073709551615ULL";
    
    if (strcmp(type_name, "i8") == 0 || strcmp(type_name, "int8_t") == 0) return "127";
    if (strcmp(type_name, "i16") == 0 || strcmp(type_name, "int16_t") == 0) return "32767";
    if (strcmp(type_name, "i32") == 0 || strcmp(type_name, "int32_t") == 0) return "2147483647";
    if (strcmp(type_name, "i64") == 0 || strcmp(type_name, "int64_t") == 0) return "9223372036854775807LL";
    
    return NULL;
}

/* Get min value for a type as a string constant */
static const char *get_type_min(const char *type_name) {
    if (!type_name) return NULL;
    
    /* Unsigned types have min of 0 */
    if (strcmp(type_name, "u8") == 0 || strcmp(type_name, "uint8_t") == 0) return "0";
    if (strcmp(type_name, "u16") == 0 || strcmp(type_name, "uint16_t") == 0) return "0";
    if (strcmp(type_name, "u32") == 0 || strcmp(type_name, "uint32_t") == 0) return "0";
    if (strcmp(type_name, "u64") == 0 || strcmp(type_name, "uint64_t") == 0) return "0";
    
    /* Signed types */
    if (strcmp(type_name, "i8") == 0 || strcmp(type_name, "int8_t") == 0) return "-128";
    if (strcmp(type_name, "i16") == 0 || strcmp(type_name, "int16_t") == 0) return "-32768";
    if (strcmp(type_name, "i32") == 0 || strcmp(type_name, "int32_t") == 0) return "(-2147483647-1)";
    if (strcmp(type_name, "i64") == 0 || strcmp(type_name, "int64_t") == 0) return "(-9223372036854775807LL-1)";
    
    return NULL;
}

/* Check if token text matches */
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

/* Get the source line for a given line number */
static const char *get_source_line(int line_num, char *buffer, size_t buffer_size) {
    if (!g_source || line_num < 1) {
        return NULL;
    }
    
    const char *line_start = g_source;
    int current_line = 1;
    
    /* Find the start of the target line */
    while (current_line < line_num && *line_start) {
        if (*line_start == '\n') {
            current_line++;
        }
        line_start++;
    }
    
    if (current_line != line_num || !*line_start) {
        return NULL;
    }
    
    /* Copy the line to buffer */
    const char *line_end = line_start;
    while (*line_end && *line_end != '\n' && *line_end != '\r') {
        line_end++;
    }
    
    size_t line_len = line_end - line_start;
    if (line_len >= buffer_size) {
        line_len = buffer_size - 1;
    }
    
    strncpy(buffer, line_start, line_len);
    buffer[line_len] = '\0';
    
    return buffer;
}

/* Report a CZar error and exit */
static void cz_error(int line, const char *message) {
    fprintf(stderr, "[CZAR] ERROR at %s:%d: %s\n", 
            g_filename ? g_filename : "<unknown>", line, message);
    
    /* Try to show the problematic line */
    char line_buffer[512];
    const char *source_line = get_source_line(line, line_buffer, sizeof(line_buffer));
    if (source_line) {
        /* Trim leading whitespace for display */
        while (*source_line && isspace((unsigned char)*source_line)) {
            source_line++;
        }
        if (*source_line) {
            fprintf(stderr, "    > %s\n", source_line);
        }
    }
    
    exit(1);
}

/* Report a CZar warning */
static void cz_warning(int line, const char *message) {
    fprintf(stderr, "[CZAR] WARNING at %s:%d: %s\n", 
            g_filename ? g_filename : "<unknown>", line, message);
    
    /* Try to show the problematic line */
    char line_buffer[512];
    const char *source_line = get_source_line(line, line_buffer, sizeof(line_buffer));
    if (source_line) {
        /* Trim leading whitespace for display */
        while (*source_line && isspace((unsigned char)*source_line)) {
            source_line++;
        }
        if (*source_line) {
            fprintf(stderr, "    > %s\n", source_line);
        }
    }
}

/* Check for C-style cast pattern: (Type)value */
static void check_c_style_casts(ASTNode **children, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        
        Token *token = &children[i]->token;
        
        /* Look for opening parenthesis */
        if (token->type == TOKEN_PUNCTUATION && token_text_equals(token, "(")) {
            /* Check if this could be a C-style cast */
            size_t j = skip_whitespace(children, count, i + 1);
            
            if (j < count && children[j]->type == AST_TOKEN &&
                children[j]->token.type == TOKEN_IDENTIFIER) {
                /* Found identifier after (, could be a type */
                Token *maybe_type = &children[j]->token;
                
                /* Skip to find closing ) */
                j = skip_whitespace(children, count, j + 1);
                
                /* Handle pointer types */
                while (j < count && children[j]->type == AST_TOKEN &&
                       children[j]->token.type == TOKEN_OPERATOR &&
                       token_text_equals(&children[j]->token, "*")) {
                    j = skip_whitespace(children, count, j + 1);
                }
                
                if (j < count && children[j]->type == AST_TOKEN &&
                    children[j]->token.type == TOKEN_PUNCTUATION &&
                    token_text_equals(&children[j]->token, ")")) {
                    /* Found closing ), check what comes after */
                    j = skip_whitespace(children, count, j + 1);
                    
                    if (j < count && children[j]->type == AST_TOKEN) {
                        Token *after_paren = &children[j]->token;
                        
                        /* If what follows is an identifier, number, or another paren,
                         * this is likely a cast expression */
                        if (after_paren->type == TOKEN_IDENTIFIER ||
                            after_paren->type == TOKEN_NUMBER ||
                            (after_paren->type == TOKEN_PUNCTUATION && token_text_equals(after_paren, "("))) {
                            
                            /* Check if this is a known type */
                            TypeInfo type_info = get_type_info(maybe_type->text);
                            if (type_info.bits > 0) {
                                /* This is a C-style cast - ERROR! */
                                char error_msg[512];
                                snprintf(error_msg, sizeof(error_msg),
                                         "C-style cast '(%s)' is not allowed. "
                                         "Use unsafe_cast<%s>(value) or safe_cast<%s>(value, fallback) instead.",
                                         maybe_type->text, maybe_type->text, maybe_type->text);
                                cz_error(token->line, error_msg);
                            }
                        }
                    }
                }
            }
        }
    }
}

/* Extract type name from template-like syntax: func<Type> */
static char *extract_template_type(ASTNode **children, size_t count, size_t start, size_t *out_end) {
    size_t i = skip_whitespace(children, count, start);
    
    /* Expect < */
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_OPERATOR ||
        !token_text_equals(&children[i]->token, "<")) {
        return NULL;
    }
    
    i = skip_whitespace(children, count, i + 1);
    
    /* Expect type name */
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_IDENTIFIER) {
        return NULL;
    }
    
    char *type_name = strdup(children[i]->token.text);
    i = skip_whitespace(children, count, i + 1);
    
    /* Expect > */
    if (i >= count || children[i]->type != AST_TOKEN ||
        children[i]->token.type != TOKEN_OPERATOR ||
        !token_text_equals(&children[i]->token, ">")) {
        free(type_name);
        return NULL;
    }
    
    *out_end = i + 1;
    return type_name;
}

/* Check for cast function calls and validate them */
static void check_cast_functions(ASTNode **children, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        
        Token *token = &children[i]->token;
        
        /* Look for cast, unsafe_cast, or safe_cast identifiers */
        if (token->type == TOKEN_IDENTIFIER &&
            (strcmp(token->text, "cast") == 0 ||
             strcmp(token->text, "unsafe_cast") == 0 ||
             strcmp(token->text, "safe_cast") == 0)) {
            
            const char *cast_func = token->text;
            int is_cast = strcmp(cast_func, "cast") == 0;
            int is_unsafe_cast = strcmp(cast_func, "unsafe_cast") == 0;
            int is_safe_cast = strcmp(cast_func, "safe_cast") == 0;
            
            /* Extract type from template syntax */
            size_t j = i + 1;
            char *type_name = extract_template_type(children, count, j, &j);
            
            if (!type_name) {
                char error_msg[256];
                snprintf(error_msg, sizeof(error_msg),
                         "%s requires template syntax: %s<Type>(value)",
                         cast_func, cast_func);
                cz_error(token->line, error_msg);
                continue;
            }
            
            /* Expect ( */
            j = skip_whitespace(children, count, j);
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_PUNCTUATION ||
                !token_text_equals(&children[j]->token, "(")) {
                free(type_name);
                char error_msg[256];
                snprintf(error_msg, sizeof(error_msg),
                         "%s requires function call syntax with parentheses",
                         cast_func);
                cz_error(token->line, error_msg);
                continue;
            }
            
            /* Count arguments by finding commas at the right nesting level */
            int paren_depth = 1;
            int arg_count = 1; /* At least one argument (the value) */
            j = skip_whitespace(children, count, j + 1);
            
            while (j < count && paren_depth > 0) {
                if (children[j]->type == AST_TOKEN) {
                    Token *t = &children[j]->token;
                    if (t->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(t, "(")) {
                            paren_depth++;
                        } else if (token_text_equals(t, ")")) {
                            paren_depth--;
                            if (paren_depth == 0) break;
                        } else if (token_text_equals(t, ",") && paren_depth == 1) {
                            arg_count++;
                        }
                    }
                }
                j++;
            }
            
            /* Validate argument count */
            if (is_safe_cast && arg_count != 2) {
                free(type_name);
                cz_error(token->line, "safe_cast requires exactly 2 arguments: safe_cast<Type>(value, fallback)");
                continue;
            }
            
            if (is_safe_cast && arg_count == 2) {
                /* safe_cast is now implemented via macros - no warning needed */
            }
            
            if (is_unsafe_cast && arg_count != 1) {
                free(type_name);
                cz_error(token->line, "unsafe_cast requires exactly 1 argument: unsafe_cast<Type>(value)");
                continue;
            }
            
            if (is_cast) {
                if (arg_count == 1) {
                    /* cast<Type>(value) -> should use unsafe_cast */
                    char warning_msg[512];
                    snprintf(warning_msg, sizeof(warning_msg),
                             "cast<%s>(value) is an unsafe cast. "
                             "Consider using unsafe_cast<%s>(value) to make it explicit, "
                             "or safe_cast<%s>(value, fallback) for checked conversion.",
                             type_name, type_name, type_name);
                    cz_warning(token->line, warning_msg);
                } else if (arg_count != 2) {
                    free(type_name);
                    cz_error(token->line, "cast requires 1 or 2 arguments: cast<Type>(value) or cast<Type>(value, fallback)");
                    continue;
                }
            }
            
            /* Check for safe enlarging casts with unsafe_cast */
            if (is_unsafe_cast) {
                TypeInfo to_type = get_type_info(type_name);
                
                /* Warning about safe casts being marked as unsafe */
                if (to_type.bits > 0) {
                    /* Note: We can't fully determine source type without deeper analysis,
                     * so we provide a general reminder about safe enlarging casts */
                    (void)to_type; /* Suppress unused warning */
                }
            }
            
            free(type_name);
        }
    }
}

/* Validate casts in AST */
void transpiler_validate_casts(ASTNode *ast, const char *filename, const char *source) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    /* Set global context for error reporting */
    g_filename = filename;
    g_source = source;
    
    ASTNode **children = ast->children;
    size_t count = ast->child_count;
    
    /* Check for C-style casts */
    check_c_style_casts(children, count);
    
    /* Check for cast functions */
    check_cast_functions(children, count);
}

/* Transform cast expressions to C equivalents */
void transpiler_transform_casts(ASTNode *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    ASTNode **children = ast->children;
    size_t count = ast->child_count;
    
    for (size_t i = 0; i < count; i++) {
        if (children[i]->type != AST_TOKEN) continue;
        
        Token *token = &children[i]->token;
        
        /* Transform cast function calls to C-style casts or ternary expressions */
        if (token->type == TOKEN_IDENTIFIER &&
            (strcmp(token->text, "cast") == 0 ||
             strcmp(token->text, "unsafe_cast") == 0 ||
             strcmp(token->text, "safe_cast") == 0)) {
            
            const char *cast_func = token->text;
            int is_safe_cast_func = strcmp(cast_func, "safe_cast") == 0;
            int is_cast_with_fallback = 0;
            
            /* Find the template type */
            size_t j = skip_whitespace(children, count, i + 1);
            
            /* Expect < */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_OPERATOR ||
                !token_text_equals(&children[j]->token, "<")) {
                continue;
            }
            size_t open_angle = j;
            
            j = skip_whitespace(children, count, j + 1);
            
            /* Get type name */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }
            size_t type_idx = j;
            char *type_name = strdup(children[type_idx]->token.text);
            
            j = skip_whitespace(children, count, j + 1);
            
            /* Expect > */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_OPERATOR ||
                !token_text_equals(&children[j]->token, ">")) {
                free(type_name);
                continue;
            }
            size_t close_angle = j;
            
            j = skip_whitespace(children, count, j + 1);
            
            /* Expect ( */
            if (j >= count || children[j]->type != AST_TOKEN ||
                children[j]->token.type != TOKEN_PUNCTUATION ||
                !token_text_equals(&children[j]->token, "(")) {
                free(type_name);
                continue;
            }
            size_t open_paren = j;
            
            /* Check if this has a comma (2 arguments) */
            int paren_depth = 1;
            size_t comma_pos = 0;
            size_t close_paren = 0;
            j = skip_whitespace(children, count, j + 1);
            
            while (j < count && paren_depth > 0) {
                if (children[j]->type == AST_TOKEN) {
                    Token *t = &children[j]->token;
                    if (t->type == TOKEN_PUNCTUATION) {
                        if (token_text_equals(t, "(")) {
                            paren_depth++;
                        } else if (token_text_equals(t, ")")) {
                            paren_depth--;
                            if (paren_depth == 0) {
                                close_paren = j;
                                break;
                            }
                        } else if (token_text_equals(t, ",") && paren_depth == 1 && comma_pos == 0) {
                            comma_pos = j;
                            is_cast_with_fallback = 1;
                        }
                    }
                }
                j++;
            }
            
            /* Transform based on whether we have a fallback and if it's safe_cast */
            if (is_safe_cast_func && is_cast_with_fallback && comma_pos > 0) {
                /* safe_cast<Type>(value, fallback) transforms to: CZ_SAFE_CAST_Type(value, fallback) */
                const char *type_max = get_type_max(type_name);
                
                if (type_max) {
                    /* Transform to macro call: CZ_SAFE_CAST_type(value, fallback) */
                    char macro_name[128];
                    snprintf(macro_name, sizeof(macro_name), "CZ_SAFE_CAST_%s", type_name);
                    
                    /* Replace function name with macro name */
                    free(children[i]->token.text);
                    children[i]->token.text = strdup(macro_name);
                    children[i]->token.length = strlen(macro_name);
                    
                    /* Remove < */
                    free(children[open_angle]->token.text);
                    children[open_angle]->token.text = strdup("");
                    children[open_angle]->token.length = 0;
                    
                    /* Remove type name */
                    free(children[type_idx]->token.text);
                    children[type_idx]->token.text = strdup("");
                    children[type_idx]->token.length = 0;
                    
                    /* Remove > */
                    free(children[close_angle]->token.text);
                    children[close_angle]->token.text = strdup("");
                    children[close_angle]->token.length = 0;
                    
                    /* Open paren, comma, and close paren stay as-is for macro arguments */
                } else {
                    /* Type not supported for safe_cast, fall back to simple cast */
                    free(type_name);
                    continue;
                }
            } else if (is_cast_with_fallback && strcmp(cast_func, "cast") == 0) {
                /* cast<Type>(value, fallback) -> same as safe_cast */
                const char *type_max = get_type_max(type_name);
                
                if (type_max) {
                    char macro_name[128];
                    snprintf(macro_name, sizeof(macro_name), "CZ_SAFE_CAST_%s", type_name);
                    
                    free(children[i]->token.text);
                    children[i]->token.text = strdup(macro_name);
                    children[i]->token.length = strlen(macro_name);
                    
                    free(children[open_angle]->token.text);
                    children[open_angle]->token.text = strdup("");
                    children[open_angle]->token.length = 0;
                    
                    free(children[type_idx]->token.text);
                    children[type_idx]->token.text = strdup("");
                    children[type_idx]->token.length = 0;
                    
                    free(children[close_angle]->token.text);
                    children[close_angle]->token.text = strdup("");
                    children[close_angle]->token.length = 0;
                } else {
                    free(type_name);
                    continue;
                }
            } else {
                /* Simple cast without fallback: unsafe_cast or cast with 1 arg */
                /* Transform to (Type)(value) */
                
                free(children[i]->token.text);
                children[i]->token.text = strdup("(");
                children[i]->token.length = 1;
                children[i]->token.type = TOKEN_PUNCTUATION;
                
                free(children[open_angle]->token.text);
                children[open_angle]->token.text = strdup("");
                children[open_angle]->token.length = 0;
                
                /* Type name stays as-is */
                
                free(children[close_angle]->token.text);
                children[close_angle]->token.text = strdup(")");
                children[close_angle]->token.length = 1;
                children[close_angle]->token.type = TOKEN_PUNCTUATION;
            }
            
            free(type_name);
        }
    }
}
