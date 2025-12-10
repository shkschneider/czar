#include <stdio.h>
#include <string.h>

#include "../cz_log.h"
#include "../cz_test.h"

int main(void) {
    // Test that logging functions work without crashing
    LOG_DEBUG("Debug test message");
    LOG_INFO("Info test message");
    LOG_WARNING("Warning test message");
    LOG_ERROR("Error test message");
    
    // Test timenow function
    char* time_str = timenow();
    assert(time_str != NULL);
    assert(strlen(time_str) > 0);
    
    return 0;
}
