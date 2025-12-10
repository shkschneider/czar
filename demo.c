#include "cz.h"
#include <stdio.h>

// Demo program showcasing the czar C extension library

void demo_string_operations() {
    LOG_INFO("=== String Operations Demo ===");
    
    // String duplication
    string s = str("Hello World");
    LOG_INFO("Original: %s", s);
    
    // Case conversions
    autofree string upper = str(s);
    case_upper(upper);
    LOG_INFO("Upper case: %s", upper);
    
    autofree string lower = str(s);
    case_lower(lower);
    LOG_INFO("Lower case: %s", lower);
    
    autofree string pascal = case_pascal(s);
    LOG_INFO("Pascal case: %s", pascal);
    
    autofree string camel = case_camel(s);
    LOG_INFO("Camel case: %s", camel);
    
    autofree string snake = case_snake(s);
    LOG_INFO("Snake case: %s", snake);
    
    // String operations
    LOG_INFO("Has prefix 'Hello': %d", strpre(s, "Hello"));
    LOG_INFO("Has suffix 'World': %d", strsuf(s, "World"));
    
    // String replacement
    autofree string replaced = str(s);
    strrpl(replaced, 'o', '0');
    LOG_INFO("Replace 'o' with '0': %s", replaced);
    
    // String drop
    autofree string dropped = strdrp(s, 'l');
    LOG_INFO("Drop 'l': %s", dropped);
    
    free(s);
}

void demo_map_operations() {
    LOG_INFO("=== Map Operations Demo ===");
    
    Map* map = map_new();
    
    // Add some entries
    map_put(map, "name", "John Doe");
    map_put(map, "role", "Developer");
    map_put(map, "language", "C");
    
    LOG_INFO("Map size: %zu", map_size(map));
    
    // Get values
    LOG_INFO("Name: %s", (char*)map_get(map, "name"));
    LOG_INFO("Role: %s", (char*)map_get(map, "role"));
    LOG_INFO("Language: %s", (char*)map_get(map, "language"));
    
    // Iterate over map
    LOG_INFO("Iterating over map:");
    Map* entry;
    map_foreach(map, entry) {
        if (entry->key != NULL) {
            LOG_INFO("  %s -> %s", (char*)entry->key, (char*)entry->value);
        }
    }
    
    // Get all keys
    void** keys = map_keys(map);
    LOG_INFO("Keys:");
    for (size_t i = 0; keys[i] != NULL; i++) {
        LOG_INFO("  %s", (char*)keys[i]);
    }
    free(keys);
    
    // Get all values
    void** values = map_values(map);
    LOG_INFO("Values:");
    for (size_t i = 0; values[i] != NULL; i++) {
        LOG_INFO("  %s", (char*)values[i]);
    }
    free(values);
    
    // Clear and free
    map_clear(map);
    free(map);
}

void demo_pair_operations() {
    LOG_INFO("=== Pair Operations Demo ===");
    
    Pair* pair = pair_new();
    pair->key = "username";
    pair->value = "alice123";
    
    LOG_INFO("Key: %s, Value: %s", (char*)pair->key, (char*)pair->value);
    
    pair_clear(pair);
    free(pair);
}

void demo_memory_features() {
    LOG_INFO("=== Memory Management Features Demo ===");
    
    // autofree - automatic memory cleanup
    {
        autofree char* temp = strdup("This will be freed automatically");
        LOG_INFO("Allocated: %s", temp);
        // temp is automatically freed when it goes out of scope
    }
    LOG_INFO("Memory automatically freed!");
    
    // free2 - free array of strings
    string* words = strdiv("one,two,three", ",");
    LOG_INFO("Split result:");
    for (int i = 0; words[i] != NULL; i++) {
        LOG_INFO("  %s", words[i]);
    }
    free2(words);
}

void demo_logging() {
    LOG_INFO("=== Logging Demo ===");
    LOG_DEBUG("This is a debug message");
    LOG_INFO("This is an info message");
    LOG_WARNING("This is a warning message");
    LOG_ERROR("This is an error message");
}

int main(void) {
    LOG_INFO("Welcome to the czar C extension library demo!");
    LOG_INFO("");
    
    demo_logging();
    LOG_INFO("");
    
    demo_string_operations();
    LOG_INFO("");
    
    demo_map_operations();
    LOG_INFO("");
    
    demo_pair_operations();
    LOG_INFO("");
    
    demo_memory_features();
    LOG_INFO("");
    
    LOG_INFO("Demo completed successfully!");
    return 0;
}
