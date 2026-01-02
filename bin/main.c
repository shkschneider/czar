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

    /* Process input line by line, stripping #pragma czar directives */
    char line[4096];
    while (fgets(line, sizeof(line), input)) {
        /* Skip lines that start with "#pragma czar" (with optional whitespace) */
        const char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        
        if (strncmp(p, "#pragma", 7) == 0) {
            p += 7;
            while (*p == ' ' || *p == '\t') p++;
            if (strncmp(p, "czar", 4) == 0) {
                /* Check that "czar" is followed by whitespace, newline, or end of string */
                char next = p[4];
                if (next == ' ' || next == '\t' || next == '\n' || next == '\r' || next == '\0') {
                    /* Skip this line - it's a #pragma czar directive */
                    continue;
                }
            }
        }
        
        /* Write all other lines (including #line directives) */
        if (fputs(line, output) == EOF) {
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
