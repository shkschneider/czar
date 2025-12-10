#include <stdio.h>

#include "cz_pair.h"
#include "cz_test.h"

int main(void) {
    // Test pair_new
    Pair* pair = pair_new();
    assert(pair->key == NULL);
    assert(pair->value == NULL);

    // Test setting values
    char* key = "test_key";
    char* value = "test_value";
    pair->key = key;
    pair->value = value;
    assert(pair->key == key);
    assert(pair->value == value);

    // Test pair_clear
    pair_clear(pair);
    assert(pair->key == NULL);
    assert(pair->value == NULL);

    free(pair);
    return 0;
}
