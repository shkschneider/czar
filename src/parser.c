/*
 * CZar - C semantic authority layer
 * Parser implementation (parser.c)
 * 
 * Parses tokens into an Abstract Syntax Tree (AST).
 */

#include "parser.h"
#include <stdlib.h>
#include <string.h>

/* Initialize parser with lexer */
void parser_init(Parser *parser, Lexer *lexer) {
    parser->lexer = lexer;
    parser->current_token.type = TOKEN_EOF;
    parser->current_token.text = NULL;
    parser->current_token.length = 0;
}

/* Create new AST node */
static ASTNode *ast_node_create(ASTNodeType type) {
    ASTNode *node = malloc(sizeof(ASTNode));
    if (!node) {
        return NULL;
    }
    
    node->type = type;
    node->children = NULL;
    node->child_count = 0;
    node->child_capacity = 0;
    
    /* Initialize token fields */
    node->token.type = TOKEN_EOF;
    node->token.text = NULL;
    node->token.length = 0;
    node->token.line = 0;
    node->token.column = 0;
    
    return node;
}

/* Add child to AST node */
static void ast_node_add_child(ASTNode *parent, ASTNode *child) {
    if (!parent || !child) {
        return;
    }
    
    /* Grow children array if needed */
    if (parent->child_count >= parent->child_capacity) {
        size_t new_capacity = parent->child_capacity == 0 ? 8 : parent->child_capacity * 2;
        ASTNode **new_children = realloc(parent->children, new_capacity * sizeof(ASTNode *));
        if (!new_children) {
            return;
        }
        parent->children = new_children;
        parent->child_capacity = new_capacity;
    }
    
    parent->children[parent->child_count++] = child;
}

/* Free AST node and all children */
void ast_node_free(ASTNode *node) {
    if (!node) {
        return;
    }
    
    /* Free children recursively */
    for (size_t i = 0; i < node->child_count; i++) {
        ast_node_free(node->children[i]);
    }
    free(node->children);
    
    /* Free token text */
    if (node->token.text) {
        free(node->token.text);
    }
    
    free(node);
}

/* Parse input into AST */
ASTNode *parser_parse(Parser *parser) {
    /* Create root node (translation unit) */
    ASTNode *root = ast_node_create(AST_TRANSLATION_UNIT);
    if (!root) {
        return NULL;
    }
    
    /* Parse all tokens into the AST */
    Token token;
    while (1) {
        token = lexer_next_token(parser->lexer);
        
        if (token.type == TOKEN_EOF) {
            token_free(&token);
            break;
        }
        
        /* Create token node */
        ASTNode *token_node = ast_node_create(AST_TOKEN);
        if (!token_node) {
            token_free(&token);
            ast_node_free(root);
            return NULL;
        }
        
        /* Copy token data to node */
        token_node->token = token;
        
        /* Add token node to root */
        ast_node_add_child(root, token_node);
    }
    
    return root;
}
