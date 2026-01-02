/*
 * CZar - C semantic authority layer
 * Parser header (parser.h)
 *
 * Parses tokens into an Abstract Syntax Tree (AST).
 */

#ifndef PARSER_H
#define PARSER_H

#include "lexer.h"
#include <stddef.h>

/* AST Node types */
typedef enum {
    AST_TOKEN,          /* Simple token node (leaf) */
    AST_TRANSLATION_UNIT /* Root node containing all tokens */
} ASTNodeType;

/* AST Node structure */
typedef struct ASTNode {
    ASTNodeType type;
    Token token;              /* Token data (for AST_TOKEN nodes) */
    struct ASTNode **children; /* Child nodes */
    size_t child_count;       /* Number of children */
    size_t child_capacity;    /* Capacity of children array */
} ASTNode;

/* Parser structure */
typedef struct {
    Lexer *lexer;
    Token current_token;
} Parser;

/* Initialize parser with lexer */
void parser_init(Parser *parser, Lexer *lexer);

/* Parse input into AST */
ASTNode *parser_parse(Parser *parser);

/* Free AST node and all children */
void ast_node_free(ASTNode *node);

#endif /* PARSER_H */
