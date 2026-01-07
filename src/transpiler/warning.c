/*
 * CZar - C semantic authority layer
 * Warning reporting implementation (transpiler/warning.c)
 *
 * Handles warning reporting with source code context.
 */

#include "../cz.h"
#include "../warnings.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Helper function to get source line for warning reporting */
static const char *get_source_line(const char *source, int line_num, char *buffer, size_t buffer_size) {
    if (!source || line_num < 1) {
        return NULL;
    }

    const char *line_start = source;
    int current_line = 1;

    /* Find the start of the target line */
    while (current_line < line_num && *line_start) {
        if (*line_start == '\n') {
            current_line++;
        }
        line_start++;
    }

    if (current_line != line_num || !*line_start) {
        return NULL;
    }

    /* Copy the line to buffer */
    const char *line_end = line_start;
    while (*line_end && *line_end != '\n' && *line_end != '\r') {
        line_end++;
    }

    size_t line_len = line_end - line_start;
    if (line_len >= buffer_size) {
        line_len = buffer_size - 1;
    }

    strncpy(buffer, line_start, line_len);
    buffer[line_len] = '\0';

    return buffer;
}

/* Report a CZar warning */
void cz_warning(const char *filename, const char *source, int line, const char *message) {
    fprintf(stdout, "[CZAR] WARNING at %s:%d: %s\n",
            filename ? filename : "<unknown>", line, message);

    /* Try to show the problematic line */
    char line_buffer[512];
    const char *source_line = get_source_line(source, line, line_buffer, sizeof(line_buffer));
    if (source_line) {
        /* Trim leading whitespace for display */
        while (*source_line && isspace((unsigned char)*source_line)) {
            source_line++;
        }
        if (*source_line) {
            fprintf(stdout, "    > %s\n", source_line);
        }
    }
}
