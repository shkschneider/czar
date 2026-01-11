#include "../../dist/cz.h"
#include <stdio.h>

int main(void) {
    const char *name = "world";
    cz_assert(name != NULL);
    cz_log_debug("Hello");
    char clock[1024];
    sprintf(&clock[0], "t = %llu ns", cz_monotonic_clock_ns());
    cz_log_info(clock);
    cz_nanosleep(42ULL);
    char timer[1024];
    sprintf(&timer[0], "t + %llu ns", cz_monotonic_timer_ns());
    cz_log_warn(timer);
    fprintf(stdout, "%s", cz_format("Hello, {{}}!\n", name));
    return 0;
}
