/*
 * CZar - C semantic authority layer
 * Monotonic clock runtime module (runtime/monotonic_clock.c)
 *
 * Emits runtime monotonic clock support in generated C code.
 * Provides cz_monotonic_clock_ns() function for high-resolution timing.
 */

#define _POSIX_C_SOURCE 200809L

#include "monotonic.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void runtime_emit_monotonic_clock(FILE *output) {
    if (!output) {
        return;
    }

    /* Emit platform detection and includes */
    fprintf(output, "/* CZar Monotonic Clock Runtime */\n");
    fprintf(output, "#ifdef _WIN32\n");
    fprintf(output, "#include <windows.h>\n");
    fprintf(output, "#else\n");
    fprintf(output, "#include <time.h>\n");
    fprintf(output, "#endif\n\n");

    /* Emit the monotonic clock function */
    fprintf(output, "/* Get current time in nanoseconds from monotonic clock */\n");
    fprintf(output, "__attribute__((unused)) static unsigned long long cz_monotonic_clock_ns(void) {\n");
    fprintf(output, "#ifdef _WIN32\n");
    fprintf(output, "    /* Windows implementation using QueryPerformanceCounter */\n");
    fprintf(output, "    LARGE_INTEGER frequency;\n");
    fprintf(output, "    LARGE_INTEGER counter;\n");
    fprintf(output, "    QueryPerformanceFrequency(&frequency);\n");
    fprintf(output, "    QueryPerformanceCounter(&counter);\n");
    fprintf(output, "    /* Convert to nanoseconds: (counter * 1e9) / frequency */\n");
    fprintf(output, "    return (unsigned long long)((counter.QuadPart * 1000000000ULL) / frequency.QuadPart);\n");
    fprintf(output, "#else\n");
    fprintf(output, "    /* POSIX implementation using clock_gettime with CLOCK_MONOTONIC */\n");
    fprintf(output, "    struct timespec ts;\n");
    fprintf(output, "    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {\n");
    fprintf(output, "        return 0;  /* Error case */\n");
    fprintf(output, "    }\n");
    fprintf(output, "    /* Convert to nanoseconds */\n");
    fprintf(output, "    return (unsigned long long)(ts.tv_sec) * 1000000000ULL + (unsigned long long)(ts.tv_nsec);\n");
    fprintf(output, "#endif\n");
    fprintf(output, "}\n\n");
}

void runtime_emit_nanosleep(FILE *output) {
    if (!output) {
        return;
    }
    /* Emit sleep function */
    fprintf(output, "/* Sleep for specified nanoseconds */\n");
    fprintf(output, "__attribute__((unused)) static void cz_nanosleep(unsigned long long nanoseconds) {\n");
    fprintf(output, "#ifdef _WIN32\n");
    fprintf(output, "    /* Windows Sleep takes milliseconds */\n");
    fprintf(output, "    DWORD ms = (DWORD)(nanoseconds / 1000000ULL);\n");
    fprintf(output, "    if (ms == 0 && nanoseconds > 0) ms = 1;  /* Minimum 1ms */\n");
    fprintf(output, "    Sleep(ms);\n");
    fprintf(output, "#else\n");
    fprintf(output, "    /* POSIX nanosleep */\n");
    fprintf(output, "    struct timespec ts;\n");
    fprintf(output, "    ts.tv_sec = (time_t)(nanoseconds / 1000000000ULL);\n");
    fprintf(output, "    ts.tv_nsec = (long)(nanoseconds %% 1000000000ULL);\n");
    fprintf(output, "    nanosleep(&ts, NULL);\n");
    fprintf(output, "#endif\n");
    fprintf(output, "}\n\n");
}

void runtime_emit_monotonic_timer(FILE *output) {
    if (!output) {
        return;
    }
    /* Emit timer function for measuring time since program start */
    fprintf(output, "/* Timer: nanoseconds since program start */\n");
    fprintf(output, "static unsigned long long __cz_timer_start = 0;\n");
    fprintf(output, "__attribute__((constructor)) static void __cz_timer_init(void) {\n");
    fprintf(output, "    __cz_timer_start = cz_monotonic_clock_ns();\n");
    fprintf(output, "}\n");
    fprintf(output, "__attribute__((unused)) static unsigned long long cz_monotonic_timer_ns(void) {\n");
    fprintf(output, "    return cz_monotonic_clock_ns() - __cz_timer_start;\n");
    fprintf(output, "}\n\n");
}

void runtime_emit_monotonic(FILE *output) {
    runtime_emit_monotonic_clock(output);
    runtime_emit_nanosleep(output);
    runtime_emit_monotonic_timer(output);
}
