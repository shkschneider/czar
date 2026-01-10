/*
 * CZar - C semantic authority layer
 * Lexer implementation (lexer.c)
 *
 * Tokenizes C source code into a stream of tokens.
 */

#include "lexer.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>

/* Initialize lexer with input string */
void lexer_init(Lexer *lexer, const char *input, size_t input_length) {
    lexer->input = input;
    lexer->input_length = input_length;
    lexer->position = 0;
    lexer->line = 1;
    lexer->column = 1;
}

/* Free token resources */
void token_free(Token *token) {
    if (token->text) {
        free(token->text);
        token->text = NULL;
    }
}

/* Check if character is valid in an identifier */
int is_identifier_char(char c, int first) {
    if (first) {
        return isalpha(c) || c == '_';
    }
    return isalnum(c) || c == '_';
}

/* Peek at current character without consuming */
static char peek(Lexer *lexer) {
    if (lexer->position >= lexer->input_length) {
        return '\0';
    }
    return lexer->input[lexer->position];
}

/* Peek at character at offset without consuming */
static char peek_at(Lexer *lexer, size_t offset) {
    if (lexer->position + offset >= lexer->input_length) {
        return '\0';
    }
    return lexer->input[lexer->position + offset];
}

/* Consume and return current character */
static char advance(Lexer *lexer) {
    if (lexer->position >= lexer->input_length) {
        return '\0';
    }
    char c = lexer->input[lexer->position++];
    if (c == '\n') {
        lexer->line++;
        lexer->column = 1;
    } else {
        lexer->column++;
    }
    return c;
}

/* Create token from current position */
static Token make_token(Lexer *lexer, TokenType type, size_t start, size_t length) {
    Token token;
    token.type = type;
    token.length = length;
    token.line = lexer->line;
    token.column = lexer->column;

    /* Allocate and copy token text */
    token.text = malloc(length + 1);
    if (token.text) {
        memcpy(token.text, &lexer->input[start], length);
        token.text[length] = '\0';
    } else {
        /* Memory allocation failed - set length to 0 to indicate error */
        token.length = 0;
    }

    return token;
}



/* Lex identifier or keyword */
static Token lex_identifier(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    while (is_identifier_char(peek(lexer), 0)) {
        advance(lexer);
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_IDENTIFIER, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex number */
static Token lex_number(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;
    int is_binary = 0;

    /* Handle hex numbers */
    if (peek(lexer) == '0' && (peek_at(lexer, 1) == 'x' || peek_at(lexer, 1) == 'X')) {
        advance(lexer); /* 0 */
        advance(lexer); /* x */
        while (isxdigit(peek(lexer)) || peek(lexer) == '_') {
            advance(lexer);
        }
    }
    /* Handle binary numbers */
    else if (peek(lexer) == '0' && (peek_at(lexer, 1) == 'b' || peek_at(lexer, 1) == 'B')) {
        is_binary = 1;
        advance(lexer); /* 0 */
        advance(lexer); /* b */
        while (peek(lexer) == '0' || peek(lexer) == '1' || peek(lexer) == '_') {
            advance(lexer);
        }
    } else {
        /* Handle decimal numbers */
        while (isdigit(peek(lexer)) || peek(lexer) == '_') {
            advance(lexer);
        }

        /* Handle decimal point */
        if (peek(lexer) == '.' && isdigit(peek_at(lexer, 1))) {
            advance(lexer); /* . */
            while (isdigit(peek(lexer)) || peek(lexer) == '_') {
                advance(lexer);
            }
        }

        /* Handle exponent */
        if (peek(lexer) == 'e' || peek(lexer) == 'E') {
            advance(lexer);
            if (peek(lexer) == '+' || peek(lexer) == '-') {
                advance(lexer);
            }
            while (isdigit(peek(lexer)) || peek(lexer) == '_') {
                advance(lexer);
            }
        }
    }

    /* Handle suffix (f, F, l, L, u, U, etc.) */
    char suffix[10] = {0};
    int suffix_len = 0;
    while (peek(lexer) && (tolower(peek(lexer)) == 'f' ||
                           tolower(peek(lexer)) == 'l' ||
                           tolower(peek(lexer)) == 'u')) {
        if (suffix_len < 9) {
            suffix[suffix_len++] = peek(lexer);
        }
        advance(lexer);
    }
    suffix[suffix_len] = '\0';

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_NUMBER, start, length);
    token.line = start_line;
    token.column = start_column;

    /* Process the token text */
    if (token.text) {
        /* First, remove underscores */
        char *src = token.text;
        char *dst = token.text;
        while (*src) {
            if (*src != '_') {
                *dst++ = *src;
            }
            src++;
        }
        *dst = '\0';
        size_t clean_length = dst - token.text;

        /* Convert binary to decimal */
        if (is_binary && clean_length > 2) {
            unsigned long long value = 0;
            const char *binary_digits = token.text + 2; /* Skip "0b" */
            int bit_count = 0;

            /* Calculate decimal value with overflow check */
            while (*binary_digits && (*binary_digits == '0' || *binary_digits == '1')) {
                /* Check if we're about to overflow (more than 64 bits) */
                if (bit_count >= 64) {
                    /* Too many bits - keep original token text */
                    break;
                }
                value = (value << 1) | (*binary_digits - '0');
                binary_digits++;
                bit_count++;
            }

            /* Convert to decimal string and append suffix - buffer sized for max u64 + suffix */
            char decimal_str[32]; /* Enough for 20 digit u64 + suffix */
            snprintf(decimal_str, sizeof(decimal_str), "%llu%s", value, suffix);

            /* Update token text */
            free(token.text);
            token.text = malloc(strlen(decimal_str) + 1);
            if (token.text) {
                strcpy(token.text, decimal_str);
                token.length = strlen(token.text);
            } else {
                /* Memory allocation failed */
                token.length = 0;
                token.type = TOKEN_UNKNOWN;
            }
        } else {
            token.length = clean_length;
        }
    }

    return token;
}

/* Lex string literal */
static Token lex_string(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    advance(lexer); /* opening " */

    while (peek(lexer) && peek(lexer) != '"') {
        if (peek(lexer) == '\\') {
            advance(lexer); /* escape */
            if (peek(lexer)) {
                advance(lexer); /* escaped char */
            }
        } else {
            advance(lexer);
        }
    }

    if (peek(lexer) == '"') {
        advance(lexer); /* closing " */
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_STRING, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex character literal */
static Token lex_char(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    advance(lexer); /* opening ' */

    while (peek(lexer) && peek(lexer) != '\'') {
        if (peek(lexer) == '\\') {
            advance(lexer); /* escape */
            if (peek(lexer)) {
                advance(lexer); /* escaped char */
            }
        } else {
            advance(lexer);
        }
    }

    if (peek(lexer) == '\'') {
        advance(lexer); /* closing ' */
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_CHAR, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex line comment */
static Token lex_line_comment(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    advance(lexer); /* / */
    advance(lexer); /* / */

    while (peek(lexer) && peek(lexer) != '\n') {
        advance(lexer);
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_COMMENT, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex block comment */
static Token lex_block_comment(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    advance(lexer); /* / */
    advance(lexer); /* * */

    while (peek(lexer)) {
        if (peek(lexer) == '*' && peek_at(lexer, 1) == '/') {
            advance(lexer); /* * */
            advance(lexer); /* / */
            break;
        }
        advance(lexer);
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_COMMENT, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex preprocessor directive */
static Token lex_preprocessor(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    advance(lexer); /* # */

    /* Read until end of line, handling line continuations */
    while (peek(lexer)) {
        if (peek(lexer) == '\\' && peek_at(lexer, 1) == '\n') {
            advance(lexer); /* \ */
            advance(lexer); /* \n */
        } else if (peek(lexer) == '\n') {
            advance(lexer); /* \n */
            break;
        } else {
            advance(lexer);
        }
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_PREPROCESSOR, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Punctuation characters */
#define PUNCTUATION_CHARS "(){}[];,"

/* Lex operator or punctuation */
static Token lex_operator(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    char c = peek(lexer);
    advance(lexer);

    /* Handle multi-character operators */
    char next = peek(lexer);

    /* Two-character operators */
    if ((c == '+' && next == '+') || (c == '-' && next == '-') ||
        (c == '+' && next == '=') || (c == '-' && next == '=') ||
        (c == '*' && next == '=') || (c == '/' && next == '=') ||
        (c == '%' && next == '=') || (c == '&' && next == '=') ||
        (c == '|' && next == '=') || (c == '^' && next == '=') ||
        (c == '=' && next == '=') || (c == '!' && next == '=') ||
        (c == '<' && next == '=') || (c == '>' && next == '=') ||
        (c == '&' && next == '&') || (c == '|' && next == '|') ||
        (c == '<' && next == '<') || (c == '>' && next == '>') ||
        (c == '-' && next == '>')) {
        advance(lexer);

        /* Three-character operators */
        char next2 = peek(lexer);
        if ((c == '<' && next == '<' && next2 == '=') ||
            (c == '>' && next == '>' && next2 == '=')) {
            advance(lexer);
        }
    }

    size_t length = lexer->position - start;

    /* Determine if it's punctuation or operator */
    TokenType type = TOKEN_OPERATOR;
    if (strchr(PUNCTUATION_CHARS, c)) {
        type = TOKEN_PUNCTUATION;
    }

    Token token = make_token(lexer, type, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Lex whitespace */
static Token lex_whitespace(Lexer *lexer) {
    size_t start = lexer->position;
    int start_line = lexer->line;
    int start_column = lexer->column;

    while (peek(lexer) && isspace(peek(lexer))) {
        advance(lexer);
    }

    size_t length = lexer->position - start;
    Token token = make_token(lexer, TOKEN_WHITESPACE, start, length);
    token.line = start_line;
    token.column = start_column;

    return token;
}

/* Get next token from lexer */
Token lexer_next_token(Lexer *lexer) {
    if (lexer->position >= lexer->input_length) {
        Token token;
        token.type = TOKEN_EOF;
        token.text = NULL;
        token.length = 0;
        token.line = lexer->line;
        token.column = lexer->column;
        return token;
    }

    char c = peek(lexer);
    int line = lexer->line;
    int column = lexer->column;

    /* Whitespace */
    if (isspace(c)) {
        return lex_whitespace(lexer);
    }

    /* Preprocessor directive */
    if (c == '#') {
        return lex_preprocessor(lexer);
    }

    /* Comments */
    if (c == '/' && peek_at(lexer, 1) == '/') {
        return lex_line_comment(lexer);
    }
    if (c == '/' && peek_at(lexer, 1) == '*') {
        return lex_block_comment(lexer);
    }

    /* String literal */
    if (c == '"') {
        return lex_string(lexer);
    }

    /* Character literal */
    if (c == '\'') {
        return lex_char(lexer);
    }

    /* Number */
    if (isdigit(c) || (c == '.' && isdigit(peek_at(lexer, 1)))) {
        return lex_number(lexer);
    }

    /* Identifier or keyword */
    if (is_identifier_char(c, 1)) {
        return lex_identifier(lexer);
    }

    /* Operator or punctuation */
    if (strchr("+-*/%&|^!<>=~?:;,(){}[].", c)) {
        return lex_operator(lexer);
    }

    /* Unknown token */
    size_t start = lexer->position;
    advance(lexer);
    Token token = make_token(lexer, TOKEN_UNKNOWN, start, 1);
    token.line = line;
    token.column = column;

    return token;
}
