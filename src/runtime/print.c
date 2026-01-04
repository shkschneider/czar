/*
 * CZar - C semantic authority layer
 * Print transpiler module (runtime/print.c)
 *
 * Emits runtime print support in generated C code.
 * Provides PRINT() macro with mustache-like template support.
 */

#define _POSIX_C_SOURCE 200809L

#include "print.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Emit Print runtime support to output */
void runtime_emit_print(FILE *output) {
    if (!output) {
        return;
    }

    /* Emit type enum for any_t */
    fprintf(output, "/* CZar Print Runtime - Type enum */\n");
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
    fprintf(output, "} any_type_t;\n\n");

    /* Emit any_t union struct */
    fprintf(output, "/* CZar Print Runtime - Type-safe value container */\n");
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
    fprintf(output, "} any_t;\n\n");

    /* Emit helper functions for creating any_t values */
    fprintf(output, "/* CZar Print Runtime - Helper constructors */\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_int(int val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_INT; a.v.i = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_uint(unsigned int val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_UINT; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_long(long val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_LONG; a.v.i = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_ulong(unsigned long val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_ULONG; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_size(size_t val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_SIZE; a.v.u = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_double(double val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_DOUBLE; a.v.d = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_char(char val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_CHAR; a.v.c = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_cstr(const char *val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_CSTR; a.v.s = val; return a;\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static inline any_t cz_any_ptr(const void *val) {\n");
    fprintf(output, "    any_t a; a.type = ANY_PTR; a.v.p = val; return a;\n");
    fprintf(output, "}\n\n");

    /* Emit the internal print function that processes template and args */
    fprintf(output, "/* CZar Print Runtime - Internal print implementation */\n");
    fprintf(output, "__attribute__((unused)) static void cz_print_internal(const char *fmt, int argc, any_t *argv) {\n");
    fprintf(output, "    if (!fmt) return;\n");
    fprintf(output, "    \n");
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
    fprintf(output, "                        printf(\"%%ld\", arg.v.i);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_UINT:\n");
    fprintf(output, "                        printf(\"%%lu\", arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_LONG:\n");
    fprintf(output, "                        printf(\"%%ld\", arg.v.i);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_ULONG:\n");
    fprintf(output, "                        printf(\"%%lu\", arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_SIZE:\n");
    fprintf(output, "                        printf(\"%%zu\", (size_t)arg.v.u);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_DOUBLE:\n");
    fprintf(output, "                        printf(\"%%g\", arg.v.d);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_CHAR:\n");
    fprintf(output, "                        printf(\"%%c\", arg.v.c);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_CSTR:\n");
    fprintf(output, "                        printf(\"%%s\", arg.v.s ? arg.v.s : \"(null)\");\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                    case ANY_PTR:\n");
    fprintf(output, "                        printf(\"%%p\", arg.v.p);\n");
    fprintf(output, "                        break;\n");
    fprintf(output, "                }\n");
    fprintf(output, "            }\n");
    fprintf(output, "            p += 2;\n");
    fprintf(output, "        } else if (*p == '{' && *(p+1) == '{') {\n");
    fprintf(output, "            /* Handle {{ named placeholder - skip name until }} */\n");
    fprintf(output, "            p += 2;\n");
    fprintf(output, "            while (*p && !(*p == '}' && *(p+1) == '}')) {\n");
    fprintf(output, "                p++;\n");
    fprintf(output, "            }\n");
    fprintf(output, "            if (*p == '}' && *(p+1) == '}') {\n");
    fprintf(output, "                /* Print the corresponding argument */\n");
    fprintf(output, "                if (arg_idx < argc) {\n");
    fprintf(output, "                    any_t arg = argv[arg_idx++];\n");
    fprintf(output, "                    switch (arg.type) {\n");
    fprintf(output, "                        case ANY_INT:\n");
    fprintf(output, "                            printf(\"%%ld\", arg.v.i);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_UINT:\n");
    fprintf(output, "                            printf(\"%%lu\", arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_LONG:\n");
    fprintf(output, "                            printf(\"%%ld\", arg.v.i);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_ULONG:\n");
    fprintf(output, "                            printf(\"%%lu\", arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_SIZE:\n");
    fprintf(output, "                            printf(\"%%zu\", (size_t)arg.v.u);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_DOUBLE:\n");
    fprintf(output, "                            printf(\"%%g\", arg.v.d);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_CHAR:\n");
    fprintf(output, "                            printf(\"%%c\", arg.v.c);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_CSTR:\n");
    fprintf(output, "                            printf(\"%%s\", arg.v.s ? arg.v.s : \"(null)\");\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                        case ANY_PTR:\n");
    fprintf(output, "                            printf(\"%%p\", arg.v.p);\n");
    fprintf(output, "                            break;\n");
    fprintf(output, "                    }\n");
    fprintf(output, "                }\n");
    fprintf(output, "                p += 2;\n");
    fprintf(output, "            }\n");
    fprintf(output, "        } else {\n");
    fprintf(output, "            /* Regular character - just print it */\n");
    fprintf(output, "            putchar(*p);\n");
    fprintf(output, "            p++;\n");
    fprintf(output, "        }\n");
    fprintf(output, "    }\n");
    fprintf(output, "    fflush(stdout);\n");
    fprintf(output, "}\n\n");

    /* Emit the PRINT macro that uses _Generic to auto-detect types */
    fprintf(output, "/* CZar Print Runtime - PRINT macro with type detection */\n");
    fprintf(output, "#define PRINT(...) PRINT_IMPL(__VA_ARGS__)\n\n");
    
    /* Emit helper macros for counting and type detection */
    fprintf(output, "/* Helper to detect type and create any_t */\n");
    fprintf(output, "#define CZ_TO_ANY(x) _Generic((x), \\\n");
    fprintf(output, "    int: cz_any_int, \\\n");
    fprintf(output, "    unsigned int: cz_any_uint, \\\n");
    fprintf(output, "    long: cz_any_long, \\\n");
    fprintf(output, "    unsigned long: cz_any_ulong, \\\n");
    fprintf(output, "    float: cz_any_double, \\\n");
    fprintf(output, "    double: cz_any_double, \\\n");
    fprintf(output, "    char: cz_any_char, \\\n");
    fprintf(output, "    char*: cz_any_cstr, \\\n");
    fprintf(output, "    const char*: cz_any_cstr, \\\n");
    fprintf(output, "    default: cz_any_ptr \\\n");
    fprintf(output, ")(x)\n\n");

    /* Emit implementation macros for different argument counts */
    fprintf(output, "/* Implementation macros for different argument counts */\n");
    fprintf(output, "#define PRINT_IMPL_1(fmt) \\\n");
    fprintf(output, "    cz_print_internal(fmt, 0, NULL)\n\n");
    
    fprintf(output, "#define PRINT_IMPL_2(fmt, a1) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 1, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");
    
    fprintf(output, "#define PRINT_IMPL_3(fmt, a1, a2) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 2, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");
    
    fprintf(output, "#define PRINT_IMPL_4(fmt, a1, a2, a3) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 3, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");
    
    fprintf(output, "#define PRINT_IMPL_5(fmt, a1, a2, a3, a4) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 4, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");
    
    fprintf(output, "#define PRINT_IMPL_6(fmt, a1, a2, a3, a4, a5) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 5, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");

    fprintf(output, "#define PRINT_IMPL_7(fmt, a1, a2, a3, a4, a5, a6) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 6, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");

    fprintf(output, "#define PRINT_IMPL_8(fmt, a1, a2, a3, a4, a5, a6, a7) \\\n");
    fprintf(output, "    do { \\\n");
    fprintf(output, "        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6), CZ_TO_ANY(a7)}; \\\n");
    fprintf(output, "        cz_print_internal(fmt, 7, _args); \\\n");
    fprintf(output, "    } while(0)\n\n");

    /* Emit argument counting logic */
    fprintf(output, "/* Argument counting logic */\n");
    fprintf(output, "#define CZ_ARG_COUNT(...) CZ_ARG_COUNT_IMPL(__VA_ARGS__, 8, 7, 6, 5, 4, 3, 2, 1)\n");
    fprintf(output, "#define CZ_ARG_COUNT_IMPL(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N\n\n");

    fprintf(output, "/* Dispatch to appropriate implementation based on argument count */\n");
    fprintf(output, "#define PRINT_IMPL(...) CZ_CONCAT(PRINT_IMPL_, CZ_ARG_COUNT(__VA_ARGS__))(__VA_ARGS__)\n");
    fprintf(output, "#define CZ_CONCAT(a, b) CZ_CONCAT_IMPL(a, b)\n");
    fprintf(output, "#define CZ_CONCAT_IMPL(a, b) a##b\n\n");
}
