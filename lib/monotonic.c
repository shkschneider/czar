/*
 * CZar Runtime Library
 * Monotonic clock implementation - High-resolution time measurement
 */

/* Define _POSIX_C_SOURCE before any includes */
#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "cz.h"

#ifdef CZ_PLATFORM_WINDOWS
#include <windows.h>
#else
#include <time.h>
#include <unistd.h>
#endif

/* Get current time in nanoseconds from monotonic clock */
unsigned long long cz_monotonic_clock_ns(void) {
#ifdef CZ_PLATFORM_WINDOWS
    /* Windows implementation using QueryPerformanceCounter */
    LARGE_INTEGER frequency;
    LARGE_INTEGER counter;
    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&counter);
    /* Convert to nanoseconds: (counter * 1e9) / frequency */
    return (unsigned long long)((counter.QuadPart * 1000000000ULL) / frequency.QuadPart);
#else
    /* POSIX implementation using clock_gettime with CLOCK_MONOTONIC */
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;  /* Error case */
    }
    /* Convert to nanoseconds */
    return (unsigned long long)(ts.tv_sec) * 1000000000ULL + (unsigned long long)(ts.tv_nsec);
#endif
}

/* Sleep for specified nanoseconds */
void cz_nanosleep(unsigned long long nanoseconds) {
#ifdef CZ_PLATFORM_WINDOWS
    /* Windows Sleep takes milliseconds */
    DWORD ms = (DWORD)(nanoseconds / 1000000ULL);
    if (ms == 0 && nanoseconds > 0) ms = 1;  /* Minimum 1ms */
    Sleep(ms);
#else
    /* POSIX nanosleep */
    struct timespec ts;
    ts.tv_sec = (time_t)(nanoseconds / 1000000000ULL);
    ts.tv_nsec = (long)(nanoseconds % 1000000000ULL);
    nanosleep(&ts, NULL);
#endif
}

/* Timer: nanoseconds since program start */
static unsigned long long g_timer_start = 0;

#ifdef __GNUC__
__attribute__((constructor))
#endif
static void cz_timer_init(void) {
    g_timer_start = cz_monotonic_clock_ns();
}

unsigned long long cz_monotonic_timer_ns(void) {
    /* Initialize on first call if constructor didn't run */
    if (g_timer_start == 0) {
        cz_timer_init();
    }
    return cz_monotonic_clock_ns() - g_timer_start;
}
