#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../cz_memory.h"
#include "../cz_test.h"

int main(void) {
    // Test autofree
    {
        autofree char* temp = strdup("test");
        assert(temp != NULL);
        assert(strcmp(temp, "test") == 0);
        // temp will be automatically freed when scope exits
    }
    
    // Test free2 with array of strings
    char** arr = malloc(sizeof(char*) * 4);
    arr[0] = strdup("one");
    arr[1] = strdup("two");
    arr[2] = strdup("three");
    arr[3] = NULL;
    free2(arr);
    
    return 0;
}
