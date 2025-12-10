#include <stdio.h>
#include <string.h>

#include "../cz_misc.h"
#include "../cz_test.h"

int main(void) {
    // Test UNUSED macro (should not generate warning)
    int unused_var = 42;
    UNUSED(unused_var);
    
    // Test NOTHING function
    NOTHING();
    
    // Test file/line/func macros
    const char* file = _FILE_;
    assert(file != NULL);
    assert(strlen(file) > 0);
    
    int line = _LINE_;
    assert(line > 0);
    
    const char* func = _FUNC_;
    assert(func != NULL);
    assert(strcmp(func, "main") == 0);
    
    return 0;
}
