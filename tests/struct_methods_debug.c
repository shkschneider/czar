/* CZar runtime functions - injected by transpiler */
#include <stdio.h>
#include <stdlib.h>

static inline void _cz_assert(int condition, const char* file, int line, const char* func, const char* cond_str) {
    if (!condition) {
        fprintf(stderr, "%s:%d: %s: Assertion failed: %s\n", file, line, func, cond_str);
        abort();
    }
}
#define cz_assert(cond) _cz_assert((cond), __FILE__, __LINE__, __func__, #cond)

static inline void _cz_todo(const char* msg, const char* file, int line, const char* func) {
    fprintf(stderr, "%s:%d: %s: TODO: %s\n", file, line, func, msg);
    abort();
}
#define cz_todo(msg) _cz_todo((msg), __FILE__, __LINE__, __func__)

static inline void _cz_fixme(const char* msg, const char* file, int line, const char* func) {
    fprintf(stderr, "%s:%d: %s: FIXME: %s\n", file, line, func, msg);
    abort();
}
#define cz_fixme(msg) _cz_fixme((msg), __FILE__, __LINE__, __func__)

static inline void _cz_unreachable(const char* msg, const char* file, int line, const char* func) {
    fprintf(stderr, "%s:%d: %s: Unreachable code reached: %s\n", file, line, func, msg);
    abort();
}
#define cz_unreachable(msg) _cz_unreachable((msg), __FILE__, __LINE__, __func__)
/* End of CZar runtime functions */

#include <stdint.h>
#include <stdio.h>

/*
 * Test struct methods
 * CZar allows defining methods on structs:
 *   RetType StructName.method_name(params) { ... }
 * This is syntax sugar for:
 *   RetType StructName_method_name(StructName* self, params) { ... }
 * 
 * Calling methods:
 *   instance.method(args) -> StructName_method(&instance, args)
 *   StructName.method(&instance, args) -> StructName_method(&instance, args)
 */

typedef struct Vec2 {
    uint8_t x;
    uint8_t y;
} Vec2;

/* Method definition - implicit self parameter */
uint8_t Vec2.length() {
    return self.x * self.y;
}

/* Method with explicit parameter */
void Vec2.set(uint8_t new_x, uint8_t new_y) {
    self.x = new_x;
    self.y = new_y;
}

/* Method returning struct */
Vec2 Vec2.add(Vec2 other) {
    Vec2 result = {0};
    result.x = self.x + other.x;
    result.y = self.y + other.y;
    return result;
}

/* Another struct with methods */
typedef struct Counter {
    int32_t value;
} Counter;

int32_t Counter.get() {
    return self.value;
}

void Counter.increment() {
    self.value = self.value + 1;
}

void Counter.add(int32_t delta) {
    self.value = self.value + delta;
}

int main(void) {
    /* Test 1: Basic method call */
    Vec2 v = {0};
    v.x = 3;
    v.y = 4;
    uint8_t len = v.length();
    cz_assert(len == 12);
    printf("Test 1 passed: Basic method call v.length() = %u\n", len);

    /* Test 2: Method with parameters */
    v.set(5, 6);
    cz_assert(v.x == 5);
    cz_assert(v.y == 6);
    printf("Test 2 passed: Method with parameters v.set(5, 6)\n");

    /* Test 3: Method returning struct */
    Vec2 v2 = {0};
    v2.x = 1;
    v2.y = 2;
    Vec2 v3 = v.add(v2);
    cz_assert(v3.x == 6);
    cz_assert(v3.y == 8);
    printf("Test 3 passed: Method returning struct v.add(v2)\n");

    /* Test 4: Static method call */
    Vec2 v4 = {0};
    v4.x = 2;
    v4.y = 3;
    uint8_t len2 = Vec2.length(&v4);
    cz_assert(len2 == 6);
    printf("Test 4 passed: Static method call Vec2.length(&v4) = %u\n", len2);

    /* Test 5: Multiple structs with methods */
    Counter c = {0};
    c.value = 10;
    int32_t val = c.get();
    cz_assert(val == 10);
    c.increment();
    cz_assert(c.value == 11);
    c.add(5);
    cz_assert(c.value == 16);
    printf("Test 5 passed: Multiple structs with methods\n");

    /* Test 6: Method on pointer (auto-dereference) */
    Vec2* vp = &v;
    uint8_t len3 = vp.length();
    cz_assert(len3 == 30);
    printf("Test 6 passed: Method on pointer vp.length() = %u\n", len3);

    printf("All struct method tests passed!\n");
    return 0;
}
