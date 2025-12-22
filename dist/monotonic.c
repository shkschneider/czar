#ifndef _POSIX_C_SOURCE
# define _POSIX_C_SOURCE 199309L  // for clock_gettime on many POSIX systems
#endif

#include <time.h>
#include <stdint.h>

uint64_t now_ns(void) {
    struct timespec ts;
#if defined(CLOCK_MONOTONIC_RAW)
    // On Linux you can use CLOCK_MONOTONIC_RAW if you want raw hardware time
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
#else
    clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static inline double ns_to_sec(uint64_t ns) { return (double)ns / 1e9; }

#include <stdio.h>

int main(void) {
    uint64_t t0 = now_ns();
    // ... work ...
    for (volatile long i = 0; i < 1000000; ++i) {}
    uint64_t t1 = now_ns();
    double elapsed = ns_to_sec(t1 - t0);
    printf("Elapsed: %.9f s\n", elapsed);
    return 0;
}
