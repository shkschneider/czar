/*
 * CZar - C semantic authority layer
 * Main entry point for the cz tool
 */

#include "cz.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lexer.h"
#include "parser.h"
#include "transpiler.h"
#include "transpiler/imports.h"
#include "errors.h"

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file.cz>\n", argv[0]);
        return 1;
    }

    const char *input_file = argv[1];

    /* Auto-generate output filename: input.cz -> input.cz.c */
    char output_file_buf[512];
    snprintf(output_file_buf, sizeof(output_file_buf), "%s.c", input_file);
    const char *output_file = output_file_buf;

    /* Open input file */
    FILE *input = fopen(input_file, "r");
    if (!input) {
        char error_msg[1024];
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
                char error_msg[1024];
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

    /* Open output file */
    FILE *output = fopen(output_file, "w");
    if (!output) {
        char error_msg[1024];
        snprintf(error_msg, sizeof(error_msg), ERR_CANNOT_OPEN_OUTPUT_FILE, output_file);
        cz_error(NULL, NULL, 0, error_msg);
        ast_node_free(ast);
        free(input_buffer);
        return 1;
    }

    /* Emit transformed AST */
    transpiler_emit(&transpiler, output);
    fclose(output);

    /* Split the generated .c file into .h (declarations) and .c (implementations) */
    transpiler_split_c_file(output_file);
    
    /* Copy cz.h and generate cz.c (from runtime sources) to output directory */
    char output_dir[512];
    const char *last_slash = strrchr(output_file, '/');
    if (last_slash) {
        size_t dir_len = last_slash - output_file;
        if (dir_len < sizeof(output_dir)) {
            strncpy(output_dir, output_file, dir_len);
            output_dir[dir_len] = '\0';
        } else {
            strcpy(output_dir, ".");
        }
    } else {
        strcpy(output_dir, ".");
    }
    
    /* Copy src/runtime/cz.h to output/cz.h */
    char dst_h[512], dst_c[512];
    snprintf(dst_h, sizeof(dst_h), "%s/cz.h", output_dir);
    snprintf(dst_c, sizeof(dst_c), "%s/cz.c", output_dir);
    
    FILE *src_file = fopen("src/runtime/cz.h", "r");
    if (src_file) {
        FILE *dst_file = fopen(dst_h, "w");
        if (dst_file) {
            char buffer[4096];
            size_t n;
            while ((n = fread(buffer, 1, sizeof(buffer), src_file)) > 0) {
                fwrite(buffer, 1, n, dst_file);
            }
            fclose(dst_file);
        }
        fclose(src_file);
    }
    
    /* Generate cz.c by combining runtime source implementations */
    FILE *dst_file = fopen(dst_c, "w");
    if (dst_file) {
        fprintf(dst_file, "/*\n");
        fprintf(dst_file, " * CZar Runtime - Combined from src/runtime/*.c\n");
        fprintf(dst_file, " */\n\n");
        fprintf(dst_file, "#include \"cz.h\"\n\n");
        
        /* List of runtime source files to combine */
        const char *runtime_files[] = {
            "src/runtime/monotonic.c",
            "src/runtime/log.c",
            "src/runtime/format.c",
            "src/runtime/assert.c",
            NULL
        };
        
        for (int i = 0; runtime_files[i] != NULL; i++) {
            FILE *runtime = fopen(runtime_files[i], "r");
            if (runtime) {
                fprintf(dst_file, "/* ========== From %s ========== */\n", runtime_files[i]);
                char buffer[4096];
                size_t n;
                int skip_initial_includes = 1;
                
                while ((n = fread(buffer, 1, sizeof(buffer), runtime)) > 0) {
                    /* Write content, but skip initial #include "cz.h" line */
                    if (skip_initial_includes) {
                        char *p = buffer;
                        char *end = buffer + n;
                        
                        while (p < end) {
                            /* Skip #include "cz.h" and #include "*.h" at start */
                            if (strncmp(p, "#include", 8) == 0) {
                                /* Skip to end of line */
                                while (p < end && *p != '\n') p++;
                                if (p < end) p++; /* skip newline */
                                continue;
                            }
                            /* Once we hit non-include, stop skipping */
                            if (*p != '/' && *p != '\n' && *p != '\r' && *p != ' ' && *p != '\t') {
                                skip_initial_includes = 0;
                            }
                            
                            /* Write rest of buffer */
                            fwrite(p, 1, end - p, dst_file);
                            break;
                        }
                    } else {
                        fwrite(buffer, 1, n, dst_file);
                    }
                }
                fprintf(dst_file, "\n");
                fclose(runtime);
            }
        }
        fclose(dst_file);
    }

    /* Clean up */
    ast_node_free(ast);
    free(input_buffer);

    return 0;
}
