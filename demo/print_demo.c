#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stdarg.h>
#include <string.h>

#define ASSERT(cond) do {\
  if (!(cond)) {\
    fprintf(stderr, "[CZAR] ASSERTION failed at %s:%d: %s\n", __FILE__, __LINE__, #cond);\
    abort();\
  }\
} while (0)\
\
/* CZar Log Runtime - Level enum */
typedef enum {
    CZ_LOG_VERBOSE = 0,
    CZ_LOG_DEBUG = 1,
    CZ_LOG_INFO = 2,
    CZ_LOG_WARN = 3,
    CZ_LOG_ERROR = 4,
    CZ_LOG_FATAL = 5
} CzLogLevel;

/* CZar Log Runtime - Debug mode (1=only info+, 0=all levels) */
static int CZ_LOG_DEBUG_MODE = 1;

/* CZar Log Runtime - Internal helper */
__attribute__((unused)) static void cz_log(CzLogLevel level, const char *file, int line, const char *func, const char *fmt, ...) {
    const char *level_str;
    FILE *out;
    switch (level) {
        case CZ_LOG_VERBOSE: level_str = "VERB"; out = stdout; break;
        case CZ_LOG_DEBUG: level_str = "DEBUG"; out = stdout; break;
        case CZ_LOG_INFO: level_str = "INFO"; out = stdout; break;
        case CZ_LOG_WARN: level_str = "WARN"; out = stdout; break;
        case CZ_LOG_ERROR: level_str = "ERROR"; out = stderr; break;
        case CZ_LOG_FATAL: level_str = "FATAL"; out = stderr; break;
        default: level_str = "UNKNOWN"; out = stdout; break;
    }
    if (CZ_LOG_DEBUG_MODE && level < CZ_LOG_INFO) return;
    fprintf(out, "[CZAR] %s ", level_str);
    if (func) fprintf(out, "in %s() ", func);
    /* Strip .c suffix from filename if present */
    const char *display_file = file ? file : "<unknown>";
    char file_buf[256];
    if (file) {
        size_t len = strlen(file);
        if (len > 2 && file[len-2] == '.' && file[len-1] == 'c') {
            if (len-2 < sizeof(file_buf)) {
                strncpy(file_buf, file, len-2);
                file_buf[len-2] = '\0';
                display_file = file_buf;
            }
        }
    }
    fprintf(out, "at %s:%d ", display_file, line);
    va_list args;
    va_start(args, fmt);
    vfprintf(out, fmt, args);
    va_end(args);
    fprintf(out, "\n");
    fflush(out);
    if (level == CZ_LOG_FATAL) abort();
}

/* CZar Log Runtime - Log struct for static method syntax */
typedef struct { int _unused; } Log;

/* CZar Log Runtime - Static method wrappers */
#ifdef __GNUC__
#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, __func__, __VA_ARGS__)
#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, __func__, __VA_ARGS__)
#else
#define cz_log_verbose(...) cz_log(CZ_LOG_VERBOSE, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_debug(...) cz_log(CZ_LOG_DEBUG, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_info(...) cz_log(CZ_LOG_INFO, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_warning(...) cz_log(CZ_LOG_WARN, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_error(...) cz_log(CZ_LOG_ERROR, __FILE__, __LINE__, NULL, __VA_ARGS__)
#define cz_log_fatal(...) cz_log(CZ_LOG_FATAL, __FILE__, __LINE__, NULL, __VA_ARGS__)
#endif

/* CZar Print Runtime - Type enum */
typedef enum {
    ANY_INT,
    ANY_UINT,
    ANY_LONG,
    ANY_ULONG,
    ANY_SIZE,
    ANY_DOUBLE,
    ANY_CHAR,
    ANY_CSTR,
    ANY_PTR
} any_type_t;

/* CZar Print Runtime - Type-safe value container */
typedef struct {
    any_type_t type;
    union {
        long i;
        unsigned long u;
        double d;
        char c;
        const char *s;
        const void *p;
    } v;
} any_t;

/* CZar Print Runtime - Helper constructors */
__attribute__((unused)) static inline any_t cz_any_int(int val) {
    any_t a; a.type = ANY_INT; a.v.i = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_uint(unsigned int val) {
    any_t a; a.type = ANY_UINT; a.v.u = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_long(long val) {
    any_t a; a.type = ANY_LONG; a.v.i = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_ulong(unsigned long val) {
    any_t a; a.type = ANY_ULONG; a.v.u = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_size(size_t val) {
    any_t a; a.type = ANY_SIZE; a.v.u = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_double(double val) {
    any_t a; a.type = ANY_DOUBLE; a.v.d = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_char(char val) {
    any_t a; a.type = ANY_CHAR; a.v.c = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_cstr(const char *val) {
    any_t a; a.type = ANY_CSTR; a.v.s = val; return a;
}
__attribute__((unused)) static inline any_t cz_any_ptr(const void *val) {
    any_t a; a.type = ANY_PTR; a.v.p = val; return a;
}

/* CZar Print Runtime - Internal print implementation */
__attribute__((unused)) static void cz_print_internal(const char *fmt, int argc, any_t *argv) {
    if (!fmt) return;
    
    int arg_idx = 0;
    const char *p = fmt;
    
    while (*p) {
        if (*p == '{' && *(p+1) == '}') {
            /* Handle {} placeholder */
            if (arg_idx < argc) {
                any_t arg = argv[arg_idx++];
                switch (arg.type) {
                    case ANY_INT:
                        printf("%ld", arg.v.i);
                        break;
                    case ANY_UINT:
                        printf("%lu", arg.v.u);
                        break;
                    case ANY_LONG:
                        printf("%ld", arg.v.i);
                        break;
                    case ANY_ULONG:
                        printf("%lu", arg.v.u);
                        break;
                    case ANY_SIZE:
                        printf("%zu", (size_t)arg.v.u);
                        break;
                    case ANY_DOUBLE:
                        printf("%g", arg.v.d);
                        break;
                    case ANY_CHAR:
                        printf("%c", arg.v.c);
                        break;
                    case ANY_CSTR:
                        printf("%s", arg.v.s ? arg.v.s : "(null)");
                        break;
                    case ANY_PTR:
                        printf("%p", arg.v.p);
                        break;
                }
            }
            p += 2;
        } else if (*p == '{' && *(p+1) == '{') {
            /* Handle {{ named placeholder - skip name until }} */
            p += 2;
            while (*p && !(*p == '}' && *(p+1) == '}')) {
                p++;
            }
            if (*p == '}' && *(p+1) == '}') {
                /* Print the corresponding argument */
                if (arg_idx < argc) {
                    any_t arg = argv[arg_idx++];
                    switch (arg.type) {
                        case ANY_INT:
                            printf("%ld", arg.v.i);
                            break;
                        case ANY_UINT:
                            printf("%lu", arg.v.u);
                            break;
                        case ANY_LONG:
                            printf("%ld", arg.v.i);
                            break;
                        case ANY_ULONG:
                            printf("%lu", arg.v.u);
                            break;
                        case ANY_SIZE:
                            printf("%zu", (size_t)arg.v.u);
                            break;
                        case ANY_DOUBLE:
                            printf("%g", arg.v.d);
                            break;
                        case ANY_CHAR:
                            printf("%c", arg.v.c);
                            break;
                        case ANY_CSTR:
                            printf("%s", arg.v.s ? arg.v.s : "(null)");
                            break;
                        case ANY_PTR:
                            printf("%p", arg.v.p);
                            break;
                    }
                }
                p += 2;
            }
        } else {
            /* Regular character - just print it */
            putchar(*p);
            p++;
        }
    }
    fflush(stdout);
}

/* CZar Print Runtime - PRINT macro with type detection */
#define PRINT(...) PRINT_IMPL(__VA_ARGS__)

/* Helper to detect type and create any_t */
#define CZ_TO_ANY(x) _Generic((x), \
    int: cz_any_int, \
    unsigned int: cz_any_uint, \
    long: cz_any_long, \
    unsigned long: cz_any_ulong, \
    float: cz_any_double, \
    double: cz_any_double, \
    char: cz_any_char, \
    char*: cz_any_cstr, \
    const char*: cz_any_cstr, \
    default: cz_any_ptr \
)(x)

/* Implementation macros for different argument counts */
#define PRINT_IMPL_1(fmt) \
    cz_print_internal(fmt, 0, NULL)

#define PRINT_IMPL_2(fmt, a1) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1)}; \
        cz_print_internal(fmt, 1, _args); \
    } while(0)

#define PRINT_IMPL_3(fmt, a1, a2) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2)}; \
        cz_print_internal(fmt, 2, _args); \
    } while(0)

#define PRINT_IMPL_4(fmt, a1, a2, a3) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3)}; \
        cz_print_internal(fmt, 3, _args); \
    } while(0)

#define PRINT_IMPL_5(fmt, a1, a2, a3, a4) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4)}; \
        cz_print_internal(fmt, 4, _args); \
    } while(0)

#define PRINT_IMPL_6(fmt, a1, a2, a3, a4, a5) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5)}; \
        cz_print_internal(fmt, 5, _args); \
    } while(0)

#define PRINT_IMPL_7(fmt, a1, a2, a3, a4, a5, a6) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6)}; \
        cz_print_internal(fmt, 6, _args); \
    } while(0)

#define PRINT_IMPL_8(fmt, a1, a2, a3, a4, a5, a6, a7) \
    do { \
        any_t _args[] = {CZ_TO_ANY(a1), CZ_TO_ANY(a2), CZ_TO_ANY(a3), CZ_TO_ANY(a4), CZ_TO_ANY(a5), CZ_TO_ANY(a6), CZ_TO_ANY(a7)}; \
        cz_print_internal(fmt, 7, _args); \
    } while(0)

/* Argument counting logic */
#define CZ_ARG_COUNT(...) CZ_ARG_COUNT_IMPL(__VA_ARGS__, 8, 7, 6, 5, 4, 3, 2, 1)
#define CZ_ARG_COUNT_IMPL(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N

/* Dispatch to appropriate implementation based on argument count */
#define PRINT_IMPL(...) CZ_CONCAT(PRINT_IMPL_, CZ_ARG_COUNT(__VA_ARGS__))(__VA_ARGS__)
#define CZ_CONCAT(a, b) CZ_CONCAT_IMPL(a, b)
#define CZ_CONCAT_IMPL(a, b) a##b

/* Demo showcasing CZar's PRINT functionality */

#include <stdio.h>

int main(void) {
    /* Basic usage with {} placeholders */
    const char *name = "CZar";
    int version = 1;
    PRINT("Welcome to {}!\n", name);
    PRINT("Version: {}\n", version);
    
    /* Multiple arguments */
    int x = 10;
    int y = 20;
    PRINT("Coordinates: ({}, {})\n", x, y);
    
    /* Named placeholders for readability */
    int width = 1920;
    int height = 1080;
    PRINT("Resolution: {{width}}x{{height}}\n", width, height);
    
    /* Mixed types */
    double pi = 3.14159;
    char grade = 'A';
    PRINT("Pi = {}, Grade = {}\n", pi, grade);
    
    /* Expressions */
    PRINT("Result: {} + {} = {}\n", 5, 3, 5 + 3);
    
    return 0;
}
