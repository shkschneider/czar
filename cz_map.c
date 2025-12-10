#include <stdio.h>
#include <string.h>

#include "cz_map.h"
#include "cz_test.h"

int main(void) {
    // Test map_new
    Map* map = map_new();
    assert(map->key == NULL);
    assert(map->value == NULL);
    assert(map->next == NULL);

    // Test map_put and map_get
    char* key1 = "key1";
    char* val1 = "value1";
    char* key2 = "key2";
    char* val2 = "value2";
    char* key3 = "key3";
    char* val3 = "value3";

    map_put(map, key1, val1);
    assert(map_get(map, key1) == val1);
    assert(map_size(map) == 1);

    map_put(map, key2, val2);
    assert(map_get(map, key2) == val2);
    assert(map_size(map) == 2);

    map_put(map, key3, val3);
    assert(map_get(map, key3) == val3);
    assert(map_size(map) == 3);

    // Test map_keys
    void** keys = map_keys(map);
    assert(keys[0] == key1);
    assert(keys[1] == key2);
    assert(keys[2] == key3);
    assert(keys[3] == NULL);
    free(keys);

    // Test map_values
    void** values = map_values(map);
    assert(values[0] == val1);
    assert(values[1] == val2);
    assert(values[2] == val3);
    assert(values[3] == NULL);
    free(values);

    // Test map_foreach
    int count = 0;
    Map* entry;
    map_foreach(map, entry) {
        count++;
    }
    assert(count == 3);

    // Test map_delete
    map_delete(map, key2);
    assert(map_get(map, key2) == NULL);
    assert(map_size(map) == 2);

    // Test map_clear
    map_clear(map);
    assert(map->key == NULL);
    assert(map->value == NULL);
    assert(map->next == NULL);
    assert(map_size(map) == 1); // Size is 1 because the first entry still exists but is cleared

    free(map);
    return 0;
}
