# czar - C Extension Library Examples

This document provides examples of using the czar C extension library.

## Building and Running

### Build everything
```bash
make
```

### Build the demo
```bash
make demo
./demo
```

### Build and run tests
```bash
make test
```

### Clean build artifacts
```bash
make clean
```

## String Operations

### String Case Conversions

```c
#include "cz.h"

string s = str("Hello World");

// Convert to UPPER CASE
string upper = str(s);
case_upper(upper);  // "HELLO WORLD"

// Convert to lower case
string lower = str(s);
case_lower(lower);  // "hello world"

// Convert to Title Case
string title = str(s);
case_title(title);  // "Hello world"

// Convert to PascalCase
string pascal = case_pascal(s);  // "HelloWorld" (allocates)

// Convert to camelCase
string camel = case_camel(s);  // "helloWorld" (allocates)

// Convert to snake_case
string snake = case_snake(s);  // "hello_world" (allocates)
```

### String Manipulation

```c
#include "cz.h"

// Check if strings are equal
assert(streq("test", "test") == true);
assert(streq("test", "other") == false);

// Check if string has content
assert(strsmth("hello") == true);
assert(strsmth("") == false);
assert(strsmth(NULL) == false);

// Check prefix
assert(strpre("hello world", "hello") == true);
assert(strpre("hello world", "world") == false);

// Check suffix
assert(strsuf("hello world", "world") == true);
assert(strsuf("hello world", "hello") == false);

// Trim whitespace
string trimmed = strtrmc("  hello  ");  // "hello" (allocates)

// Split string
string* parts = strdiv("one,two,three", ",");  // (allocates)
// parts[0] = "one", parts[1] = "two", parts[2] = "three", parts[3] = NULL
free2(parts);  // Free array of strings

// Replace character
string s = strdup("hello");
strrpl(s, 'l', 'r');  // "herro"

// Drop/remove character
string dropped = strdrp("hello", 'l');  // "heo" (allocates)
```

## Map Operations

Maps are key-value stores with linked list implementation.

```c
#include "cz.h"

// Create a new map
Map* map = map_new();

// Add entries
map_put(map, "name", "John Doe");
map_put(map, "role", "Developer");
map_put(map, "language", "C");

// Get values
char* name = (char*)map_get(map, "name");  // "John Doe"
char* role = (char*)map_get(map, "role");  // "Developer"

// Get map size
size_t size = map_size(map);  // 3

// Get all keys
void** keys = map_keys(map);
for (size_t i = 0; keys[i] != NULL; i++) {
    printf("Key: %s\n", (char*)keys[i]);
}
free(keys);

// Get all values
void** values = map_values(map);
for (size_t i = 0; values[i] != NULL; i++) {
    printf("Value: %s\n", (char*)values[i]);
}
free(values);

// Iterate over map
Map* entry;
map_foreach(map, entry) {
    if (entry->key != NULL) {
        printf("%s -> %s\n", (char*)entry->key, (char*)entry->value);
    }
}

// Delete an entry
map_delete(map, "role");

// Clear all entries
map_clear(map);

// Free the map
free(map);
```

## Pair Operations

Pairs are simple key-value containers.

```c
#include "cz.h"

// Create a new pair
Pair* pair = pair_new();

// Set key and value
pair->key = "username";
pair->value = "alice123";

// Access key and value
printf("Key: %s, Value: %s\n", (char*)pair->key, (char*)pair->value);

// Clear the pair
pair_clear(pair);

// Free the pair
free(pair);
```

## Memory Management

### Automatic Cleanup

The library provides automatic cleanup attributes for RAII-style memory management:

```c
#include "cz.h"

// autofree - automatically free memory when variable goes out of scope
{
    autofree char* temp = strdup("This will be freed automatically");
    printf("%s\n", temp);
    // temp is automatically freed here
}

// autoclose - automatically close file descriptors
{
    autoclose int fd = open("file.txt", O_RDONLY);  // Requires: #include <fcntl.h>
    // ... use fd ...
    // fd is automatically closed here
}

// autofclose - automatically close FILE pointers
{
    autofclose FILE* file = fopen("file.txt", "r");
    // ... use file ...
    // file is automatically closed here
}
```

### Free Macros

```c
// free1 - free a single pointer
char* str = strdup("hello");
free1(str);

// free2 - free an array of strings (NULL-terminated)
string* words = strdiv("one,two,three", ",");
free2(words);  // Frees each string and the array
```

## Logging

The library provides simple logging macros:

```c
#include "cz.h"

LOG_DEBUG("Debug message: value = %d", 42);
LOG_INFO("Info message: %s", "success");
LOG_WARNING("Warning: something might be wrong");
LOG_ERROR("Error occurred: %s", strerr());
```

Output format: `YYYY-MM-DD HH:MM:SS [LEVEL/file:line] message`

## Type Definitions

The library provides convenient type aliases:

```c
// Boolean
bit b = 0;  // _Bool

// Integer types
i8 a = -128;        // int8_t
i16 b = -32768;     // int16_t
i32 c = -2147483648; // int32_t
i64 d = -9223372036854775808LL; // int64_t

u8 e = 255;         // uint8_t
u16 f = 65535;      // uint16_t
u32 g = 4294967295; // uint32_t
u64 h = 18446744073709551615ULL; // uint64_t

// Floating point types
f32 x = 3.14f;      // float
f64 y = 3.14159;    // double
f128 z = 3.14159L;  // long double

// String type
string s = "hello"; // char*

// Generic pointer
any* ptr = NULL;    // void*
```

## Whitespace Constants

```c
#include "cz.h"

char space = SPC;  // ' '
char tab = TAB;    // '\t'
char newline = LF; // '\n'
char vtab = VT;    // '\v'
char feed = FF;    // '\f'
char cr = CR;      // '\r'
```

## Utility Macros

```c
#include "cz.h"

// Get size of type
size_t size = SIZE(int);  // sizeof(int)

// Mark variable as unused (suppress warnings)
UNUSED(variable);

// Do nothing
NOTHING();

// Mark unimplemented code
TODO();  // Prints error and aborts

// File/line/function macros
printf("File: %s\n", _FILE_);  // Current file basename
printf("Line: %d\n", _LINE_);  // Current line number
printf("Function: %s\n", _FUNC_); // Current function name
```

## Testing

The library includes a simple testing framework:

```c
#include "cz_test.h"

int main(void) {
    // Test equality
    TEST(5, 5);  // Pass
    TEST("hello", "hello");  // Pass
    
    // Use standard assertions
    assert(1 + 1 == 2);
    
    // Static assertions
    ASSERT(sizeof(int) == 4, "int must be 4 bytes");
    
    return 0;
}
```

## Complete Example

```c
#include "cz.h"
#include <stdio.h>

int main(void) {
    LOG_INFO("Starting application");
    
    // Create a map to store user data
    Map* users = map_new();
    map_put(users, "user1", "Alice");
    map_put(users, "user2", "Bob");
    
    // Process usernames
    Map* entry;
    map_foreach(users, entry) {
        if (entry->key != NULL) {
            char* username = (char*)entry->value;
            
            // Convert to different cases
            autofree string snake = case_snake(username);
            autofree string camel = case_camel(username);
            
            LOG_INFO("User: %s, snake: %s, camel: %s", 
                     username, snake, camel);
        }
    }
    
    // Cleanup
    map_clear(users);
    free(users);
    
    LOG_INFO("Application finished");
    return 0;
}
```

## See Also

- [README.md](README.md) - Main documentation
- [demo.c](demo.c) - Complete demo program
- Test files: `cz_*.c` - Unit tests for each module
