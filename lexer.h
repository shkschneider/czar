/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Tokenizes C source code into a stream of tokens.
 */

#pragma once

#include <stddef.h>

/* Token types */
typedef enum {
    TOKEN_EOF,
    TOKEN_IDENTIFIER,
    TOKEN_KEYWORD,
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_CHAR,
    TOKEN_OPERATOR,
    TOKEN_PUNCTUATION,
    TOKEN_PREPROCESSOR,
    TOKEN_WHITESPACE,
    TOKEN_COMMENT,
    TOKEN_UNKNOWN
} TokenType;

/* Token structure */
typedef struct {
    TokenType type;
    char *text;       /* Token text (owned by token, must be freed) */
    size_t length;    /* Length of token text */
    int line;         /* Line number (for error reporting) */
    int column;       /* Column number (for error reporting) */
} Token;

/* Lexer structure */
typedef struct {
    const char *input;      /* Input string */
    size_t input_length;    /* Length of input */
    size_t position;        /* Current position in input */
    int line;               /* Current line number */
    int column;             /* Current column number */
} Lexer;

/* Initialize lexer with input string */
void lexer_init(Lexer *lexer, const char *input, size_t input_length);

/* Get next token from lexer */
Token lexer_next_token(Lexer *lexer);

/* Free token resources */
void token_free(Token *token);

/* Check if character is valid in an identifier */
int is_identifier_char(char c, int first);
