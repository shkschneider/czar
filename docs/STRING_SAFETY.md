# String Safety in Czar

## Overview

Czar's string implementation is designed to be **memory-safe** and prevent common buffer overflow vulnerabilities found in C code. The compiler actively warns about unsafe C functions in generated code.

## Internal String Structure

```c
typedef struct czar_string {
    char* data;       // Dynamically allocated buffer
    int32_t length;   // Current string length
    int32_t capacity; // Allocated capacity
} czar_string;
```

## Usage

### Stack Allocation
```czar
string s = string "Hello"
```

### Heap Allocation
```czar
string* s = new string "Hello"
free s
```

### Accessing Fields
```czar
i32 len = s.length
i32 cap = s.capacity
```

### C-String Conversion
```czar
print(s.cstr())  // Returns char* for printf, etc.
```

## Memory-Safe Operations

Czar provides built-in safe string operations that automatically handle:
- **Bounds checking**: All operations check buffer capacity
- **Dynamic resizing**: Strings grow automatically as needed
- **Null termination**: Always guaranteed

### Available Safe Operations

1. **czar_string_ensure_capacity(s, required)** - Dynamically resize to meet capacity needs
2. **czar_string_append(dest, src, len)** - Safe append with automatic resizing
3. **czar_string_concat(dest, src)** - Safe concatenate two strings
4. **czar_string_copy(dest, src, len)** - Safe copy with bounds checking

## Unsafe C Functions (Compiler Warnings)

The Czar compiler detects and warns about these unsafe functions in generated code:

### String Operations (No Bounds Checking)
| Unsafe Function | Why Unsafe | Safe Alternative |
|----------------|------------|------------------|
| `strcpy()` | No bounds checking | `snprintf()`, `memcpy()` with length |
| `strcat()` | No bounds checking on destination | `snprintf()`, proper length calculation |
| `strncpy()` | Doesn't guarantee null termination | `memcpy()` with explicit null termination |
| `strncat()` | Only limits source, not destination capacity | `snprintf()` or manual bounds checking |
| `gets()` | No way to limit input size | `fgets()` with size limit |
| `sprintf()` | No buffer size check | `snprintf()` with buffer size |
| `vsprintf()` | No buffer size check | `vsnprintf()` with buffer size |

### String Conversion (No Error Handling)
| Unsafe Function | Why Unsafe | Safe Alternative |
|----------------|------------|------------------|
| `atoi()` | No error handling, undefined on overflow | `strtol()` with error checking |
| `atof()` | No error handling, undefined on overflow | `strtod()` with error checking |
| `atol()` | No error handling, undefined on overflow | `strtol()` with error checking |
| `atoll()` | No error handling, undefined on overflow | `strtoll()` with error checking |

### Input Operations (Buffer Overflow Risks)
| Unsafe Function | Why Unsafe | Safe Alternative |
|----------------|------------|------------------|
| `scanf()` | Buffer overflow with %s | `fgets()` + parsing or custom parsing |
| `sscanf()` | Buffer overflow risks | Manual parsing with bounds checks |
| `vscanf()` | Buffer overflow risks | Safer parsing approaches |
| `vsscanf()` | Buffer overflow risks | Safer parsing approaches |

### Other Problematic Functions
| Unsafe Function | Why Unsafe | Safe Alternative |
|----------------|------------|------------------|
| `strtok()` | Not thread-safe, modifies input | `strtok_r()` (reentrant version) |
| `tmpnam()` | Race condition vulnerability | `mkstemp()` |
| `getenv()` | Returns pointer to internal data | `secure_getenv()` or careful handling |

## Design Philosophy

> "The max-limited string copy (strncpy) works well enough to prevent buffer overruns when copying strings, but the max-limited string concatenate (strncat) does not. It only limits how many characters it copies from the source buffer, without any regard to how much room is left in the destination buffer."

Czar's string implementation addresses this by:

1. **Always tracking both length and capacity**
2. **Automatic bounds checking before any operation**
3. **Dynamic resizing when needed**
4. **Using `memcpy()` with explicit lengths** (never `strcpy`, `strcat`, etc.)
5. **Compile-time warnings** for any unsafe C functions in generated code

## Example: Safe String Operations

```czar
fn main() i32 {
    // Create string with initial capacity
    string* s = new string "Hello"
    
    // Safe - all bounds are checked automatically
    // (Note: append/concat would be exposed as methods in future versions)
    
    // Access is safe
    i32 len = s.length      // 5
    i32 cap = s.capacity    // 16 (automatically sized)
    
    // Get C-string for printing
    print(s.cstr())
    
    free s
    return 0
}
```

## Future Enhancements

Planned additions to the string API:
- `string.append(str)` - Append another string
- `string.concat(s1, s2)` - Concatenate two strings
- `string.substring(start, end)` - Extract substring
- `string.find(needle)` - Find substring (using safe `strstr()`)
- `string.split(delimiter)` - Split string (using safe `strchr()`)
- `string.trim()` - Trim whitespace (using safe `strspn()`, `strcspn()`)
