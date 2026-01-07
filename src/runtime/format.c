/*
 * CZar - C semantic authority layer
 * Format transpiler module (runtime/format.c)
 *
 * Emits runtime format support in generated C code.
 * Provides cz_format() function with mustache-like template support.
 */

#include "../cz.h"
#include "format.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Emit Format runtime support to output */
void runtime_emit_format(FILE *output) {
    if (!output) {
        return;
    }

    /* Emit type enum for any_t */
    fprintf(output, "/* CZar Format Runtime - Type enum */\n");
    fprintf(output, "typedef enum {\n");
    fprintf(output, "    ANY_INT,\n");
    fprintf(output, "    ANY_UINT,\n");
    fprintf(output, "    ANY_LONG,\n");
    fprintf(output, "    ANY_ULONG,\n");
    fprintf(output, "    ANY_SIZE,\n");
    fprintf(output, "    ANY_DOUBLE,\n");
    fprintf(output, "    ANY_CHAR,\n");
    fprintf(output, "    ANY_CSTR,\n");
    fprintf(output, "    ANY_PTR\n");
    fprintf(output, "} any_type_t;\n");

    fprintf(output, "\n");

    /* Emit any_t union struct */
    fprintf(output, "/* CZar Format Runtime - Type-safe value container */\n");
    fprintf(output, "typedef struct {\n");
    fprintf(output, "    any_type_t type;\n");
    fprintf(output, "    union {\n");
    fprintf(output, "        long i;\n");
    fprintf(output, "        unsigned long u;\n");
    fprintf(output, "        double d;\n");
    fprintf(output, "        char c;\n");
    fprintf(output, "        const char *s;\n");
    fprintf(output, "        const void *p;\n");
    fprintf(output, "    } v;\n");
    fprintf(output, "} any_t;\n");

    fprintf(output, "\n");

    /* Emit helper functions for creating any_t values */
    fprintf(output, "/* CZar Format Runtime - Helper constructors */\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_int(int val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_INT; a.v.i = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_uint(unsigned int val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_UINT; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_long(long val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_LONG; a.v.i = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_ulong(unsigned long val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_ULONG; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_size(size_t val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_SIZE; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_double(double val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_DOUBLE; a.v.d = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_char(char val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_CHAR; a.v.c = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_cstr(const char *val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_CSTR; a.v.s = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t _cz_any_ptr(const void *val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_PTR; a.v.p = val; return a;\n");
    fprintf(output, "}\n");

    fprintf(output, "\n");

    /* Emit the internal format function that processes template and args and returns a string */
    fprintf(output, "/* CZar Format Runtime - Internal format implementation */\n");
    fprintf(output, "__attribute__((unused)) static char* _cz_format(const char *fmt, int argc, any_t *argv) {\n");
    fprintf(output, "    if (!fmt) {\n");
    fprintf(output, "        char *empty = (char*)malloc(1);\n");
    fprintf(output, "        if (empty) empty[0] = '\\0';\n");
    fprintf(output, "        return empty;\n");
    fprintf(output, "    }\n");
    fprintf(output, "    \n");
    fprintf(output, "    /* Estimate buffer size */\n");
    fprintf(output, "    size_t estimated_size = strlen(fmt) + argc * 64 + 1;\n");
    fprintf(output, "    char *result = malloc(estimated_size);\n");
    fprintf(output, "    if (!result) {\n");
    fprintf(output, "        char *empty = (char*)malloc(1);\n");
    fprintf(output, "        if (empty) empty[0] = '\\0';\n");
    fprintf(output, "        return empty;\n");
    fprintf(output, "    }\n");
    fprintf(output, "    \n");
    fprintf(output, "    char *out = result;\n");
    fprintf(output, "    int arg_idx = 0;\n");
    fprintf(output, "    const char *p = fmt;\n");
    fprintf(output, "    \n");
    fprintf(output, "    while (*p) {\n");
    fprintf(output, "        if (*p == '{' && *(p+1) == '}') {\n");
    fprintf(output, "            /* Handle {} placeholder */\n");
    fprintf(output, "            if (arg_idx < argc) {\n");
    fprintf(output, "                any_t arg = argv[arg_idx++];\n");
    fprintf(output, "                switch (arg.type) {\n");
    fprintf(output, "                    case ANY_INT:\n");
    fprintf(output, "                        out += sprintf(out, \"%%ld\", arg.v.i);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_UINT:\n");
    fprintf(output, "                        out += sprintf(out, \"%%lu\", arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_LONG:\n");
    fprintf(output, "                        out += sprintf(out, \"%%ld\", arg.v.i);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_ULONG:\n");
    fprintf(output, "                        out += sprintf(out, \"%%lu\", arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_SIZE:\n");
    fprintf(output, "                        out += sprintf(out, \"%%zu\", (size_t)arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_DOUBLE:\n");
    fprintf(output, "                        out += sprintf(out, \"%%g\", arg.v.d);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_CHAR:\n");
    fprintf(output, "                        *out++ = arg.v.c;\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_CSTR:\n");
    fprintf(output, "                        if (arg.v.s) {\n");
    fprintf(output, "                            strcpy(out, arg.v.s);\n");
    fprintf(output, "                            out += strlen(arg.v.s);\n");
    fprintf(output, "                        }\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_PTR:\n");
    fprintf(output, "                        out += sprintf(out, \"%%p\", arg.v.p);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                }\n");
    fprintf(output, "            }\n");
    fprintf(output, "            p += 2;\n");
    fprintf(output, "        } else if (*p == '{' && *(p+1) == '{') {\n");
    fprintf(output, "            /* Handle {{name}} placeholder */\n");
    fprintf(output, "            p += 2;\n");
    fprintf(output, "            /* Skip the name part */\n");
    fprintf(output, "            while (*p && !(*p == '}' && *(p+1) == '}')) p++;\n");
    fprintf(output, "            if (*p == '}' && *(p+1) == '}') {\n");
    fprintf(output, "                /* Use next argument */\n");
    fprintf(output, "                if (arg_idx < argc) {\n");
    fprintf(output, "                    any_t arg = argv[arg_idx++];\n");
    fprintf(output, "                    switch (arg.type) {\n");
    fprintf(output, "                        case ANY_INT:\n");
    fprintf(output, "                            out += sprintf(out, \"%%ld\", arg.v.i);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_UINT:\n");
    fprintf(output, "                            out += sprintf(out, \"%%lu\", arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_LONG:\n");
    fprintf(output, "                            out += sprintf(out, \"%%ld\", arg.v.i);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_ULONG:\n");
    fprintf(output, "                            out += sprintf(out, \"%%lu\", arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_SIZE:\n");
    fprintf(output, "                            out += sprintf(out, \"%%zu\", (size_t)arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_DOUBLE:\n");
    fprintf(output, "                            out += sprintf(out, \"%%g\", arg.v.d);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_CHAR:\n");
    fprintf(output, "                            *out++ = arg.v.c;\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_CSTR:\n");
    fprintf(output, "                            if (arg.v.s) {\n");
    fprintf(output, "                                strcpy(out, arg.v.s);\n");
    fprintf(output, "                                out += strlen(arg.v.s);\n");
    fprintf(output, "                            }\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_PTR:\n");
    fprintf(output, "                            out += sprintf(out, \"%%p\", arg.v.p);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                    }\n");
    fprintf(output, "                }\n");
    fprintf(output, "                p += 2;\n");
    fprintf(output, "            }\n");
    fprintf(output, "        } else {\n");
    fprintf(output, "            *out++ = *p++;\n");
    fprintf(output, "        }\n");
    fprintf(output, "    }\n");
    fprintf(output, "    *out = '\\0';\n");
    fprintf(output, "    return result;\n");
    fprintf(output, "}\n");

    fprintf(output, "\n");

    /* Emit the cz_format macro that uses _Generic to auto-detect types */
    fprintf(output, "/* CZar Format Runtime - cz_format macro with type detection */\n");
    fprintf(output, "#define cz_format(...) _CZ_FORMAT(__VA_ARGS__)\n");

    fprintf(output, "\n");

    /* Emit helper macros for counting and type detection */
    fprintf(output, "/* Helper to detect type and create any_t */\n");
    fprintf(output, "#define CZ_TO_ANY(x) _Generic((x), \\\n");
    fprintf(output, "    int: _cz_any_int, \\\n");
    fprintf(output, "    unsigned int: _cz_any_uint, \\\n");
    fprintf(output, "    long: _cz_any_long, \\\n");
    fprintf(output, "    unsigned long: _cz_any_ulong, \\\n");
    fprintf(output, "    float: _cz_any_double, \\\n");
    fprintf(output, "    double: _cz_any_double, \\\n");
    fprintf(output, "    char: _cz_any_char, \\\n");
    fprintf(output, "    char*: _cz_any_cstr, \\\n");
    fprintf(output, "    const char*: _cz_any_cstr, \\\n");
    fprintf(output, "    default: _cz_any_ptr \\\n");
    fprintf(output, ")(x)\n");

    fprintf(output, "\n");

    /* Emit implementation macros for different argument counts */
    fprintf(output, "/* Implementation macros for different argument counts */\n");
    fprintf(output, "#define _CZ_FORMAT_1(fmt) _cz_format(fmt, 0, NULL)\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_2(fmt, a1) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 1, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_3(fmt, a1, a2) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 2, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_4(fmt, a1, a2, a3) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 3, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_5(fmt, a1, a2, a3, a4) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 4, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_6(fmt, a1, a2, a3, a4, a5) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 5, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_7(fmt, a1, a2, a3, a4, a5, a6) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 6, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    fprintf(output, "#define _CZ_FORMAT_8(fmt, a1, a2, a3, a4, a5, a6, a7) ({ \\\n");
    fprintf(output, "    any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6), CZ_TO_ANY(a7)}; \\\n");
    fprintf(output, "    _cz_format(fmt, 7, _args); \\\n");
    fprintf(output, "})\n");

    fprintf(output, "\n");

    /* Emit argument counting logic */
    fprintf(output, "/* Argument counting logic */\n");
    fprintf(output, "#define _CZ_ARG_COUNT(...) _CZ_ARG_COUNT_IMPL(__VA_ARGS__, 8, 7, 6, 5, 4, 3, 2, 1)\n");
    fprintf(output, "#define _CZ_ARG_COUNT_IMPL(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N\n");

    fprintf(output, "\n");

    fprintf(output, "/* Dispatch to appropriate implementation based on argument count */\n");
    fprintf(output, "#define _CZ_FORMAT(...) _CZ_CONCAT(_CZ_FORMAT_, _CZ_ARG_COUNT(__VA_ARGS__))(__VA_ARGS__)\n");
    fprintf(output, "#define _CZ_CONCAT(a, b) _CZ_CONCAT_IMPL(a, b)\n");
    fprintf(output, "#define _CZ_CONCAT_IMPL(a, b) a##b\n");

    fprintf(output, "\n");
}
