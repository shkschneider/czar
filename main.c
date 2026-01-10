/*
 * CZar - C semantic authority layer
 * Main entry point for the cz tool
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "lexer.h"
#include "parser.h"
#include "transpiler.h"
#include "src/errors.h"

bool transpile(const char *input_file) {
    /* Generate output file names */
    size_t input_len = strlen(input_file);
    
    /* Check for overflow: input_len + 3 should not overflow */
    if (input_len > SIZE_MAX - 3) {
        cz_error(NULL, NULL, 0, "Input filename too long");
        return false;
    }
    
    char *header_file = malloc(input_len + 3);  /* input_file + .h + \0 */
    char *source_file = malloc(input_len + 3);  /* input_file + .c + \0 */

    if (!header_file || !source_file) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        free(header_file);
        free(source_file);
        return false;
    }

    snprintf(header_file, input_len + 3, "%s.h", input_file);
    snprintf(source_file, input_len + 3, "%s.c", input_file);

    /* Extract just the filename for the include directive */
    const char *filename_only = strrchr(input_file, '/');
    filename_only = filename_only ? filename_only + 1 : input_file;
    size_t filename_len = strlen(filename_only);
    
    /* Check for overflow: filename_len + 3 should not overflow */
    if (filename_len > SIZE_MAX - 3) {
        cz_error(NULL, NULL, 0, "Filename too long");
        free(header_file);
        free(source_file);
        return false;
    }
    
    char *header_name = malloc(filename_len + 3);
    if (!header_name) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        free(header_file);
        free(source_file);
        return false;
    }
    snprintf(header_name, filename_len + 3, "%s.h", filename_only);

    /* Open input file */
    FILE *input = fopen(input_file, "r");
    if (!input) {
        char error_msg[512];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_INPUT_FILE, input_file);
        cz_error(NULL, NULL, 0, error_msg);
        free(header_file);
        free(source_file);
        free(header_name);
        return false;
    }

    /* Read entire input file into memory */
    if (fseek(input, 0, SEEK_END) != 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_SEEK_INPUT_FILE);
        fclose(input);
        free(header_file);
        free(source_file);
        free(header_name);
        return false;
    }

    long input_size = ftell(input);
    if (input_size < 0) {
        cz_error(NULL, NULL, 0, ERR_FAILED_TO_GET_INPUT_FILE_SIZE);
        fclose(input);
        free(header_file);
        free(source_file);
        free(header_name);
        return false;
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
        return false;
    }

    char *input_buffer = malloc(input_size + 1);
    if (!input_buffer) {
        cz_error(NULL, NULL, 0, ERR_MEMORY_ALLOCATION_FAILED);
        fclose(input);
        free(header_file);
        free(source_file);
        free(header_name);
        return false;
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
        return false;
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
        return false;
    }

    /* Emit header file */
    transpiler_emit_header(&transpiler, h_output);
    fclose(h_output);

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
        return false;
    }

    /* Emit source file */
    transpiler_emit_source(&transpiler, c_output, header_name);
    fclose(c_output);

    fprintf(stdout, "%s %s\n", header_file, source_file);

    /* Clean up */
    ast_node_free(ast);
    free(input_buffer);
    free(header_file);
    free(source_file);
    free(header_name);

    return true;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file.cz ...>\n", argv[0]);
        fprintf(stderr, "Generates .cz.h and .cz.c files\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        transpile(argv[i]);
    }

    return 0;
}
