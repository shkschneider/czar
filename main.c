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
#include "src/errors.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file.cz>\n", argv[0]);
        fprintf(stderr, "Generates <input_file.cz.h> and <input_file.cz.c>\n");
        return 1;
    }

    const char *input_file = argv[1];
    
    /* Generate output file names */
    size_t input_len = strlen(input_file);
    char *header_file = malloc(input_len + 3);  /* .cz + .h + \0 */
    char *source_file = malloc(input_len + 3);  /* .cz + .c + \0 */
    
    if (!header_file || !source_file) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        free(header_file);
        free(source_file);
        return 1;
    }
    
    snprintf(header_file, input_len + 3, "%s.h", input_file);
    snprintf(source_file, input_len + 3, "%s.c", input_file);
    
    /* Extract just the filename for the include directive */
    const char *filename_only = strrchr(input_file, '/');
    filename_only = filename_only ? filename_only + 1 : input_file;
    char *header_name = malloc(strlen(filename_only) + 3);
    if (!header_name) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        free(header_file);
        free(source_file);
        return 1;
    }
    snprintf(header_name, strlen(filename_only) + 3, "%s.h", filename_only);

    /* Open input file */
    FILE *input = fopen(input_file, "r");
    if (!input) {
        char error_msg[512];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_INPUT_FILE, input_file);
        cz_error(NULL, NULL, 0, error_msg);
        free(header_file);
        free(source_file);
        free(header_name);
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
        /* For empty input, create empty output files */
        FILE *h_out = fopen(header_file, "w");
        FILE *c_out = fopen(source_file, "w");
        if (h_out) fclose(h_out);
        if (c_out) fclose(c_out);
        free(header_file);
        free(source_file);
        free(header_name);
        return 0;
    }

    if (fseek(input, 0, SEEK_SET) != 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_SEEK_INPUT_FILE);
        fclose(input);
        free(header_file);
        free(source_file);
        free(header_name);
        return 1;
    }

    char *input_buffer = malloc(input_size + 1);
    if (!input_buffer) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        fclose(input);
        free(header_file);
        free(source_file);
        free(header_name);
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
        free(header_file);
        free(source_file);
        free(header_name);
        return 1;
    }

    /* Initialize transpiler */
    Transpiler transpiler;
    transpiler_init(&transpiler, ast, input_file, input_buffer);

    /* Transform AST */
    transpiler_transform(&transpiler);

    /* Open header output file */
    FILE *h_output = fopen(header_file, "w");
    if (!h_output) {
        char error_msg[512];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_OUTPUT_FILE, header_file);
        cz_error(NULL, NULL, 0, error_msg);
        ast_node_free(ast);
        free(input_buffer);
        free(header_file);
        free(source_file);
        free(header_name);
        return 1;
    }

    /* Emit header file */
    transpiler_emit_header(&transpiler, h_output);
    fclose(h_output);
    printf("Generated: %s\n", header_file);

    /* Open source output file */
    FILE *c_output = fopen(source_file, "w");
    if (!c_output) {
        char error_msg[512];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_OUTPUT_FILE, source_file);
        cz_error(NULL, NULL, 0, error_msg);
        ast_node_free(ast);
        free(input_buffer);
        free(header_file);
        free(source_file);
        free(header_name);
        return 1;
    }

    /* Emit source file */
    transpiler_emit_source(&transpiler, c_output, header_name);
    fclose(c_output);
    printf("Generated: %s\n", source_file);

    /* Clean up */
    ast_node_free(ast);
    free(input_buffer);
    free(header_file);
    free(source_file);
    free(header_name);

    return 0;
}
