/*
 * CZar - C semantic authority layer
 * Main entry point for the cz tool
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lexer.h"
#include "parser.h"
#include "transpiler.h"
#include "errors.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file> [output_file]\n", argv[0]);
        return 1;
    }

    const char *input_file = argv[1];
    const char *output_file = (argc >= 3) ? argv[2] : NULL;

    /* Open input file */
    FILE *input = fopen(input_file, "r");
    if (!input) {
        char error_msg[512];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_INPUT_FILE, input_file);
        cz_error(NULL, NULL, 0, error_msg);
        return 1;
    }

    /* Read entire input file into memory */
    if (fseek(input, 0, SEEK_END) != 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_SEEK_INPUT_FILE);
        fclose(input);
        return 1;
    }
    
    long input_size = ftell(input);
    if (input_size < 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_GET_INPUT_FILE_SIZE);
        fclose(input);
        return 1;
    }
    
    /* Handle empty input file */
    if (input_size == 0) {
        fclose(input);
        /* For empty input, create empty output */
        FILE *output = stdout;
        if (output_file) {
            output = fopen(output_file, "w");
            if (!output) {
                char error_msg[512];
                snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_OUTPUT_FILE, output_file);
                cz_error(NULL, NULL, 0, error_msg);
                return 1;
            }
            fclose(output);
        }
        return 0;
    }
    
    if (fseek(input, 0, SEEK_SET) != 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_SEEK_INPUT_FILE);
        fclose(input);
        return 1;
    }

    char *input_buffer = malloc(input_size + 1);
    if (!input_buffer) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        fclose(input);
        return 1;
    }

    size_t bytes_read = fread(input_buffer, 1, input_size, input);
    input_buffer[bytes_read] = '\0';
    fclose(input);

    /* Initialize lexer */
    Lexer lexer;
    lexer_init(&lexer, input_buffer, bytes_read);

    /* Initialize parser */
    Parser parser;
    parser_init(&parser, &lexer);

    /* Parse input into AST */
    ASTNode *ast = parser_parse(&parser);
    if (!ast) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_PARSE_INPUT);
        free(input_buffer);
        return 1;
    }

    /* Initialize transpiler */
    Transpiler transpiler;
    transpiler_init(&transpiler, ast, input_file, input_buffer);

    /* Transform AST */
    transpiler_transform(&transpiler);

    /* Open output file (stdout if not specified) */
    FILE *output = stdout;
    if (output_file) {
        output = fopen(output_file, "w");
        if (!output) {
            char error_msg[512];
            snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_OUTPUT_FILE, output_file);
            cz_error(NULL, NULL, 0, error_msg);
            ast_node_free(ast);
            free(input_buffer);
            return 1;
        }
    }

    /* Emit transformed AST */
    transpiler_emit(&transpiler, output);

    /* Clean up */
    if (output_file) {
        fclose(output);
    }
    ast_node_free(ast);
    free(input_buffer);

    return 0;
}
