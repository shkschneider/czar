/*
 * CZar - C semantic authority layer
 * Log transpiler module (transpiler/log.c)
 *
 * Emits runtime logging support in generated C code.
 */

#define _POSIX_C_SOURCE 200809L

#include "log.h"
#include <stdio.h>

/* Emit Log runtime support to output */
void transpiler_emit_log_runtime(FILE *output, int debug_mode) {
    if (!output) {
        return;
    }

    /* Emit Log level enum */
    fprintf(output, "/* CZar Log Runtime - Level enum */\n");
    fprintf(output, "typedef enum {\n");
    fprintf(output, "    CZ_LOG_VERBOSE = 0,\n");
    fprintf(output, "    CZ_LOG_DEBUG = 1,\n");
    fprintf(output, "    CZ_LOG_INFO = 2,\n");
    fprintf(output, "    CZ_LOG_WARN = 3,\n");
    fprintf(output, "    CZ_LOG_ERROR = 4,\n");
    fprintf(output, "    CZ_LOG_FATAL = 5\n");
    fprintf(output, "} CzLogLevel;\n\n");

    /* Emit global debug mode variable */
    fprintf(output, "/* CZar Log Runtime - Debug mode (1=only info+, 0=all levels) */\n");
    fprintf(output, "static int cz_log_debug_mode = %d;\n\n", debug_mode);

    /* Emit internal helper function */
    fprintf(output, "/* CZar Log Runtime - Internal helper */\n");
    fprintf(output, "__attribute__((unused)) static void cz_log_internal(CzLogLevel level, const char *file, int line, const char *func, const char *fmt, ...) {\n");
    fprintf(output, "    const char *level_str;\n");
    fprintf(output, "    FILE *out;\n");
    fprintf(output, "    switch (level) {\n");
    fprintf(output, "        case CZ_LOG_VERBOSE: level_str = \"VERB\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_DEBUG: level_str = \"DEBUG\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_INFO: level_str = \"INFO\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_WARN: level_str = \"WARN\"; out = stdout; break;\n");
    fprintf(output, "        case CZ_LOG_ERROR: level_str = \"ERROR\"; out = stderr; break;\n");
    fprintf(output, "        case CZ_LOG_FATAL: level_str = \"FATAL\"; out = stderr; break;\n");
    fprintf(output, "        default: level_str = \"UNKNOWN\"; out = stdout; break;\n");
    fprintf(output, "    }\n");
    fprintf(output, "    if (cz_log_debug_mode && level < CZ_LOG_INFO) return;\n");
    fprintf(output, "    fprintf(out, \"[CZAR] %%s \", level_str);\n");
    fprintf(output, "    if (func) fprintf(out, \"in %%s() \", func);\n");
    fprintf(output, "    /* Strip .c suffix from filename if present */\n");
    fprintf(output, "    const char *display_file = file ? file : \"<unknown>\";\n");
    fprintf(output, "    char file_buf[256];\n");
    fprintf(output, "    if (file) {\n");
    fprintf(output, "        size_t len = strlen(file);\n");
    fprintf(output, "        if (len > 2 && file[len-2] == '.' && file[len-1] == 'c') {\n");
    fprintf(output, "            if (len-2 < sizeof(file_buf)) {\n");
    fprintf(output, "                strncpy(file_buf, file, len-2);\n");
    fprintf(output, "                file_buf[len-2] = '\\0';\n");
    fprintf(output, "                display_file = file_buf;\n");
    fprintf(output, "            }\n");
    fprintf(output, "        }\n");
    fprintf(output, "    }\n");
    fprintf(output, "    fprintf(out, \"at %%s:%%d \", display_file, line);\n");
    fprintf(output, "    va_list args;\n");
    fprintf(output, "    va_start(args, fmt);\n");
    fprintf(output, "    vfprintf(out, fmt, args);\n");
    fprintf(output, "    va_end(args);\n");
    fprintf(output, "    fprintf(out, \"\\n\");\n");
    fprintf(output, "    fflush(out);\n");
    fprintf(output, "    if (level == CZ_LOG_FATAL) abort();\n");
    fprintf(output, "}\n\n");

    /* Emit convenience macros with __func__ support */
    fprintf(output, "/* CZar Log Runtime - Convenience macros */\n");
    fprintf(output, "#ifdef __GNUC__\n");
    fprintf(output, "#define Log_verbose(...) cz_log_internal(CZ_LOG_VERBOSE, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define Log_debug(...) cz_log_internal(CZ_LOG_DEBUG, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define Log_info(...) cz_log_internal(CZ_LOG_INFO, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define Log_warning(...) cz_log_internal(CZ_LOG_WARN, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define Log_error(...) cz_log_internal(CZ_LOG_ERROR, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#define Log_fatal(...) cz_log_internal(CZ_LOG_FATAL, __FILE__, __LINE__, __func__, __VA_ARGS__)\n");
    fprintf(output, "#else\n");
    fprintf(output, "#define Log_verbose(...) cz_log_internal(CZ_LOG_VERBOSE, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define Log_debug(...) cz_log_internal(CZ_LOG_DEBUG, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define Log_info(...) cz_log_internal(CZ_LOG_INFO, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define Log_warning(...) cz_log_internal(CZ_LOG_WARN, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define Log_error(...) cz_log_internal(CZ_LOG_ERROR, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#define Log_fatal(...) cz_log_internal(CZ_LOG_FATAL, __FILE__, __LINE__, NULL, __VA_ARGS__)\n");
    fprintf(output, "#endif\n\n");

    /* Emit Log struct with static method syntax support */
    fprintf(output, "/* CZar Log Runtime - Log struct for static method syntax */\n");
    fprintf(output, "typedef struct { int _unused; } Log;\n\n");
}
