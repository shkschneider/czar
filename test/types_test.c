#include <stdio.h>
#include <assert.h>

#include "../cz_types.h"
#include "../cz_test.h"

int main(void) {
    // Test integer types
    i8 a = -128;
    assert(a == -128);
    
    i16 b = -32768;
    assert(b == -32768);
    
    i32 c = -2147483648;
    assert(c == -2147483648);
    
    u8 d = 255;
    assert(d == 255);
    
    u16 e = 65535;
    assert(e == 65535);
    
    u32 f = 4294967295U;
    assert(f == 4294967295U);
    
    // Test floating point types
    f32 x = 3.14f;
    assert(x > 3.13f && x < 3.15f);
    
    f64 y = 3.14159;
    assert(y > 3.14 && y < 3.15);
    
    f128 z = 3.14159L;
    assert(z > 3.14L && z < 3.15L);
    
    // Test bit type
    bit flag = 0;
    assert(flag == 0);
    flag = 1;
    assert(flag == 1);
    
    // Test SIZE macro
    assert(SIZE(int) == sizeof(int));
    assert(SIZE(char) == 1);
    assert(SIZE(double) == sizeof(double));
    
    // Test whitespace constants
    assert(SPC == ' ');
    assert(TAB == '\t');
    assert(LF == '\n');
    assert(VT == '\v');
    assert(FF == '\f');
    assert(CR == '\r');
    
    return 0;
}
