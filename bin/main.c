/*
 * CZar - C semantic authority layer
 * Main entry point for the cz tool
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        fprintf(stderr, "Error: Cannot open input file '%s'\n", input_file);
        return 1;
    }

    /* Open output file (stdout if not specified) */
    FILE *output = stdout;
    if (output_file) {
        output = fopen(output_file, "w");
        if (!output) {
            fprintf(stderr, "Error: Cannot open output file '%s'\n", output_file);
            fclose(input);
            return 1;
        }
    }

    /* Read input and write to output (no processing yet) */
    char buffer[4096];
    size_t bytes_read;
    while ((bytes_read = fread(buffer, 1, sizeof(buffer), input)) > 0) {
        if (fwrite(buffer, 1, bytes_read, output) != bytes_read) {
            fprintf(stderr, "Error: Write failed\n");
            fclose(input);
            if (output_file) fclose(output);
            return 1;
        }
    }

    /* Clean up */
    fclose(input);
    if (output_file) fclose(output);

    return 0;
}
