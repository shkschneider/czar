/*
 * CZar Runtime Library
 * Format implementation - Type-safe string formatting
 */

#include "cz.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Internal format implementation */
char* cz_format_impl(const char *fmt, int argc, cz_any_t *argv) {
    if (!fmt) {
        char *empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    
    /* Estimate buffer size */
    size_t estimated_size = strlen(fmt) + argc * 64 + 1;
    char *result = malloc(estimated_size);
    if (!result) {
        char *empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    
    char *out = result;
    int arg_idx = 0;
    const char *p = fmt;
    
    while (*p) {
        if (*p == '{' && *(p+1) == '}') {
            /* Handle {} placeholder */
            if (arg_idx < argc) {
                cz_any_t arg = argv[arg_idx++];
                switch (arg.type) {
                    case CZ_ANY_INT:
                        out += sprintf(out, "%ld", arg.v.i);
                        break;
                    case CZ_ANY_UINT:
                        out += sprintf(out, "%lu", arg.v.u);
                        break;
                    case CZ_ANY_LONG:
                        out += sprintf(out, "%ld", arg.v.i);
                        break;
                    case CZ_ANY_ULONG:
                        out += sprintf(out, "%lu", arg.v.u);
                        break;
                    case CZ_ANY_SIZE:
                        out += sprintf(out, "%zu", (size_t)arg.v.u);
                        break;
                    case CZ_ANY_DOUBLE:
                        out += sprintf(out, "%g", arg.v.d);
                        break;
                    case CZ_ANY_CHAR:
                        *out++ = arg.v.c;
                        break;
                    case CZ_ANY_CSTR:
                        if (arg.v.s) {
                            strcpy(out, arg.v.s);
                            out += strlen(arg.v.s);
                        }
                        break;
                    case CZ_ANY_PTR:
                        out += sprintf(out, "%p", arg.v.p);
                        break;
                }
            }
            p += 2;
        } else if (*p == '{' && *(p+1) == '{') {
            /* Handle {{name}} placeholder */
            p += 2;
            /* Skip the name part */
            while (*p && !(*p == '}' && *(p+1) == '}')) p++;
            if (*p == '}' && *(p+1) == '}') {
                /* Use next argument */
                if (arg_idx < argc) {
                    cz_any_t arg = argv[arg_idx++];
                    switch (arg.type) {
                        case CZ_ANY_INT:
                            out += sprintf(out, "%ld", arg.v.i);
                            break;
                        case CZ_ANY_UINT:
                            out += sprintf(out, "%lu", arg.v.u);
                            break;
                        case CZ_ANY_LONG:
                            out += sprintf(out, "%ld", arg.v.i);
                            break;
                        case CZ_ANY_ULONG:
                            out += sprintf(out, "%lu", arg.v.u);
                            break;
                        case CZ_ANY_SIZE:
                            out += sprintf(out, "%zu", (size_t)arg.v.u);
                            break;
                        case CZ_ANY_DOUBLE:
                            out += sprintf(out, "%g", arg.v.d);
                            break;
                        case CZ_ANY_CHAR:
                            *out++ = arg.v.c;
                            break;
                        case CZ_ANY_CSTR:
                            if (arg.v.s) {
                                strcpy(out, arg.v.s);
                                out += strlen(arg.v.s);
                            }
                            break;
                        case CZ_ANY_PTR:
                            out += sprintf(out, "%p", arg.v.p);
                            break;
                    }
                }
                p += 2;
            }
        } else {
            *out++ = *p++;
        }
    }
    *out = '\0';
    return result;
}
